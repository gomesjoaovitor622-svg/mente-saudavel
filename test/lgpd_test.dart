import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/database/usuario_dao.dart';
import 'package:mente_saudavel/legal/textos_legais.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/screens/termos_screen.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/services/consentimento_service.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/ambiente_local.dart';
import 'helpers/banco_de_teste.dart';

void main() {
  setUpAll(() => iniciarSqliteDeTeste(semIsolate: true));

  const senha = 'Senh@-Forte-2026';

  setUp(prepararBancoLocal);
  tearDown(() => AuthService.atual.value = null);

  group('aceite dos termos', () {
    test('o aparelho só vale como "aceito" para a versão atual dos textos', () async {
      SharedPreferences.setMockInitialValues({});
      await Consentimento.carregar();
      expect(Consentimento.aceitoNoAparelho.value, isFalse); // primeiro acesso

      await Consentimento.aceitarNoAparelho();
      Consentimento.aceitoNoAparelho.value = false;
      await Consentimento.carregar();
      expect(Consentimento.aceitoNoAparelho.value, isTrue); // lembrou

      SharedPreferences.setMockInitialValues({'ms_aceite_versao': 'versao-antiga'});
      await Consentimento.carregar();
      expect(Consentimento.aceitoNoAparelho.value, isFalse); // textos mudaram: pede de novo
    });

    test('o cadastro local grava a versão aceita na conta; registrarAceite atualiza contas antigas', () async {
      final nova = await AuthService.cadastrar(nome: 'Ana', email: 'ana@t.com', senha: senha, perfil: Perfil.paciente);
      expect(nova.aceiteTermosVersao, kVersaoTermos);

      // Conta criada antes da LGPD: sem aceite registrado.
      final dao = UsuarioDao();
      final id = await dao.inserir(Usuario(
        nome: 'Antiga', email: 'antiga@t.com', senhaHash: 'x', salt: 'y', perfil: Perfil.paciente, criadoEm: '2020-01-01T00:00:00',
      ));
      AuthService.atual.value = await dao.buscarPorId(id);
      expect(AuthService.atual.value!.aceiteTermosVersao, isNull);
      await AuthService.registrarAceite();
      expect(AuthService.atual.value!.aceiteTermosVersao, kVersaoTermos);
      expect((await dao.buscarPorId(id))!.aceiteTermosVersao, kVersaoTermos);
    });

    testWidgets('a tela de aceite só libera o botão depois de marcar a caixa', (t) async {
      var aceitou = 0;
      await t.pumpWidget(MaterialApp(home: TermosScreen(aoAceitar: () async => aceitou++)));

      FilledButton botao() => t.widget<FilledButton>(find.byKey(const Key('botao-aceitar')));
      expect(botao().onPressed, isNull);

      await t.tap(find.byKey(const Key('aceite-termos')));
      await t.pump();
      expect(botao().onPressed, isNotNull);

      await t.tap(find.byKey(const Key('botao-aceitar')));
      await t.pump();
      expect(aceitou, 1);
    });

    testWidgets('os textos legais abrem a partir da tela de aceite', (t) async {
      await t.pumpWidget(MaterialApp(home: TermosScreen(aoAceitar: () async {})));
      await t.tap(find.text('Ler a Política de Privacidade'));
      await t.pumpAndSettle();
      expect(find.text('Política de Privacidade'), findsOneWidget);
      expect(find.textContaining('dados SENSÍVEIS'), findsOneWidget);
    });

    testWidgets('falha ao registrar o aceite mostra mensagem e mantém a tela', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: TermosScreen(aoAceitar: () async => throw const AppException('Sem conexão.')))));
      await t.tap(find.byKey(const Key('aceite-termos')));
      await t.pump();
      await t.tap(find.byKey(const Key('botao-aceitar')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Sem conexão.'), findsOneWidget);
      expect(find.byKey(const Key('botao-aceitar')), findsOneWidget);
    });
  });

  group('direito ao esquecimento (banco local)', () {
    Future<(int pac, int pro, int sessaoPassada, int sessaoFutura)> cenario() async {
      final pro = await AuthService.cadastrar(
        nome: 'Dra. Marta', email: 'marta@t.com', senha: senha, perfil: Perfil.profissional, registro: '06/1',
      );
      final pac = await AuthService.cadastrar(nome: 'Ana Souza', email: 'ana@t.com', senha: senha, perfil: Perfil.paciente);
      final db = await DatabaseHelper.instance.database;
      final futuro = DateTime.now().add(const Duration(days: 3)).toIso8601String();
      final passado = DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
      Future<int> sessao(String quando, String status) => db.insert('sessoes', {
            'paciente_id': pac.id, 'profissional_id': pro.id, 'data_hora': quando, 'modalidade': 'Online',
            'status': status, 'anotacoes': 'nota clínica do profissional', 'criado_em': passado,
          });
      final concluida = await sessao(passado, 'concluida');
      final agendada = await sessao(futuro, 'agendada');
      await db.insert('humor_registros', {'usuario_id': pac.id, 'nivel': 2, 'nota': 'dia difícil', 'data_hora': passado});
      await db.insert('avaliacoes', {
        'sessao_id': concluida, 'paciente_id': pac.id, 'profissional_id': pro.id, 'nota': 5,
        'comentario': 'falei do meu pai', 'criado_em': passado,
      });
      AuthService.atual.value = pac;
      return (pac.id!, pro.id!, concluida, agendada);
    }

    test('anonimiza o paciente, apaga humor e comentário, cancela futuras e mantém o histórico', () async {
      final (pac, _, concluida, agendada) = await cenario();
      await AuthService.anonimizarConta(senha);
      final db = await DatabaseHelper.instance.database;

      final u = (await db.query('usuarios', where: 'id = ?', whereArgs: [pac])).single;
      expect(u['nome'], 'Paciente anonimizado');
      expect(u['email'], 'anonimizado-$pac@anonimizado.invalid');
      expect(u['anonimizado_em'], isNotNull);
      expect(await db.query('humor_registros', where: 'usuario_id = ?', whereArgs: [pac]), isEmpty);
      expect((await db.query('avaliacoes')).single['comentario'], '');
      expect((await db.query('sessoes', where: 'id = ?', whereArgs: [agendada])).single['status'], 'cancelada');
      final passada = (await db.query('sessoes', where: 'id = ?', whereArgs: [concluida])).single;
      expect(passada['status'], 'concluida'); // histórico do profissional preservado
      expect(passada['anotacoes'], 'nota clínica do profissional');
      expect(AuthService.atual.value, isNull); // sessão encerrada
    });

    test('depois de anonimizada, ninguém consegue entrar na conta, nem com a senha antiga', () async {
      await cenario();
      await AuthService.anonimizarConta(senha);
      await expectLater(AuthService.entrar('ana@t.com', senha), throwsA(isA<AppException>()));
      await expectLater(AuthService.entrar('anonimizado-2@anonimizado.invalid', senha), throwsA(isA<AppException>()));
    });

    test('senha errada não anonimiza nada', () async {
      final (pac, _, _, _) = await cenario();
      await expectLater(AuthService.anonimizarConta('senha-errada-123'), throwsA(isA<AppException>()));
      final db = await DatabaseHelper.instance.database;
      expect((await db.query('usuarios', where: 'id = ?', whereArgs: [pac])).single['nome'], 'Ana Souza');
      expect(AuthService.atual.value, isNotNull);
    });

    test('profissional não usa a anonimização (os pacientes dependem do histórico)', () async {
      await cenario();
      AuthService.atual.value = await UsuarioDao().buscarPorEmail('marta@t.com');
      await expectLater(AuthService.anonimizarConta(senha), throwsA(isA<AppException>()));
    });

    test('é tudo ou nada: se algo falha no meio, nada fica pela metade', () async {
      final (pac, _, _, _) = await cenario();
      final db = await DatabaseHelper.instance.database;
      // Gatilho que faz o UPDATE final dos usuários falhar, DEPOIS de apagar o humor.
      await db.execute("CREATE TRIGGER falha BEFORE UPDATE ON usuarios BEGIN SELECT RAISE(ABORT, 'falha de teste'); END");
      await expectLater(UsuarioDao().anonimizar(pac), throwsA(isA<DatabaseException>()));
      expect(await db.query('humor_registros', where: 'usuario_id = ?', whereArgs: [pac]), hasLength(1));
      expect((await db.query('avaliacoes')).single['comentario'], 'falei do meu pai');
    });
  });
}
