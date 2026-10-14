import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crud_jsonplaceholder/models/post.dart';
import 'package:crud_jsonplaceholder/services/post_service.dart';

http.Response _json(Object corpo, [int status = 200]) =>
    http.Response(jsonEncode(corpo), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('listar: GET /posts converte o JSON em objetos Post', () async {
    late http.Request visto;
    final service = PostService(client: MockClient((req) async {
      visto = req;
      return _json([
        {'userId': 1, 'id': 1, 'title': 'a', 'body': 'x'},
        {'userId': 2, 'id': 2, 'title': 'b', 'body': 'y'},
      ]);
    }));
    final posts = await service.listar();
    expect(visto.method, 'GET');
    expect(visto.url.path, '/posts');
    expect(visto.url.queryParameters['_limit'], '20'); // só 20 posts, não os 100
    expect(posts.map((p) => p.title), ['a', 'b']);
    expect(posts.last.userId, 2);
  });

  test('listar com userId usa a query ?userId=', () async {
    late Uri url;
    final service = PostService(client: MockClient((req) async {
      url = req.url;
      return _json([]);
    }));
    await service.listar(userId: 3, limite: 5);
    expect(url.queryParameters['userId'], '3');
    expect(url.queryParameters['_limit'], '5');
  });

  test('buscar: GET /posts/{id}', () async {
    final service = PostService(client: MockClient((req) async {
      expect(req.url.path, '/posts/7');
      return _json({'userId': 1, 'id': 7, 'title': 't', 'body': 'b'});
    }));
    final post = await service.buscar(7);
    expect(post.id, 7);
  });

  test('comentarios: GET /posts/{id}/comments', () async {
    final service = PostService(client: MockClient((req) async {
      expect(req.url.path, '/posts/1/comments');
      return _json([
        {'postId': 1, 'id': 1, 'name': 'n', 'email': 'e@x.com', 'body': 'c'},
      ]);
    }));
    final lista = await service.comentarios(1);
    expect(lista.single.email, 'e@x.com');
  });

  test('criar: POST /posts envia JSON e devolve o post com id', () async {
    late http.Request visto;
    final service = PostService(client: MockClient((req) async {
      visto = req;
      return _json({'userId': 1, 'id': 101, 'title': 'novo', 'body': 'texto'}, 201);
    }));
    final criado = await service.criar(const Post(userId: 1, title: 'novo', body: 'texto'));
    expect(visto.method, 'POST');
    expect(visto.url.path, '/posts');
    expect(visto.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(visto.body), {'userId': 1, 'title': 'novo', 'body': 'texto'}); // sem id
    expect(criado.id, 101);
  });

  test('atualizar: PUT /posts/{id} envia o post inteiro', () async {
    late http.Request visto;
    final service = PostService(client: MockClient((req) async {
      visto = req;
      return _json({'userId': 1, 'id': 5, 'title': 'editado', 'body': 'b'});
    }));
    final editado = await service.atualizar(const Post(id: 5, userId: 1, title: 'editado', body: 'b'));
    expect(visto.method, 'PUT');
    expect(visto.url.path, '/posts/5');
    expect(jsonDecode(visto.body)['id'], 5);
    expect(editado.title, 'editado');
  });

  test('atualizar sem id é recusado antes de chamar a API', () async {
    final service = PostService(client: MockClient((req) async => fail('não deveria chamar a API')));
    expect(
      () => service.atualizar(const Post(userId: 1, title: 't', body: 'b')),
      throwsA(isA<ApiException>()),
    );
  });

  test('excluir: DELETE /posts/{id} aceita resposta {}', () async {
    late http.Request visto;
    final service = PostService(client: MockClient((req) async {
      visto = req;
      return _json({});
    }));
    await service.excluir(9);
    expect(visto.method, 'DELETE');
    expect(visto.url.path, '/posts/9');
  });

  test('erros: 404, 500, JSON inválido e falta de conexão viram ApiException', () async {
    Future<void> espera(http.Client c, String trecho) async {
      await expectLater(
        PostService(client: c).buscar(1),
        throwsA(isA<ApiException>().having((e) => e.mensagem, 'mensagem', contains(trecho))),
      );
    }

    await espera(MockClient((_) async => http.Response('{}', 404)), 'não encontrado');
    await espera(MockClient((_) async => http.Response('x', 500)), '500');
    await espera(MockClient((_) async => http.Response('isto nao e json', 200)), 'inválida');
    await espera(MockClient((_) async => throw http.ClientException('sem rede')), 'Sem conexão');
  });
}
