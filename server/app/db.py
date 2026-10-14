from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy import Engine, create_engine, event, inspect, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker


class Base(DeclarativeBase):
    pass


def make_engine(url: str) -> Engine:
    if url.startswith("sqlite"):
        engine = create_engine(url, connect_args={"check_same_thread": False})

        @event.listens_for(engine, "connect")
        def _fk(dbapi_conn, _record):  # type: ignore[no-untyped-def]
            cur = dbapi_conn.cursor()
            cur.execute("PRAGMA foreign_keys=ON")
            cur.close()

        return engine
    return create_engine(url, pool_pre_ping=True)


def make_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, expire_on_commit=False)


def session_iter(factory: sessionmaker[Session]) -> Iterator[Session]:
    with factory() as session:
        yield session


# Colunas acrescentadas depois da 1ª versão. `create_all` só cria tabelas novas; para bancos
# que já existem, esta migração leve adiciona as colunas que faltam (idempotente).
_COLUNAS_NOVAS: tuple[tuple[str, str, str], ...] = (
    ("usuarios", "valor_sessao_centavos", "INTEGER"),
    ("sessoes", "valor_centavos", "INTEGER NOT NULL DEFAULT 0"),
)


def garantir_colunas(engine: Engine) -> list[str]:
    """Adiciona colunas que faltam. Devolve a lista do que foi criado (ex.: 'usuarios.valor_sessao_centavos')."""
    criadas: list[str] = []
    insp = inspect(engine)
    for tabela, coluna, ddl in _COLUNAS_NOVAS:
        if tabela not in insp.get_table_names():
            continue
        if coluna in {c["name"] for c in insp.get_columns(tabela)}:
            continue
        with engine.begin() as conn:
            conn.execute(text(f"ALTER TABLE {tabela} ADD COLUMN {coluna} {ddl}"))
        criadas.append(f"{tabela}.{coluna}")
    return criadas
