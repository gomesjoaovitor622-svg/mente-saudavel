import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mente_saudavel/services/telemetria.dart';
import 'package:mente_saudavel/services/token_store.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/utils/build_flags.dart';

/// Cliente HTTP da API do Mente Saudável (usado só quando `usaServidor` é true).
/// Guarda o token de login e converte erros do servidor em [AppException].
class ApiClient {
  static const Duration _limite = Duration(seconds: 20);

  /// Na web a credencial é um cookie HttpOnly (o navegador envia sozinho, no mesmo domínio do
  /// site). No celular é o token guardado no Keystore/Keychain, enviado no cabeçalho.
  static bool usaCookie = kIsWeb;

  static TokenStore armazenamento = kIsWeb ? TokenStoreWeb() : TokenStoreSeguro();

  static String? _token;

  /// Cliente HTTP. Trocável nos testes (`MockClient`).
  static http.Client cliente = http.Client();

  /// Chamado quando o servidor responde 401 (sessão expirada): a tela raiz volta ao login.
  static void Function()? aoExpirar;

  static Future<String?> carregarToken() async {
    if (_token != null) return _token;
    try {
      _token = await armazenamento.ler();
    } catch (_) {
      _token = null;
    }
    return _token;
  }

  static Future<void> salvarToken(String token) async {
    if (usaCookie) return; // o servidor já mandou o cookie; o token não fica acessível ao app
    _token = token;
    try {
      await armazenamento.gravar(token);
    } catch (_) {
      // Sem armazenamento: o login vale só até fechar o app.
    }
  }

  static Future<void> limparToken() async {
    _token = null;
    try {
      await armazenamento.apagar();
    } catch (_) {}
  }

  /// Encerra a sessão: o servidor apaga o cookie (só ele consegue) e o token local some.
  static Future<void> encerrarSessao() async {
    try {
      await _enviar('POST', '/auth/sair');
    } catch (_) {
      // Sem rede ou sessão já expirada: o logout local continua valendo.
    }
    await limparToken();
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
    Map<String, String>? extras,
  }) async {
    // X-Requested-With: o servidor exige este cabeçalho nas ações feitas com cookie (anti-CSRF).
    final cabecalhos = <String, String>{'Content-Type': 'application/json', 'X-Requested-With': 'mente-saudavel'};
    final token = autenticado ? await carregarToken() : null;
    if (token != null) cabecalhos['Authorization'] = 'Bearer $token';
    if (extras != null) cabecalhos.addAll(extras);

    final req = http.Request(metodo, _uri(caminho, consulta))..headers.addAll(cabecalhos);
    if (corpo != null) req.body = jsonEncode(corpo);

    final relogio = Stopwatch()..start();
    final nomeMetrica = Telemetria.normalizarCaminho(metodo, caminho);
    http.Response resposta;
    try {
      resposta = await http.Response.fromStream(await cliente.send(req).timeout(_limite));
    } on TimeoutException {
      Telemetria.registrarRede(nomeMetrica, relogio.elapsedMilliseconds, 0);
      throw const SemConexaoException('O servidor demorou para responder. Tente novamente.');
    } catch (_) {
      Telemetria.registrarRede(nomeMetrica, relogio.elapsedMilliseconds, 0);
      throw const SemConexaoException('Sem conexão com o servidor. Verifique a internet.');
    }
    Telemetria.registrarRede(nomeMetrica, relogio.elapsedMilliseconds, resposta.statusCode);

    final texto = utf8.decode(resposta.bodyBytes);
    final dados = texto.isEmpty ? null : _decodificar(texto);

    if (resposta.statusCode >= 200 && resposta.statusCode < 300) return dados;

    if (resposta.statusCode == 401 && autenticado) {
      await limparToken();
      aoExpirar?.call();
    }
    final mensagem = _mensagemDeErro(resposta.statusCode, dados);
    // 409 = conflito com o estado atual (ex.: horário já ocupado): tipo próprio para a tela reagir.
    if (resposta.statusCode == 409) throw ConflitoException(mensagem);
    throw AppException(mensagem, statusHttp: resposta.statusCode);
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

  /// [chaveIdempotencia]: o servidor devolve o MESMO resultado se a mesma chave chegar de novo
  /// (necessário para a fila offline reenviar sem duplicar).
  static Future<dynamic> post(String caminho, {Object? corpo, bool autenticado = true, String? chaveIdempotencia}) =>
      _enviar('POST', caminho,
          corpo: corpo,
          autenticado: autenticado,
          extras: chaveIdempotencia == null ? null : {'Idempotency-Key': chaveIdempotencia});

  static Future<dynamic> put(String caminho, {Object? corpo}) => _enviar('PUT', caminho, corpo: corpo);

  static Future<dynamic> patch(String caminho, {Object? corpo}) => _enviar('PATCH', caminho, corpo: corpo);

  static Future<dynamic> delete(String caminho) => _enviar('DELETE', caminho);

  /// Lista de objetos JSON (resposta que é um array).
  static List<Map<String, Object?>> comoLista(dynamic dados) =>
      (dados as List<dynamic>).map((e) => Map<String, Object?>.from(e as Map)).toList();
}
