import 'package:flutter_test/flutter_test.dart';
import 'package:mente_saudavel/services/api_client.dart';
import 'package:mente_saudavel/services/token_store.dart';

class _Memoria implements TokenStore {
  String? valor;
  int gravacoes = 0;
  @override
  Future<String?> ler() async => valor;
  @override
  Future<void> gravar(String token) async {
    gravacoes++;
    valor = token;
  }

  @override
  Future<void> apagar() async => valor = null;
}

void main() {
  tearDown(() async {
    await ApiClient.limparToken();
    ApiClient.usaCookie = false;
  });

  test('celular: o token vai para o armazenamento seguro e volta de lá', () async {
    final loja = _Memoria();
    ApiClient.armazenamento = loja;
    ApiClient.usaCookie = false;
    await ApiClient.salvarToken('abc');
    expect(loja.valor, 'abc');
    expect(await ApiClient.carregarToken(), 'abc');
    await ApiClient.limparToken();
    expect(loja.valor, isNull);
  });

  test('web: o token NÃO é guardado em lugar nenhum (a credencial é o cookie HttpOnly)', () async {
    final loja = _Memoria();
    ApiClient.armazenamento = loja;
    ApiClient.usaCookie = true;
    await ApiClient.salvarToken('abc');
    expect(loja.gravacoes, 0);
    expect(await ApiClient.carregarToken(), isNull);
  });
}
