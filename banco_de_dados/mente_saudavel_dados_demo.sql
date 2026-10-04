-- Mente Saudável: estrutura + dados de demonstração
-- Contas: helena@mentesaudavel.app / mente123 (profissional) | carlos@email.com / 123456 (paciente)
BEGIN TRANSACTION;
CREATE TABLE app_sessao (
      id          INTEGER PRIMARY KEY CHECK (id = 1),
      usuario_id  INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE
    );
CREATE TABLE humor_registros (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id  INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
      nivel       INTEGER NOT NULL CHECK (nivel BETWEEN 1 AND 5),
      nota        TEXT,
      data_hora   TEXT NOT NULL
    );
INSERT INTO "humor_registros" VALUES(1,4,3,'Dia cansativo no trabalho','2026-10-01T20:00:00.000');
INSERT INTO "humor_registros" VALUES(2,4,4,'Consegui dormir melhor','2026-10-02T20:00:00.000');
INSERT INTO "humor_registros" VALUES(3,4,5,'Ótimo dia!','2026-10-03T20:00:00.000');
CREATE TABLE sessoes (
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
INSERT INTO "sessoes" VALUES(1,4,1,'2026-09-25T10:00:00.000','Online','concluida','Primeira sessão: queixa principal de ansiedade no trabalho.','2026-10-04T02:19:51.000');
INSERT INTO "sessoes" VALUES(2,4,1,'2026-10-02T10:00:00.000','Online','concluida','Trabalhadas técnicas de respiração e rotina de sono.','2026-10-04T02:19:51.000');
INSERT INTO "sessoes" VALUES(3,4,1,'2026-10-04T14:00:00.000','Online','agendada',NULL,'2026-10-04T02:19:51.000');
INSERT INTO "sessoes" VALUES(4,4,1,'2026-10-07T15:00:00.000','Presencial','agendada',NULL,'2026-10-04T02:19:51.000');
CREATE TABLE usuarios (
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
INSERT INTO "usuarios" VALUES(1,'Dra. Helena Marques','helena@mentesaudavel.app','1c3883b2dc2f36fd14a5715602446e0954bf658378aa463f4f83072427b96e1d','ml5FCCHaS1-TFBRTseuI_w==','profissional','06/12345','Psicologia clínica','Av. Paulista, 1000, Bela Vista, São Paulo - SP','2026-10-04T02:19:51.000');
INSERT INTO "usuarios" VALUES(2,'Dr. Rafael Andrade','rafael@mentesaudavel.app','40cea2e8721c1da171d264248c23493a9e6312d05305e37bbf3d8760fa0083cb','kSIOKdG-brmMDhCsyPMgiQ==','profissional','06/54321','Terapia cognitivo-comportamental',NULL,'2026-10-04T02:19:51.000');
INSERT INTO "usuarios" VALUES(3,'Dra. Beatriz Souza','beatriz@mentesaudavel.app','e6cbfd6b0cd42441a8228fdbd2d4c9177c47bda9985d0e68f09215c731145e57','u37WQsXKlnHMxcPfnFCFmg==','profissional','06/11223','Psicologia infantil',NULL,'2026-10-04T02:19:51.000');
INSERT INTO "usuarios" VALUES(4,'Carlos Silva','carlos@email.com','621fc18838de961d12742d474ba3c1710fb608f7f47491b856e9d4eb7e1f64df','sX-4aSZAwYgt1VznJluWfw==','paciente',NULL,NULL,NULL,'2026-10-04T02:19:51.000');
CREATE INDEX idx_sessoes_prof ON sessoes (profissional_id, data_hora);
CREATE INDEX idx_sessoes_pac ON sessoes (paciente_id, data_hora);
CREATE INDEX idx_humor_usuario ON humor_registros (usuario_id, data_hora);
DELETE FROM "sqlite_sequence";
INSERT INTO "sqlite_sequence" VALUES('usuarios',4);
INSERT INTO "sqlite_sequence" VALUES('sessoes',4);
INSERT INTO "sqlite_sequence" VALUES('humor_registros',3);
COMMIT;
