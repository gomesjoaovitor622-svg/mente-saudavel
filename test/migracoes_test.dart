import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/database/database_schema.dart';
import 'package:mente_saudavel/database/migracoes.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/banco_de_teste.dart';

/// Esquema da VERSÃO 2 (o que está instalado em celulares que já usam o app).
Future<void> _criarV2(Database db) async {
  await db.execute('''
    CREATE TABLE usuarios (
      id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE COLLATE NOCASE, senha_hash TEXT NOT NULL, salt TEXT NOT NULL,
      perfil TEXT NOT NULL CHECK (perfil IN ('paciente', 'profissional')),
      registro TEXT, especialidade TEXT, endereco TEXT, criado_em TEXT NOT NULL)''');
  await db.execute('''
    CREATE TABLE sessoes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      paciente_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      profissional_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      data_hora TEXT NOT NULL, modalidade TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'agendada' CHECK (status IN ('agendada', 'concluida', 'cancelada')),
      anotacoes TEXT, criado_em TEXT NOT NULL)''');
  await db.execute(DatabaseSchema.avaliacoes);
}

Future<Set<String>> _colunas(Database db, String tabela) async =>
    (await db.rawQuery('PRAGMA table_info($tabela)')).map((c) => c['name']! as String).toSet();

Future<Set<String>> _indices(Database db) async => (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'uq_%'",
    ))
        .map((l) => l['name']! as String)
        .toSet();

void main() {
  setUpAll(iniciarSqliteDeTeste);

  Future<Database> bancoV2ComDados(String caminho) async {
    final v2 = await databaseFactory.openDatabase(
      caminho,
      options: OpenDatabaseOptions(version: 2, onCreate: (db, _) => _criarV2(db)),
    );
    final agora = DateTime.now().toIso8601String();
    await v2.insert('usuarios', {'nome': 'Ana', 'email': 'ana@t.com', 'senha_hash': 'x', 'salt': 'y', 'perfil': 'paciente', 'criado_em': agora});
    await v2.insert('usuarios', {'nome': 'Bia', 'email': 'bia@t.com', 'senha_hash': 'x', 'salt': 'y', 'perfil': 'paciente', 'criado_em': agora});
    await v2.insert('usuarios', {'nome': 'Dr', 'email': 'dr@t.com', 'senha_hash': 'x', 'salt': 'y', 'perfil': 'profissional', 'criado_em': agora});
    // Duas sessões ATIVAS no mesmo horário (possível na v2, que só conferia antes de gravar).
    for (final paciente in [1, 2]) {
      await v2.insert('sessoes', {
        'paciente_id': paciente, 'profissional_id': 3, 'data_hora': '2030-01-01T10:00:00',
        'modalidade': 'Online', 'status': 'agendada', 'anotacoes': 'nota $paciente', 'criado_em': agora,
      });
    }
    await v2.close();
    return databaseFactory.openDatabase(
      caminho,
      options: OpenDatabaseOptions(
        version: Migracoes.versaoAtual,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onUpgrade: Migracoes.atualizar,
      ),
    );
  }

  test('v2 -> atual acrescenta colunas (preço, LGPD) e tabelas (outbox) sem perder dados', () async {
    final db = await bancoV2ComDados(await caminhoTemporario());
    expect(await _colunas(db, 'usuarios'), contains('valor_sessao_centavos'));
    expect(await _colunas(db, 'sessoes'), contains('valor_centavos'));
    expect(await _colunas(db, 'usuarios'), containsAll(['aceite_termos_versao', 'aceite_termos_em', 'anonimizado_em']));
    expect(await _colunas(db, 'outbox'), containsAll(['payload', 'chave', 'estado']));
    expect(await db.query('usuarios'), hasLength(3));
    final sessoes = await db.query('sessoes', orderBy: 'id');
    expect(sessoes, hasLength(2));
    expect(sessoes.map((s) => s['anotacoes']), ['nota 1', 'nota 2']); // nada foi apagado
    expect(sessoes.every((s) => s['valor_centavos'] == 0), isTrue);
    await db.close();
  });

  test('duplicatas antigas: a mais nova vira cancelada e o índice único é criado', () async {
    final db = await bancoV2ComDados(await caminhoTemporario());
    final status = (await db.query('sessoes', orderBy: 'id')).map((s) => s['status']).toList();
    expect(status, ['agendada', 'cancelada']);
    expect(await _indices(db), {'uq_sessao_prof_horario', 'uq_sessao_pac_horario'});
    await db.close();
  });

  test('banco migrado e banco novo ficam com as MESMAS colunas e índices', () async {
    final migrado = await bancoV2ComDados(await caminhoTemporario());
    final novo = await abrirBancoNovo();
    for (final tabela in ['usuarios', 'sessoes', 'avaliacoes', 'outbox', 'cache_kv', 'humor_registros']) {
      if (tabela == 'humor_registros') continue; // não existia no v2 de teste
      expect(await _colunas(migrado, tabela), await _colunas(novo, tabela), reason: tabela);
    }
    expect(await _indices(migrado), await _indices(novo));
    await migrado.close();
    await novo.close();
  });

  test('migração é repetível: rodar de novo não falha nem duplica coluna', () async {
    final db = await bancoV2ComDados(await caminhoTemporario());
    await Migracoes.atualizar(db, 2, Migracoes.versaoAtual);
    expect((await _colunas(db, 'sessoes')).where((c) => c == 'valor_centavos'), hasLength(1));
    await db.close();
  });

  test('v4 -> v5: a fila passa a aceitar humor e perfil e as ações pendentes são preservadas', () async {
    final caminho = await caminhoTemporario();
    // Esquema EXATO da v4 (CHECK antigo: só agendar, status e remarcar), com ações pendentes.
    final v4 = await databaseFactory.openDatabase(
      caminho,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await _criarV2(db);
          await db.execute('''
            CREATE TABLE outbox (
              id INTEGER PRIMARY KEY AUTOINCREMENT, usuario_id INTEGER NOT NULL,
              tipo TEXT NOT NULL CHECK (tipo IN ('agendar', 'status', 'remarcar')),
              payload TEXT NOT NULL, chave TEXT NOT NULL UNIQUE,
              estado TEXT NOT NULL DEFAULT 'pendente' CHECK (estado IN ('pendente', 'conflito', 'falhou')),
              tentativas INTEGER NOT NULL DEFAULT 0, ultimo_erro TEXT, criado_em TEXT NOT NULL)''');
          await db.execute('CREATE INDEX idx_outbox_usuario ON outbox (usuario_id, id)');
          await db.execute(DatabaseSchema.cacheKv);
        },
      ),
    );
    final agora = DateTime.now().toIso8601String();
    await v4.insert('outbox', {'usuario_id': 1, 'tipo': 'agendar', 'payload': '{"a":1}', 'chave': 'k1', 'estado': 'pendente', 'criado_em': agora});
    await v4.insert('outbox', {'usuario_id': 1, 'tipo': 'status', 'payload': '{"b":2}', 'chave': 'k2', 'estado': 'falhou', 'tentativas': 3, 'ultimo_erro': 'boom', 'criado_em': agora});
    // Antes da correção, o banco recusava humor/perfil:
    await expectLater(
      v4.insert('outbox', {'usuario_id': 1, 'tipo': 'humor', 'payload': '{}', 'chave': 'k3', 'criado_em': agora}),
      throwsA(isA<DatabaseException>()),
    );
    await v4.close();

    final db = await databaseFactory.openDatabase(
      caminho,
      options: OpenDatabaseOptions(version: Migracoes.versaoAtual, onUpgrade: Migracoes.atualizar),
    );
    final fila = await db.query('outbox', orderBy: 'id');
    expect(fila.map((l) => l['chave']), ['k1', 'k2']); // nada se perdeu
    expect(fila[1]['estado'], 'falhou');
    expect(fila[1]['tentativas'], 3);
    expect(fila[1]['ultimo_erro'], 'boom');
    for (final tipo in ['humor', 'perfil']) {
      await db.insert('outbox', {'usuario_id': 1, 'tipo': tipo, 'payload': '{}', 'chave': 'novo-$tipo', 'criado_em': agora});
    }
    await expectLater(
      db.insert('outbox', {'usuario_id': 1, 'tipo': 'inexistente', 'payload': '{}', 'chave': 'x', 'criado_em': agora}),
      throwsA(isA<DatabaseException>()), // o CHECK continua protegendo contra tipos inválidos
    );
    final indices = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_outbox_usuario'");
    expect(indices, hasLength(1));
    expect(await db.rawQuery("SELECT name FROM sqlite_master WHERE name = 'outbox_antiga'"), isEmpty);
    await db.close();
  });

  test('versão sem passo escrito falha de forma explícita (e a transação desfaz tudo)', () async {
    final db = await abrirBancoNovo();
    await expectLater(() => Migracoes.atualizar(db, Migracoes.versaoAtual, Migracoes.versaoAtual + 1), throwsStateError);
    await db.close();
  });
}
