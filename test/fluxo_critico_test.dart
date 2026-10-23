import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/app/dependencias.dart';
import 'package:mente_saudavel/data/local/sessao_repository_local.dart';
import 'package:mente_saudavel/database/database_helper.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/screens/paciente/minhas_sessoes_tab.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/services/seguranca.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/relogio.dart';

import 'helpers/ambiente_local.dart';
import 'helpers/banco_de_teste.dart';

/// Fluxo crítico de ponta a ponta no app (banco SQLite real em memória, telas reais):
/// login com senha robusta -> agendar -> conflito (409) -> lista atualizada pelo provider.
void main() {
  setUpAll(() => iniciarSqliteDeTeste(semIsolate: true));

  const senhaForte = 'Senh@-Forte-2026';
  const quando = (ano: 2031, mes: 3, dia: 10);

  late Usuario profissional;
  late Usuario rival;
  late Usuario ana;

  setUp(() async {
    await prepararBancoLocal();
    // As contas são criadas aqui (fora do relógio falso do teste de widget): o hash PBKDF2 usa isolate.
    profissional = await AuthService.cadastrar(
      nome: 'Dra. Marta Lima',
      email: 'marta@t.com',
      senha: senhaForte,
      perfil: Perfil.profissional,
      registro: '06/12345',
    );
    await AuthService.sair();
    rival = await AuthService.cadastrar(nome: 'Rival', email: 'rival@t.com', senha: senhaForte, perfil: Perfil.paciente);
    await AuthService.sair();
    ana = await AuthService.cadastrar(nome: 'Ana Souza', email: 'ana@t.com', senha: senhaForte, perfil: Perfil.paciente);
    await AuthService.sair();

    // "Hoje" fixo: 10/03/2031 às 07:00. O seletor de data abre nesse dia e todos os horários estão livres.
    Relogio.fonte = () => DateTime(quando.ano, quando.mes, quando.dia, 7);
    Dependencias.configurar(Dependencias(sessoes: SessaoRepositoryLocal()));
  });

  tearDown(() {
    Relogio.restaurar();
    AuthService.atual.value = null;
  });

  test('login com senha robusta: a errada é recusada, a certa entra, e o hash guardado é PBKDF2', () async {
    await expectLater(AuthService.entrar('ana@t.com', 'senha-errada'), throwsA(isA<AppException>()));
    expect(AuthService.atual.value, isNull);

    await AuthService.entrar('ana@t.com', senhaForte);
    expect(AuthService.atual.value?.email, 'ana@t.com');

    final db = await DatabaseHelper.instance.database;
    final hash = (await db.query('usuarios', columns: ['senha_hash'], where: 'email = ?', whereArgs: ['ana@t.com'])).single['senha_hash']! as String;
    expect(hash, startsWith('${Seguranca.prefixo}\$'));
    expect(hash, isNot(contains(senhaForte)));
  });

  testWidgets('agendar -> conflito 409 -> outro horário -> a lista se atualiza pelo provider', (t) async {
    AuthService.atual.value = ana;
    final repo = SessaoRepositoryLocal();

    await t.pumpWidget(
      ProviderScope(
        overrides: [sessaoRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: MinhasSessoesTab()),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('Nenhuma sessão encontrada'), findsOneWidget);

    // Abre "Agendar", escolhe a profissional, a data (hoje, fixado) e as 10:00.
    await t.tap(find.text('Agendar'));
    await t.pumpAndSettle();
    await t.tap(find.text(profissional.nome));
    await t.pumpAndSettle();
    await t.tap(find.text('Escolher data'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await t.tap(find.text('10:00'));
    await t.pumpAndSettle();

    // Enquanto a tela está aberta, outra pessoa agenda o MESMO horário (corrida real).
    await repo.agendar(
      pacienteId: rival.id!,
      profissionalId: profissional.id!,
      dataHora: DateTime(quando.ano, quando.mes, quando.dia, 10),
      modalidade: 'Online',
    );

    // Confirmar -> ConflitoException (o mesmo caminho do HTTP 409): mensagem na tela, nada gravado para a Ana.
    await t.tap(find.text('Confirmar agendamento'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('já tem uma sessão'), findsOneWidget);
    expect(find.text('Agendar sessão'), findsOneWidget); // continua na tela de agendar
    expect(await repo.doPaciente(ana.id!), isEmpty);

    // Outro horário (11:00) funciona; ao voltar, o provider recarrega e a lista mostra a sessão nova.
    await t.tap(find.text('11:00'));
    await t.pumpAndSettle();
    await t.tap(find.text('Confirmar agendamento'));
    await t.pumpAndSettle();
    expect(find.text('Agendar sessão'), findsNothing); // voltou para "Minhas sessões"
    expect(find.text(profissional.nome), findsOneWidget); // cartão da sessão nova, sem recarregar à mão
    expect(find.textContaining('Nenhuma sessão encontrada'), findsNothing);
    expect(await repo.doPaciente(ana.id!), hasLength(1));
  });
}
