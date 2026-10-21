import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/data/local/sessao_repository_local.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/banco_de_teste.dart';

void main() {
  setUpAll(iniciarSqliteDeTeste);

  late Database db;
  late SessaoRepositoryLocal repo;
  late int ana;
  late int bia;
  late int doutor;
  late DateTime amanha10h;

  setUp(() async {
    db = await abrirBancoNovo();
    repo = SessaoRepositoryLocal(abrirBanco: () async => db);
    ana = await novoUsuario(db, 'Ana', 'paciente');
    bia = await novoUsuario(db, 'Bia', 'paciente');
    doutor = await novoUsuario(db, 'Doutor', 'profissional', valorCentavos: 15000);
    final h = DateTime.now().add(const Duration(days: 1));
    amanha10h = DateTime(h.year, h.month, h.day, 10);
  });

  tearDown(() => db.close());

  Future<int> agendar(int paciente, DateTime quando) => repo.agendar(
        pacienteId: paciente,
        profissionalId: doutor,
        dataHora: quando,
        modalidade: 'Online',
      );

  test('agenda e congela o preço vigente', () async {
    final id = await agendar(ana, amanha10h);
    await db.update('usuarios', {'valor_sessao_centavos': 99900}, where: 'id = ?', whereArgs: [doutor]);
    final linha = (await db.query('sessoes', where: 'id = ?', whereArgs: [id])).single;
    expect(linha['valor_centavos'], 15000); // mudar o preço depois não afeta a sessão já marcada
  });

  test('mesmo horário com o mesmo profissional -> ConflitoException', () async {
    await agendar(ana, amanha10h);
    await expectLater(() => agendar(bia, amanha10h), throwsA(isA<ConflitoException>()));
  });

  test('o paciente também não pode ter duas sessões no mesmo horário', () async {
    final outro = await novoUsuario(db, 'Outro', 'profissional');
    await agendar(ana, amanha10h);
    await expectLater(
      () => repo.agendar(pacienteId: ana, profissionalId: outro, dataHora: amanha10h, modalidade: 'Online'),
      throwsA(isA<ConflitoException>()),
    );
  });

  test('o índice único do BANCO barra a duplicata mesmo sem passar pela checagem', () async {
    await agendar(ana, amanha10h);
    final linha = {
      'paciente_id': bia,
      'profissional_id': doutor,
      'data_hora': amanha10h.toIso8601String(),
      'modalidade': 'Online',
      'status': 'agendada',
      'criado_em': DateTime.now().toIso8601String(),
    };
    await expectLater(
      () => db.insert('sessoes', linha),
      throwsA(isA<DatabaseException>().having((e) => e.isUniqueConstraintError(), 'unique', isTrue)),
    );
    // Cancelada não ocupa horário.
    await db.insert('sessoes', {...linha, 'status': 'cancelada'});
  });

  test('cancelar libera o horário', () async {
    final id = await agendar(ana, amanha10h);
    await repo.atualizarStatus(id, StatusSessao.cancelada);
    await agendar(bia, amanha10h); // não lança
    expect(await repo.horasOcupadas(doutor, amanha10h), {10});
  });

  test('remarcar para horário ocupado falha e mantém a sessão onde estava', () async {
    await agendar(ana, amanha10h);
    final id = await agendar(bia, amanha10h.add(const Duration(hours: 1)));
    await expectLater(() => repo.remarcar(id, amanha10h), throwsA(isA<ConflitoException>()));
    final linha = (await db.query('sessoes', where: 'id = ?', whereArgs: [id])).single;
    expect(linha['data_hora'], amanha10h.add(const Duration(hours: 1)).toIso8601String());
  });

  test('remarcar para horário livre funciona', () async {
    final id = await agendar(ana, amanha10h);
    await repo.remarcar(id, amanha10h.add(const Duration(hours: 2)));
    expect(await repo.horasOcupadas(doutor, amanha10h), {12});
  });

  test('horário no passado é recusado', () async {
    await expectLater(
      () => agendar(ana, DateTime.now().subtract(const Duration(hours: 1))),
      throwsA(isA<AppException>()),
    );
  });

  test('duas tentativas SIMULTÂNEAS: só uma grava, a outra recebe conflito', () async {
    final resultados = await Future.wait([
      agendar(ana, amanha10h).then<Object>((id) => id).catchError((Object e) => e),
      agendar(bia, amanha10h).then<Object>((id) => id).catchError((Object e) => e),
    ]);
    expect(resultados.whereType<int>(), hasLength(1));
    expect(resultados.whereType<ConflitoException>(), hasLength(1));
    expect(await db.query('sessoes'), hasLength(1));
  });
}
