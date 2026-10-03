import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mente_saudavel/utils/app_exception.dart';

/// Integração com APIs públicas (sem chave). O app continua funcionando
/// offline: se a internet falhar, as telas apenas deixam de mostrar o extra.
class ApiService {
  static final Map<int, Map<String, String>> _cacheFeriados = {};

  /// BrasilAPI: feriados nacionais do ano. Retorna {"2026-12-25": "Natal"}.
  /// Em caso de falha (sem internet etc.) retorna um mapa vazio.
  static Future<Map<String, String>> feriados(int ano) async {
    final emCache = _cacheFeriados[ano];
    if (emCache != null) return emCache;

    try {
      final resposta = await http
          .get(Uri.parse('https://brasilapi.com.br/api/feriados/v1/$ano'))
          .timeout(const Duration(seconds: 8));
      if (resposta.statusCode == 200) {
        final lista = jsonDecode(utf8.decode(resposta.bodyBytes)) as List<dynamic>;
        final mapa = <String, String>{};
        for (final item in lista) {
          final m = item as Map<String, dynamic>;
          mapa[m['date'] as String] = m['name'] as String;
        }
        _cacheFeriados[ano] = mapa;
        return mapa;
      }
    } catch (_) {
      // Sem internet ou API fora do ar: segue sem a informação de feriados.
    }
    return {};
  }

  /// ViaCEP: transforma um CEP em endereço (logradouro, bairro, cidade - UF).
  static Future<String> buscarCep(String cep) async {
    final digitos = cep.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length != 8) {
      throw const AppException('Informe um CEP com 8 dígitos.');
    }

    try {
      final resposta = await http
          .get(Uri.parse('https://viacep.com.br/ws/$digitos/json/'))
          .timeout(const Duration(seconds: 8));
      if (resposta.statusCode != 200) {
        throw const AppException('Não foi possível consultar o CEP agora.');
      }
      final dados = jsonDecode(utf8.decode(resposta.bodyBytes)) as Map<String, dynamic>;
      if (dados['erro'] != null) {
        throw const AppException('CEP não encontrado.');
      }

      final logradouro = (dados['logradouro'] ?? '').toString();
      final bairro = (dados['bairro'] ?? '').toString();
      final cidade = (dados['localidade'] ?? '').toString();
      final uf = (dados['uf'] ?? '').toString();

      final partes = <String>[
        logradouro,
        bairro,
        if (cidade.isNotEmpty) (uf.isNotEmpty ? '$cidade - $uf' : cidade),
      ];
      return partes.where((p) => p.trim().isNotEmpty).join(', ');
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException('Sem conexão. Verifique a internet e tente novamente.');
    }
  }
}
