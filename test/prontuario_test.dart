import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/models/prontuario.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/prontuario_providers.dart';
import 'package:mente_saudavel/screens/profissional/prontuario_screen.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/services/prontuario_api.dart';
import 'package:mente_saudavel/utils/app_exception.dart';

import 'helpers/fakes.dart';

/// Servidor de prontuário falso, em memória.
class FakeProntuarioApi extends ProntuarioApi {
  final List<EntradaProntuario> registros = [];
  final Map<int, List<RevisaoProntuario>> historico = {};
  Object? falhar;
  int listagens = 0;
  int _proximo = 1;

  void _talvezFalhar() {
    final erro = falhar;
    if (erro != null) {
      falhar = null;
      throw erro;
    }
  }

  @override
  Future<List<EntradaProntuario>> listar(int pacienteId) async {
    listagens++;
    _talvezFalhar();
    return registros.where((e) => e.pacienteId == pacienteId).toList();
  }

  @override
  Future<EntradaProntuario> criar(int pacienteId, {required String tipo, required String conteudo, int? sessaoId}) async {
    _talvezFalhar();
    final e = EntradaProntuario(
      id: _proximo++,
      pacienteId: pacienteId,
      tipo: tipo,
      conteudo: conteudo,
      versao: 1,
      criadoEm: DateTime(2031, 1, 12, 10),
      atualizadoEm: DateTime(2031, 1, 12, 10),
    );
    registros.insert(0, e);
    return e;
  }

  @override
  Future<EntradaProntuario> editar(int entradaId, {required String conteudo, required int versaoEsperada}) async {
    _talvezFalhar();
    final i = registros.indexWhere((e) => e.id == entradaId);
    final atual = registros[i];
    if (atual.versao != versaoEsperada) {
      throw const ConflitoException('Este registro foi alterado em outro lugar. Recarregue e edite de novo.');
    }
    historico.putIfAbsent(entradaId, () => []).add(RevisaoProntuario(versao: atual.versao, conteudo: atual.conteudo, substituidaEm: DateTime(2031, 1, 13)));
    final novo = EntradaProntuario(
      id: atual.id,
      pacienteId: atual.pacienteId,
      tipo: atual.tipo,
      conteudo: conteudo,
      versao: atual.versao + 1,
      criadoEm: atual.criadoEm,
      atualizadoEm: DateTime(2031, 1, 13),
    );
    registros[i] = novo;
    return novo;
  }

  @override
  Future<List<RevisaoProntuario>> revisoes(int entradaId) async => historico[entradaId] ?? [];
}

void main() {
  late FakeProntuarioApi api;
  const paciente = PacienteResumo(id: 5, nome: 'Ana Souza', email: 'ana@teste.com', totalSessoes: 3, concluidas: 1);

  EntradaProntuario entrada(String texto, {int id = 100, int versao = 1, int pacienteId = 5}) => EntradaProntuario(
        id: id,
        pacienteId: pacienteId,
        tipo: TipoProntuario.evolucao,
        conteudo: texto,
        versao: versao,
        criadoEm: DateTime(2031, 1, 10, 9),
        atualizadoEm: DateTime(2031, 1, 10, 9),
      );

  setUp(() {
    api = FakeProntuarioApi();
    AuthService.atual.value = profissionalDeTeste();
  });

  tearDown(() => AuthService.atual.value = null);

  ProviderContainer novoContainer() {
    final c = ProviderContainer(overrides: [prontuarioApiProvider.overrideWithValue(api)]);
    addTearDown(c.dispose);
    return c;
  }

  group('modelo', () {
    test('lê a resposta do servidor', () {
      final e = EntradaProntuario.fromMap({
        'id': 1,
        'paciente_id': 5,
        'sessao_id': null,
        'tipo': 'anamnese',
        'conteudo': 'texto',
        'versao': 2,
        'criado_em': '2031-01-12T10:00:00',
        'atualizado_em': '2031-01-13T10:00:00',
      });
      expect(e.editado, isTrue);
      expect(e.sessaoId, isNull);
      expect(TipoProntuario.rotulo(e.tipo), 'Anamnese');
    });
  });

  group('provider', () {
    test('lista só os registros do paciente pedido', () async {
      api.registros.addAll([entrada('A', id: 1), entrada('B', id: 2, pacienteId: 9)]);
      final lista = await novoContainer().read(prontuarioProvider(5).future);
      expect(lista.map((e) => e.conteudo), ['A']);
    });

    test('criar e editar recarregam a lista', () async {
      final c = novoContainer();
      await c.read(prontuarioProvider(5).future);
      await c.read(prontuarioProvider(5).notifier).criar(tipo: TipoProntuario.evolucao, conteudo: 'Primeiro');
      var lista = await c.read(prontuarioProvider(5).future);
      expect(lista.single.conteudo, 'Primeiro');
      await c.read(prontuarioProvider(5).notifier).editar(lista.single, 'Primeiro (revisado)');
      lista = await c.read(prontuarioProvider(5).future);
      expect(lista.single.conteudo, 'Primeiro (revisado)');
      expect(lista.single.versao, 2);
    });

    test('editar com versão antiga dá conflito (edição feita em outro aparelho)', () async {
      api.registros.add(entrada('Texto', versao: 3));
      final c = novoContainer();
      final lista = await c.read(prontuarioProvider(5).future);
      final desatualizada = entrada('Texto', versao: 2);
      await expectLater(
        c.read(prontuarioProvider(5).notifier).editar(desatualizada, 'Novo'),
        throwsA(isA<ConflitoException>()),
      );
      expect(lista.single.conteudo, 'Texto');
    });

    test('sem usuário logado nada é pedido ao servidor', () async {
      AuthService.atual.value = null;
      expect(await novoContainer().read(prontuarioProvider(5).future), isEmpty);
      expect(api.listagens, 0);
    });

    test('o conteúdo sai da memória quando ninguém mais observa (autoDispose)', () async {
      api.registros.add(entrada('Sigiloso'));
      final c = novoContainer();
      final sub = c.listen(prontuarioProvider(5), (_, __) {});
      await c.read(prontuarioProvider(5).future);
      expect(api.listagens, 1);
      sub.close();
      await Future<void>.delayed(Duration.zero);
      await c.read(prontuarioProvider(5).future); // nova leitura = novo pedido ao servidor
      expect(api.listagens, 2);
    });

    test('trocar de conta recarrega', () async {
      final c = novoContainer();
      final sub = c.listen(prontuarioProvider(5), (_, __) {});
      addTearDown(sub.close);
      await c.read(prontuarioProvider(5).future);
      AuthService.atual.value = profissionalDeTeste(id: 7);
      await c.read(prontuarioProvider(5).future);
      expect(api.listagens, 2);
    });
  });

  group('tela', () {
    Future<void> abrir(WidgetTester t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [prontuarioApiProvider.overrideWithValue(api)],
          child: const MaterialApp(home: ProntuarioScreen(paciente: paciente)),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('lista vazia explica como começar e avisa que só o psicólogo vê', (t) async {
      await abrir(t);
      expect(find.textContaining('Nenhum registro ainda'), findsOneWidget);
      expect(find.textContaining('Só você vê estes registros'), findsOneWidget);
    });

    testWidgets('cria um registro novo e ele aparece na lista', (t) async {
      await abrir(t);
      await t.tap(find.text('Novo registro'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Paciente relata melhora do sono.');
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(find.text('Paciente relata melhora do sono.'), findsOneWidget);
      expect(api.registros, hasLength(1));
    });

    testWidgets('não deixa salvar registro vazio', (t) async {
      await abrir(t);
      await t.tap(find.text('Novo registro'));
      await t.pumpAndSettle();
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(find.text('Escreva o registro antes de salvar.'), findsOneWidget);
      expect(api.registros, isEmpty);
    });

    testWidgets('edita um registro: sobe a versão e mostra o selo "v2"', (t) async {
      api.registros.add(entrada('Texto original'));
      await abrir(t);
      await t.tap(find.textContaining('Texto original'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Texto corrigido');
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(find.text('Texto corrigido'), findsOneWidget);
      expect(find.text('v2'), findsOneWidget);
    });

    testWidgets('conflito de versão aparece dentro do editor, sem perder o texto digitado', (t) async {
      api.registros.add(entrada('Texto', versao: 1));
      await abrir(t);
      await t.tap(find.textContaining('Texto'));
      await t.pumpAndSettle();
      // outro aparelho edita enquanto o editor está aberto
      api.registros[0] = entrada('Texto de outro aparelho', versao: 2);
      await t.enterText(find.byType(TextField), 'Minha edição');
      await t.tap(find.text('Salvar'));
      await t.pumpAndSettle();
      expect(find.textContaining('foi alterado em outro lugar'), findsOneWidget);
      expect(find.text('Minha edição'), findsOneWidget);
    });

    testWidgets('erro de carregamento oferece "Tentar novamente"', (t) async {
      api.falhar = const AppException('Paciente não encontrado.');
      await abrir(t);
      expect(find.text('Paciente não encontrado.'), findsOneWidget);
      await t.tap(find.text('Tentar novamente'));
      await t.pumpAndSettle();
      expect(find.textContaining('Nenhum registro ainda'), findsOneWidget);
    });
  });
}
