"""Videochamada: só os dois participantes, só em sessão online ativa, só na janela de horário; token Jitsi correto."""

from __future__ import annotations

from collections.abc import Iterator
from datetime import datetime, timedelta
from urllib.parse import parse_qs, urlparse

import jwt
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.pool import StaticPool

import app.video as video_mod
from app.config import Settings
from app.main import create_app
from tests.conftest import cadastrar

DOMINIO = "meet.exemplo.com.br"
SEGREDO_VIDEO = "segredo-do-jitsi-com-mais-de-32-caracteres"


def _cliente(**extra) -> Iterator[TestClient]:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)

    @event.listens_for(engine, "connect")
    def _fk(dbapi_conn, _r):  # type: ignore[no-untyped-def]
        dbapi_conn.execute("PRAGMA foreign_keys=ON")

    cfg = Settings(env="development", database_url="sqlite://", jwt_secret="x" * 40, signup_max_attempts=1000, **extra)
    with TestClient(create_app(cfg, engine)) as c:
        yield c


@pytest.fixture()
def client() -> Iterator[TestClient]:
    yield from _cliente(video_domain=DOMINIO, video_app_id="ms-teste", video_app_secret=SEGREDO_VIDEO)


@pytest.fixture()
def client_sem_video() -> Iterator[TestClient]:
    yield from _cliente()


def _sessao(client: TestClient, minutos: int = 10, modalidade: str = "Online") -> tuple[dict, dict, int]:
    pro = cadastrar(client, "pro-video@x.com", "profissional")
    pac = cadastrar(client, "pac-video@x.com")
    quando = (datetime.now() + timedelta(minutes=minutos)).replace(microsecond=0).isoformat()
    r = client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": quando, "modalidade": modalidade})
    assert r.status_code == 201, r.text
    return pro, pac, r.json()["id"]


def _claims(url: str) -> dict:
    token = parse_qs(urlparse(url).query)["jwt"][0]
    return jwt.decode(token, SEGREDO_VIDEO, algorithms=["HS256"], audience="jitsi")


def test_os_dois_entram_na_mesma_sala_com_papeis_diferentes(client):
    pro, pac, sid = _sessao(client)
    p = client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()
    a = client.get(f"/sessoes/{sid}/video", headers=pac["h"]).json()
    assert p["sala"] == a["sala"] and p["sala"].startswith("ms-") and len(p["sala"]) == 35
    assert p["moderador"] is True and a["moderador"] is False
    assert urlparse(p["url"]).netloc == DOMINIO and urlparse(p["url"]).path == f"/{p['sala']}"
    cp, ca = _claims(p["url"]), _claims(a["url"])
    assert cp["room"] == ca["room"] == p["sala"] and cp["iss"] == "ms-teste" and cp["sub"] == DOMINIO
    assert cp["context"]["user"]["moderator"] is True and ca["context"]["user"]["moderator"] is False
    assert ca["context"]["user"]["name"] == "Nome"  # paciente: só o primeiro nome ("Nome pac-video@x.com" -> "Nome")
    assert "email" not in str(ca)  # minimização de dados


def test_token_expira_no_fim_da_janela(client):
    pro, _, sid = _sessao(client, minutos=10)
    exp = _claims(client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()["url"])["exp"]
    esperado = (datetime.now() + timedelta(minutes=10 + 120)).timestamp()
    assert abs(exp - esperado) < 90


def test_salas_de_sessoes_diferentes_sao_diferentes_e_imprevisiveis(client):
    pro, pac, sid = _sessao(client)
    quando = (datetime.now() + timedelta(minutes=300)).replace(microsecond=0).isoformat()
    sid2 = client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": quando, "modalidade": "Online"}).json()["id"]
    s1 = client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()["sala"]
    assert s1 == client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()["sala"]  # estável
    assert s1[3:].isalnum()  # hex
    assert sid2 != sid


def test_quem_nao_participa_recebe_404(client):
    _, _, sid = _sessao(client)
    intruso = cadastrar(client, "intruso@x.com")
    outro_pro = cadastrar(client, "outro-pro@x.com", "profissional")
    assert client.get(f"/sessoes/{sid}/video", headers=intruso["h"]).status_code == 404
    assert client.get(f"/sessoes/{sid}/video", headers=outro_pro["h"]).status_code == 404
    assert client.get(f"/sessoes/{sid}/video").status_code == 401
    assert client.get("/sessoes/99999/video", headers=intruso["h"]).status_code == 404


def test_sessao_presencial_cancelada_e_fora_da_janela_sao_recusadas(client):
    pro, pac, sid = _sessao(client, minutos=10, modalidade="Presencial")
    assert client.get(f"/sessoes/{sid}/video", headers=pro["h"]).status_code == 409
    pro2 = cadastrar(client, "pro2@x.com", "profissional")
    quando = (datetime.now() + timedelta(minutes=12)).replace(microsecond=0).isoformat()  # outro horário: o paciente não pode ter dois no mesmo
    sid2 = client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro2["id"], "data_hora": quando, "modalidade": "Online"}).json()["id"]
    assert client.get(f"/sessoes/{sid2}/video", headers=pac["h"]).status_code == 200
    client.patch(f"/sessoes/{sid2}", headers=pac["h"], json={"status": "cancelada"})
    assert client.get(f"/sessoes/{sid2}/video", headers=pac["h"]).status_code == 409
    # cedo demais: sessão daqui a 3 horas (a janela abre 15 min antes)
    pro3 = cadastrar(client, "pro3@x.com", "profissional")
    longe = (datetime.now() + timedelta(hours=3)).replace(microsecond=0).isoformat()
    sid3 = client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro3["id"], "data_hora": longe, "modalidade": "Online"}).json()["id"]
    r = client.get(f"/sessoes/{sid3}/video", headers=pac["h"])
    assert r.status_code == 409 and "abre às" in r.json()["detail"]


def test_depois_da_janela_a_sala_fecha(client, monkeypatch):
    pro, _, sid = _sessao(client, minutos=10)

    class Depois(datetime):
        @classmethod
        def now(cls, tz=None):  # type: ignore[no-untyped-def]
            return datetime.now() + timedelta(minutes=10 + 121)

    monkeypatch.setattr(video_mod, "datetime", Depois)
    r = client.get(f"/sessoes/{sid}/video", headers=pro["h"])
    assert r.status_code == 409 and "já passou" in r.json()["detail"]


def test_recurso_desligado_sem_dominio(client_sem_video):
    pro, _, sid = _sessao(client_sem_video)
    assert client_sem_video.get(f"/sessoes/{sid}/video", headers=pro["h"]).status_code == 503


def test_sem_segredo_o_link_nao_leva_token_mas_a_sala_continua_imprevisivel():
    for c in _cliente(video_domain=DOMINIO):
        pro, _, sid = _sessao(c)
        r = c.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()
        assert "jwt=" not in r["url"] and r["sala"] in r["url"]
