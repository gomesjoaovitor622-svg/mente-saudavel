-- Mente Saudável: estrutura do banco SQLite (igual à criada pelo app)
-- Arquivo do banco no app: mente_saudavel.db

PRAGMA foreign_keys = ON;

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
    );

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
    );

CREATE TABLE IF NOT EXISTS humor_registros (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id  INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      nivel       INTEGER NOT NULL CHECK (nivel BETWEEN 1 AND 5),
      nota        TEXT,
      data_hora   TEXT NOT NULL
    );

CREATE TABLE IF NOT EXISTS app_sessao (
      id          INTEGER PRIMARY KEY CHECK (id = 1),
      usuario_id  INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE
    );

CREATE INDEX IF NOT EXISTS idx_sessoes_prof ON sessoes (profissional_id, data_hora);

CREATE INDEX IF NOT EXISTS idx_sessoes_pac ON sessoes (paciente_id, data_hora);

CREATE INDEX IF NOT EXISTS idx_humor_usuario ON humor_registros (usuario_id, data_hora);

