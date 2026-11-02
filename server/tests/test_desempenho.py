"""Desempenho: listagens não podem fazer 1 consulta por linha (N+1)."""

from __future__ import annotations

from sqlalchemy import event

from tests.conftest import cadastrar, futuro


def _contar(client, chamada) -> int:
    eng = client.app.state.session_factory.kw["bind"]
    n = [0]

    def _conta(*_a, **_k):  # type: ignore[no-untyped-def]
        n[0] += 1

    event.listen(eng, "before_cursor_execute", _conta)
    try:
        chamada()
    finally:
        event.remove(eng, "before_cursor_execute", _conta)
    return n[0]


def _popular(client, qtd: int):
    pro = cadastrar(client, "pro-perf@x.com", "profissional")
    pac = cadastrar(client, "pac-perf@x.com")
    for h in range(qtd):
        r = client.post(
            "/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": futuro(horas=48 + 24 * (h // 10), hora=8 + h % 10), "modalidade": "Online"}
        )
        assert r.status_code == 201, r.text
    return pro, pac


def test_listar_sessoes_usa_numero_fixo_de_consultas(client):
    pro, pac = _popular(client, 3)
    pouco = _contar(client, lambda: client.get("/sessoes", headers=pac["h"]))
    pro2, pac2 = _popular_extra(client)
    muito = _contar(client, lambda: client.get("/sessoes", headers=pac["h"]))
    assert muito == pouco  # mesma quantidade de consultas com mais linhas
    assert muito <= 4  # usuário (token) + sessões (+ juntas); nunca 1 por sessão


def _popular_extra(client):
    pac = cadastrar(client, "pac-perf2@x.com")
    pro = cadastrar(client, "pro-perf2@x.com", "profissional")
    return pro, pac


def test_listagem_do_profissional_com_muitos_pacientes_nao_faz_consulta_por_paciente(client):
    """O caso que denuncia N+1: cada sessão de um paciente DIFERENTE (o cache da sessão não ajuda)."""
    pro = cadastrar(client, "pro-muitos@x.com", "profissional")
    for i in range(10):
        pac = cadastrar(client, f"pac-muitos{i}@x.com")
        assert client.post("/sessoes", headers=pac["h"], json={"profissional_id": pro["id"], "data_hora": futuro(hora=8 + i), "modalidade": "Online"}).status_code == 201
    qtd = _contar(client, lambda: client.get("/sessoes", headers=pro["h"]))
    assert qtd <= 4, f"{qtd} consultas para 10 sessões: há consulta por linha (N+1)"
    qtd_av = _contar(client, lambda: client.get(f"/profissionais/{pro['id']}/avaliacoes", headers=pro["h"]))
    assert qtd_av <= 4, qtd_av
