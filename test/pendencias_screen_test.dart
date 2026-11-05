import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/data/remote/sessao_repository_remoto.dart';
import 'package:mente_saudavel/presentation/providers/sessoes_providers.dart';
import 'package:mente_saudavel/screens/pendencias_screen.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/services/sincronizador_outbox.dart';
import 'package:mente_saudavel/services/token_store.dart';

import 'helpers/fakes.dart';

/// Token em memória: o armazenamento seguro de verdade usa canal de plataforma, que trava em `testWidgets`.
class _TokenMemoria implements TokenStore {
  @override
  Future<String?> ler() async => 'token-de-teste';
  @override
  Future<void> gravar(String token) async {}
  @override
  Future<void> apagar() async {}
}

/// Fila em memória: a tela é testada sem SQLite (o repositório de verdade já tem teste próprio).
class _OutboxMemoria extends OutboxRepository {
  _OutboxMemoria(this.itens);
  final List<ItemOutbox> itens;

  @override
  Future<List<ItemOutbox>> todos(int usuarioId) async => itens.where((i) => i.usuarioId == usuarioId).toList();

  @override
  Future<int> reativarFalhas(int usuarioId, {int? id}) async {
    var n = 0;
    for (var k = 0; k < itens.length; k++) {
      final i = itens[k];
      if (i.usuarioId == usuarioId && i.falhou && (id == null || i.id == id)) {
        itens[k] = _item(i.id, EstadoOutbox.pendente);
        n++;
      }
    }
    return n;
  }

  @override
  Future<void> marcar(int id, String estado, {String? erro, bool contarTentativa = false}) async {
    final k = itens.indexWhere((i) => i.id == id);
    if (k < 0) return;
    itens[k] = _item(id, estado, erro: erro, tentativas: itens[k].tentativas + (contarTentativa ? 1 : 0));
  }

  @override
  Future<void> remover(int id) async => itens.removeWhere((i) => i.id == id);
}

ItemOutbox _item(int id, String estado, {String? erro, int tentativas = 0}) => ItemOutbox(
      id: id,
      usuarioId: 1,
      tipo: TipoOutbox.agendar,
      payload: const {'profissional_id': 9, 'data_hora': '2031-01-10T10:00:00', 'modalidade': 'Online'},
      chave: 'chave-$id-abcdefgh',
      estado: estado,
      tentativas: tentativas,
      criadoEm: '2031-01-01T00:00:00',
      ultimoErro: erro,
    );

void main() {
  late _OutboxMemoria fila;
  late http.Response Function() servidor;

  setUp(() {
    AuthService.atual.value = pacienteDeTeste();
    servidor = () => http.Response(jsonEncode({'id': 9}), 201, headers: {'content-type': 'application/json; charset=utf-8'});
    ApiClient.usaCookie = false;
    ApiClient.armazenamento = _TokenMemoria();
    ApiClient.cliente = MockClient((_) async => servidor());
  });

  tearDown(() {
    AuthService.atual.value = null;
    ApiClient.cliente = http.Client();
  });

  Future<void> abrir(WidgetTester t, List<ItemOutbox> itens) async {
    fila = _OutboxMemoria(itens);
    final sync = SincronizadorOutbox(outbox: fila, remoto: SessaoRepositoryRemoto(), usuarioId: () => 1);
    await t.pumpWidget(
      ProviderScope(
        overrides: [sincronizadorProvider.overrideWithValue(sync)],
        child: const MaterialApp(home: PendenciasScreen()),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('sem pendências mostra que está tudo enviado', (t) async {
    await abrir(t, []);
    expect(find.byKey(const Key('pendencias-vazio')), findsOneWidget);
  });

  testWidgets('item que estourou as tentativas aparece com o motivo, a contagem e o botão Reenviar', (t) async {
    await abrir(t, [_item(1, EstadoOutbox.falhou, erro: 'Servidor indisponível', tentativas: 20)]);
    expect(find.text('Com falha (1)'), findsOneWidget);
    expect(find.textContaining('Servidor indisponível'), findsOneWidget);
    expect(find.textContaining('20 tentativa(s)'), findsOneWidget);
    expect(find.byKey(const Key('reenviar-1')), findsOneWidget);
    expect(find.byKey(const Key('reenviar-todas')), findsOneWidget);
  });

  testWidgets('Reenviar todas: o item é enviado e some da lista', (t) async {
    await abrir(t, [_item(1, EstadoOutbox.falhou, erro: 'x', tentativas: 20), _item(2, EstadoOutbox.falhou, erro: 'y', tentativas: 20)]);
    await t.tap(find.byKey(const Key('reenviar-todas')));
    await t.pumpAndSettle();
    expect(fila.itens, isEmpty);
    expect(find.byKey(const Key('pendencias-vazio')), findsOneWidget);
  });

  testWidgets('Reenviar um item só reenvia aquele', (t) async {
    await abrir(t, [_item(1, EstadoOutbox.falhou, erro: 'x', tentativas: 20), _item(2, EstadoOutbox.falhou, erro: 'y', tentativas: 20)]);
    await t.tap(find.byKey(const Key('reenviar-1')));
    await t.pumpAndSettle();
    expect(fila.itens.map((i) => i.id), [2]);
    expect(fila.itens.single.estado, EstadoOutbox.falhou);
  });

  testWidgets('servidor ainda fora do ar: o item continua visível (nada se perde em silêncio)', (t) async {
    servidor = () => http.Response(jsonEncode({'detail': 'erro'}), 500, headers: {'content-type': 'application/json; charset=utf-8'});
    await abrir(t, [_item(1, EstadoOutbox.falhou, erro: 'x', tentativas: 20)]);
    await t.tap(find.byKey(const Key('reenviar-todas')));
    await t.pumpAndSettle();
    expect(fila.itens, hasLength(1));
    expect(find.byKey(const Key('pendencia-1')), findsOneWidget);
    expect(find.byKey(const Key('pendencias-vazio')), findsNothing);
  });

  testWidgets('conflito: só pode descartar (não há Reenviar) e descartar pede confirmação', (t) async {
    await abrir(t, [_item(3, EstadoOutbox.conflito, erro: 'horário ocupado')]);
    expect(find.text('Precisam da sua decisão (1)'), findsOneWidget);
    expect(find.byKey(const Key('reenviar-3')), findsNothing);

    await t.tap(find.byKey(const Key('descartar-3')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(fila.itens, hasLength(1)); // cancelou: continua lá

    await t.tap(find.byKey(const Key('descartar-3')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Descartar'));
    await t.pumpAndSettle();
    expect(fila.itens, isEmpty);
  });

  testWidgets('item aguardando envio aparece sem botão Reenviar/Descartar', (t) async {
    await abrir(t, [_item(4, EstadoOutbox.pendente)]);
    expect(find.text('Aguardando envio (1)'), findsOneWidget);
    expect(find.byKey(const Key('reenviar-4')), findsNothing);
    expect(find.byKey(const Key('descartar-4')), findsNothing);
    expect(find.byKey(const Key('sincronizar-agora')), findsOneWidget);
  });
}
