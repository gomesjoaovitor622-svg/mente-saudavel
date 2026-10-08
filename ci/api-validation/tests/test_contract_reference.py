"""Contrato do serviço de referência: regras que a especificação não expressa sozinha.

Os casos de status/schema vêm de ``contracts/openapi.yaml`` (test_conformance_openapi.py).
Aqui ficam invariantes comportamentais: determinismo, cabeçalhos, mensagens de erro.
"""

from __future__ import annotations

import pytest
import requests

from apival.checks import ContractViolation, expect_json, expect_status
from apival.contracts import validate_named

pytestmark = [pytest.mark.reference, pytest.mark.contract]

PAYLOAD = {"paciente_id": 1, "profissional_id": 2, "data_hora": "2026-10-10T14:00:00", "modalidade": "Online"}


@pytest.mark.parametrize("ano", [2024, 2026, 2030])
def test_feriados_contem_natal_e_so_do_ano(api: requests.Session, ano: int) -> None:
    corpo = expect_json(api.get(f"/api/v1/feriados/{ano}"))
    datas = {item["date"] for item in corpo}
    if f"{ano}-12-25" not in datas:
        raise ContractViolation(f"[CONTRACT] feriados/{ano}: Natal (12-25) ausente")
    if not all(d.startswith(str(ano)) for d in datas):
        raise ContractViolation(f"[CONTRACT] feriados/{ano}: há datas de outro ano")


def test_sala_de_videochamada_e_deterministica(api: requests.Session) -> None:
    a = expect_json(api.post("/api/v1/sessoes/validar", json=PAYLOAD))
    b = expect_json(api.post("/api/v1/sessoes/validar", json=PAYLOAD))
    if a["sala"] != b["sala"]:
        raise ContractViolation("[CONTRACT] a mesma sessão deve gerar sempre a mesma sala")


@pytest.mark.parametrize(
    ("campo", "valor"),
    [
        ("paciente_id", 0),
        ("paciente_id", "1"),
        ("paciente_id", True),
        ("profissional_id", None),
        ("data_hora", "ontem"),
        ("modalidade", "Remoto"),
    ],
)
def test_erro_422_aponta_o_campo_invalido(api: requests.Session, campo: str, valor: object) -> None:
    resp = api.post("/api/v1/sessoes/validar", json={**PAYLOAD, campo: valor})
    expect_status(resp, 422, f"POST validar com {campo}={valor!r}")
    corpo = expect_json(resp)
    validate_named(corpo, "Error", "erro de validação")
    campos = {d["field"] for d in corpo["error"]["details"]}
    if campo not in campos:
        raise ContractViolation(f"[CONTRACT] o erro 422 deveria apontar '{campo}', apontou {sorted(campos)}")


def test_corpo_vazio_gera_um_erro_por_campo_obrigatorio(api: requests.Session) -> None:
    resp = api.post("/api/v1/sessoes/validar", json={})
    assert len(expect_json(resp)["error"]["details"]) == 4


@pytest.mark.parametrize(
    ("metodo", "caminho", "permitido"),
    [
        ("DELETE", "/api/v1/feriados/2026", "GET"),
        ("POST", "/health", "GET"),
        ("GET", "/api/v1/sessoes/validar", "POST"),
    ],
)
def test_metodo_nao_permitido_informa_allow(api: requests.Session, metodo: str, caminho: str, permitido: str) -> None:
    resp = api.request(metodo, caminho)
    expect_status(resp, 405, f"{metodo} {caminho}")
    if permitido not in resp.headers.get("Allow", ""):
        raise ContractViolation(f"[CONTRACT] 405 deve informar Allow com {permitido}")


def test_rota_inexistente_devolve_json_de_erro(api: requests.Session) -> None:
    resp = api.get("/api/v1/nao-existe")
    expect_status(resp, 404, "GET rota inexistente")
    validate_named(expect_json(resp), "Error", "404")
