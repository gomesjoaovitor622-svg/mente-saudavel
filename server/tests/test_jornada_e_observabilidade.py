"""Jornada ponta a ponta (E2E na API), idempotência do humor, prontidão do banco e métricas de produção."""

from __future__ import annotations

import os
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.exc import OperationalError
from sqlalchemy.pool import StaticPool

from app.config import Settings
from app.deps import get_db
from app.main import create_app
from tests.conftest import cadastrar, futuro
from tests.test_conta import Caixa, ctx

H_WEB = {"X-Requested-With": "mente-saudavel"}


# ------------------------------------------------------------------ E2E: jornada completa do paciente
def test_jornada_completa_cadastro_confirmacao_agenda_humor_logout_e_novo_login(ctx):
    c, caixa = ctx
    pro = cadastrar(c, "pro-jornada@x.com", "profissional")

    # 1) cadastro devolve sessão; o código chega por e-mail e confirma a conta
    r = c.post("/auth/cadastro", json={"nome": "Ana", "email": "ana-jornada@x.com", "senha": "senha-forte-1", "perfil": "paciente"})
    assert r.status_code == 201
    h = {"Authorization": f"Bearer {r.json()['token']}"}
    assert c.post("/auth/email/verificar", headers=h, json={"codigo": caixa.codigo("ana-jornada@x.com")}).status_code in {200, 204}

    # 2) agenda (com chave de idempotência, como o app offline) e registra humor
    quando = futuro()
    corpo = {"profissional_id": pro["id"], "data_hora": quando, "modalidade": "Online"}
    sid = c.post("/sessoes", headers={**h, "Idempotency-Key": "jornada-sessao-1"}, json=corpo)
    assert sid.status_code == 201
    assert c.post("/humor", headers={**h, "Idempotency-Key": "jornada-humor-1"}, json={"nivel": 4, "nota": "ok"}).status_code == 201

    # 3) sair revoga a sessão em todos os aparelhos
    assert c.post("/auth/sair", headers=h).status_code == 204
    assert c.get("/sessoes", headers=h).status_code == 401

    # 4) entrar de novo: os dados continuam lá e o reenvio da fila offline não duplica nada
    novo = c.post("/auth/entrar", json={"email": "ana-jornada@x.com", "senha": "senha-forte-1"}).json()["token"]
    h2 = {"Authorization": f"Bearer {novo}"}
    assert len(c.get("/sessoes", headers=h2).json()) == 1
    assert len(c.get("/humor", headers=h2).json()) == 1
    assert c.post("/sessoes", headers={**h2, "Idempotency-Key": "jornada-sessao-1"}, json=corpo).status_code == 200
    assert c.post("/humor", headers={**h2, "Idempotency-Key": "jornada-humor-1"}, json={"nivel": 4, "nota": "ok"}).status_code == 200
    assert len(c.get("/sessoes", headers=h2).json()) == 1
    assert len(c.get("/humor", headers=h2).json()) == 1


def test_agendamentos_concorrentes_mesmo_horario_so_um_vence_no_sqlite_sequencial(client):
    """Mesma regra da corrida real (PostgreSQL), aqui em sequência: o 2º paciente no mesmo horário recebe 409."""
    pro = cadastrar(client, "pro-seq@x.com", "profissional")
    a, b = cadastrar(client, "pac-seq-a@x.com"), cadastrar(client, "pac-seq-b@x.com")
    quando = futuro()
    corpo = {"profissional_id": pro["id"], "data_hora": quando, "modalidade": "Online"}
    assert client.post("/sessoes", headers=a["h"], json=corpo).status_code == 201
    assert client.post("/sessoes", headers=b["h"], json=corpo).status_code == 409


# ------------------------------------------------------------------ humor idempotente (fila offline do app)
def test_humor_com_mesma_chave_nao_duplica_e_devolve_o_existente(client):
    pac = cadastrar(client, "pac-humor-idem@x.com")
    h = {**pac["h"], "Idempotency-Key": "humor-chave-0001"}
    primeiro = client.post("/humor", headers=h, json={"nivel": 3, "nota": "a"})
    reenvio = client.post("/humor", headers=h, json={"nivel": 3, "nota": "a"})
    assert (primeiro.status_code, reenvio.status_code) == (201, 200)
    assert primeiro.json()["id"] == reenvio.json()["id"]
    assert len(client.get("/humor", headers=pac["h"]).json()) == 1


def test_humor_chaves_diferentes_ou_sem_chave_criam_registros_e_a_chave_e_por_usuario(client):
    a, b = cadastrar(client, "pac-h1@x.com"), cadastrar(client, "pac-h2@x.com")
    assert client.post("/humor", headers={**a["h"], "Idempotency-Key": "humor-chave-0002"}, json={"nivel": 2}).status_code == 201
    assert client.post("/humor", headers={**a["h"], "Idempotency-Key": "humor-chave-0003"}, json={"nivel": 2}).status_code == 201
    assert client.post("/humor", headers=a["h"], json={"nivel": 2}).status_code == 201  # sem chave: compatível com versões antigas do app
    assert client.post("/humor", headers={**b["h"], "Idempotency-Key": "humor-chave-0002"}, json={"nivel": 5}).status_code == 201  # outra pessoa, mesma chave
    assert len(client.get("/humor", headers=a["h"]).json()) == 3
    assert len(client.get("/humor", headers=b["h"]).json()) == 1


def test_humor_chave_invalida_e_422(client):
    pac = cadastrar(client, "pac-humor-422@x.com")
    for ruim in ["curta", "tem espaco na chave", "x" * 65]:
        assert client.post("/humor", headers={**pac["h"], "Idempotency-Key": ruim}, json={"nivel": 3}).status_code == 422


@pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="precisa de PostgreSQL real (TEST_DATABASE_URL)")
def test_humor_reenviado_em_paralelo_cria_so_um_registro(client):
    from concurrent.futures import ThreadPoolExecutor

    pac = cadastrar(client, "pac-humor-par@x.com")
    h = {**pac["h"], "Idempotency-Key": "humor-paralelo-01"}
    with ThreadPoolExecutor(max_workers=6) as ex:
        codigos = list(ex.map(lambda _: client.post("/humor", headers=h, json={"nivel": 4, "nota": "x"}).status_code, range(6)))
    assert set(codigos) <= {200, 201}, codigos
    assert codigos.count(201) == 1, codigos
    assert len(client.get("/humor", headers=pac["h"]).json()) == 1


# ------------------------------------------------------------------ prontidão (health/ready)
def test_ready_ok_com_banco_respondendo(client):
    r = client.get("/health/ready")
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["status"] == "ok"
    assert corpo["checks"]["banco"]["ok"] is True
    assert corpo["checks"]["banco"]["ms"] >= 0


def test_ready_devolve_503_sem_vazar_o_erro_do_banco(client, caplog):
    class SessaoQuebrada:
        def execute(self, *_a: object, **_k: object) -> None:
            raise OperationalError("SELECT 1", {}, Exception("senha-do-banco=hunter2"))

    def quebrado() -> Iterator[SessaoQuebrada]:
        yield SessaoQuebrada()

    client.app.dependency_overrides[get_db] = quebrado  # type: ignore[attr-defined]
    try:
        r = client.get("/health/ready")
    finally:
        client.app.dependency_overrides.clear()  # type: ignore[attr-defined]
    assert r.status_code == 503
    assert r.json() == {"status": "degradado", "checks": {"banco": {"ok": False, "ms": r.json()["checks"]["banco"]["ms"]}}}
    assert "hunter2" not in r.text


# ------------------------------------------------------------------ métricas de produção
@pytest.fixture
def app_com_metricas() -> Iterator[TestClient]:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    cfg = Settings(env="development", database_url="sqlite://", jwt_secret="x" * 40, metrics_token="tok-metricas-123")  # pragma: allowlist secret
    app = create_app(cfg, engine)

    @app.get("/boom")
    def boom() -> None:
        raise RuntimeError("falha-inesperada")

    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


def _metricas(c: TestClient) -> str:
    return c.get("/metricas", headers={"Authorization": "Bearer tok-metricas-123"}).text


def test_metricas_contam_erros_globais_e_expoem_banco_e_requisicoes_em_andamento(app_com_metricas):
    c = app_com_metricas
    assert c.get("/boom").status_code == 500
    assert c.get("/health/ready").status_code == 200
    texto = _metricas(c)
    assert "ms_erros_nao_tratados_total 1" in texto
    assert "ms_db_up 1" in texto
    assert "ms_db_latency_seconds" in texto
    assert "ms_http_requests_in_flight" in texto
    assert 'ms_http_requests_total{metodo="GET",rota="/boom",status="5xx"} 1' in texto
    assert "ms_process_start_time_seconds" in texto
    assert "falha-inesperada" not in texto  # nunca texto de erro nas métricas


def test_telemetria_do_app_vira_metricas_com_rotulos_de_conjunto_fechado(app_com_metricas):
    c = app_com_metricas
    eventos = [
        {"tipo": "rede", "nome": "GET /sessoes", "duracao_ms": 120, "status": 503},
        {"tipo": "rede", "nome": "GET /humor", "duracao_ms": 80, "status": 200},
        {"tipo": "erro", "nome": "FormatException"},
    ]
    assert c.post("/telemetria", json={"plataforma": "android", "eventos": eventos}).status_code == 204
    assert c.post("/telemetria", json={"plataforma": 'x"}\ninjetado', "eventos": [{"tipo": "tela", "nome": "inicio"}]}).status_code == 204
    texto = _metricas(c)
    assert 'ms_cliente_eventos_total{plataforma="android",tipo="rede"} 2' in texto
    assert 'ms_cliente_eventos_total{plataforma="android",tipo="erro"} 1' in texto
    assert 'ms_cliente_rede_duracao_ms_sum{plataforma="android"} 200' in texto
    assert 'ms_cliente_rede_duracao_ms_count{plataforma="android"} 2' in texto
    assert 'ms_cliente_rede_erros_5xx_total{plataforma="android"} 1' in texto
    assert 'plataforma="outra"' in texto  # texto livre do cliente nunca vira rótulo
    assert "injetado" not in texto
