import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mente_saudavel/models/usuario.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/services/auth_service.dart';
import 'package:mente_saudavel/utils/app_exception.dart';
import 'package:mente_saudavel/widgets/avisos_conta.dart';

http.Response _json(int status, Object corpo) =>
    http.Response.bytes(utf8.encode(jsonEncode(corpo)), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, Object?> _usuario({String perfil = 'paciente', bool verificado = true, bool precisaEmail = false}) => {
      'id': 1,
      'nome': 'Ana Souza',
      'email': 'ana@x.com',
      'perfil': perfil,
      'criado_em': '2026-10-28T10:00:00',
      'verificado': verificado,
      'precisa_verificar_email': precisaEmail,
    };

Widget _app(Usuario? u) => MaterialApp(home: Scaffold(body: AvisosConta(usuario: u)));

void main() {
  late List<http.Request> recebidas;

  void servidor(http.Response Function(http.Request) resposta) {
    recebidas = [];
    ApiClient.cliente = MockClient((req) async {
      recebidas.add(req);
      return resposta(req);
    });
  }

  tearDown(() => ApiClient.cliente = http.Client());

  group('Usuario', () {
    test('lê os campos novos do servidor', () {
      final u = Usuario.fromMap(_usuario(perfil: 'profissional', verificado: false, precisaEmail: true));
      expect(u.verificado, isFalse);
      expect(u.precisaVerificarEmail, isTrue);
    });

    test('sem os campos (modo local ou servidor antigo) nada é bloqueado', () {
      final u = Usuario.fromMap({'id': 1, 'nome': 'A', 'perfil': 'paciente'});
      expect(u.verificado, isTrue);
      expect(u.precisaVerificarEmail, isFalse);
    });

    test('copyWith preserva os avisos', () {
      final u = Usuario.fromMap(_usuario(verificado: false, precisaEmail: true)).copyWith(nome: 'Outra');
      expect(u.verificado, isFalse);
      expect(u.precisaVerificarEmail, isTrue);
    });
  });

  group('AuthService (recuperação e confirmação)', () {
    test('esqueci a senha manda só o e-mail, sem token', () async {
      servidor((_) => http.Response('', 204));
      await AuthService.esqueciSenha('  ana@x.com ');
      expect(recebidas.single.url.path, endsWith('/auth/senha/esqueci'));
      expect(jsonDecode(recebidas.single.body), {'email': 'ana@x.com'});
      expect(recebidas.single.headers.containsKey('authorization'), isFalse);
    });

    test('redefinir envia e-mail, código e nova senha; código errado vira mensagem', () async {
      servidor((_) => _json(400, {'detail': 'Código inválido ou expirado. Peça um novo código.'}));
      await expectLater(
        AuthService.redefinirSenha('ana@x.com', ' 123456 ', 'nova-senha-1'),
        throwsA(isA<AppException>().having((e) => e.mensagem, 'mensagem', contains('Código inválido'))),
      );
      expect(jsonDecode(recebidas.single.body), {'email': 'ana@x.com', 'codigo': '123456', 'nova_senha': 'nova-senha-1'});
    });

    test('confirmar e-mail recarrega o usuário e o aviso some', () async {
      servidor((req) {
        if (req.url.path.endsWith('/auth/email/verificar')) return http.Response('', 204);
        return _json(200, _usuario(precisaEmail: false));
      });
      await AuthService.verificarEmail('123456');
      expect(recebidas.length, 2);
      expect(recebidas[0].url.path, endsWith('/auth/email/verificar'));
      expect(recebidas[1].url.path, endsWith('/auth/eu'));
      expect(AuthService.atual.value!.precisaVerificarEmail, isFalse);
    });
  });

  group('AvisosConta', () {
    testWidgets('profissional em análise vê o aviso', (t) async {
      await t.pumpWidget(_app(Usuario.fromMap(_usuario(perfil: 'profissional', verificado: false))));
      expect(find.text('Cadastro em análise'), findsOneWidget);
    });

    testWidgets('profissional aprovado não vê aviso', (t) async {
      await t.pumpWidget(_app(Usuario.fromMap(_usuario(perfil: 'profissional'))));
      expect(find.text('Cadastro em análise'), findsNothing);
    });

    testWidgets('paciente nunca vê "em análise", mesmo com verificado=false', (t) async {
      await t.pumpWidget(_app(Usuario.fromMap(_usuario(verificado: false))));
      expect(find.text('Cadastro em análise'), findsNothing);
    });

    testWidgets('e-mail pendente mostra o aviso e abre o diálogo do código', (t) async {
      await t.pumpWidget(_app(Usuario.fromMap(_usuario(precisaEmail: true))));
      expect(find.text('Confirme seu e-mail'), findsOneWidget);
      await t.tap(find.text('Digitar código'));
      await t.pumpAndSettle();
      expect(find.text('Confirmar e-mail'), findsOneWidget);
      await t.tap(find.text('Confirmar'));
      await t.pump();
      expect(find.text('Digite os 6 números.'), findsOneWidget);
    });

    testWidgets('sem usuário não mostra nada', (t) async {
      await t.pumpWidget(_app(null));
      expect(find.byType(Container), findsNothing);
    });
  });
}
