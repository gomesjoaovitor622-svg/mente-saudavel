from __future__ import annotations

from datetime import datetime, timedelta

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
    assert sorted(garantir_colunas(engine)) == ["sessoes.valor_centavos", "usuarios.valor_sessao_centavos"]
    assert garantir_colunas(engine) == []  # idempotente
    colunas = {c["name"] for c in inspect(engine).get_columns("sessoes")}
    assert "valor_centavos" in colunas
    with engine.connect() as c:
        assert c.exec_driver_sql("SELECT valor_centavos FROM sessoes").scalar() == 0
        assert c.exec_driver_sql("SELECT nome FROM usuarios").scalar() == "Ana"
    engine.dispose()
