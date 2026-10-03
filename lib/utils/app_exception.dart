/// Erro "esperado" do app, com uma mensagem pronta para mostrar ao usuário.
class AppException implements Exception {
  final String mensagem;
  const AppException(this.mensagem);

  @override
  String toString() => mensagem;
}
