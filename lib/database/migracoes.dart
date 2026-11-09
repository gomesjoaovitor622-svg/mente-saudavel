import 'package:sqflite/sqflite.dart';
import 'package:mente_saudavel/database/database_schema.dart';

/// Um passo de migração: leva o banco da versão (N-1) para a versão N.
typedef Migracao = Future<void> Function(DatabaseExecutor db);

/// Migrações VERSIONADAS do banco local.
///
/// Regras para criar uma nova versão (ex.: 4):
///  1. Some 1 em [versaoAtual] e acrescente `4: _v4` em [_passos].
///  2. Use `ALTER TABLE ... ADD COLUMN` (nunca apague tabelas com dados). Exceção: mudar um CHECK exige
///     recriar a tabela; faça isso COPIANDO as linhas (veja `_v5`) e com teste que parte do banco antigo.
///  3. Atualize também `DatabaseSchema`, para que instalações novas (onCreate) e migradas
///     fiquem IDÊNTICAS. O teste `migracoes_test.dart` compara os dois caminhos.
///
/// O sqflite já executa `onCreate`/`onUpgrade` dentro de UMA transação: se qualquer passo
/// falhar, tudo é desfeito e o banco continua na versão antiga, com os dados intactos.
class Migracoes {
  Migracoes._();

  static const int versaoAtual = 5;

  static final Map<int, Migracao> _passos = {
    2: _v2,
    3: _v3,
    4: _v4,
    5: _v5,
  };

  /// Aplica, em ordem, todos os passos de [de] (exclusive) até [para] (inclusive).
  static Future<void> atualizar(DatabaseExecutor db, int de, int para) async {
    for (var versao = de + 1; versao <= para; versao++) {
      final passo = _passos[versao];
      if (passo == null) {
        throw StateError('Migração para a versão $versao não foi escrita.');
      }
      await passo(db);
    }
  }

  // v1 -> v2: avaliações das sessões.
  static Future<void> _v2(DatabaseExecutor db) async {
    await db.execute(DatabaseSchema.avaliacoes);
    await db.execute(DatabaseSchema.idxAvaliacoes);
  }

  // v2 -> v3: preço da sessão + proteção contra horário duplicado.
  static Future<void> _v3(DatabaseExecutor db) async {
    await _adicionarColuna(db, 'usuarios', 'valor_sessao_centavos', 'INTEGER');
    await _adicionarColuna(db, 'sessoes', 'valor_centavos', 'INTEGER NOT NULL DEFAULT 0');

    // Bancos antigos podem ter duplicatas (o app só conferia ANTES de gravar). O índice único
    // não nasce com duplicatas, então a mais nova de cada horário é marcada como cancelada
    // (nada é apagado; o histórico e as anotações continuam lá).
    for (final coluna in const ['profissional_id', 'paciente_id']) {
      await db.execute('''
        UPDATE sessoes SET status = 'cancelada'
        WHERE status <> 'cancelada'
          AND id NOT IN (
            SELECT MIN(id) FROM sessoes WHERE status <> 'cancelada' GROUP BY $coluna, data_hora
          )
      ''');
    }
    await db.execute(DatabaseSchema.idxSessaoProfissionalUnico);
    await db.execute(DatabaseSchema.idxSessaoPacienteUnico);
  }

  // v3 -> v4: LGPD (aceite dos termos e anonimização) + fila offline + cache de leitura.
  static Future<void> _v4(DatabaseExecutor db) async {
    await _adicionarColuna(db, 'usuarios', 'aceite_termos_versao', 'TEXT');
    await _adicionarColuna(db, 'usuarios', 'aceite_termos_em', 'TEXT');
    await _adicionarColuna(db, 'usuarios', 'anonimizado_em', 'TEXT');
    await db.execute(DatabaseSchema.outbox);
    await db.execute(DatabaseSchema.idxOutbox);
    await db.execute(DatabaseSchema.cacheKv);
  }

  // v4 -> v5: a fila passa a aceitar os tipos 'humor' e 'perfil'. Na v4 o CHECK só permitia
  // 'agendar', 'status' e 'remarcar': gravar humor ou cadastro offline era recusado pelo banco.
  // O SQLite não altera CHECK; por isso a tabela é recriada COPIANDO as ações pendentes (nada se perde).
  // Repetível: se a tabela já está no formato novo (instalação nova ou migração repetida), não faz nada.
  static Future<void> _v5(DatabaseExecutor db) async {
    final atual = await db.rawQuery("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'outbox'");
    final ddl = atual.isEmpty ? '' : (atual.first['sql'] as String? ?? '');
    if (atual.isEmpty || ddl.contains("'perfil'")) return;
    await db.execute('DROP INDEX IF EXISTS idx_outbox_usuario');
    await db.execute('ALTER TABLE outbox RENAME TO outbox_antiga');
    await db.execute(DatabaseSchema.outbox);
    await db.execute('''
      INSERT INTO outbox (id, usuario_id, tipo, payload, chave, estado, tentativas, ultimo_erro, criado_em)
      SELECT id, usuario_id, tipo, payload, chave, estado, tentativas, ultimo_erro, criado_em FROM outbox_antiga
    ''');
    await db.execute('DROP TABLE outbox_antiga');
    await db.execute(DatabaseSchema.idxOutbox);
  }

  /// `ADD COLUMN` que não falha se a coluna já existir (migração repetível).
  /// Os nomes vêm só deste arquivo (constantes), nunca de entrada do usuário.
  static Future<void> _adicionarColuna(
    DatabaseExecutor db,
    String tabela,
    String coluna,
    String definicao,
  ) async {
    final colunas = await db.rawQuery('PRAGMA table_info($tabela)');
    if (colunas.any((c) => c['name'] == coluna)) return;
    await db.execute('ALTER TABLE $tabela ADD COLUMN $coluna $definicao');
  }
}
