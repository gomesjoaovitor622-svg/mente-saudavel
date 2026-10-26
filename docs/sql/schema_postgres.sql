BEGIN;

CREATE TABLE alembic_version (
    version_num VARCHAR(32) NOT NULL, 
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);

-- Running upgrade  -> 0001

CREATE TABLE usuarios (
    id SERIAL NOT NULL, 
    nome VARCHAR(120) NOT NULL, 
    email VARCHAR(254) NOT NULL, 
    senha_hash VARCHAR(255) NOT NULL, 
    perfil VARCHAR(20) NOT NULL, 
    registro VARCHAR(40), 
    especialidade VARCHAR(120), 
    endereco VARCHAR(255), 
    valor_sessao_centavos INTEGER, 
    criado_em TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
    aceite_termos_versao VARCHAR(20), 
    aceite_termos_em TIMESTAMP WITHOUT TIME ZONE, 
    anonimizado_em TIMESTAMP WITHOUT TIME ZONE, 
    PRIMARY KEY (id), 
    CONSTRAINT ck_perfil CHECK (perfil IN ('paciente','profissional'))
);

CREATE UNIQUE INDEX ix_usuarios_email ON usuarios (email);

CREATE TABLE sessoes (
    id SERIAL NOT NULL, 
    paciente_id INTEGER NOT NULL, 
    profissional_id INTEGER NOT NULL, 
    data_hora TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
    modalidade VARCHAR(20) NOT NULL, 
    status VARCHAR(20) NOT NULL, 
    anotacoes TEXT, 
    chave_idempotencia VARCHAR(64), 
    valor_centavos INTEGER DEFAULT '0' NOT NULL, 
    criado_em TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
    PRIMARY KEY (id), 
    CONSTRAINT ck_status CHECK (status IN ('agendada','concluida','cancelada')), 
    FOREIGN KEY(paciente_id) REFERENCES usuarios (id) ON DELETE CASCADE, 
    FOREIGN KEY(profissional_id) REFERENCES usuarios (id) ON DELETE CASCADE
);

CREATE INDEX idx_sessoes_prof ON sessoes (profissional_id, data_hora);

CREATE INDEX idx_sessoes_pac ON sessoes (paciente_id, data_hora);

CREATE UNIQUE INDEX uq_sessao_prof_horario ON sessoes (profissional_id, data_hora) WHERE status <> 'cancelada';

CREATE UNIQUE INDEX uq_sessao_pac_horario ON sessoes (paciente_id, data_hora) WHERE status <> 'cancelada';

CREATE UNIQUE INDEX uq_sessao_idempotencia ON sessoes (paciente_id, chave_idempotencia) WHERE chave_idempotencia IS NOT NULL;

CREATE TABLE humor_registros (
    id SERIAL NOT NULL, 
    usuario_id INTEGER NOT NULL, 
    nivel INTEGER NOT NULL, 
    nota TEXT NOT NULL, 
    data_hora TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
    PRIMARY KEY (id), 
    CONSTRAINT ck_nivel CHECK (nivel BETWEEN 1 AND 5), 
    FOREIGN KEY(usuario_id) REFERENCES usuarios (id) ON DELETE CASCADE
);

CREATE INDEX idx_humor_usuario ON humor_registros (usuario_id, data_hora);

CREATE TABLE avaliacoes (
    id SERIAL NOT NULL, 
    sessao_id INTEGER NOT NULL, 
    paciente_id INTEGER NOT NULL, 
    profissional_id INTEGER NOT NULL, 
    nota INTEGER NOT NULL, 
    comentario TEXT NOT NULL, 
    criado_em TIMESTAMP WITHOUT TIME ZONE NOT NULL, 
    PRIMARY KEY (id), 
    CONSTRAINT ck_nota CHECK (nota BETWEEN 1 AND 5), 
    CONSTRAINT uq_avaliacao_sessao UNIQUE (sessao_id), 
    FOREIGN KEY(sessao_id) REFERENCES sessoes (id) ON DELETE CASCADE, 
    FOREIGN KEY(paciente_id) REFERENCES usuarios (id) ON DELETE CASCADE, 
    FOREIGN KEY(profissional_id) REFERENCES usuarios (id) ON DELETE CASCADE
);

CREATE INDEX idx_avaliacoes_prof ON avaliacoes (profissional_id);

INSERT INTO alembic_version (version_num) VALUES ('0001') RETURNING alembic_version.version_num;

COMMIT;

