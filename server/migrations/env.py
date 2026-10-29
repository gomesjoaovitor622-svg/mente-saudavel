"""Ambiente do Alembic. A URL vem de DATABASE_URL; os testes podem entregar uma conexão pronta."""

from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy.engine import Connection

from app import models  # noqa: F401  (registra as tabelas em Base.metadata)
from app.config import url_do_banco
from app.db import Base, make_engine

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name, disable_existing_loggers=False)

target_metadata = Base.metadata


def _configurar(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
        render_as_batch=connection.dialect.name == "sqlite",  # SQLite não altera colunas direto
    )


def run_migrations_offline() -> None:
    """Gera o SQL sem conectar (`alembic upgrade head --sql`): útil para revisar ou aplicar à mão."""
    context.configure(
        url=url_do_banco(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    pronta = config.attributes.get("connection")
    if pronta is not None:  # testes: conexão já aberta
        _configurar(pronta)
        with context.begin_transaction():
            context.run_migrations()
        return
    engine = make_engine(url_do_banco())
    try:
        with engine.connect() as connection:
            _configurar(connection)
            with context.begin_transaction():
                context.run_migrations()
            connection.commit()
    finally:
        engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
