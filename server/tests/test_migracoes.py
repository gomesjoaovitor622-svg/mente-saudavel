"""Migrações Alembic: o esquema versionado precisa ser IDÊNTICO ao dos models e valer as regras anti-corrida."""

from __future__ import annotations

import os
from collections.abc import Iterator
from datetime import datetime
from pathlib import Path

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import Engine, text
from sqlalchemy.exc import IntegrityError

from app.config import url_do_banco
from app.db import Base, make_engine
from app.migracoes import config_alembic, exigir_banco_migrado, versao_atual, versao_esperada


@pytest.fixture
def engine(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[Engine]:
    url = os.environ.get("TEST_DATABASE_URL") or f"sqlite:///{tmp_path / 'mig.db'}"
    monkeypatch.setenv("DATABASE_URL", url)
    eng = make_engine(url_do_banco())
    _limpar(eng)
    yield eng
    _limpar(eng)
    eng.dispose()


def _limpar(eng: Engine) -> None:
    Base.metadata.drop_all(eng)
    with eng.begin() as c:
        c.execute(text("DROP TABLE IF EXISTS alembic_version"))


def _subir(eng: Engine) -> None:
    cfg = config_alembic()
    with eng.begin() as conn:
        cfg.attributes["connection"] = conn
        command.upgrade(cfg, "head")


def test_banco_novo_sobe_ate_head_e_bate_com_os_models(engine: Engine) -> None:
    assert versao_atual(engine) is None
    with pytest.raises(RuntimeError):
        exigir_banco_migrado(engine)
    _subir(engine)
    assert versao_atual(engine) == versao_esperada()
    exigir_banco_migrado(engine)
    with engine.connect() as conn:
        diffs = compare_metadata(MigrationContext.configure(conn, opts={"compare_type": True}), Base.metadata)
    assert diffs == []


def test_indices_parciais_bloqueiam_horario_duplicado_mas_liberam_cancelada(engine: Engine) -> None:
    _subir(engine)
    agora = datetime(2030, 1, 1, 10, 0)
    with engine.begin() as c:
        for i, perfil in ((1, "paciente"), (2, "profissional"), (3, "paciente")):
            c.execute(
                text("INSERT INTO usuarios (id, nome, email, senha_hash, perfil, criado_em) VALUES (:i, 'x', :e, 'h', :p, :t)"),
                {"i": i, "e": f"u{i}@x.com", "p": perfil, "t": agora},
            )

    def inserir(c, pac: int, status: str) -> None:  # noqa: ANN001
        c.execute(
            text("INSERT INTO sessoes (paciente_id, profissional_id, data_hora, modalidade, status, criado_em) VALUES (:pac, 2, :t, 'online', :s, :t)"),
            {"pac": pac, "s": status, "t": agora},
        )

    with engine.begin() as c:
        inserir(c, 1, "agendada")
    with pytest.raises(IntegrityError), engine.begin() as c:
        inserir(c, 3, "agendada")  # mesmo profissional e horário
    with engine.begin() as c:
        inserir(c, 3, "cancelada")  # cancelada não ocupa o horário


def test_downgrade_remove_tudo(engine: Engine) -> None:
    _subir(engine)
    cfg = config_alembic()
    with engine.begin() as conn:
        cfg.attributes["connection"] = conn
        command.downgrade(cfg, "base")
    with engine.connect() as conn:
        assert "usuarios" not in MigrationContext.configure(conn).connection.dialect.get_table_names(conn)  # type: ignore[union-attr]
