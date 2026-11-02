import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mente_saudavel/app/dependencias.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/presentation/providers/prontuario_providers.dart';
import 'package:mente_saudavel/screens/profissional/paciente_detalhe_screen.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/services/token_store.dart';
import 'package:mente_saudavel/services/video_service.dart';
import 'package:mente_saudavel/widgets/componentes.dart' show SessaoCard;
import 'package:mente_saudavel/widgets/sessao_sheet.dart';

import 'helpers/fakes.dart';
import 'prontuario_test.dart' show FakeProntuarioApi;

/// Armazenamento de token em memória: o seguro de verdade usa canal de plataforma, que não existe nos testes.
class _TokenMemoria implements TokenStore {
  String? valor = 'token-de-teste';
  @override
  Future<String?> ler() async => valor;
  @override
  Future<void> gravar(String token) async => valor = token;
  @override
  Future<void> apagar() async => valor = null;
}

http.Response _json(int status, Object corpo) =>
    http.Response.bytes(utf8.encode(jsonEncode(corpo)), status, headers: {'content-type': 'application/json; charset=utf-8'});

Sessao _sessao({String modalidade = Modalidade.online, String status = StatusSessao.agendada, bool pendente = false, int? id = 42}) => Sessao(
      id: id,
      pacienteId: 1,
      profissionalId: 99,
      dataHora: DateTime(2031, 1, 10, 10),
      modalidade: modalidade,
      status: status,
      pacienteNome: 'Ana Souza',
      profissionalNome: 'Dra. Marta',
      pendente: pendente,
    );

/// Tela com um botão que abre o painel da sessão (como a agenda faz).
Widget _app(Sessao s, {required bool servidor, bool profissional = true}) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => mostrarSessaoSheet(context, sessao: s, comoProfissional: profissional, servidor: servidor),
              child: const Text('abrir painel'),
            ),
          ),
        ),
      ),
    );

void main() {
  late List<http.Request> recebidas;
  late List<Uri> abertas;

  void servidor(http.Response Function(http.Request) resposta) {
    ApiClient.cliente = MockClient((req) async {
      recebidas.add(req);
      return resposta(req);
    });
  }

  setUp(() {
    recebidas = [];
    abertas = [];
    ApiClient.usaCookie = false;
    ApiClient.armazenamento = _TokenMemoria();
    Dependencias.configurar(Dependencias(sessoes: FakeSessaoRepository([])));
    AuthService.atual.value = profissionalDeTeste(id: 99);
    VideoService.abrir = (url) async {
      abertas.add(url);
      return true;
    };
  });

  tearDown(() async {
    await ApiClient.limparToken();
    ApiClient.cliente = http.Client();
    AuthService.atual.value = null;
    VideoService.abrir = (url) async => true;
  });

  Future<void> abrirPainel(WidgetTester t, Sessao s, {required bool servidor, bool profissional = true}) async {
    t.view.physicalSize = const Size(900, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(s, servidor: servidor, profissional: profissional));
    await t.tap(find.text('abrir painel'));
    await t.pumpAndSettle();
  }

  group('botão da videochamada no atendimento', () {
    testWidgets('sessão online agendada, no modo servidor: o PROFISSIONAL vê o botão', (t) async {
      await abrirPainel(t, _sessao(), servidor: true);
      expect(find.text('Entrar na videochamada'), findsOneWidget);
    });

    testWidgets('o paciente também vê o botão (a sala é a mesma)', (t) async {
      await abrirPainel(t, _sessao(), servidor: true, profissional: false);
      expect(find.text('Entrar na videochamada'), findsOneWidget);
    });

    testWidgets('não aparece em sessão presencial, cancelada, concluída, pendente de envio ou sem id', (t) async {
      for (final s in [
        _sessao(modalidade: Modalidade.presencial),
        _sessao(status: StatusSessao.cancelada),
        _sessao(status: StatusSessao.concluida),
        _sessao(pendente: true),
        _sessao(id: null),
      ]) {
        await abrirPainel(t, s, servidor: true);
        expect(find.text('Entrar na videochamada'), findsNothing, reason: '${s.modalidade}/${s.status}/pendente=${s.pendente}/id=${s.id}');
        await t.pumpWidget(const SizedBox()); // descarta o painel antes do próximo caso
      }
    });

    testWidgets('sem servidor (modo local) NÃO há link de vídeo: aparece só o aviso', (t) async {
      await abrirPainel(t, _sessao(), servidor: false);
      expect(find.text('Entrar na videochamada'), findsNothing);
      expect(find.textContaining('precisa do servidor'), findsOneWidget);
      expect(find.textContaining('meet.jit.si'), findsNothing);
    });

    testWidgets('toque: pede a sala ao servidor e abre o link com token no navegador', (t) async {
      servidor((_) => _json(200, {
            'url': 'https://video.exemplo.com/ms-abc?jwt=tok',
            'sala': 'ms-abc',
            'moderador': true,
            'expira_em': '2031-01-10T12:00:00',
          }));
      await abrirPainel(t, _sessao(), servidor: true);
      await t.tap(find.text('Entrar na videochamada'));
      await t.pumpAndSettle();
      expect(recebidas.single.url.path, endsWith('/sessoes/42/video'));
      expect(abertas.single.host, 'video.exemplo.com');
      expect(abertas.single.queryParameters['jwt'], 'tok');
    });

    testWidgets('sala ainda fechada: a mensagem do servidor aparece e nada é aberto', (t) async {
      servidor((_) => _json(409, {'detail': 'A sala abre às 09:45 de 10/01.'}));
      await abrirPainel(t, _sessao(), servidor: true);
      await t.tap(find.text('Entrar na videochamada'));
      await t.pumpAndSettle();
      expect(find.textContaining('A sala abre às 09:45'), findsOneWidget);
      expect(abertas, isEmpty);
    });

    testWidgets('sem internet: mensagem de erro e o botão volta a ficar disponível', (t) async {
      ApiClient.cliente = MockClient((_) async => throw Exception('sem rede'));
      await abrirPainel(t, _sessao(), servidor: true);
      await t.tap(find.text('Entrar na videochamada'));
      await t.pumpAndSettle();
      expect(find.textContaining('Sem conexão'), findsOneWidget);
      final botao = t.widget<ButtonStyleButton>(find.ancestor(of: find.text('Entrar na videochamada'), matching: find.bySubtype<ButtonStyleButton>()));
      expect(botao.onPressed, isNotNull);
    });

    testWidgets('navegador não abriu: avisa que o link foi copiado', (t) async {
      servidor((_) => _json(200, {'url': 'https://video.exemplo.com/ms-abc?jwt=tok', 'sala': 'ms-abc', 'moderador': false, 'expira_em': '2031-01-10T12:00:00'}));
      VideoService.abrir = (_) async => false;
      String? copiado;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copiado = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await abrirPainel(t, _sessao(), servidor: true);
      await t.tap(find.text('Entrar na videochamada'));
      await t.pumpAndSettle();
      expect(find.textContaining('Link copiado'), findsOneWidget);
      expect(copiado, 'https://video.exemplo.com/ms-abc?jwt=tok'); // o link com token foi para a área de transferência
    });
  });

  group('acesso ao prontuário no painel do profissional', () {
    Future<void> abrirDetalhe(WidgetTester t, {required bool servidor}) async {
      Dependencias.configurar(Dependencias(sessoes: FakeSessaoRepository([_sessao()])));
      await t.pumpWidget(
        ProviderScope(
          overrides: [prontuarioApiProvider.overrideWithValue(FakeProntuarioApi())],
          child: MaterialApp(home: PacienteDetalheScreen(paciente: pacienteResumoDeTeste('Ana Souza', id: 1), servidor: servidor)),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('no modo servidor o ícone "Prontuário" aparece e abre a tela do prontuário', (t) async {
      await abrirDetalhe(t, servidor: true);
      await t.tap(find.byTooltip('Prontuário'));
      await t.pumpAndSettle();
      expect(find.textContaining('Nenhum registro ainda'), findsOneWidget);
      expect(find.textContaining('Só você vê estes registros'), findsOneWidget);
    });

    testWidgets('no modo local não existe prontuário (ele só existe cifrado, no servidor)', (t) async {
      await abrirDetalhe(t, servidor: false);
      expect(find.byTooltip('Prontuário'), findsNothing);
    });

    testWidgets('tocar numa sessão online do histórico mostra o botão de vídeo do profissional', (t) async {
      await abrirDetalhe(t, servidor: true);
      t.view.physicalSize = const Size(900, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.tap(find.byType(SessaoCard).first);
      await t.pumpAndSettle();
      expect(find.text('Entrar na videochamada'), findsOneWidget);
    });
  });
}
