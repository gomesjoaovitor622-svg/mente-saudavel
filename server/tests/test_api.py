from __future__ import annotations

import logging
import os
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from tests.conftest import cadastrar, futuro


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_cadastro_login_e_token(client):
    u = cadastrar(client, "ana@x.com")
    assert client.get("/auth/eu", headers=u["h"]).json()["email"] == "ana@x.com"
    r = client.post("/auth/entrar", json={"email": "ANA@x.com", "senha": "senha-forte-1"})
    assert r.status_code == 200 and r.json()["token"]


def test_senha_nunca_vaza(client):
    u = cadastrar(client, "ana@x.com")
    texto = client.get("/auth/eu", headers=u["h"]).text + client.post("/auth/entrar", json={"email": "ana@x.com", "senha": "senha-forte-1"}).text
    assert "senha" not in texto and "scrypt" not in texto


def test_cadastro_validacoes(client):
    cadastrar(client, "ana@x.com")
    base = {"nome": "Ana", "email": "ana@x.com", "senha": "senha-forte-1", "perfil": "paciente"}
    assert client.post("/auth/cadastro", json=base).status_code == 409
    assert client.post("/auth/cadastro", json={**base, "email": "b@x.com", "senha": "curta"}).status_code == 422
    assert client.post("/auth/cadastro", json={**base, "email": "c@x.com", "perfil": "profissional"}).status_code == 422
    assert client.post("/auth/cadastro", json={**base, "email": "d@x.com", "perfil": "admin"}).status_code == 422
    assert client.post("/auth/cadastro", json={**base, "email": "e@x.com", "is_admin": True}).status_code == 422


def test_login_errado_e_limite(client):
    cadastrar(client, "ana@x.com")
    for _ in range(5):
        assert client.post("/auth/entrar", json={"email": "ana@x.com", "senha": "errada"}).status_code == 401
    assert client.post("/auth/entrar", json={"email": "ana@x.com", "senha": "senha-forte-1"}).status_code == 429


def test_login_email_inexistente_mesma_mensagem(client):
    r = client.post("/auth/entrar", json={"email": "nao@x.com", "senha": "qualquer"})
    assert r.status_code == 401 and r.json()["detail"] == "E-mail ou senha incorretos."


def test_sem_token_e_token_invalido(client):
    assert client.get("/sessoes").status_code == 401
    assert client.get("/sessoes", headers={"Authorization": "Bearer lixo"}).status_code == 401


def test_cors_somente_origem_exata(client):
    ok = client.options("/sessoes", headers={"Origin": "https://site.exemplo", "Access-Control-Request-Method": "GET"})
    assert ok.headers.get("access-control-allow-origin") == "https://site.exemplo"
    ruim = client.options("/sessoes", headers={"Origin": "https://evil.exemplo", "Access-Control-Request-Method": "GET"})
    assert "access-control-allow-origin" not in ruim.headers


def test_fluxo_sessao_completo(client):
    pac = cadastrar(client, "pac@x.com")
    pro = cadastrar(client, "pro@x.com", "profissional")
    quando = futuro()
    r = client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": quando, "modalidade": "Online"})
    assert r.status_code == 201
    sid = r.json()["id"]
    assert [s["id"] for s in client.get("/sessoes", headers=pac["h"]).json()] == [sid]
    assert [s["id"] for s in client.get("/sessoes", headers=pro["h"]).json()] == [sid]
    # horário ocupado aparece e gera conflito para outro paciente
    dia = quando[:10]
    assert client.get(f"/profissionais/{pro['id']}/horas-ocupadas", params={"dia": dia}, headers=pac["h"]).json() == [10]
    outro = cadastrar(client, "outro@x.com")
    r2 = client.post("/sessoes", headers=outro["h"], json={"profissional_id": pro["id"], "data_hora": quando, "modalidade": "Online"})
    assert r2.status_code == 409
    # profissional conclui e anota; paciente avalia
    assert client.patch(f"/sessoes/{sid}", headers=pro["h"], json={"status": "concluida", "anotacoes": "privado"}).status_code == 200
    vista = client.get("/sessoes", headers=pac["h"]).json()[0]
    assert vista["status"] == "concluida" and vista["anotacoes"] is None  # anotações NUNCA vão ao paciente
    assert client.get("/sessoes", headers=pro["h"]).json()[0]["anotacoes"] == "privado"
    assert client.put(f"/sessoes/{sid}/avaliacao", headers=pac["h"], json={"nota": 4, "comentario": "ótimo"}).status_code == 200
    assert client.put(f"/sessoes/{sid}/avaliacao", headers=pac["h"], json={"nota": 5, "comentario": "melhor"}).json()["nota"] == 5
    lista = client.get("/profissionais", headers=pac["h"]).json()
    assert lista[0]["media"] == 5.0 and lista[0]["total"] == 1
    assert client.get(f"/profissionais/{pro['id']}/avaliacoes", headers=pac["h"]).json()[0]["comentario"] == "melhor"
    pacientes = client.get("/profissional/pacientes", headers=pro["h"]).json()
    assert pacientes[0]["total"] == 1 and pacientes[0]["concluidas"] == 1


def test_isolamento_entre_usuarios(client):
    a = cadastrar(client, "a@x.com")
    b = cadastrar(client, "b@x.com")
    pro = cadastrar(client, "pro@x.com", "profissional")
    sid = client.post("/sessoes", headers=a["h"], json={"profissional_id": pro["id"], "data_hora": futuro(), "modalidade": "Online"}).json()["id"]
    assert client.get("/sessoes", headers=b["h"]).json() == []
    assert client.patch(f"/sessoes/{sid}", headers=b["h"], json={"status": "cancelada"}).status_code == 404
    assert client.delete(f"/sessoes/{sid}", headers=b["h"]).status_code == 404
    assert client.get(f"/sessoes/{sid}/avaliacao", headers=b["h"]).status_code == 404
    h = client.post("/humor", headers=a["h"], json={"nivel": 4}).json()
    assert client.delete(f"/humor/{h['id']}", headers=b["h"]).status_code == 404
    assert client.get("/humor", headers=b["h"]).json() == []


def test_regras_de_perfil_e_status(client):
    pac = cadastrar(client, "pac@x.com")
    pro = cadastrar(client, "pro@x.com", "profissional")
    assert client.post("/sessoes", headers=pro["h"], json={"profissional_id": pro["id"], "data_hora": futuro(), "modalidade": "Online"}).status_code == 403
    assert client.get("/profissional/pacientes", headers=pac["h"]).status_code == 403
    assert client.post("/humor", headers=pro["h"], json={"nivel": 3}).status_code == 403
    assert client.post("/sessoes", headers=pac["h"], json={"profissional_id": pac["id"], "data_hora": futuro(), "modalidade": "Online"}).status_code == 404
    passado = (datetime.now() - timedelta(days=1)).isoformat()
    assert client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": passado, "modalidade": "Online"}).status_code == 422
    sid = client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": futuro(), "modalidade": "Online"}).json()["id"]
    assert client.patch(f"/sessoes/{sid}", headers=pac["h"], json={"status": "concluida"}).status_code == 409  # paciente não conclui
    assert client.patch(f"/sessoes/{sid}", headers=pac["h"], json={"anotacoes": "x"}).status_code == 403
    assert client.put(f"/sessoes/{sid}/avaliacao", headers=pac["h"], json={"nota": 5}).status_code == 409  # ainda não concluída
    assert client.delete(f"/sessoes/{sid}", headers=pac["h"]).status_code == 409  # ativa: cancelar antes
    assert client.patch(f"/sessoes/{sid}", headers=pac["h"], json={"status": "cancelada"}).status_code == 200
    assert client.delete(f"/sessoes/{sid}", headers=pac["h"]).status_code == 204


def test_remarcar(client):
    pac = cadastrar(client, "pac@x.com")
    pro = cadastrar(client, "pro@x.com", "profissional")
    sid = client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": futuro(48, 10), "modalidade": "Online"}).json()["id"]
    r = client.patch(f"/sessoes/{sid}", headers=pac["h"], json={"data_hora": futuro(72, 15)})
    assert r.status_code == 200 and r.json()["data_hora"].endswith("15:00:00")
    assert client.patch(f"/sessoes/{sid}", headers=pro["h"], json={"data_hora": futuro(96)}).status_code == 403


def test_humor_e_filtros(client):
    pac = cadastrar(client, "pac@x.com")
    assert client.post("/humor", headers=pac["h"], json={"nivel": 6}).status_code == 422
    assert client.post("/humor", headers=pac["h"], json={"nivel": 4, "nota": "bem"}).status_code == 201
    assert client.get("/humor", headers=pac["h"], params={"dias": 7}).json()[0]["nivel"] == 4


def test_busca_profissionais(client):
    pac = cadastrar(client, "pac@x.com")
    cadastrar(client, "p1@x.com", "profissional", especialidade="Psicologia infantil")
    cadastrar(client, "p2@x.com", "profissional", especialidade="Terapia de casal")
    assert len(client.get("/profissionais", headers=pac["h"]).json()) == 2
    achou = client.get("/profissionais", headers=pac["h"], params={"q": "infantil"}).json()
    assert len(achou) == 1 and "email" not in achou[0]


def test_perfil_senha_e_exclusao(client):
    pro = cadastrar(client, "pro@x.com", "profissional")
    r = client.patch("/auth/eu", headers=pro["h"], json={"nome": "Dra. Nova", "registro": "06/1", "especialidade": "TCC", "endereco": "Rua 1"})
    assert r.json()["endereco"] == "Rua 1"
    assert client.post("/auth/senha", headers=pro["h"], json={"senha_atual": "errada", "nova_senha": "nova-senha-123"}).status_code == 400
    assert client.post("/auth/senha", headers=pro["h"], json={"senha_atual": "senha-forte-1", "nova_senha": "nova-senha-123"}).status_code == 204
    assert client.post("/auth/entrar", json={"email": "pro@x.com", "senha": "nova-senha-123"}).status_code == 200
    assert client.delete("/auth/eu", headers=pro["h"]).status_code == 204
    assert client.get("/auth/eu", headers=pro["h"]).status_code == 401


def test_exclusao_de_conta_apaga_em_cascata(client):
    pac = cadastrar(client, "pac@x.com")
    pro = cadastrar(client, "pro@x.com", "profissional")
    client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": futuro(), "modalidade": "Online"})
    client.post("/humor", headers=pac["h"], json={"nivel": 3})
    assert client.delete("/auth/eu", headers=pac["h"]).status_code == 204
    assert client.get("/sessoes", headers=pro["h"]).json() == []


def test_cabecalhos_de_seguranca(client):
    h = client.get("/health").headers
    assert h["x-content-type-options"] == "nosniff" and h["cache-control"] == "no-store"


def test_cadastro_tem_limite_por_ip():
    from sqlalchemy import create_engine
    from sqlalchemy.pool import StaticPool

    from app.config import Settings
    from app.main import create_app

    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    cfg = Settings(env="development", database_url="sqlite://", jwt_secret="x" * 40, signup_max_attempts=3)
    from fastapi.testclient import TestClient

    with TestClient(create_app(cfg, engine)) as c:
        codigos = [c.post("/auth/cadastro", json={"nome": "Ana", "email": f"a{i}@x.com", "senha": "senha-forte-1", "perfil": "paciente"}).status_code for i in range(5)]
    assert codigos == [201, 201, 201, 429, 429]


def test_exportar_meus_dados_paciente_nao_traz_anotacoes_do_profissional(client):
    prof = cadastrar(client, "dra@x.com", "profissional")
    pac = cadastrar(client, "p@x.com")
    s = client.post("/sessoes", headers=pac["h"], json={"profissional_id": prof["id"], "data_hora": futuro(), "modalidade": "Online"}).json()
    client.patch(f"/sessoes/{s['id']}", headers=prof["h"], json={"anotacoes": "SIGILO CLINICO"})
    client.post("/humor", headers=pac["h"], json={"nivel": 4, "nota": "ok"})

    meus = client.get("/auth/eu/exportar", headers=pac["h"])
    assert meus.status_code == 200
    d = meus.json()
    assert d["usuario"]["email"] == "p@x.com" and len(d["sessoes"]) == 1 and len(d["humor"]) == 1
    assert "SIGILO CLINICO" not in meus.text and "senha" not in meus.text and "scrypt" not in meus.text

    do_prof = client.get("/auth/eu/exportar", headers=prof["h"]).json()
    assert do_prof["sessoes"][0]["anotacoes"] == "SIGILO CLINICO" and "humor" not in do_prof
    assert client.get("/auth/eu/exportar").status_code == 401


def test_preco_da_sessao_e_financeiro_do_profissional(client):
    prof = cadastrar(client, "dra@x.com", "profissional")
    pac = cadastrar(client, "p@x.com")
    perfil = {"nome": "Dra Teste", "registro": "06/1", "valor_sessao_centavos": 20000}
    assert client.patch("/auth/eu", headers=prof["h"], json=perfil).json()["valor_sessao_centavos"] == 20000
    # o paciente vê o preço na busca
    assert client.get("/profissionais", headers=pac["h"]).json()[0]["valor_sessao_centavos"] == 20000

    s = client.post("/sessoes", headers=pac["h"], json={"profissional_id": prof["id"], "data_hora": futuro(), "modalidade": "Online"}).json()
    assert s["valor_centavos"] == 20000
    # mudar o preço depois NÃO altera sessões já agendadas (preço congelado)
    client.patch("/auth/eu", headers=prof["h"], json={**perfil, "valor_sessao_centavos": 30000})
    assert client.get("/sessoes", headers=pac["h"]).json()[0]["valor_centavos"] == 20000

    mes = datetime.fromisoformat(s["data_hora"]).strftime("%Y-%m")
    antes = client.get(f"/profissional/financeiro?mes={mes}", headers=prof["h"]).json()
    assert antes["a_receber_centavos"] == 20000 and antes["recebido_centavos"] == 0 and antes["sessoes_agendadas"] == 1
    client.patch(f"/sessoes/{s['id']}", headers=prof["h"], json={"status": "concluida"})
    depois = client.get(f"/profissional/financeiro?mes={mes}", headers=prof["h"]).json()
    assert depois["recebido_centavos"] == 20000 and depois["a_receber_centavos"] == 0 and depois["sessoes_concluidas"] == 1


def test_financeiro_so_para_profissional_e_valida_mes_e_preco(client):
    prof = cadastrar(client, "dra@x.com", "profissional")
    pac = cadastrar(client, "p@x.com")
    assert client.get("/profissional/financeiro", headers=pac["h"]).status_code == 403
    assert client.get("/profissional/financeiro", headers=prof["h"]).status_code == 200  # mês atual
    assert client.get("/profissional/financeiro?mes=2026-13", headers=prof["h"]).status_code == 422
    assert client.get("/profissional/financeiro").status_code == 401
    assert client.patch("/auth/eu", headers=prof["h"], json={"nome": "Dra", "valor_sessao_centavos": -5}).status_code == 422


def test_migracao_adiciona_colunas_em_banco_antigo(tmp_path):
    """Banco criado pela versão anterior (sem as colunas de preço) é atualizado sem perder dados."""
    import sqlite3

    from sqlalchemy import create_engine, inspect

    from app.db import garantir_colunas

    arquivo = tmp_path / "antigo.db"
    con = sqlite3.connect(arquivo)
    con.execute("CREATE TABLE usuarios (id INTEGER PRIMARY KEY, nome TEXT)")
    con.execute("CREATE TABLE sessoes (id INTEGER PRIMARY KEY, status TEXT)")
    con.execute("INSERT INTO usuarios (nome) VALUES ('Ana')")
    con.execute("INSERT INTO sessoes (status) VALUES ('agendada')")
    con.commit()
    con.close()

    engine = create_engine(f"sqlite:///{arquivo}")
    assert sorted(garantir_colunas(engine)) == [
        "sessoes.chave_idempotencia",
        "sessoes.valor_centavos",
        "usuarios.aceite_termos_em",
        "usuarios.aceite_termos_versao",
        "usuarios.anonimizado_em",
        "usuarios.valor_sessao_centavos",
    ]
    assert garantir_colunas(engine) == []  # idempotente
    colunas = {c["name"] for c in inspect(engine).get_columns("sessoes")}
    assert "valor_centavos" in colunas
    with engine.connect() as c:
        assert c.exec_driver_sql("SELECT valor_centavos FROM sessoes").scalar() == 0
        assert c.exec_driver_sql("SELECT nome FROM usuarios").scalar() == "Ana"
    engine.dispose()


# ---------------------------------------------------------------- anti-corrida (índice único)
def _agendar(client, pac, pro_id, quando):
    return client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro_id, "data_hora": quando, "modalidade": "Online"})


def test_banco_recusa_sessao_ativa_duplicada_mas_aceita_cancelada(client):
    """O índice único parcial vale no banco, mesmo sem passar pela checagem da API."""
    import pytest
    from sqlalchemy.exc import IntegrityError

    from app.models import Sessao

    pro = cadastrar(client, "pro-idx@x.com", "profissional")
    pac = cadastrar(client, "pac-idx@x.com")
    quando = datetime.fromisoformat(futuro())
    factory = client.app.state.session_factory

    def nova(status: str = "agendada") -> Sessao:
        return Sessao(paciente_id=pac["id"], profissional_id=pro["id"], data_hora=quando, modalidade="Online", status=status)

    with factory() as db:
        db.add(nova())
        db.commit()
    with factory() as db:
        db.add(nova())
        with pytest.raises(IntegrityError):
            db.commit()
    with factory() as db:  # cancelada não ocupa horário
        db.add(nova("cancelada"))
        db.commit()


def test_corrida_no_agendamento_vira_409(client):
    """Simula a corrida: um rival grava o mesmo horário DEPOIS da checagem e ANTES do INSERT."""
    from sqlalchemy import event, insert

    from app.models import Sessao

    pro = cadastrar(client, "pro-race@x.com", "profissional")
    pac = cadastrar(client, "pac-race@x.com")
    rival = cadastrar(client, "rival-race@x.com")
    quando = futuro()
    engine = client.app.state.session_factory.kw["bind"]
    estado = {"ativo": True}

    @event.listens_for(engine, "before_cursor_execute")
    def _rival_grava_primeiro(conn, cursor, statement, parameters, context, executemany):  # type: ignore[no-untyped-def]
        if estado["ativo"] and statement.lstrip().upper().startswith("INSERT INTO SESSOES"):
            estado["ativo"] = False
            conn.execute(  # mesma conexão: o INSERT real que vem a seguir viola o índice único
                insert(Sessao.__table__).values(
                    paciente_id=rival["id"], profissional_id=pro["id"], data_hora=datetime.fromisoformat(quando), modalidade="Online", status="agendada", valor_centavos=0
                )
            )

    try:
        r = _agendar(client, pac, pro["id"], quando)
    finally:
        event.remove(engine, "before_cursor_execute", _rival_grava_primeiro)
    assert r.status_code == 409, r.text
    assert "horário" in r.json()["detail"]
    # só a sessão do rival existe; a do paciente não foi gravada
    assert client.get("/sessoes", headers=pac["h"]).json() == []


def test_remarcar_para_horario_ocupado_continua_409(client):
    pro = cadastrar(client, "pro-rem@x.com", "profissional")
    a = cadastrar(client, "pac-rem-a@x.com")
    b = cadastrar(client, "pac-rem-b@x.com")
    assert _agendar(client, a, pro["id"], futuro(48, 9)).status_code == 201
    sb = _agendar(client, b, pro["id"], futuro(48, 11)).json()["id"]
    r = client.patch(f"/sessoes/{sb}", headers=b["h"], json={"data_hora": futuro(48, 9)})
    assert r.status_code == 409


def test_cancelar_libera_o_horario(client):
    pro = cadastrar(client, "pro-lib@x.com", "profissional")
    a = cadastrar(client, "pac-lib-a@x.com")
    b = cadastrar(client, "pac-lib-b@x.com")
    sid = _agendar(client, a, pro["id"], futuro()).json()["id"]
    assert _agendar(client, b, pro["id"], futuro()).status_code == 409
    assert client.patch(f"/sessoes/{sid}", headers=a["h"], json={"status": "cancelada"}).status_code == 200
    assert _agendar(client, b, pro["id"], futuro()).status_code == 201


def test_migracao_cria_indices_em_banco_antigo_e_avisa_duplicadas(tmp_path):
    from sqlalchemy import create_engine, text

    from app.db import garantir_indices

    eng = create_engine(f"sqlite:///{tmp_path / 'velho.db'}")
    with eng.begin() as c:
        c.execute(text("CREATE TABLE sessoes (id INTEGER PRIMARY KEY, paciente_id INT, profissional_id INT, data_hora DATETIME, status TEXT, chave_idempotencia TEXT)"))
        c.execute(
            text(
                "INSERT INTO sessoes (id, paciente_id, profissional_id, data_hora, status) VALUES (1,1,9,'2030-01-01 10:00:00','agendada'),(2,2,9,'2030-01-01 10:00:00','agendada')"
            )
        )
    assert garantir_indices(eng) == ["uq_sessao_prof_horario"]  # duplicada: não cria, não derruba o servidor
    with eng.begin() as c:
        c.execute(text("UPDATE sessoes SET status='cancelada' WHERE id=2"))
    assert garantir_indices(eng) == []
    assert garantir_indices(eng) == []  # idempotente


# ---------------------------------------------------------------- sessão web: cookie HttpOnly
@pytest.fixture()
def web():
    """Cliente que guarda cookies, como um navegador (cookie_secure=False só porque o teste usa http)."""
    from sqlalchemy import create_engine
    from sqlalchemy.pool import StaticPool

    from app.config import Settings
    from app.main import create_app

    eng = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    cfg = Settings(env="development", database_url="sqlite://", jwt_secret="y" * 40, cookie_secure=False, signup_max_attempts=1000)
    with TestClient(create_app(cfg, eng)) as c:
        yield c


def _cadastro_web(c, email="web@x.com"):
    return c.post("/auth/cadastro", json={"nome": "Web", "email": email, "senha": "senha-forte-1", "perfil": "paciente"})


def test_cookie_de_sessao_e_httponly_samesite_strict(web):
    r = _cadastro_web(web)
    assert r.status_code == 201
    cookie = r.headers["set-cookie"].lower()
    assert "ms_sessao=" in cookie and "httponly" in cookie and "samesite=strict" in cookie and "path=/" in cookie


def test_cookie_autentica_leitura_sem_cabecalho_authorization(web):
    _cadastro_web(web)
    assert web.get("/auth/eu").json()["email"] == "web@x.com"


def test_cookie_exige_cabecalho_csrf_para_alterar_dados(web):
    _cadastro_web(web)
    assert web.patch("/auth/eu", json={"nome": "Novo"}).status_code == 403  # sem X-Requested-With
    ok = web.patch("/auth/eu", json={"nome": "Novo"}, headers={"X-Requested-With": "mente-saudavel"})
    assert ok.status_code == 200 and ok.json()["nome"] == "Novo"


def test_sair_apaga_o_cookie(web):
    _cadastro_web(web)
    assert web.post("/auth/sair").status_code == 204
    assert web.get("/auth/eu").status_code == 401


def test_bearer_continua_valendo_sem_exigir_csrf(client):
    """Celular: o token vai no cabeçalho (não é enviado sozinho pelo navegador, então não há CSRF)."""
    u = cadastrar(client, "mobile@x.com")
    assert client.patch("/auth/eu", headers=u["h"], json={"nome": "Mob"}).status_code == 200


# ---------------------------------------------------------------- idempotência (fila offline do app)
def _agendar_chave(client, pac, pro_id, quando, chave):
    return client.post(
        "/sessoes",
        headers={**pac["h"], "Idempotency-Key": chave},
        json={"profissional_id": pro_id, "data_hora": quando, "modalidade": "Online"},
    )


def test_reenvio_com_a_mesma_chave_nao_duplica_a_sessao(client):
    pro = cadastrar(client, "pro-idem@x.com", "profissional")
    pac = cadastrar(client, "pac-idem@x.com")
    a = _agendar_chave(client, pac, pro["id"], futuro(), "chave-offline-0001")
    b = _agendar_chave(client, pac, pro["id"], futuro(), "chave-offline-0001")
    assert a.status_code == 201 and b.status_code == 200
    assert a.json()["id"] == b.json()["id"]
    assert len(client.get("/sessoes", headers=pac["h"]).json()) == 1


def test_reenvio_funciona_mesmo_que_o_horario_ja_esteja_ocupado_pela_propria_sessao(client):
    """A resposta do 1º envio se perdeu: o 2º não pode virar 409 contra a própria sessão."""
    pro = cadastrar(client, "pro-idem2@x.com", "profissional")
    pac = cadastrar(client, "pac-idem2@x.com")
    assert _agendar_chave(client, pac, pro["id"], futuro(), "chave-perdida-0002").status_code == 201
    assert _agendar_chave(client, pac, pro["id"], futuro(), "chave-perdida-0002").status_code == 200


def test_chave_diferente_no_mesmo_horario_continua_409(client):
    pro = cadastrar(client, "pro-idem3@x.com", "profissional")
    a = cadastrar(client, "pac-idem3a@x.com")
    b = cadastrar(client, "pac-idem3b@x.com")
    assert _agendar_chave(client, a, pro["id"], futuro(), "chave-aaaaaaaa-1").status_code == 201
    assert _agendar_chave(client, b, pro["id"], futuro(), "chave-bbbbbbbb-2").status_code == 409


def test_chave_invalida_e_recusada(client):
    pro = cadastrar(client, "pro-idem4@x.com", "profissional")
    pac = cadastrar(client, "pac-idem4@x.com")
    assert _agendar_chave(client, pac, pro["id"], futuro(), "curta").status_code == 422


# ---------------------------------------------------------------- LGPD: aceite e anonimização
def test_aceite_dos_termos_fica_registrado(client):
    u = cadastrar(client, "aceite@x.com")
    assert client.get("/auth/eu", headers=u["h"]).json()["aceite_termos_versao"] is None
    r = client.post("/auth/eu/aceite", headers=u["h"], json={"versao": "2026-10"})
    assert r.status_code == 200 and r.json()["aceite_termos_versao"] == "2026-10"
    assert client.get("/auth/eu", headers=u["h"]).json()["aceite_termos_versao"] == "2026-10"


def test_cadastro_pode_trazer_o_aceite(client):
    r = client.post("/auth/cadastro", json={"nome": "Com Aceite", "email": "ca@x.com", "senha": "senha-forte-1", "perfil": "paciente", "aceite_termos_versao": "2026-10"})
    assert r.status_code == 201 and r.json()["usuario"]["aceite_termos_versao"] == "2026-10"


def _paciente_com_dados(client):
    pro = cadastrar(client, "pro-lgpd@x.com", "profissional")
    pac = cadastrar(client, "pac-lgpd@x.com")
    sid = _agendar(client, pac, pro["id"], futuro()).json()["id"]
    client.post("/humor", headers=pac["h"], json={"nivel": 4, "nota": "dia difícil"})
    assert client.patch(f"/sessoes/{sid}", headers=pro["h"], json={"status": "concluida"}).status_code == 200
    assert client.put(f"/sessoes/{sid}/avaliacao", headers=pac["h"], json={"nota": 5, "comentario": "Muito bom, falei do meu pai"}).status_code in (200, 201)
    return pro, pac, sid


def test_anonimizar_apaga_humor_e_comentario_e_bloqueia_o_acesso(client):
    pro, pac, sid = _paciente_com_dados(client)
    assert client.post("/auth/eu/anonimizar", headers=pac["h"], json={"senha": "errada-errada"}).status_code == 401
    assert client.post("/auth/eu/anonimizar", headers=pac["h"], json={"senha": "senha-forte-1"}).status_code == 204

    # o token antigo e o login deixam de funcionar
    assert client.get("/auth/eu", headers=pac["h"]).status_code == 401
    assert client.post("/auth/entrar", json={"email": "pac-lgpd@x.com", "senha": "senha-forte-1"}).status_code == 401

    # o profissional continua com o histórico, sem identificar a pessoa
    sessoes = client.get("/sessoes", headers=pro["h"]).json()
    assert len(sessoes) == 1 and sessoes[0]["paciente_nome"] == "Paciente anonimizado"
    aval = client.get(f"/profissionais/{pro['id']}/avaliacoes", headers=pro["h"]).json()
    assert aval and aval[0]["comentario"] == "" and aval[0]["nota"] == 5

    # dados pessoais sumiram do banco
    from sqlalchemy import text

    with client.app.state.session_factory() as db:
        assert db.execute(text("SELECT COUNT(*) FROM humor_registros")).scalar() == 0
        email, nome = db.execute(text("SELECT email, nome FROM usuarios WHERE perfil='paciente'")).one()
    assert email.endswith("@anonimizado.invalid") and "lgpd" not in email and nome == "Paciente anonimizado"


def test_anonimizar_cancela_sessoes_futuras_e_mantem_as_concluidas(client):
    pro, pac, _ = _paciente_com_dados(client)  # 1 sessão concluída
    futura = _agendar(client, pac, pro["id"], futuro(72, 14)).json()["id"]
    assert client.post("/auth/eu/anonimizar", headers=pac["h"], json={"senha": "senha-forte-1"}).status_code == 204
    por_id = {s["id"]: s["status"] for s in client.get("/sessoes", headers=pro["h"]).json()}
    assert por_id[futura] == "cancelada"
    assert "concluida" in por_id.values()
    # o horário da futura volta a ficar livre para outras pessoas
    outro = cadastrar(client, "outro-lgpd@x.com")
    assert _agendar(client, outro, pro["id"], futuro(72, 14)).status_code == 201


def test_email_anonimizado_pode_ser_usado_de_novo(client):
    _, pac, _ = _paciente_com_dados(client)
    assert client.post("/auth/eu/anonimizar", headers=pac["h"], json={"senha": "senha-forte-1"}).status_code == 204
    assert cadastrar(client, "pac-lgpd@x.com")["id"] != pac["id"]


def test_profissional_nao_usa_anonimizacao(client):
    pro = cadastrar(client, "pro-anon@x.com", "profissional")
    assert client.post("/auth/eu/anonimizar", headers=pro["h"], json={"senha": "senha-forte-1"}).status_code == 403


# ---------------------------------------------------------------- observabilidade
def test_toda_resposta_traz_id_e_tempo(client):
    r = client.get("/health", headers={"X-Request-ID": "meu-id-de-teste-01"})
    assert r.headers["X-Request-ID"] == "meu-id-de-teste-01"
    assert r.headers["Server-Timing"].startswith("app;dur=")
    # id inválido (ex.: tentativa de injeção em log) é substituído por um gerado
    ruim = client.get("/health", headers={"X-Request-ID": "a b\tc"})
    assert ruim.headers["X-Request-ID"] != "a b\tc" and len(ruim.headers["X-Request-ID"]) == 32


def test_log_de_requisicao_e_json_sem_dados_pessoais(client, caplog):
    import json

    from app.observabilidade import JsonFormatter

    caplog.set_level(logging.INFO, logger="mente_saudavel")
    u = cadastrar(client, "segredo@x.com")
    client.get("/sessoes?status=agendada", headers=u["h"])
    linhas = [json.loads(JsonFormatter().format(r)) for r in caplog.records if r.getMessage() == "requisicao"]
    assert any(x["rota"] == "/sessoes" and x["status"] == 200 and x["duracao_ms"] >= 0 for x in linhas)
    todo_o_log = json.dumps(linhas)
    assert "segredo@x.com" not in todo_o_log and "senha-forte-1" not in todo_o_log and "agendada" not in todo_o_log


def test_erro_nao_tratado_vira_500_com_codigo_e_log(client, caplog):
    caplog.set_level(logging.ERROR, logger="mente_saudavel")

    def explode() -> None:
        raise RuntimeError("falha de teste")

    client.app.add_api_route("/__explode", explode)
    r = client.get("/__explode")
    assert r.status_code == 500
    assert "falha de teste" not in r.text and r.headers["X-Request-ID"] in r.json()["detail"]
    registro = next(x for x in caplog.records if x.getMessage() == "erro_nao_tratado")
    assert registro.campos["request_id"] == r.headers["X-Request-ID"] and registro.exc_info


def test_telemetria_do_app_vira_log_sem_email(client, caplog):
    caplog.set_level(logging.INFO, logger="mente_saudavel")
    corpo = {
        "versao_app": "1.0.0",
        "plataforma": "android",
        "eventos": [
            {"tipo": "erro", "nome": "FlutterError", "mensagem": "falhou para joao@exemplo.com", "pilha": "linha 1\nlinha 2"},
            {"tipo": "tela", "nome": "MinhasSessoes", "duracao_ms": 180},
        ],
    }
    assert client.post("/telemetria", json=corpo).status_code == 204
    eventos = [r.campos for r in caplog.records if r.getMessage() == "evento_cliente"]
    assert len(eventos) == 2 and eventos[0]["mensagem"] == "falhou para [email]" and eventos[1]["duracao_ms"] == 180


def test_telemetria_valida_tamanho_e_tem_limite(client):
    assert client.post("/telemetria", json={"eventos": []}).status_code == 422
    assert client.post("/telemetria", json={"eventos": [{"tipo": "hack", "nome": "x"}]}).status_code == 422
    assert client.post("/telemetria", json={"eventos": [{"tipo": "erro", "nome": "x" * 81}]}).status_code == 422
    ok = {"eventos": [{"tipo": "rede", "nome": "GET /sessoes", "duracao_ms": 50, "status": 200}]}
    codigos = [client.post("/telemetria", json=ok).status_code for _ in range(35)]
    assert codigos[0] == 204 and codigos[-1] == 429


def test_metricas_desligadas_por_padrao_e_protegidas_por_token(client):
    from sqlalchemy import create_engine
    from sqlalchemy.pool import StaticPool

    from app.config import Settings
    from app.main import create_app

    assert client.get("/metricas").status_code == 404
    eng = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    cfg = Settings(env="development", database_url="sqlite://", jwt_secret="z" * 40, metrics_token="token-de-metricas", signup_max_attempts=1000)
    with TestClient(create_app(cfg, eng)) as c:
        c.get("/health")
        assert c.get("/metricas").status_code == 401
        assert c.get("/metricas", headers={"Authorization": "Bearer errado"}).status_code == 401
        texto = c.get("/metricas", headers={"Authorization": "Bearer token-de-metricas"}).text
    assert 'ms_http_requests_total{metodo="GET",rota="/health",status="2xx"}' in texto
    assert "ms_http_request_duration_seconds_bucket" in texto


# ---------------------------------------------------------------- histórico de faturamento
def test_historico_financeiro_lista_meses_com_totais(client):
    pro = cadastrar(client, "pro-fin@x.com", "profissional")
    assert client.patch("/auth/eu", headers=pro["h"], json={"nome": "Dra Fin", "valor_sessao_centavos": 15000}).status_code == 200
    pac = cadastrar(client, "pac-fin@x.com")
    sid = _agendar(client, pac, pro["id"], futuro()).json()["id"]
    assert client.patch(f"/sessoes/{sid}", headers=pro["h"], json={"status": "concluida"}).status_code == 200

    h = client.get("/profissional/financeiro/historico?meses=3", headers=pro["h"]).json()
    assert len(h) == 3 and h[0]["mes"] > h[1]["mes"] > h[2]["mes"]  # do mais recente para o mais antigo
    # A sessão é daqui a 48 h: pode cair neste mês ou no próximo. Confere o total no mês dela.
    mes_da_sessao = futuro()[:7]
    unico = client.get(f"/profissional/financeiro?mes={mes_da_sessao}", headers=pro["h"]).json()
    assert unico["recebido_centavos"] == 15000
    if mes_da_sessao == h[0]["mes"]:  # caiu no mês corrente: o histórico traz o mesmo valor
        assert h[0]["recebido_centavos"] == 15000
    else:
        assert all(m["recebido_centavos"] == 0 for m in h)
    assert client.get("/profissional/financeiro/historico?meses=99", headers=pro["h"]).status_code == 422


def test_historico_financeiro_e_so_do_profissional(client):
    pac = cadastrar(client, "pac-fin2@x.com")
    assert client.get("/profissional/financeiro/historico", headers=pac["h"]).status_code == 403


# ---------------------------------------------------------------- corrida real (só roda com PostgreSQL: TEST_DATABASE_URL)
@pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="precisa de PostgreSQL real (TEST_DATABASE_URL)")
def test_corrida_de_agendamentos_simultaneos_gera_uma_sessao_e_o_resto_409(client):
    from concurrent.futures import ThreadPoolExecutor

    pro = cadastrar(client, "pro-corrida@x.com", "profissional")
    pacs = [cadastrar(client, f"pac-corrida{i}@x.com") for i in range(8)]
    quando = futuro()
    with ThreadPoolExecutor(max_workers=8) as ex:
        codigos = list(ex.map(lambda p: _agendar_chave(client, p, pro["id"], quando, f"chave-corrida-{p['id']}").status_code, pacs))
    assert sorted(codigos) == [201] + [409] * 7, codigos
    assert len(client.get("/sessoes", headers=pro["h"]).json()) == 1


@pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="precisa de PostgreSQL real (TEST_DATABASE_URL)")
def test_mesmo_agendamento_reenviado_em_paralelo_cria_so_uma_sessao(client):
    from concurrent.futures import ThreadPoolExecutor

    pro = cadastrar(client, "pro-paralelo@x.com", "profissional")
    pac = cadastrar(client, "pac-paralelo@x.com")
    quando = futuro()
    with ThreadPoolExecutor(max_workers=6) as ex:
        codigos = list(ex.map(lambda _: _agendar_chave(client, pac, pro["id"], quando, "chave-reenvio-paralelo").status_code, range(6)))
    assert set(codigos) <= {200, 201} and codigos.count(201) == 1, codigos
    assert len(client.get("/sessoes", headers=pac["h"]).json()) == 1
