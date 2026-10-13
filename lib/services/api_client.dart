import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Cliente HTTP da API do Mente Saudável (usado só quando `usaServidor` é true).
/// Guarda o token de login e converte erros do servidor em [AppException].
class ApiClient {
  static const String _chaveToken = 'ms_token';
  static const Duration _limite = Duration(seconds: 20);

  static String? _token;

  /// Chamado quando o servidor responde 401 (sessão expirada): a tela raiz volta ao login.
  static void Function()? aoExpirar;

  static Future<String?> carregarToken() async {
    if (_token != null) return _token;
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_chaveToken);
    } catch (_) {
      _token = null;
    }
    return _token;
  }

  static Future<void> salvarToken(String token) async {
    _token = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_chaveToken, token);
    } catch (_) {
      // Sem armazenamento: o login vale só até fechar o app.
    }
  }

  static Future<void> limparToken() async {
    _token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_chaveToken);
    } catch (_) {}
  }

  static Uri _uri(String caminho, Map<String, String>? consulta) {
    final base = kApiUrl.endsWith('/') ? kApiUrl.substring(0, kApiUrl.length - 1) : kApiUrl;
    final uri = Uri.parse('$base$caminho');
    if (consulta == null || consulta.isEmpty) return uri;
    // `Uri.parse` aceita base relativa (ex.: "/api"), que o navegador resolve no mesmo domínio.
    return uri.replace(queryParameters: consulta);
  }

  static Future<dynamic> _enviar(
    String metodo,
    String caminho, {
    Map<String, String>? consulta,
    Object? corpo,
    bool autenticado = true,
  }) async {
    final cabecalhos = <String, String>{'Content-Type': 'application/json'};
    final token = autenticado ? await carregarToken() : null;
    if (token != null) cabecalhos['Authorization'] = 'Bearer $token';

    final req = http.Request(metodo, _uri(caminho, consulta))..headers.addAll(cabecalhos);
    if (corpo != null) req.body = jsonEncode(corpo);

    http.Response resposta;
    try {
      resposta = await http.Response.fromStream(await req.send().timeout(_limite));
    } on TimeoutException {
      throw const AppException('O servidor demorou para responder. Tente novamente.');
    } catch (_) {
      throw const AppException('Sem conexão com o servidor. Verifique a internet.');
    }

    final texto = utf8.decode(resposta.bodyBytes);
    final dados = texto.isEmpty ? null : _decodificar(texto);

    if (resposta.statusCode >= 200 && resposta.statusCode < 300) return dados;

    if (resposta.statusCode == 401 && autenticado) {
      await limparToken();
      aoExpirar?.call();
    }
    throw AppException(_mensagemDeErro(resposta.statusCode, dados));
  }

  static dynamic _decodificar(String texto) {
    try {
      return jsonDecode(texto);
    } catch (_) {
      return null;
    }
  }

  static String _mensagemDeErro(int status, dynamic dados) {
    if (dados is Map && dados['detail'] is String) return dados['detail'] as String;
    if (dados is Map && dados['detail'] is List && (dados['detail'] as List).isNotEmpty) {
      return 'Confira os dados informados e tente novamente.';
    }
    if (status == 429) return 'Muitas tentativas. Aguarde um pouco.';
    if (status >= 500) return 'Erro no servidor. Tente novamente em instantes.';
    return 'Não foi possível concluir a operação.';
  }

  static Future<dynamic> get(String caminho, {Map<String, String>? consulta}) =>
      _enviar('GET', caminho, consulta: consulta);

  static Future<dynamic> post(String caminho, {Object? corpo, bool autenticado = true}) =>
      _enviar('POST', caminho, corpo: corpo, autenticado: autenticado);

  static Future<dynamic> put(String caminho, {Object? corpo}) => _enviar('PUT', caminho, corpo: corpo);

  static Future<dynamic> patch(String caminho, {Object? corpo}) => _enviar('PATCH', caminho, corpo: corpo);

  static Future<dynamic> delete(String caminho) => _enviar('DELETE', caminho);

  /// Lista de objetos JSON (resposta que é um array).
  static List<Map<String, Object?>> comoLista(dynamic dados) =>
      (dados as List<dynamic>).map((e) => Map<String, Object?>.from(e as Map)).toList();
}
