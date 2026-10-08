/// Flags de compilação. Definidas com `--dart-define=NOME=valor` (o CI faz isso).
library;

/// `true` somente em builds de demonstração: cria contas/dados de exemplo e mostra as
/// credenciais na tela de login. Builds de PRODUÇÃO (tag vX.Y.Z) compilam com `false`.
///
/// Uso local: `flutter run --dart-define=DEMO_MODE=true`
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');
