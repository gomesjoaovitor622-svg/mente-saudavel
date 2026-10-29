import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/screens/paciente/minhas_sessoes_tab.dart';
import 'package:mente_saudavel/services/auth_service.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeSessaoRepository repo;

  setUp(() {
    repo = FakeSessaoRepository([
      sessaoDeTeste('Dra. Marta', StatusSessao.agendada),
      sessaoDeTeste('Dr. Paulo', StatusSessao.concluida, dia: 5),
      sessaoDeTeste('Outra pessoa', StatusSessao.agendada, pacienteId: 2),
    ]);
    AuthService.atual.value = pacienteDeTeste();
  });

  tearDown(() => AuthService.atual.value = null);

  ProviderContainer novoContainer() {
    final c = ProviderContainer(overrides: [sessaoRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    return c;
  }

  group('provider (sem tela)', () {
    test('traz só as sessões do usuário logado', () async {
      final c = novoContainer();
      final lista = await c.read(minhasSessoesProvider.future);
      expect(lista.map((s) => s.profissionalNome), ['Dra. Marta', 'Dr. Paulo']);
    });

    test('trocar o filtro recarrega sozinho', () async {
      final c = novoContainer();
      await c.read(minhasSessoesProvider.future);
      c.read(filtroSessoesProvider.notifier).state = StatusSessao.concluida;
      final lista = await c.read(minhasSessoesProvider.future);
      expect(lista.map((s) => s.profissionalNome), ['Dr. Paulo']);
    });

    test('invalidate busca de novo (é o que a tela de agendar faz ao gravar)', () async {
      final c = novoContainer();
      await c.read(minhasSessoesProvider.future);
      final antes = repo.consultas;
      repo.sessoes.add(sessaoDeTeste('Nova', StatusSessao.agendada, dia: 20));
      c.invalidate(minhasSessoesProvider);
      final lista = await c.read(minhasSessoesProvider.future);
      expect(repo.consultas, antes + 1);
      expect(lista, hasLength(3));
    });

    test('falha do repositório vira AsyncError (não derruba o app)', () async {
      final c = novoContainer();
      repo.falhar = Exception('sem rede');
      await expectLater(c.read(minhasSessoesProvider.future), throwsException);
      expect(c.read(minhasSessoesProvider).hasError, isTrue);
    });

    test('sem usuário logado a lista é vazia e o repositório nem é consultado', () async {
      AuthService.atual.value = null;
      final c = novoContainer();
      expect(await c.read(minhasSessoesProvider.future), isEmpty);
      expect(repo.consultas, 0);
    });

    test('trocar de conta recarrega a lista da nova conta', () async {
      final c = novoContainer();
      await c.read(minhasSessoesProvider.future);
      AuthService.atual.value = pacienteDeTeste(id: 2);
      final lista = await c.read(minhasSessoesProvider.future);
      expect(lista.map((s) => s.profissionalNome), ['Outra pessoa']);
    });
  });

  group('tela', () {
    Future<void> abrir(WidgetTester t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [sessaoRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: MinhasSessoesTab()),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('lista as sessões e filtra pelos chips', (t) async {
      await abrir(t);
      expect(find.text('Dra. Marta'), findsOneWidget);
      expect(find.text('Dr. Paulo'), findsOneWidget);

      await t.tap(find.text('Concluídas'));
      await t.pumpAndSettle();
      expect(find.text('Dra. Marta'), findsNothing);
      expect(find.text('Dr. Paulo'), findsOneWidget);
    });

    testWidgets('mostra a mensagem de lista vazia', (t) async {
      repo.sessoes.clear();
      await abrir(t);
      expect(find.textContaining('Nenhuma sessão encontrada'), findsOneWidget);
    });

    testWidgets('erro mostra "Tentar novamente", que recarrega', (t) async {
      repo.falhar = Exception('sem rede');
      await abrir(t);
      expect(find.text('Erro ao carregar as sessões.'), findsOneWidget);

      await t.tap(find.text('Tentar novamente'));
      await t.pumpAndSettle();
      expect(find.text('Dra. Marta'), findsOneWidget);
    });
  });
}
