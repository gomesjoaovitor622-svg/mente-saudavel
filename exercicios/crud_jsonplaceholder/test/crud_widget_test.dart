import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:crud_jsonplaceholder/main.dart';
import 'package:crud_jsonplaceholder/services/post_service.dart';

/// API falsa: responde como a JSONPlaceholder (inclusive "criar" sempre devolvendo id 101).
PostService _apiFalsa() {
  return PostService(client: MockClient((req) async {
    http.Response ok(Object corpo, [int status = 200]) =>
        http.Response(jsonEncode(corpo), status, headers: {'content-type': 'application/json; charset=utf-8'});
    final caminho = req.url.path;
    if (req.method == 'GET' && caminho == '/posts') {
      return ok([
        {'userId': 1, 'id': 1, 'title': 'Primeiro post', 'body': 'texto 1'},
        {'userId': 1, 'id': 2, 'title': 'Segundo post', 'body': 'texto 2'},
        {'userId': 2, 'id': 3, 'title': 'Terceiro post', 'body': 'texto 3'},
      ]);
    }
    if (req.method == 'POST') {
      return ok({...jsonDecode(req.body) as Map<String, dynamic>, 'id': 101}, 201);
    }
    if (req.method == 'PUT') return ok(jsonDecode(req.body));
    if (req.method == 'DELETE') return ok({});
    return http.Response('nao encontrado', 404);
  }));
}

Future<void> _abrirApp(WidgetTester tester) async {
  await tester.pumpWidget(CrudApp(service: _apiFalsa()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('READ: lista os posts vindos da API', (tester) async {
    await _abrirApp(tester);
    expect(find.text('Primeiro post'), findsOneWidget);
    expect(find.text('Segundo post'), findsOneWidget);
    expect(find.text('Terceiro post'), findsOneWidget);
  });

  testWidgets('READ: a busca filtra a lista', (tester) async {
    await _abrirApp(tester);
    await tester.enterText(find.byType(TextField), 'segundo');
    await tester.pumpAndSettle();
    expect(find.text('Segundo post'), findsOneWidget);
    expect(find.text('Primeiro post'), findsNothing);
  });

  testWidgets('CREATE: valida o formulário e adiciona o post na lista', (tester) async {
    await _abrirApp(tester);
    await tester.tap(find.byKey(const Key('novo-post')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('salvar'))); // vazio -> erros
    await tester.pumpAndSettle();
    expect(find.text('Informe o título.'), findsOneWidget);
    expect(find.text('Informe o texto do post.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('titulo')), 'Meu novo post');
    await tester.enterText(find.byKey(const Key('corpo')), 'conteúdo do post');
    await tester.tap(find.byKey(const Key('salvar')));
    await tester.pumpAndSettle();

    expect(find.text('Meu novo post'), findsOneWidget);
  });

  testWidgets('UPDATE: edita um post existente', (tester) async {
    await _abrirApp(tester);
    await tester.tap(find.byKey(const Key('menu-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('titulo')), 'Segundo post EDITADO');
    await tester.tap(find.byKey(const Key('salvar')));
    await tester.pumpAndSettle();

    expect(find.text('Segundo post EDITADO'), findsOneWidget);
    expect(find.text('Segundo post'), findsNothing);
  });

  testWidgets('DELETE: confirma e remove o post da lista', (tester) async {
    await _abrirApp(tester);
    await tester.tap(find.byKey(const Key('menu-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmar-exclusao')));
    await tester.pumpAndSettle();

    expect(find.text('Segundo post'), findsNothing);
    expect(find.text('Primeiro post'), findsOneWidget);
  });
}
