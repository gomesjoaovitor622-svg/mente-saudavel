"""Robustez e segurança na borda: erros sem eco de dados sensíveis, limites de entrada, CORS, .env consistente."""

from __future__ import annotations

import re
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.pool import StaticPool

from app.config import Settings
from app.main import create_app
from tests.conftest import cadastrar, futuro

RAIZ = Path(__file__).resolve().parents[2]


def test_422_nao_repete_o_valor_enviado(client):
    senha = "S3nh4-Super-Secreta-" + "x" * 120  # passa de 128: erro de validação NO campo da senha
    r = client.post("/auth/entrar", json={"email": "a@x.com", "senha": senha})
    assert r.status_code == 422
    assert senha not in r.text and "input" not in r.text
    itens = r.json()["detail"]
    assert itens and set(itens[0]) == {"loc", "msg", "type"}


def test_json_invalido_tambem_nao_vaza(client):
    r = client.post("/auth/entrar", content=b'{"senha": "abc', headers={"content-type": "application/json"})
    assert r.status_code == 422 and "abc" not in r.text


def test_caractere_nulo_vira_422_e_nao_500(client):
    r = client.post("/auth/cadastro", json={"nome": "Ana\x00", "email": "n@x.com", "senha": "senha-forte-1", "perfil": "paciente"})
    assert r.status_code == 422
    pac = cadastrar(client, "ok@x.com")
    assert client.patch("/auth/eu", headers=pac["h"], json={"nome": "Nome\x00Falso"}).status_code == 422


def test_campo_desconhecido_e_recusado(client):
    r = client.post("/auth/entrar", json={"email": "a@x.com", "senha": "x", "perfil": "admin"})
    assert r.status_code == 422


def test_corpo_gigante_e_recusado_antes_de_processar(client):
    r = client.post("/auth/entrar", content=b"x" * 2_000_000, headers={"content-type": "application/json"})
    assert r.status_code == 413


def test_cors_so_libera_a_origem_configurada(client):
    ok = client.options("/auth/entrar", headers={"Origin": "https://site.exemplo", "Access-Control-Request-Method": "POST"})
    assert ok.headers.get("access-control-allow-origin") == "https://site.exemplo"
    mau = client.options("/auth/entrar", headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"})
    assert "access-control-allow-origin" not in mau.headers
    assert "access-control-allow-credentials" not in ok.headers  # token vai no cabeçalho/cookie same-site, nunca CORS com credenciais


def test_erro_interno_nao_vaza_detalhes(monkeypatch):
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    app = create_app(Settings(env="development", database_url="sqlite://", jwt_secret="x" * 40), engine)

    @app.get("/boom")
    def boom() -> None:
        raise RuntimeError("senha-do-banco=hunter2")

    r = TestClient(app, raise_server_exceptions=False).get("/boom")
    assert r.status_code == 500 and "hunter2" not in r.text and "Informe o código" in r.json()["detail"]


def test_endpoints_protegidos_exigem_login(client):
    for metodo, caminho in [
        ("get", "/sessoes"),
        ("get", "/auth/eu"),
        ("get", "/humor"),
        ("get", "/profissional/pacientes"),
        ("get", "/profissional/financeiro"),
        ("post", "/auth/eu/aceite"),
    ]:
        assert getattr(client, metodo)(caminho).status_code == 401, caminho


def test_cabecalhos_de_seguranca_em_toda_resposta(client):
    r = client.get("/health")
    assert r.headers["x-content-type-options"] == "nosniff" and r.headers["cache-control"] == "no-store" and "x-request-id" in r.headers


def test_variaveis_de_ambiente_lidas_estao_documentadas_no_env_example():
    """Toda variável que o servidor lê precisa constar em deploy/.env.example (ou ser interna do compose)."""
    codigo = (RAIZ / "server/app/config.py").read_text()
    lidas = set(re.findall(r'os\.environ\.get\("([A-Z_]+)"', codigo)) | set(re.findall(r'_bool\("([A-Z_]+)"', codigo))
    exemplo = (RAIZ / "deploy/.env.example").read_text()
    compose = (RAIZ / "deploy/docker-compose.prod.yml").read_text()
    # APP_ENV/SCHEMA_MODE/COOKIE_SECURE/DATABASE_URL/CORS_ORIGINS são fixados pelo compose; o resto vem do .env.
    fixadas = {"APP_ENV", "SCHEMA_MODE", "COOKIE_SECURE", "DATABASE_URL", "CORS_ORIGINS"}
    faltam = sorted(v for v in lidas - fixadas if not re.search(rf"^#?\s*{v}=", exemplo, re.M) and v not in compose)
    assert not faltam, f"variáveis lidas pelo servidor sem documentação no .env.example: {faltam}"
    for v in sorted(lidas - fixadas):
        assert v in compose, f"{v} não chega ao contêiner da API (falta no docker-compose.prod.yml)"


def test_env_example_nao_traz_segredo_real():
    exemplo = (RAIZ / "deploy/.env.example").read_text()
    for linha in exemplo.splitlines():
        if re.match(r"^(JWT_SECRET|POSTGRES_PASSWORD|PRONTUARIO_KEYS|SMTP_PASSWORD|VIDEO_APP_SECRET|METRICS_TOKEN)=.+", linha):
            pytest.fail(f"segredo preenchido no .env.example: {linha.split('=')[0]}")


def test_agendamento_futuro_obrigatorio_e_perfil_correto(client):
    pro = cadastrar(client, "p@x.com", "profissional")
    pac = cadastrar(client, "c@x.com")
    # profissional não agenda; paciente não agenda no passado
    assert client.post("/sessoes", headers=pro["h"], json={"profissional_id": pro["id"], "data_hora": futuro(), "modalidade": "Online"}).status_code == 403
    assert client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": "2020-01-01T10:00:00", "modalidade": "Online"}).status_code == 422
