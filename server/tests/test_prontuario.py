"""Prontuário: cifrado no banco, só o profissional com vínculo acessa, sem DELETE, com revisões e trilha de acesso."""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from sqlalchemy import Engine, create_engine, event, text
from sqlalchemy.pool import StaticPool

from app.config import Settings, load_settings
from app.cripto import Cofre, ProntuarioIlegivel
from app.db import Base
from app.main import create_app
from tests.conftest import cadastrar, futuro

SEGREDO = "texto-clinico-muito-sigiloso"


@pytest.fixture()
def ambiente() -> Iterator[tuple[TestClient, Engine]]:
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)

    @event.listens_for(engine, "connect")
    def _fk(dbapi_conn, _r):  # type: ignore[no-untyped-def]
        dbapi_conn.execute("PRAGMA foreign_keys=ON")

    cfg = Settings(env="development", database_url="sqlite://", jwt_secret="x" * 40, signup_max_attempts=1000)
    with TestClient(create_app(cfg, engine)) as c:
        yield c, engine
    Base.metadata.drop_all(engine)


def _vinculo(client: TestClient, email_pro: str = "pro@x.com", email_pac: str = "pac@x.com") -> tuple[dict, dict]:
    pro = cadastrar(client, email_pro, "profissional")
    pac = cadastrar(client, email_pac)
    r = client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": futuro(), "modalidade": "Online"})
    assert r.status_code == 201
    pro["sessao_id"] = r.json()["id"]
    return pro, pac


def _novo(client, pro, pac, conteudo=SEGREDO, **extra):
    return client.post(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pro["h"], json={"conteudo": conteudo, **extra})


def test_registro_fica_cifrado_no_banco_e_volta_legivel_pela_api(ambiente):
    client, engine = ambiente
    pro, pac = _vinculo(client)
    r = _novo(client, pro, pac, tipo="evolucao", sessao_id=pro["sessao_id"])
    assert r.status_code == 201 and r.json()["conteudo"] == SEGREDO and r.json()["versao"] == 1
    with engine.connect() as c:
        bruto = c.execute(text("SELECT conteudo_cifrado FROM prontuario_entradas")).scalar_one()
    assert SEGREDO not in bruto and bruto.startswith("gAAAA")  # texto cifrado (Fernet), nunca o original
    lista = client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pro["h"]).json()
    assert [e["conteudo"] for e in lista] == [SEGREDO]


def test_paciente_nunca_acessa_o_prontuario(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    e = _novo(client, pro, pac).json()
    assert client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pac["h"]).status_code == 403
    assert client.post(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pac["h"], json={"conteudo": "x"}).status_code == 403
    assert client.patch(f"/profissional/prontuario/{e['id']}", headers=pac["h"], json={"conteudo": "x", "versao_esperada": 1}).status_code == 403
    assert client.get(f"/profissional/prontuario/{e['id']}/revisoes", headers=pac["h"]).status_code == 403
    # e as anotações simples da sessão continuam invisíveis para o paciente
    assert SEGREDO not in client.get("/auth/eu/exportar", headers=pac["h"]).text


def test_so_o_profissional_com_vinculo_acessa(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    e = _novo(client, pro, pac).json()
    outro = cadastrar(client, "outro-pro@x.com", "profissional")
    assert client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=outro["h"]).status_code == 404
    assert _novo(client, outro, pac).status_code == 404
    assert client.patch(f"/profissional/prontuario/{e['id']}", headers=outro["h"], json={"conteudo": "x", "versao_esperada": 1}).status_code == 404
    assert client.get(f"/profissional/prontuario/{e['id']}/revisoes", headers=outro["h"]).status_code == 404
    # paciente que existe, mas nunca teve sessão com este profissional
    estranho = cadastrar(client, "estranho@x.com")
    assert _novo(client, pro, estranho).status_code == 404
    # paciente inexistente: mesma resposta (não revela quem existe)
    assert client.get("/profissional/pacientes/99999/prontuario", headers=pro["h"]).status_code == 404


def test_sessao_cancelada_nao_cria_vinculo(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    assert client.patch(f"/sessoes/{pro['sessao_id']}", headers=pac["h"], json={"status": "cancelada"}).status_code == 200
    assert _novo(client, pro, pac).status_code == 404


def test_edicao_guarda_a_versao_anterior_e_exige_versao_esperada(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    e = _novo(client, pro, pac, conteudo="primeira").json()
    ok = client.patch(f"/profissional/prontuario/{e['id']}", headers=pro["h"], json={"conteudo": "segunda", "versao_esperada": 1})
    assert ok.status_code == 200 and ok.json()["versao"] == 2 and ok.json()["conteudo"] == "segunda"
    # edição "velha" (outro aparelho ainda na versão 1) não sobrescreve
    velha = client.patch(f"/profissional/prontuario/{e['id']}", headers=pro["h"], json={"conteudo": "terceira", "versao_esperada": 1})
    assert velha.status_code == 409
    rev = client.get(f"/profissional/prontuario/{e['id']}/revisoes", headers=pro["h"]).json()
    assert [(r["versao"], r["conteudo"]) for r in rev] == [(1, "primeira")]


def test_nao_existe_exclusao_de_prontuario(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    e = _novo(client, pro, pac).json()
    assert client.delete(f"/profissional/prontuario/{e['id']}", headers=pro["h"]).status_code == 405
    assert client.delete(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pro["h"]).status_code == 405


def test_trilha_de_acesso_registra_leitura_criacao_e_edicao(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    e = _novo(client, pro, pac).json()
    client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pro["h"])
    client.patch(f"/profissional/prontuario/{e['id']}", headers=pro["h"], json={"conteudo": "novo", "versao_esperada": 1})
    client.get(f"/profissional/prontuario/{e['id']}/revisoes", headers=pro["h"])
    acoes = [a["acao"] for a in client.get(f"/profissional/pacientes/{pac['id']}/prontuario/acessos", headers=pro["h"]).json()]
    assert acoes == ["revisoes", "edicao", "leitura", "criacao"]  # do mais recente ao mais antigo
    assert SEGREDO not in str(client.get(f"/profissional/pacientes/{pac['id']}/prontuario/acessos", headers=pro["h"]).json())


def test_validacoes(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    assert _novo(client, pro, pac, conteudo="").status_code == 422
    assert _novo(client, pro, pac, conteudo="x" * 20001).status_code == 422
    assert _novo(client, pro, pac, tipo="fofoca").status_code == 422
    assert _novo(client, pro, pac, campo_extra=1).status_code == 422
    outro_pac = cadastrar(client, "pac2@x.com")
    sessao_alheia = client.post("/sessoes", headers=outro_pac["h"], json={"profissional_id": pro["id"], "data_hora": futuro(72), "modalidade": "Online"}).json()["id"]
    assert _novo(client, pro, pac, sessao_id=sessao_alheia).status_code == 422  # sessão de OUTRO paciente


def test_conta_com_prontuario_nao_pode_ser_apagada_e_anonimizar_preserva_o_registro(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    _novo(client, pro, pac)
    assert client.delete("/auth/eu", headers=pro["h"]).status_code == 409
    assert client.delete("/auth/eu", headers=pac["h"]).status_code == 409
    assert client.post("/auth/eu/anonimizar", headers=pac["h"], json={"senha": "senha-forte-1"}).status_code == 204
    lista = client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pro["h"]).json()
    assert [e["conteudo"] for e in lista] == [SEGREDO]  # guarda legal: o registro permanece
    assert _novo(client, pro, pac).status_code == 409  # mas não recebe registros novos


def test_chave_errada_da_erro_claro_sem_vazar(ambiente):
    client, engine = ambiente
    pro, pac = _vinculo(client)
    _novo(client, pro, pac)
    with engine.begin() as c:
        c.execute(text("UPDATE prontuario_entradas SET conteudo_cifrado = :t"), {"t": Cofre([Fernet.generate_key().decode()]).cifrar("outro")})
    r = client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pro["h"])
    assert r.status_code == 500 and SEGREDO not in r.text and "outro" not in r.text


def test_cofre_rotacao_de_chaves():
    antiga, nova = Fernet.generate_key().decode(), Fernet.generate_key().decode()
    velho = Cofre([antiga]).cifrar("dado")
    cofre = Cofre([nova, antiga])  # a nova cifra; a antiga ainda decifra
    assert cofre.decifrar(velho) == "dado"
    recifrado = cofre.recifrar(velho)
    assert Cofre([nova]).decifrar(recifrado) == "dado"  # agora só a chave nova basta
    with pytest.raises(ProntuarioIlegivel):
        Cofre([Fernet.generate_key().decode()]).decifrar(velho)
    with pytest.raises(ValueError):
        Cofre([])


def test_producao_exige_chave_do_prontuario(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("JWT_SECRET", "y" * 40)
    monkeypatch.delenv("PRONTUARIO_KEYS", raising=False)
    with pytest.raises(RuntimeError, match="PRONTUARIO_KEYS"):
        load_settings()
    monkeypatch.setenv("PRONTUARIO_KEYS", Fernet.generate_key().decode())
    assert len(load_settings().prontuario_chaves) == 1
