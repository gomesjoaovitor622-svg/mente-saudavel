"""Contrato da API de referência: status HTTP, tipos de dados e schemas.

Cada teste cobre uma regra do contrato. Falhas levantam ContractViolation,
que o auto-diagnóstico classifica como "Falhas de Contrato de API".
"""
import pytest

import schemas
from support import (ContractViolation, expect_json, expect_json_content_type,
                     expect_status, validate_schema)

pytestmark = [pytest.mark.mock, pytest.mark.contract]

PAYLOAD_VALIDO = {
    "paciente_id": 1, "profissional_id": 2,
    "data_hora": "2026-10-10T14:00:00", "modalidade": "Online",
}


def test_health_contrato(api):
    r = api.get("/health")
    expect_status(r, 200, "GET /health")
    expect_json_content_type(r, "GET /health")
    validate_schema(expect_json(r), schemas.HEALTH, "GET /health")


@pytest.mark.parametrize("ano", [2024, 2026, 2030])
def test_feriados_sucesso(api, ano):
    r = api.get(f"/api/v1/feriados/{ano}")
    expect_status(r, 200, f"GET feriados/{ano}")
    corpo = expect_json(r)
    validate_schema(corpo, schemas.FERIADOS, f"GET feriados/{ano}")
    datas = {item["date"] for item in corpo}
    if f"{ano}-12-25" not in datas:
        raise ContractViolation(f"[CONTRACT] feriados/{ano}: Natal (12-25) ausente da lista")
    if not all(d.startswith(str(ano)) for d in datas):
        raise ContractViolation(f"[CONTRACT] feriados/{ano}: há datas de outro ano")


@pytest.mark.parametrize("ano", ["abc", "20", "1800", "2101", "2026a"])
def test_feriados_ano_invalido(api, ano):
    r = api.get(f"/api/v1/feriados/{ano}")
    expect_status(r, 400, f"GET feriados/{ano}")
    validate_schema(expect_json(r), schemas.ERROR, f"GET feriados/{ano}")


def test_cep_sucesso(api):
    r = api.get("/api/v1/cep/01001000")
    expect_status(r, 200, "GET cep/01001000")
    validate_schema(expect_json(r), schemas.CEP, "GET cep/01001000")


def test_cep_inexistente(api):
    r = api.get("/api/v1/cep/99999999")
    expect_status(r, 404, "GET cep/99999999")
    validate_schema(expect_json(r), schemas.ERROR, "GET cep/99999999")


@pytest.mark.parametrize("cep", ["123", "abcdefgh", "0100100", "010010000"])
def test_cep_formato_invalido(api, cep):
    r = api.get(f"/api/v1/cep/{cep}")
    expect_status(r, 400, f"GET cep/{cep}")
    validate_schema(expect_json(r), schemas.ERROR, f"GET cep/{cep}")


def test_validar_sessao_sucesso(api):
    r = api.post("/api/v1/sessoes/validar", json=PAYLOAD_VALIDO)
    expect_status(r, 200, "POST sessoes/validar")
    validate_schema(expect_json(r), schemas.VALIDAR_OK, "POST sessoes/validar")


def test_validar_sessao_e_deterministico(api):
    a = api.post("/api/v1/sessoes/validar", json=PAYLOAD_VALIDO).json()
    b = api.post("/api/v1/sessoes/validar", json=PAYLOAD_VALIDO).json()
    if a["sala"] != b["sala"]:
        raise ContractViolation("[CONTRACT] mesma sessão deve gerar sempre a mesma sala")


@pytest.mark.parametrize("campo,valor", [
    ("paciente_id", 0), ("paciente_id", -3), ("paciente_id", "1"), ("paciente_id", True),
    ("profissional_id", None), ("data_hora", "ontem"), ("modalidade", "Remoto"),
])
def test_validar_sessao_campos_invalidos(api, campo, valor):
    payload = {**PAYLOAD_VALIDO, campo: valor}
    r = api.post("/api/v1/sessoes/validar", json=payload)
    expect_status(r, 422, f"POST validar com {campo}={valor!r}")
    corpo = expect_json(r)
    validate_schema(corpo, schemas.ERROR, "erro de validação")
    campos = {d["field"] for d in corpo["error"]["details"]}
    if campo not in campos:
        raise ContractViolation(f"[CONTRACT] erro 422 deveria apontar o campo '{campo}', apontou {sorted(campos)}")


def test_validar_sessao_campos_ausentes(api):
    r = api.post("/api/v1/sessoes/validar", json={})
    expect_status(r, 422, "POST validar com {}")
    assert len(r.json()["error"]["details"]) == 4


def test_validar_content_type_errado(api):
    r = api.post("/api/v1/sessoes/validar", data="x=1", headers={"Content-Type": "text/plain"})
    expect_status(r, 415, "POST validar text/plain")
    validate_schema(expect_json(r), schemas.ERROR, "415")


def test_validar_json_malformado(api):
    r = api.post("/api/v1/sessoes/validar", data="{nao-e-json", headers={"Content-Type": "application/json"})
    expect_status(r, 400, "POST validar JSON inválido")
    validate_schema(expect_json(r), schemas.ERROR, "400")


def test_validar_corpo_grande_demais(api):
    r = api.post("/api/v1/sessoes/validar", data="x" * (70 * 1024), headers={"Content-Type": "application/json"})
    expect_status(r, 413, "POST validar corpo > 64 KiB")


@pytest.mark.parametrize("metodo,caminho,permitido", [
    ("DELETE", "/api/v1/feriados/2026", "GET"),
    ("POST", "/health", "GET"),
    ("GET", "/api/v1/sessoes/validar", "POST"),
])
def test_metodo_nao_permitido(api, metodo, caminho, permitido):
    r = api.request(metodo, caminho)
    expect_status(r, 405, f"{metodo} {caminho}")
    allow = r.headers.get("Allow", "")
    if permitido not in allow:
        raise ContractViolation(f"[CONTRACT] 405 deve informar Allow com {permitido}; recebido '{allow}'")


def test_rota_inexistente(api):
    r = api.get("/api/v1/nao-existe")
    expect_status(r, 404, "GET rota inexistente")
    validate_schema(expect_json(r), schemas.ERROR, "404")


@pytest.mark.parametrize("caminho", ["/health", "/api/v1/feriados/2026", "/api/v1/nao-existe"])
def test_headers_de_seguranca_em_toda_resposta(api, caminho):
    r = api.get(caminho)
    if r.headers.get("X-Content-Type-Options") != "nosniff":
        raise ContractViolation(f"[CONTRACT] {caminho}: falta X-Content-Type-Options: nosniff")
    if "no-store" not in r.headers.get("Cache-Control", ""):
        raise ContractViolation(f"[CONTRACT] {caminho}: falta Cache-Control: no-store")
    if not r.headers.get("X-Request-Id"):
        raise ContractViolation(f"[CONTRACT] {caminho}: falta X-Request-Id (rastreabilidade)")
