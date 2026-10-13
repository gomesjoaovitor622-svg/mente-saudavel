/// Flags de compilação. Definidas com `--dart-define=NOME=valor` (o CI faz isso).
library;

/// `true` somente em builds de demonstração: cria contas/dados de exemplo e mostra as
/// credenciais na tela de login. Builds de PRODUÇÃO (tag vX.Y.Z) compilam com `false`.
///
/// Uso local: `flutter run --dart-define=DEMO_MODE=true`
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');

/// Endereço da API. Vazio = modo LOCAL (SQLite no aparelho, sem servidor).
/// No site hospedado o CI usa `--dart-define=API_URL=/api` (mesmo domínio, via Caddy).
/// No celular, use a URL completa: `--dart-define=API_URL=https://app.seudominio.com/api`.
const String kApiUrl = String.fromEnvironment('API_URL');

/// `true` quando o app conversa com o servidor em vez do SQLite local.
const bool usaServidor = kApiUrl != '';
