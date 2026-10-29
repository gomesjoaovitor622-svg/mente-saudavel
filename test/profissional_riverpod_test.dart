import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/profissional_providers.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/screens/profissional/agenda_tab.dart';
import 'package:mente_saudavel/screens/profissional/pacientes_tab.dart';
import 'package:mente_saudavel/services/auth_service.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeSessaoRepository repo;
  final hoje = DateTime.now();

  Sessao sessaoNoDia(String paciente, DateTime dia, {int profissionalId = 99}) => Sessao(
        id: paciente.hashCode,
        pacienteId: 1,
        profissionalId: profissionalId,
        dataHora: DateTime(dia.year, dia.month, dia.day, 10),
        modalidade: 'Online',
        status: StatusSessao.agendada,
        pacienteNome: paciente,
      );

  setUp(() {
    repo = FakeSessaoRepository([
      sessaoNoDia('Carlos', hoje),
      sessaoNoDia('Beatriz', hoje.add(const Duration(days: 1))),
      sessaoNoDia('De outro profissional', hoje, profissionalId: 7),
    ])
      ..pacientes.addAll([
        pacienteResumoDeTeste('Ana Souza', id: 1),
        pacienteResumoDeTeste('Bruno Lima', id: 2, email: 'bruno@clinica.com'),
      ]);
    AuthService.atual.value = profissionalDeTeste();
  });

  tearDown(() => AuthService.atual.value = null);

  ProviderContainer novoContainer() {
    final c = ProviderContainer(overrides: [sessaoRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> abrir(WidgetTester t, Widget tela) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [sessaoRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: tela),
      ),
    );
    await t.pumpAndSettle();
  }

  group('agenda (provider)', () {
    test('traz só as sessões do profissional logado, no dia escolhido', () async {
      final c = novoContainer();
      final lista = await c.read(agendaSessoesProvider.future);
      expect(lista.map((s) => s.pacienteNome), ['Carlos']);
    });

    test('trocar o dia recarrega sozinho', () async {
      final c = novoContainer();
      await c.read(agendaSessoesProvider.future);
      c.read(agendaDiaProvider.notifier).state = DateTime(hoje.year, hoje.month, hoje.day + 1);
      final lista = await c.read(agendaSessoesProvider.future);
      expect(lista.map((s) => s.pacienteNome), ['Beatriz']);
    });

    test('trocar de conta recarrega e volta para hoje (isolamento entre contas)', () async {
      final c = novoContainer();
      await c.read(agendaSessoesProvider.future);
      c.read(agendaDiaProvider.notifier).state = DateTime(2031, 5, 5);
      AuthService.atual.value = profissionalDeTeste(id: 7);
      final lista = await c.read(agendaSessoesProvider.future);
      expect(lista.map((s) => s.pacienteNome), ['De outro profissional']);
      expect(c.read(agendaDiaProvider).day, hoje.day);
    });

    test('falha do repositório vira AsyncError', () async {
      final c = novoContainer();
      repo.falhar = Exception('sem rede');
      await expectLater(c.read(agendaSessoesProvider.future), throwsException);
      expect(c.read(agendaSessoesProvider).hasError, isTrue);
    });

    test('sem usuário logado nem consulta o repositório', () async {
      AuthService.atual.value = null;
      final c = novoContainer();
      expect(await c.read(agendaSessoesProvider.future), isEmpty);
      expect(repo.consultas, 0);
    });
  });

  group('pacientes (provider)', () {
    test('busca por nome ou e-mail, sem diferenciar maiúsculas', () async {
      final c = novoContainer();
      await c.read(pacientesProvider.future);
      c.read(buscaPacientesProvider.notifier).state = 'ANA';
      expect(c.read(pacientesFiltradosProvider).value!.map((p) => p.nome), ['Ana Souza']);
      c.read(buscaPacientesProvider.notifier).state = 'clinica.com';
      expect(c.read(pacientesFiltradosProvider).value!.map((p) => p.nome), ['Bruno Lima']);
      c.read(buscaPacientesProvider.notifier).state = 'zzz';
      expect(c.read(pacientesFiltradosProvider).value, isEmpty);
    });

    test('a busca digitada some quando troca a conta', () async {
      final c = novoContainer();
      c.read(buscaPacientesProvider.notifier).state = 'ana';
      AuthService.atual.value = profissionalDeTeste(id: 7);
      expect(c.read(buscaPacientesProvider), '');
    });
  });

  group('telas', () {
    testWidgets('agenda lista o dia, navega para o dia seguinte e volta com "Hoje"', (t) async {
      await abrir(t, const AgendaTab());
      expect(find.text('Carlos'), findsOneWidget);
      expect(find.text('Beatriz'), findsNothing);
      expect(find.text('De outro profissional'), findsNothing);

      await t.tap(find.byTooltip('Próximo dia'));
      await t.pumpAndSettle();
      expect(find.text('Beatriz'), findsOneWidget);
      expect(find.text('Carlos'), findsNothing);

      await t.tap(find.text('Hoje'));
      await t.pumpAndSettle();
      expect(find.text('Carlos'), findsOneWidget);
    });

    testWidgets('agenda vazia mostra a mensagem', (t) async {
      repo.sessoes.clear();
      await abrir(t, const AgendaTab());
      expect(find.text('Nenhuma sessão neste dia.'), findsOneWidget);
    });

    testWidgets('agenda com erro oferece "Tentar novamente"', (t) async {
      repo.falhar = Exception('sem rede');
      await abrir(t, const AgendaTab());
      expect(find.text('Erro ao carregar a agenda.'), findsOneWidget);
      await t.tap(find.text('Tentar novamente'));
      await t.pumpAndSettle();
      expect(find.text('Carlos'), findsOneWidget);
    });

    testWidgets('pacientes: lista, busca e mensagem de "não encontrado"', (t) async {
      await abrir(t, const PacientesTab());
      expect(find.text('Ana Souza'), findsOneWidget);
      expect(find.text('Bruno Lima'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'bruno');
      await t.pumpAndSettle();
      expect(find.text('Ana Souza'), findsNothing);
      expect(find.text('Bruno Lima'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'nada');
      await t.pumpAndSettle();
      expect(find.text('Nenhum paciente encontrado.'), findsOneWidget);

      await t.tap(find.byTooltip('Limpar busca'));
      await t.pumpAndSettle();
      expect(find.text('Ana Souza'), findsOneWidget);
    });

    testWidgets('pacientes: lista vazia explica como os pacientes aparecem', (t) async {
      repo.pacientes.clear();
      await abrir(t, const PacientesTab());
      expect(find.textContaining('Você ainda não tem pacientes'), findsOneWidget);
    });

    testWidgets('pacientes com erro oferece "Tentar novamente"', (t) async {
      repo.falhar = Exception('sem rede');
      await abrir(t, const PacientesTab());
      expect(find.text('Erro ao carregar os pacientes.'), findsOneWidget);
      await t.tap(find.text('Tentar novamente'));
      await t.pumpAndSettle();
      expect(find.text('Ana Souza'), findsOneWidget);
    });
  });
}
