"""Ponte entre a API e o Alembic: descobre a versão esperada (head) e confere a do banco."""

from __future__ import annotations

from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import Engine, inspect, text

RAIZ = Path(__file__).resolve().parent.parent  # pasta server/ (ou /srv na imagem Docker)


def config_alembic() -> Config:
    cfg = Config(str(RAIZ / "alembic.ini"))
    cfg.set_main_option("script_location", str(RAIZ / "migrations"))
    return cfg


def versao_esperada() -> str:
    """Última revisão (head) existente nos arquivos de migração."""
    return ScriptDirectory.from_config(config_alembic()).get_current_head() or ""


def versao_atual(engine: Engine) -> str | None:
    """Revisão gravada no banco (None = nunca migrado)."""
    if "alembic_version" not in inspect(engine).get_table_names():
        return None
    with engine.connect() as conn:
        return conn.execute(text("SELECT version_num FROM alembic_version")).scalar()


def exigir_banco_migrado(engine: Engine) -> None:
    esperada, atual = versao_esperada(), versao_atual(engine)
    if atual != esperada:
        raise RuntimeError(
            f"Banco na versão {atual!r}, a API espera {esperada!r}. Rode as migrações antes de subir: `alembic upgrade head` "
            "(banco que já existia sem Alembic: `alembic stamp 0001`, depois `alembic upgrade head`)."
        )
