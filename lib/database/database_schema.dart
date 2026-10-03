import 'package:sqflite/sqflite.dart';

/// Scripts de criação das tabelas. Rodam automaticamente ao abrir o banco.
/// Todos usam "IF NOT EXISTS", então são seguros de executar várias vezes.
class DatabaseSchema {
  static const String _usuarios = '''
    CREATE TABLE IF NOT EXISTS usuarios (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      nome           TEXT NOT NULL,
      email          TEXT NOT NULL UNIQUE COLLATE NOCASE,
      senha_hash     TEXT NOT NULL,
      salt           TEXT NOT NULL,
      perfil         TEXT NOT NULL CHECK (perfil IN ('paciente', 'profissional')),
      registro       TEXT,
      especialidade  TEXT,
      endereco       TEXT,
      criado_em      TEXT NOT NULL
    )
  ''';

  static const String _sessoes = '''
    CREATE TABLE IF NOT EXISTS sessoes (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      paciente_id      INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      profissional_id  INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      data_hora        TEXT NOT NULL,
      modalidade       TEXT NOT NULL,
      status           TEXT NOT NULL DEFAULT 'agendada'
                       CHECK (status IN ('agendada', 'concluida', 'cancelada')),
      anotacoes        TEXT,
      criado_em        TEXT NOT NULL
    )
  ''';

  static const String _humor = '''
    CREATE TABLE IF NOT EXISTS humor_registros (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id  INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      nivel       INTEGER NOT NULL CHECK (nivel BETWEEN 1 AND 5),
      nota        TEXT,
      data_hora   TEXT NOT NULL
    )
  ''';

  // Guarda quem está logado, para o app abrir direto na tela certa.
  static const String _appSessao = '''
    CREATE TABLE IF NOT EXISTS app_sessao (
      id          INTEGER PRIMARY KEY CHECK (id = 1),
      usuario_id  INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE
    )
  ''';

  static const String _idxSessoesProfissional =
      'CREATE INDEX IF NOT EXISTS idx_sessoes_prof ON sessoes (profissional_id, data_hora)';
  static const String _idxSessoesPaciente =
      'CREATE INDEX IF NOT EXISTS idx_sessoes_pac ON sessoes (paciente_id, data_hora)';
  static const String _idxHumor =
      'CREATE INDEX IF NOT EXISTS idx_humor_usuario ON humor_registros (usuario_id, data_hora)';

  static const List<String> _scripts = [
    _usuarios,
    _sessoes,
    _humor,
    _appSessao,
    _idxSessoesProfissional,
    _idxSessoesPaciente,
    _idxHumor,
  ];

  static Future<void> executar(DatabaseExecutor db) async {
    for (final script in _scripts) {
      await db.execute(script);
    }
  }
}
