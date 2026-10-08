"""Conformidade dirigida pela especificação: ``contracts/openapi.yaml`` é a fonte da verdade.

Para cada caso ``x-conformance``: executa a requisição, confere o status esperado, confere que
o status está DOCUMENTADO para a operação e valida o corpo contra o schema documentado.
Um segundo teste garante que todo status documentado é exercitado (cobertura do contrato).
"""

from __future__ import annotations

import pytest
import requests

from apival.checks import ContractViolation, expect_json, expect_status, security_check
from apival.contracts import (
    Case,
    conformance_cases,
    documented_statuses,
    load_spec,
    operations,
    response_schema_name,
    validate_named,
)

pytestmark = [pytest.mark.reference, pytest.mark.contract, pytest.mark.conformance]

CASES = conformance_cases()


@pytest.mark.parametrize("case", CASES, ids=[c.id for c in CASES])
def test_caso_de_conformidade(case: Case, api: requests.Session, auth_enabled: bool) -> None:
    if case.requires_auth and not auth_enabled:
        pytest.skip("o serviço foi iniciado sem autenticação")
    kwargs: dict[str, object] = {"headers": dict(case.headers)}
    if case.body is not None:
        kwargs["json"] = case.body
    elif case.repeat_body_bytes is not None:
        kwargs["data"] = "x" * case.repeat_body_bytes
    elif case.body_text is not None:
        kwargs["data"] = case.body_text

    resp = api.request(case.method, case.path, **kwargs)  # type: ignore[arg-type]
    if case.security:  # controle de segurança (autenticação, limite de corpo): falha = vulnerabilidade
        security_check(
            resp.status_code == case.expect_status,
            f"{case.id}: controle não aplicado (esperado HTTP {case.expect_status}, veio {resp.status_code})",
        )
    expect_status(resp, case.expect_status, case.id)
    if case.expect_status not in documented_statuses(case.method, case.template):
        raise ContractViolation(
            f"[CONTRACT] {case.id}: status {case.expect_status} não está documentado em openapi.yaml"
        )
    schema = response_schema_name(case.method, case.template, case.expect_status)
    if schema:
        validate_named(expect_json(resp, case.id), schema, case.id)


def test_todo_status_documentado_e_exercitado() -> None:
    """Contrato sem teste é apenas documentação: todo status declarado precisa de um caso."""
    cobertos: dict[tuple[str, str], set[int]] = {}
    for caso in CASES:
        cobertos.setdefault((caso.method, caso.template), set()).add(caso.expect_status)
    faltando: list[str] = []
    for metodo, caminho, operacao in operations():
        isentos = {int(x) for x in operacao.get("x-conformance-exempt", [])}
        pendentes = documented_statuses(metodo, caminho) - isentos - cobertos.get((metodo.upper(), caminho), set())
        if pendentes:
            faltando.append(f"{metodo.upper()} {caminho}: {sorted(pendentes)}")
    if faltando:
        raise ContractViolation("[CONTRACT] status documentados sem caso de conformidade: " + "; ".join(faltando))


def test_politica_cors_esta_declarada_na_especificacao() -> None:
    cors = load_spec().get("x-cors", {})
    if cors.get("wildcardWithCredentials") != "forbidden" or not cors.get("allowedMethods"):
        raise ContractViolation("[CONTRACT] openapi.yaml deve declarar a política CORS (x-cors)")
