import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Funções para guardar senhas de forma segura (nunca em texto puro).
class Seguranca {
  /// Gera um "sal" aleatório, diferente para cada usuário.
  static String gerarSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// SHA-256 de (sal + senha). Só o hash é gravado no banco.
  static String hashSenha(String senha, String salt) {
    return sha256.convert(utf8.encode('$salt:$senha')).toString();
  }
}
