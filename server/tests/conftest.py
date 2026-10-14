from __future__ import annotations

import os
from collections.abc import Iterator
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool

from app.config import Settings
from app.db import Base, make_engine
from app.main import create_app


@pytest.fixture()
def client() -> Iterator[TestClient]:
    from sqlalchemy import create_engine, event

    pg = os.environ.get("TEST_DATABASE_URL")  # roda a mesma suíte em PostgreSQL de verdade
    if pg:
        engine = make_engine(pg)
        Base.metadata.drop_all(engine)
    else:
        engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)

        @event.listens_for(engine, "connect")
        def _fk(dbapi_conn, _r):  # type: ignore[no-untyped-def]
            dbapi_conn.execute("PRAGMA foreign_keys=ON")

    cfg = Settings(
        env="development",
        database_url="sqlite://",
        jwt_secret="x" * 40,
        cors_origins=("https://site.exemplo",),
        password_min=8,
        login_max_attempts=5,
        signup_max_attempts=1000,
    )
    with TestClient(create_app(cfg, engine)) as c:
        yield c


def cadastrar(client: TestClient, email: str, perfil: str = "paciente", senha: str = "senha-forte-1", **extra: str) -> dict:
    body = {"nome": f"Nome {email}", "email": email, "senha": senha, "perfil": perfil, **extra}
    if perfil == "profissional":
        body.setdefault("registro", "06/00001")
    r = client.post("/auth/cadastro", json=body)
    assert r.status_code == 201, r.text
    data = r.json()
    return {"id": data["usuario"]["id"], "h": {"Authorization": f"Bearer {data['token']}"}}


def futuro(horas: int = 48, hora: int = 10) -> str:
    d = (datetime.now() + timedelta(hours=horas)).replace(hour=hora, minute=0, second=0, microsecond=0)
    return d.isoformat()
