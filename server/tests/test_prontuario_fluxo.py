"""Prontuário: fluxo completo (cifra, revisões, trilha de auditoria, isolamento entre profissionais, logs sem conteúdo)."""

from __future__ import annotations

import logging

from sqlalchemy import text

from tests.conftest import cadastrar
from tests.test_prontuario import SEGREDO, _novo, _vinculo, ambiente


def test_mesmo_texto_gera_cifras_diferentes_e_cada_registro_decifra_o_seu(ambiente):
    client, engine = ambiente
    pro, pac = _vinculo(client)
    a = _novo(client, pro, pac).json()
    b = _novo(client, pro, pac).json()
    with engine.connect() as c:
        cifras = [r[0] for r in c.execute(text("SELECT conteudo_cifrado FROM prontuario_entradas ORDER BY id"))]
    assert len(cifras) == 2
    assert cifras[0] != cifras[1]
    assert a["conteudo"] == b["conteudo"] == SEGREDO


def test_revisoes_devolvem_as_versoes_antigas_decifradas_e_ficam_na_trilha(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    e = _novo(client, pro, pac, conteudo="versão 1").json()
    e2 = client.patch(f"/profissional/prontuario/{e['id']}", headers=pro["h"], json={"conteudo": "versão 2", "versao_esperada": 1}).json()
    e3 = client.patch(f"/profissional/prontuario/{e['id']}", headers=pro["h"], json={"conteudo": "versão 3", "versao_esperada": 2}).json()
    assert (e2["versao"], e3["versao"], e3["conteudo"]) == (2, 3, "versão 3")
    revs = client.get(f"/profissional/prontuario/{e['id']}/revisoes", headers=pro["h"]).json()
    assert [(r["versao"], r["conteudo"]) for r in revs] == [(2, "versão 2"), (1, "versão 1")]  # mais recente primeiro
    acoes = [a["acao"] for a in client.get(f"/profissional/pacientes/{pac['id']}/prontuario/acessos", headers=pro["h"]).json()]
    assert acoes.count("criacao") == 1
    assert acoes.count("edicao") == 2
    assert acoes.count("revisoes") == 1


def test_trilha_guarda_request_id_e_so_mostra_os_acessos_do_proprio_profissional(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers={**pro["h"], "X-Request-ID": "abc12345-req"})
    trilha = client.get(f"/profissional/pacientes/{pac['id']}/prontuario/acessos", headers=pro["h"]).json()
    assert trilha[0]["acao"] == "leitura"
    assert trilha[0]["request_id"] == "abc12345-req"
    # outro profissional (com vínculo próprio com o mesmo paciente) não enxerga a trilha do primeiro
    outro = cadastrar(client, "outro@x.com", "profissional")
    assert client.post("/sessoes", headers=pac["h"], json={"profissional_id": outro["id"], "data_hora": "2031-05-05T09:00:00", "modalidade": "Online"}).status_code == 201
    assert client.get(f"/profissional/pacientes/{pac['id']}/prontuario/acessos", headers=outro["h"]).json() == []


def test_profissionais_nao_veem_nem_editam_registros_um_do_outro(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    e = _novo(client, pro, pac).json()
    outro = cadastrar(client, "outro2@x.com", "profissional")
    assert client.post("/sessoes", headers=pac["h"], json={"profissional_id": outro["id"], "data_hora": "2031-06-06T09:00:00", "modalidade": "Online"}).status_code == 201
    # mesmo paciente, outro profissional com vínculo: lista vazia (cada um só vê o que escreveu)
    assert client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=outro["h"]).json() == []
    assert client.patch(f"/profissional/prontuario/{e['id']}", headers=outro["h"], json={"conteudo": "x", "versao_esperada": 1}).status_code == 404
    assert client.get(f"/profissional/prontuario/{e['id']}/revisoes", headers=outro["h"]).status_code == 404


def test_conteudo_clinico_nunca_aparece_nos_logs(ambiente, caplog):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    with caplog.at_level(logging.DEBUG):
        e = _novo(client, pro, pac, conteudo="paciente relatou ideação X-UNICO-123").json()
        client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pro["h"])
        client.patch(f"/profissional/prontuario/{e['id']}", headers=pro["h"], json={"conteudo": "outro texto Y-UNICO-456", "versao_esperada": 1})
    assert "X-UNICO-123" not in caplog.text
    assert "Y-UNICO-456" not in caplog.text


def test_resposta_de_erro_de_prontuario_nao_repete_o_conteudo(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    r = _novo(client, pro, pac, conteudo="z" * 20001)  # passa do limite
    assert r.status_code == 422
    assert "zzzz" not in r.text
    r = _novo(client, pro, pac, tipo="inexistente")
    assert r.status_code == 422


def test_sessao_de_outro_paciente_nao_pode_ser_ligada_ao_registro(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    outro_pac = cadastrar(client, "pac-outro@x.com")
    sid = client.post("/sessoes", headers=outro_pac["h"], json={"profissional_id": pro["id"], "data_hora": "2031-07-07T09:00:00", "modalidade": "Online"}).json()["id"]
    assert _novo(client, pro, pac, sessao_id=sid).status_code == 422


def test_listagem_vem_do_mais_novo_para_o_mais_antigo_e_respeita_o_limite(ambiente):
    client, _ = ambiente
    pro, pac = _vinculo(client)
    for i in range(5):
        _novo(client, pro, pac, conteudo=f"registro {i}")
    todos = client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pro["h"]).json()
    assert [e["conteudo"] for e in todos] == [f"registro {i}" for i in (4, 3, 2, 1, 0)]
    assert len(client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pro["h"], params={"limite": 2}).json()) == 2
    assert client.get(f"/profissional/pacientes/{pac['id']}/prontuario", headers=pro["h"], params={"limite": 501}).status_code == 422


def test_sem_login_nada_de_prontuario_abre(ambiente):
    client, _ = ambiente
    for caminho in ("/profissional/pacientes/1/prontuario", "/profissional/pacientes/1/prontuario/acessos", "/profissional/prontuario/1/revisoes"):
        assert client.get(caminho).status_code == 401
