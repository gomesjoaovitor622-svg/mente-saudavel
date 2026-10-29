import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;

/// Resultado da conferência de uma senha.
enum ResultadoSenha {
  invalida,
  valida,

  /// Senha certa, mas o hash guardado é antigo/fraco: grave um novo (veja [Seguranca.criarHash]).
  validaPrecisaAtualizar,
}

/// Guarda e confere senhas do modo LOCAL (SQLite). Nunca em texto puro.
///
/// Formato novo: `pbkdf2-sha256$<iterações>$<hash em base64>` (autodescritivo: dá para aumentar as
/// iterações no futuro sem quebrar contas antigas). Formato antigo: SHA-256 de `sal:senha`,
/// ainda aceito no login e trocado pelo novo assim que a senha é digitada corretamente.
///
/// Por que PBKDF2 e não Argon2id: roda só com o pacote `crypto` (sem código nativo, igual em
/// Android, iOS, desktop e web). Em Dart puro o Argon2id é lento demais, então o custo fica em
/// [iteracoes]. No modo servidor a senha é tratada pelo servidor (scrypt), não aqui.
class Seguranca {
  static const String prefixo = 'pbkdf2-sha256';
  static const int iteracoes = 100000;

  /// Gera um "sal" aleatório, diferente para cada usuário.
  static String gerarSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// FORMATO ANTIGO (SHA-256 rápido). Não use para senhas novas: serve só para conferir
  /// contas antigas e para derivar identificadores que não são segredo (ex.: nome da sala de vídeo).
  static String hashSenha(String senha, String salt) {
    return sha256.convert(utf8.encode('$salt:$senha')).toString();
  }

  /// Hash novo da senha (PBKDF2-HMAC-SHA256). Roda em segundo plano para não travar a tela.
  static Future<String> criarHash(String senha, String salt, {int iteracoes = Seguranca.iteracoes}) async {
    final derivado = await compute(_derivarEmSegundoPlano, <Object>[senha, salt, iteracoes]);
    return '$prefixo\$$iteracoes\$${base64.encode(derivado)}';
  }

  /// Confere [senha] com o [hashGuardado] (novo ou antigo) usando comparação em tempo constante.
  static Future<ResultadoSenha> verificar(String senha, String hashGuardado, String salt) async {
    if (hashGuardado.startsWith('$prefixo\$')) {
      final partes = hashGuardado.split('\$');
      final it = partes.length == 3 ? int.tryParse(partes[1]) : null;
      if (it == null || it < 1) return ResultadoSenha.invalida;
      final esperado = await criarHash(senha, salt, iteracoes: it);
      if (!comparar(esperado, hashGuardado)) return ResultadoSenha.invalida;
      return it < iteracoes ? ResultadoSenha.validaPrecisaAtualizar : ResultadoSenha.valida;
    }
    // Formato antigo.
    return comparar(hashSenha(senha, salt), hashGuardado)
        ? ResultadoSenha.validaPrecisaAtualizar
        : ResultadoSenha.invalida;
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018), 1 bloco de 32 bytes. Pública para os testes (vetores oficiais).
  static Uint8List pbkdf2(List<int> senha, List<int> salt, int iteracoes) {
    final hmac = Hmac(sha256, senha);
    var u = Uint8List.fromList(hmac.convert([...salt, 0, 0, 0, 1]).bytes);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iteracoes; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t;
  }

  /// Comparação que leva o mesmo tempo qualquer que seja a posição da diferença.
  static bool comparar(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diferenca = x.length ^ y.length;
    for (var i = 0; i < x.length && i < y.length; i++) {
      diferenca |= x[i] ^ y[i];
    }
    return diferenca == 0;
  }
}

// Função de topo (exigência do `compute`): recebe [senha, salt, iterações].
Uint8List _derivarEmSegundoPlano(List<Object> p) =>
    Seguranca.pbkdf2(utf8.encode(p[0] as String), utf8.encode(p[1] as String), p[2] as int);
