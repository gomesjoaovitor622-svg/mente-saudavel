import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crud_jsonplaceholder/models/post.dart';

/// Erro com mensagem pronta para mostrar ao usuário.
class ApiException implements Exception {
  final String mensagem;
  const ApiException(this.mensagem);

  @override
  String toString() => mensagem;
}

/// Todas as chamadas HTTP à API https://jsonplaceholder.typicode.com ficam aqui.
///
/// Cada letra do CRUD é um método HTTP:
///   C (Create) -> POST   /posts
///   R (Read)   -> GET    /posts  e  GET /posts/{id}
///   U (Update) -> PUT    /posts/{id}
///   D (Delete) -> DELETE /posts/{id}
///
/// IMPORTANTE: a JSONPlaceholder é uma API de teste. Ela responde com sucesso a POST, PUT e
/// DELETE, mas NÃO grava nada no servidor (só o GET devolve os dados originais).
class PostService {
  static const String urlPadrao = 'https://jsonplaceholder.typicode.com';
  static const Duration _limite = Duration(seconds: 15);
  static const Map<String, String> _cabecalhos = {'Content-Type': 'application/json; charset=UTF-8'};

  final http.Client _client;
  final String _base;

  /// [client] e [baseUrl] podem ser trocados nos testes (sem acessar a internet).
  PostService({http.Client? client, String baseUrl = urlPadrao})
      : _client = client ?? http.Client(),
        _base = baseUrl;

  Uri _uri(String caminho, [Map<String, String>? consulta]) =>
      Uri.parse('$_base$caminho').replace(queryParameters: consulta);

  /// Envia a requisição, confere o status e devolve o JSON já decodificado.
  Future<dynamic> _enviar(Future<http.Response> Function() chamada) async {
    try {
      final resposta = await chamada().timeout(_limite);
      if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
        if (resposta.statusCode == 404) throw const ApiException('Registro não encontrado (404).');
        throw ApiException('O servidor respondeu com erro ${resposta.statusCode}.');
      }
      if (resposta.body.isEmpty) return null;
      return jsonDecode(utf8.decode(resposta.bodyBytes));
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('A conexão demorou demais. Tente novamente.');
    } on FormatException {
      throw const ApiException('Resposta inválida do servidor.');
    } catch (_) {
      throw const ApiException('Sem conexão. Verifique a internet e tente novamente.');
    }
  }

  // ---------------------------------------------------------------- READ
  /// GET /posts  (opcional: ?userId=1)
  Future<List<Post>> listar({int? userId}) async {
    final dados = await _enviar(
      () => _client.get(_uri('/posts', userId == null ? null : {'userId': '$userId'})),
    );
    return (dados as List<dynamic>).map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// GET /posts/{id}
  Future<Post> buscar(int id) async {
    final dados = await _enviar(() => _client.get(_uri('/posts/$id')));
    return Post.fromJson(dados as Map<String, dynamic>);
  }

  /// GET /posts/{id}/comments
  Future<List<Comentario>> comentarios(int postId) async {
    final dados = await _enviar(() => _client.get(_uri('/posts/$postId/comments')));
    return (dados as List<dynamic>).map((e) => Comentario.fromJson(e as Map<String, dynamic>)).toList();
  }

  // -------------------------------------------------------------- CREATE
  /// POST /posts  -> a API devolve o post com um id novo (sempre 101).
  Future<Post> criar(Post post) async {
    final dados = await _enviar(
      () => _client.post(_uri('/posts'), headers: _cabecalhos, body: jsonEncode(post.toJson())),
    );
    return Post.fromJson(dados as Map<String, dynamic>);
  }

  // -------------------------------------------------------------- UPDATE
  /// PUT /posts/{id}  -> substitui o post inteiro.
  Future<Post> atualizar(Post post) async {
    final id = post.id;
    if (id == null) throw const ApiException('Não é possível atualizar um post sem id.');
    final dados = await _enviar(
      () => _client.put(_uri('/posts/$id'), headers: _cabecalhos, body: jsonEncode(post.toJson())),
    );
    return Post.fromJson(dados as Map<String, dynamic>);
  }

  // -------------------------------------------------------------- DELETE
  /// DELETE /posts/{id}  -> a API devolve {} (objeto vazio).
  Future<void> excluir(int id) async {
    await _enviar(() => _client.delete(_uri('/posts/$id')));
  }

  void fechar() => _client.close();
}
