import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/data/remote/sessao_repository_offline.dart';
import 'package:mente_saudavel/data/remote/sessao_repository_remoto.dart';
import 'package:mente_saudavel/models/sessao.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/services/sincronizador_outbox.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/banco_de_teste.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

http.Response _resp(int status, Object corpo) => http.Response(jsonEncode(corpo), status, headers: _json);

Map<String, Object?> _sessaoJson({int id = 5, String status = 'agendada'}) => {
      'id': id,
      'paciente_id': 1,
      'profissional_id': 9,
      'data_hora': '2031-01-10T10:00:00',
      'modalidade': 'Online',
      'status': status,
      'profissional_nome': 'Dra. Marta',
    };

void main() {
  setUpAll(iniciarSqliteDeTeste);

  late Database db;
  late OutboxRepository outbox;
  late CacheKv cache;
  late SessaoRepositoryOffline repo;
  late SincronizadorOutbox sync;

  // "Rede" simulada: o teste liga/desliga e escolhe o que o servidor responde.
  late bool online;
  late List<http.Request> recebidas;
  late http.Response Function(http.Request) servidor;

  setUp(() async {
    db = await abrirBancoNovo();
    outbox = OutboxRepository(abrirBanco: () async => db);
    cache = CacheKv(abrirBanco: () async => db);
    online = true;
    recebidas = [];
    servidor = (req) {
      if (req.method == 'GET') return _resp(200, <Object>[]);
      if (req.method == 'POST') return _resp(201, {'id': 77});
      return _resp(200, {'ok': true});
    };
    ApiClient.cliente = MockClient((req) async {
      if (!online) throw http.ClientException('sem rede');
      recebidas.add(req);
      return servidor(req);
    });
    final remoto = SessaoRepositoryRemoto();
    repo = SessaoRepositoryOffline(remoto: remoto, outbox: outbox, cache: cache, usuarioId: () => 1);
    sync = SincronizadorOutbox(outbox: outbox, remoto: remoto, usuarioId: () => 1, maxTentativas: 2);
  });

  tearDown(() async {
    ApiClient.cliente = http.Client();
    await db.close();
  });

  final quando = DateTime(2031, 1, 12, 9);

  Future<int> agendar() => repo.agendar(pacienteId: 1, profissionalId: 9, dataHora: quando, modalidade: 'Online');

  group('guardar offline', () {
    test('sem internet o agendamento vai para a fila e devolve id negativo', () async {
      online = false;
      final id = await agendar();
      expect(id, lessThan(0));
      final fila = await outbox.todos(1);
      expect(fila, hasLength(1));
      expect(fila.single.tipo, TipoOutbox.agendar);
      expect(fila.single.estado, EstadoOutbox.pendente);
      expect(fila.single.chave, matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
    });

    test('com internet vai direto ao servidor e a fila fica vazia', () async {
      expect(await agendar(), 77);
      expect(await outbox.todos(1), isEmpty);
    });

    test('recusa do servidor (409) NÃO vai para a fila: sobe como ConflitoException', () async {
      servidor = (_) => _resp(409, {'detail': 'O profissional já tem uma sessão neste horário.'});
      await expectLater(agendar(), throwsA(isA<ConflitoException>()));
      expect(await outbox.todos(1), isEmpty);
    });

    test('a lista offline mostra o cache com o agendamento pendente por cima', () async {
      servidor = (_) => _resp(200, [_sessaoJson()]);
      expect(await repo.doPaciente(1), hasLength(1)); // online: grava o cache
      online = false;
      await agendar();
      final lista = await repo.doPaciente(1);
      expect(lista, hasLength(2));
      expect(lista.where((s) => s.pendente), hasLength(1));
      expect(lista.firstWhere((s) => s.pendente).id, lessThan(0));
    });

    test('cancelar offline aparece cancelado na lista, mesmo antes de sincronizar', () async {
      servidor = (_) => _resp(200, [_sessaoJson()]);
      await repo.doPaciente(1);
      online = false;
      await repo.atualizarStatus(5, StatusSessao.cancelada);
      final lista = await repo.doPaciente(1);
      expect(lista.single.status, StatusSessao.cancelada);
      expect((await outbox.todos(1)).single.tipo, TipoOutbox.status);
    });

    test('offline e sem cache nenhum: o erro de conexão sobe (nada a mostrar)', () async {
      online = false;
      await expectLater(repo.doPaciente(1), throwsA(isA<SemConexaoException>()));
    });

    test('filtro por status também vale sobre o cache offline', () async {
      servidor = (_) => _resp(200, [_sessaoJson(), _sessaoJson(id: 6, status: 'concluida')]);
      await repo.doPaciente(1);
      online = false;
      final concluidas = await repo.doPaciente(1, status: StatusSessao.concluida);
      expect(concluidas.map((s) => s.id), [6]);
    });
  });

  group('sincronizar', () {
    test('quando a internet volta, envia com a MESMA chave de idempotência e esvazia a fila', () async {
      online = false;
      await agendar();
      final chave = (await outbox.todos(1)).single.chave;

      online = true;
      final r = await sync.sincronizar();
      expect(r.enviados, 1);
      expect(await outbox.todos(1), isEmpty);
      final post = recebidas.firstWhere((q) => q.method == 'POST');
      expect(post.headers['Idempotency-Key'], chave);
    });

    test('ainda sem internet: mantém tudo na fila e não conta tentativa', () async {
      online = false;
      await agendar();
      final r = await sync.sincronizar();
      expect(r.semConexao, isTrue);
      final item = (await outbox.todos(1)).single;
      expect(item.estado, EstadoOutbox.pendente);
      expect(item.tentativas, 0);
    });

    test('conflito no envio: marca "conflito" e segue para o próximo item', () async {
      online = false;
      await agendar();
      await repo.atualizarStatus(5, StatusSessao.cancelada);
      online = true;
      servidor = (req) => req.method == 'POST'
          ? _resp(409, {'detail': 'O profissional já tem uma sessão neste horário.'})
          : _resp(200, {'ok': true});
      final r = await sync.sincronizar();
      expect(r.conflitos, 1);
      expect(r.enviados, 1); // o cancelamento foi enviado mesmo com o conflito antes dele
      final fila = await outbox.todos(1);
      expect(fila, hasLength(1));
      expect(fila.single.estado, EstadoOutbox.conflito);
      expect(fila.single.ultimoErro, contains('horário'));
    });

    test('recusa 4xx é definitiva (falhou); 5xx tenta de novo até esgotar', () async {
      online = false;
      await agendar();
      online = true;

      servidor = (_) => _resp(422, {'detail': 'dados inválidos'});
      await sync.sincronizar();
      expect((await outbox.todos(1)).single.estado, EstadoOutbox.falhou);

      await outbox.limparUsuario(1);
      online = false;
      await agendar();
      online = true;
      servidor = (_) => _resp(500, {'detail': 'erro'});
      await sync.sincronizar();
      var item = (await outbox.todos(1)).single;
      expect([item.estado, item.tentativas], [EstadoOutbox.pendente, 1]);
      await sync.sincronizar(); // 2ª tentativa = máximo (maxTentativas: 2)
      item = (await outbox.todos(1)).single;
      expect(item.estado, EstadoOutbox.falhou);
    });

    test('401 (sessão expirada) para a rodada sem mexer na fila', () async {
      online = false;
      await agendar();
      online = true;
      servidor = (_) => _resp(401, {'detail': 'Sessão expirada.'});
      await sync.sincronizar();
      final item = (await outbox.todos(1)).single;
      expect([item.estado, item.tentativas], [EstadoOutbox.pendente, 0]);
    });

    test('sem usuário logado não envia nada', () async {
      online = false;
      await agendar();
      online = true;
      final semLogin = SincronizadorOutbox(outbox: outbox, remoto: SessaoRepositoryRemoto(), usuarioId: () => null);
      expect((await semLogin.sincronizar()).enviados, 0);
      expect(await outbox.todos(1), hasLength(1));
    });

    test('descartar remove o item e avisa quem está escutando', () async {
      online = false;
      await agendar();
      final id = (await outbox.todos(1)).single.id;
      final antes = sync.versao.value;
      await sync.descartar(id);
      expect(await outbox.todos(1), isEmpty);
      expect(sync.versao.value, greaterThan(antes));
    });
  });

  test('a fila de uma pessoa não aparece para outra', () async {
    await outbox.enfileirar(1, TipoOutbox.status, {'id': 1, 'status': 'cancelada'});
    await outbox.enfileirar(2, TipoOutbox.status, {'id': 2, 'status': 'cancelada'});
    expect(await outbox.todos(1), hasLength(1));
    await outbox.limparUsuario(1);
    expect(await outbox.todos(1), isEmpty);
    expect(await outbox.todos(2), hasLength(1));
  });
}
