import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/paciente_providers.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/screens/paciente/paciente_inicio_tab.dart';
import 'package:mente_saudavel/services/auth_service.dart';

import 'helpers/fakes.dart';

void main() {
  late FakeSessaoRepository repo;

  setUp(() {
    repo = FakeSessaoRepository([
      sessaoDeTeste('Dra. Marta', StatusSessao.agendada, dia: 20),
      sessaoDeTeste('Dr. Paulo', StatusSessao.concluida, dia: 5),
      sessaoDeTeste('Dr. Paulo', StatusSessao.concluida, dia: 6),
      sessaoDeTeste('Outra pessoa', StatusSessao.agendada, pacienteId: 2, dia: 2),
    ]);
    AuthService.atual.value = pacienteDeTeste();
  });

  tearDown(() => AuthService.atual.value = null);

  ProviderContainer novoContainer() {
    final c = ProviderContainer(overrides: [sessaoRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    return c;
  }

  group('provider', () {
    test('traz a próxima sessão e o total de concluídas da pessoa logada', () async {
      final d = await novoContainer().read(inicioPacienteProvider.future);
      expect(d.proxima?.profissionalNome, 'Dra. Marta');
      expect(d.concluidas, 2);
    });

    test('trocar de conta mostra os dados da nova conta', () async {
      final c = novoContainer();
      await c.read(inicioPacienteProvider.future);
      AuthService.atual.value = pacienteDeTeste(id: 2);
      final d = await c.read(inicioPacienteProvider.future);
      expect(d.proxima?.profissionalNome, 'Outra pessoa');
      expect(d.concluidas, 0);
    });

    test('falha do repositório vira AsyncError', () async {
      final c = novoContainer();
      repo.falhar = Exception('sem rede');
      await expectLater(c.read(inicioPacienteProvider.future), throwsException);
    });
  });

  group('tela', () {
    Future<void> abrir(WidgetTester t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [sessaoRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(home: PacienteInicioTab(onVerSessoes: () {})),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('mostra saudação, próxima sessão e concluídas', (t) async {
      await abrir(t);
      expect(find.text('Olá, Ana!'), findsOneWidget);
      expect(find.text('Dra. Marta'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // sessões concluídas
    });

    testWidgets('sem sessão futura oferece "Agendar agora"', (t) async {
      repo.sessoes.removeWhere((s) => s.status == StatusSessao.agendada);
      await abrir(t);
      expect(find.text('Você não tem sessões agendadas.'), findsOneWidget);
      expect(find.text('Agendar agora'), findsOneWidget);
    });

    testWidgets('erro mostra "Tentar novamente", que recarrega', (t) async {
      repo.falhar = Exception('sem rede');
      await abrir(t);
      expect(find.text('Erro ao carregar seus dados.'), findsOneWidget);
      await t.tap(find.text('Tentar novamente'));
      await t.pumpAndSettle();
      expect(find.text('Dra. Marta'), findsOneWidget);
    });
  });
}
