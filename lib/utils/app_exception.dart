/// Erro "esperado" do app, com uma mensagem pronta para mostrar ao usuário.
class AppException implements Exception {
  final String mensagem;

  /// Status HTTP quando o erro veio do servidor (null para erros locais).
  final int? statusHttp;
  const AppException(this.mensagem, {this.statusHttp});

  @override
  String toString() => mensagem;
}

/// Conflito com o estado atual (HTTP 409 na API; índice único no SQLite): por exemplo,
/// horário já ocupado. A tela deve mostrar a mensagem e recarregar a disponibilidade.
class ConflitoException extends AppException {
  const ConflitoException(super.mensagem) : super(statusHttp: 409);
}

/// Falha de REDE (sem internet, servidor fora do ar, tempo esgotado). Diferente de um erro do
/// servidor: aqui vale guardar a ação na fila offline e tentar de novo depois.
class SemConexaoException extends AppException {
  const SemConexaoException(super.mensagem);
}
