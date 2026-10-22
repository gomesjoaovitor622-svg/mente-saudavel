import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/services/seguranca.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PBKDF2-HMAC-SHA256 (vetores de teste conhecidos)', () {
    test('1 iteração', () {
      expect(
        _hex(Seguranca.pbkdf2(utf8.encode('password'), utf8.encode('salt'), 1)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b', // pragma: allowlist secret
      );
    });
    test('2 iterações', () {
      expect(
        _hex(Seguranca.pbkdf2(utf8.encode('password'), utf8.encode('salt'), 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43', // pragma: allowlist secret
      );
    });
    test('4096 iterações', () {
      expect(
        _hex(Seguranca.pbkdf2(utf8.encode('password'), utf8.encode('salt'), 4096)),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a', // pragma: allowlist secret
      );
    });
  });

  group('verificar', () {
    const salt = 'sal-de-teste';

    test('hash novo: senha certa vale, errada não', () async {
      final hash = await Seguranca.criarHash('segredo-123', salt);
      expect(hash, startsWith('pbkdf2-sha256\$100000\$'));
      expect(await Seguranca.verificar('segredo-123', hash, salt), ResultadoSenha.valida);
      expect(await Seguranca.verificar('outra-senha', hash, salt), ResultadoSenha.invalida);
    });

    test('mesma senha com sais diferentes gera hashes diferentes', () async {
      expect(await Seguranca.criarHash('x', 'a', iteracoes: 10), isNot(await Seguranca.criarHash('x', 'b', iteracoes: 10)));
    });

    test('hash antigo (SHA-256) ainda entra, mas pede atualização', () async {
      final antigo = Seguranca.hashSenha('123456', salt);
      expect(await Seguranca.verificar('123456', antigo, salt), ResultadoSenha.validaPrecisaAtualizar);
      expect(await Seguranca.verificar('errada', antigo, salt), ResultadoSenha.invalida);
    });

    test('hash novo com poucas iterações pede atualização', () async {
      final fraco = await Seguranca.criarHash('abc', salt, iteracoes: 1000);
      expect(await Seguranca.verificar('abc', fraco, salt), ResultadoSenha.validaPrecisaAtualizar);
    });

    test('hash malformado é inválido (não lança)', () async {
      expect(await Seguranca.verificar('x', 'pbkdf2-sha256\$lixo', salt), ResultadoSenha.invalida);
      expect(await Seguranca.verificar('x', 'pbkdf2-sha256\$0\$AAAA', salt), ResultadoSenha.invalida);
    });
  });

  test('comparar distingue textos de tamanhos e conteúdos diferentes', () {
    expect(Seguranca.comparar('abc', 'abc'), isTrue);
    expect(Seguranca.comparar('abc', 'abd'), isFalse);
    expect(Seguranca.comparar('abc', 'abcd'), isFalse);
  });
}
