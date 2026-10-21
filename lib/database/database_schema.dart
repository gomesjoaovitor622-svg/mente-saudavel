import 'package:sqflite/sqflite.dart';

/// Scripts de criação do banco (versão MAIS RECENTE do esquema).
///
/// Rodam só na 1ª execução (`onCreate`). Bancos que já existem não passam por aqui:
/// eles evoluem pelos passos de `Migracoes`, que precisam deixar o banco idêntico a este.
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
      valor_sessao_centavos INTEGER,
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
      valor_centavos   INTEGER NOT NULL DEFAULT 0,
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

  // v2: nota (1 a 5) e comentário que o paciente dá a uma sessão concluída.
  static const String avaliacoes = '''
    CREATE TABLE IF NOT EXISTS avaliacoes (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      sessao_id        INTEGER NOT NULL UNIQUE REFERENCES sessoes(id) ON DELETE CASCADE,
      paciente_id      INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      profissional_id  INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      nota             INTEGER NOT NULL CHECK (nota BETWEEN 1 AND 5),
      comentario       TEXT,
      criado_em        TEXT NOT NULL
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
  // Anti-corrida: o BANCO recusa duas sessões ativas no mesmo horário (cancelar libera o horário).
  static const String idxSessaoProfissionalUnico =
      "CREATE UNIQUE INDEX IF NOT EXISTS uq_sessao_prof_horario ON sessoes (profissional_id, data_hora) WHERE status <> 'cancelada'";
  static const String idxSessaoPacienteUnico =
      "CREATE UNIQUE INDEX IF NOT EXISTS uq_sessao_pac_horario ON sessoes (paciente_id, data_hora) WHERE status <> 'cancelada'";

  static const String _idxHumor =
      'CREATE INDEX IF NOT EXISTS idx_humor_usuario ON humor_registros (usuario_id, data_hora)';

  static const String idxAvaliacoes =
      'CREATE INDEX IF NOT EXISTS idx_avaliacoes_prof ON avaliacoes (profissional_id)';

  static const List<String> _scripts = [
    _usuarios,
    _sessoes,
    _humor,
    avaliacoes,
    _appSessao,
    _idxSessoesProfissional,
    _idxSessoesPaciente,
    _idxHumor,
    idxAvaliacoes,
    idxSessaoProfissionalUnico,
    idxSessaoPacienteUnico,
  ];

  static Future<void> criarTudo(DatabaseExecutor db) async {
    for (final script in _scripts) {
      await db.execute(script);
    }
  }
}
