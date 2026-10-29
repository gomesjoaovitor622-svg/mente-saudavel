"""Aprovação de profissional, confirmação de e-mail, recuperação de senha, fuso e CLI de administração."""

from __future__ import annotations

import re
from collections.abc import Iterator
from datetime import UTC

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.pool import StaticPool

from app import admin, tempo
from app.config import Settings
from app.main import create_app
from app.models import CodigoEmail, Usuario
from tests.conftest import cadastrar, futuro


class Caixa:
    """E-mail falso: guarda o que seria enviado."""

    def __init__(self) -> None:
        self.msgs: list[tuple[str, str, str]] = []

    def enviar(self, para: str, assunto: str, texto: str) -> None:
        self.msgs.append((para, assunto, texto))

    def codigo(self, para: str) -> str:
        texto = [m for m in self.msgs if m[0] == para][-1][2]
        return re.search(r"\b(\d{6})\b", texto).group(1)  # type: ignore[union-attr]


@pytest.fixture()
def ctx() -> Iterator[tuple[TestClient, Caixa]]:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)

    @event.listens_for(engine, "connect")
    def _fk(c, _r):  # type: ignore[no-untyped-def]
        c.execute("PRAGMA foreign_keys=ON")

    cfg = Settings(env="development", database_url="sqlite://", jwt_secret="x" * 40, signup_max_attempts=1000, smtp_host="smtp.exemplo", smtp_from="no-reply@exemplo.com")
    caixa = Caixa()
    with TestClient(create_app(cfg, engine, mailer=caixa)) as c:
        yield c, caixa


def test_profissional_novo_fica_pendente_e_nao_aparece_na_busca_nem_recebe_sessao(client):
    pro = cadastrar(client, "pend@x.com", "profissional", aprovado=False)
    pac = cadastrar(client, "pac@x.com")
    assert all(p["id"] != pro["id"] for p in client.get("/profissionais", headers=pac["h"]).json())
    r = client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": futuro(), "modalidade": "Online"})
    assert r.status_code == 404
    client.app.state.aprovar(pro["id"])  # type: ignore[attr-defined]
    assert any(p["id"] == pro["id"] for p in client.get("/profissionais", headers=pac["h"]).json())
    assert client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": futuro(), "modalidade": "Online"}).status_code == 201


def test_config_publica_informa_fuso_sem_segredos(client):
    c = client.get("/config").json()
    assert c["fuso"] == "America/Sao_Paulo" and "Brasília" in c["fuso_rotulo"]
    assert set(c) == {"fuso", "fuso_rotulo", "email_ativo", "video_ativo"}
    assert c["email_ativo"] is False


def test_sem_smtp_as_rotas_de_email_respondem_503(client):
    assert client.post("/auth/senha/esqueci", json={"email": "a@x.com"}).status_code == 503


def test_cadastro_envia_codigo_e_confirmar_libera_agendamento(ctx):
    client, caixa = ctx
    pro = cadastrar(client, "p@x.com", "profissional")
    pac = cadastrar(client, "pac@x.com")
    assert caixa.codigo("pac@x.com")
    corpo = {"profissional_id": pro["id"], "data_hora": futuro(), "modalidade": "Online"}
    assert client.post("/sessoes", headers=pac["h"], json=corpo).status_code == 403  # e-mail ainda não confirmado
    assert client.post("/auth/email/verificar", headers=pac["h"], json={"codigo": "000000"}).status_code in (400, 422)
    assert client.post("/auth/email/verificar", headers=pac["h"], json={"codigo": caixa.codigo("pac@x.com")}).status_code == 204
    assert client.post("/sessoes", headers=pac["h"], json=corpo).status_code == 201
    assert client.post("/auth/email/codigo", headers=pac["h"]).status_code == 409  # já confirmado


def test_codigo_morre_depois_de_tentativas_erradas(ctx):
    client, caixa = ctx
    pac = cadastrar(client, "pac@x.com")
    certo = caixa.codigo("pac@x.com")
    for _ in range(5):
        client.post("/auth/email/verificar", headers=pac["h"], json={"codigo": "999999" if certo != "999999" else "111111"})
    assert client.post("/auth/email/verificar", headers=pac["h"], json={"codigo": certo}).status_code in (400, 429)


def test_recuperar_senha_fluxo_completo_e_derruba_tokens_antigos(ctx):
    client, caixa = ctx
    pac = cadastrar(client, "pac@x.com", senha="senha-antiga-1")
    assert client.post("/auth/senha/esqueci", json={"email": "pac@x.com"}).status_code == 204
    codigo = caixa.codigo("pac@x.com")
    r = client.post("/auth/senha/redefinir", json={"email": "pac@x.com", "codigo": codigo, "nova_senha": "senha-nova-123"})
    assert r.status_code == 204
    assert client.post("/auth/entrar", json={"email": "pac@x.com", "senha": "senha-antiga-1"}).status_code == 401
    assert client.post("/auth/entrar", json={"email": "pac@x.com", "senha": "senha-nova-123"}).status_code == 200
    assert client.get("/sessoes", headers=pac["h"]).status_code == 401  # token antigo revogado
    # o código só vale uma vez
    r = client.post("/auth/senha/redefinir", json={"email": "pac@x.com", "codigo": codigo, "nova_senha": "outra-senha-123"})
    assert r.status_code == 400


def test_esqueci_senha_nao_revela_se_a_conta_existe(ctx):
    client, caixa = ctx
    cadastrar(client, "existe@x.com")
    n = len(caixa.msgs)
    a = client.post("/auth/senha/esqueci", json={"email": "existe@x.com"})
    b = client.post("/auth/senha/esqueci", json={"email": "nao-existe@x.com"})
    assert a.status_code == b.status_code == 204 and a.text == b.text
    assert len(caixa.msgs) == n + 1  # só a conta real recebe e-mail


def test_esqueci_senha_tem_limite_por_endereco(ctx):
    client, _ = ctx
    cadastrar(client, "pac@x.com")
    codigos = [client.post("/auth/senha/esqueci", json={"email": "pac@x.com"}).status_code for _ in range(5)]
    assert 429 in codigos


def test_codigo_nao_fica_em_texto_no_banco(ctx):
    client, caixa = ctx
    cadastrar(client, "pac@x.com")
    codigo = caixa.codigo("pac@x.com")
    with client.app.state.session_factory() as s:  # type: ignore[attr-defined]
        assert all(c.codigo_hash != codigo for c in s.query(CodigoEmail))


def test_admin_cli_aprova_lista_e_revoga(client):
    pro = cadastrar(client, "crp@x.com", "profissional", aprovado=False)
    with client.app.state.session_factory() as s:  # type: ignore[attr-defined]
        assert [u.email for u in admin.pendentes(s)] == ["crp@x.com"]
        assert admin.aprovar(s, "CRP@x.com").verificado_em is not None
        assert admin.pendentes(s) == []
        assert admin.revogar(s, "crp@x.com").verificado_em is None
        assert s.get(Usuario, pro["id"]).verificado_em is None  # type: ignore[union-attr]
        with pytest.raises(SystemExit):
            admin.aprovar(s, "naoexiste@x.com")


def test_agora_usa_o_fuso_da_clinica_e_nao_o_do_conteiner():
    from datetime import datetime

    utc = datetime.now(UTC).replace(tzinfo=None)
    diff = (utc - tempo.agora()).total_seconds()
    assert 2 * 3600 < diff < 4 * 3600  # Brasília = UTC-3
