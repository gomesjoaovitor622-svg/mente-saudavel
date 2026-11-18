import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mente_saudavel/data/local/outbox_repository.dart';
import 'package:mente_saudavel/data/remote/humor_perfil_remoto.dart';
import 'package:mente_saudavel/data/remote/perfil_offline.dart';
import 'package:mente_saudavel/data/remote/sessao_repository_remoto.dart';
import 'package:mente_saudavel/database/humor_dao.dart';
import 'package:mente_saudavel/models/humor.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/services/sincronizador_outbox.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/banco_de_teste.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

http.Response _resp(int status, Object corpo) => http.Response(jsonEncode(corpo), status, headers: _json);

Map<String, Object?> _humorJson(int id, int nivel, String dataHora, {String nota = ''}) =>
    {'id': id, 'usuario_id': 1, 'nivel': nivel, 'nota': nota, 'data_hora': dataHora};

void main() {
  setUpAll(iniciarSqliteDeTeste);

  late Database db;
  late OutboxRepository outbox;
  late CacheKv cache;
  late SincronizadorOutbox sync;
  late HumorDao dao;
  late PerfilOffline perfil;

  late bool online;
  late List<http.Request> recebidas;
  late http.Response Function(http.Request) servidor;
  late int avisosDeFila;

  setUp(() async {
    db = await abrirBancoNovo();
    outbox = OutboxRepository(abrirBanco: () async => db);
    cache = CacheKv(abrirBanco: () async => db);
    online = true;
    recebidas = [];
    avisosDeFila = 0;
    servidor = (req) {
      if (req.method == 'GET') return _resp(200, <Object>[]);
      if (req.method == 'POST') return _resp(201, {'id': 500});
      return _resp(200, {'ok': true});
    };
    ApiClient.cliente = MockClient((req) async {
      if (!online) throw http.ClientException('sem rede');
      recebidas.add(req);
      return servidor(req);
    });
    sync = SincronizadorOutbox(outbox: outbox, remoto: SessaoRepositoryRemoto(), usuarioId: () => 1, maxTentativas: 2);
    dao = HumorDao(servidor: true, outbox: outbox, cache: cache, usuarioId: () => 1, aoMudarFila: () => avisosDeFila++);
    perfil = PerfilOffline(remoto: PerfilRemoto(), outbox: outbox, usuarioId: () => 1, aoMudarFila: () => avisosDeFila++);
  });

  tearDown(() async {
    ApiClient.cliente = http.Client();
    await db.close();
  });

  final agora = DateTime(2031, 1, 12, 9);
  HumorRegistro novo({int nivel = 4, String nota = 'ok'}) =>
      HumorRegistro(usuarioId: 1, nivel: nivel, nota: nota, dataHora: agora);

  group('humor: guardar offline', () {
    test('com internet vai direto ao servidor com Idempotency-Key e a fila fica vazia', () async {
      expect(await dao.inserir(novo()), 500);
      final post = recebidas.single;
      expect(post.url.path, '/humor');
      expect(post.headers['Idempotency-Key'], matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
      expect(await outbox.todos(1), isEmpty);
    });

    test('sem internet o registro vai para a fila, devolve id negativo e avisa a fila', () async {
      online = false;
      final id = await dao.inserir(novo());
      expect(id, lessThan(0));
      final item = (await outbox.todos(1)).single;
      expect([item.tipo, item.estado, -item.id], [TipoOutbox.humor, EstadoOutbox.pendente, id]);
      expect(item.payload['nivel'], 4);
      expect(avisosDeFila, 1);
    });

    test('recusa do servidor (422) NÃO vai para a fila: sobe como erro', () async {
      servidor = (_) => _resp(422, {'detail': 'inválido'});
      await expectLater(dao.inserir(novo()), throwsA(isA<AppException>()));
      expect(await outbox.todos(1), isEmpty);
    });

    test('sem fila disponível (navegador) o erro de conexão sobe para a tela', () async {
      online = false;
      final semFila = HumorDao(servidor: true, outbox: null, usuarioId: () => null);
      await expectLater(semFila.inserir(novo()), throwsA(isA<SemConexaoException>()));
    });
  });

  group('humor: ler offline', () {
    test('offline mostra o cache da última lista com o pendente por cima, marcado como pendente', () async {
      servidor = (_) => _resp(200, [_humorJson(7, 3, '2031-01-10T08:00:00')]);
      expect(await dao.listar(1), hasLength(1)); // online: grava o cache
      online = false;
      await dao.inserir(novo());
      final lista = await dao.listar(1);
      expect(lista, hasLength(2));
      expect(lista.first.pendente, isTrue); // mais novo primeiro
      expect(lista.where((r) => r.pendente), hasLength(1));
      expect(lista.last.id, 7);
    });

    test('offline e sem cache nenhum: o erro de conexão sobe (nada a mostrar)', () async {
      online = false;
      await expectLater(dao.listar(1), throwsA(isA<SemConexaoException>()));
    });

    test('média offline usa o cache do período e inclui o pendente', () async {
      final hoje = DateTime.now();
      servidor = (_) => _resp(200, [
            _humorJson(1, 2, hoje.subtract(const Duration(days: 1)).toIso8601String()),
            _humorJson(2, 5, hoje.subtract(const Duration(days: 30)).toIso8601String()), // fora dos 7 dias
          ]);
      await dao.listar(1);
      online = false;
      await dao.inserir(HumorRegistro(usuarioId: 1, nivel: 4, nota: '', dataHora: hoje));
      expect(await dao.mediaUltimosDias(1, 7), 3.0); // (2 + 4) / 2
    });

    test('excluir um pendente só o tira da fila (nunca foi ao servidor); excluir online chama a API', () async {
      online = false;
      final id = await dao.inserir(novo());
      expect(await dao.excluir(id), 1);
      expect(await outbox.todos(1), isEmpty);
      expect(recebidas, isEmpty);

      online = true;
      await dao.excluir(9);
      expect(recebidas.single.method, 'DELETE');
      expect(recebidas.single.url.path, '/humor/9');
    });
  });

  group('humor: sincronizar', () {
    test('quando a internet volta envia com a MESMA chave e esvazia a fila', () async {
      online = false;
      await dao.inserir(novo(nivel: 2, nota: 'dia difícil'));
      final chave = (await outbox.todos(1)).single.chave;

      online = true;
      final r = await sync.sincronizar();
      expect(r.enviados, 1);
      expect(await outbox.todos(1), isEmpty);
      final post = recebidas.firstWhere((q) => q.method == 'POST');
      expect(post.headers['Idempotency-Key'], chave);
      final corpo = jsonDecode(post.body) as Map<String, dynamic>;
      expect([corpo['nivel'], corpo['nota']], [2, 'dia difícil']);
    });

    test('reenvio depois de resposta perdida: o servidor devolve 200 com o registro existente e a fila esvazia', () async {
      online = false;
      await dao.inserir(novo());
      online = true;
      servidor = (_) => _resp(200, {'id': 500}); // replay idempotente
      final r = await sync.sincronizar();
      expect([r.enviados, r.falhas], [1, 0]);
      expect(await outbox.todos(1), isEmpty);
    });

    test('recusa 4xx na sincronização vira "falhou" e a retransmissão manual a reenvia', () async {
      online = false;
      await dao.inserir(novo());
      online = true;
      servidor = (_) => _resp(422, {'detail': 'inválido'});
      await sync.sincronizar();
      expect((await outbox.todos(1)).single.falhou, isTrue);

      servidor = (_) => _resp(201, {'id': 501});
      final r = await sync.reenviar();
      expect(r.enviados, 1);
      expect(await outbox.todos(1), isEmpty);
    });
  });

  group('cadastro (perfil): offline-first', () {
    const campos = {'nome': 'Dra. Marta', 'registro': '06/123', 'especialidade': 'TCC', 'endereco': null, 'valor_sessao_centavos': 15000};

    test('com internet devolve a resposta do servidor e não enfileira', () async {
      servidor = (_) => _resp(200, {'nome': 'Dra. Marta'});
      final r = await perfil.salvar(campos);
      expect((r as Map)['nome'], 'Dra. Marta');
      expect(recebidas.single.method, 'PATCH');
      expect(recebidas.single.url.path, '/auth/eu');
      expect(await outbox.todos(1), isEmpty);
    });

    test('sem internet guarda na fila e devolve null; duas alterações seguidas deixam só a MAIS RECENTE', () async {
      online = false;
      expect(await perfil.salvar({...campos, 'nome': 'Primeiro'}), isNull);
      expect(await perfil.salvar({...campos, 'nome': 'Segundo'}), isNull);
      final fila = await outbox.todos(1);
      expect(fila, hasLength(1));
      expect(fila.single.tipo, TipoOutbox.perfil);
      expect(fila.single.payload['nome'], 'Segundo');
      expect(avisosDeFila, 2);
    });

    test('a fila de perfil não apaga outros tipos pendentes nem itens de outra pessoa', () async {
      await outbox.enfileirar(1, TipoOutbox.humor, {'nivel': 3, 'nota': '', 'data_hora': agora.toIso8601String()});
      await outbox.enfileirar(2, TipoOutbox.perfil, {'nome': 'Outra pessoa'});
      online = false;
      await perfil.salvar(campos);
      expect((await outbox.todos(1)).map((i) => i.tipo), [TipoOutbox.humor, TipoOutbox.perfil]);
      expect(await outbox.todos(2), hasLength(1));
    });

    test('ao sincronizar envia o PATCH com os campos guardados', () async {
      online = false;
      await perfil.salvar(campos);
      online = true;
      servidor = (_) => _resp(200, {'ok': true});
      final r = await sync.sincronizar();
      expect(r.enviados, 1);
      final patch = recebidas.firstWhere((q) => q.method == 'PATCH');
      final corpo = jsonDecode(patch.body) as Map<String, dynamic>;
      expect([corpo['nome'], corpo['valor_sessao_centavos']], ['Dra. Marta', 15000]);
      expect(await outbox.todos(1), isEmpty);
    });

    test('recusa do servidor (422) sobe para a tela e não enfileira', () async {
      servidor = (_) => _resp(422, {'detail': 'inválido'});
      await expectLater(perfil.salvar(campos), throwsA(isA<AppException>()));
      expect(await outbox.todos(1), isEmpty);
    });

    test('sem usuário logado o erro de conexão sobe (nada a enfileirar)', () async {
      online = false;
      final semDono = PerfilOffline(remoto: PerfilRemoto(), outbox: outbox, usuarioId: () => null);
      await expectLater(semDono.salvar(campos), throwsA(isA<SemConexaoException>()));
    });
  });
}
