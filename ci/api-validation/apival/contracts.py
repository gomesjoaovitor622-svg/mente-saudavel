"""Contrato dirigido pela especificação: ``contracts/openapi.yaml`` é a fonte única da verdade.

Os testes de conformidade leem a especificação, executam os casos declarados em
``x-conformance`` e validam status e corpo contra os schemas documentados.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml

from apival.checks import ContractViolation, validate_schema

SPEC_PATH = Path(__file__).resolve().parent.parent / "contracts" / "openapi.yaml"
HTTP_METHODS = ("get", "post", "put", "patch", "delete")


@lru_cache(maxsize=1)
def load_spec() -> dict[str, Any]:
    with SPEC_PATH.open(encoding="utf-8") as arquivo:
        spec = yaml.safe_load(arquivo)
    if not isinstance(spec, dict) or "paths" not in spec:
        raise ContractViolation("[CONTRACT] openapi.yaml inválido: faltam 'paths'")
    return spec


def schema_by_name(name: str) -> dict[str, Any]:
    """Schema nomeado de ``components.schemas``, com ``$ref`` internos resolvíveis."""
    spec = load_spec()
    return {"$ref": f"#/components/schemas/{name}", "components": spec["components"]}


def validate_named(instance: object, name: str, label: str) -> None:
    validate_schema(instance, schema_by_name(name), label)


@dataclass(frozen=True)
class Case:
    """Um caso de conformidade declarado na especificação."""

    operation: str
    method: str
    template: str  # caminho como documentado, ex.: /api/v1/feriados/{ano}
    path: str  # caminho concreto do caso, ex.: /api/v1/feriados/2026
    name: str
    expect_status: int
    headers: dict[str, str | None] = field(default_factory=dict)  # None remove o header da sessão
    body: Any = None
    body_text: str | None = None
    repeat_body_bytes: int | None = None
    requires_auth: bool = False
    security: bool = False  # falha = violação de segurança (não apenas de contrato)

    @property
    def id(self) -> str:
        return f"{self.method.upper()} {self.path} :: {self.name}"


def operations() -> list[tuple[str, str, dict[str, Any]]]:
    return [
        (method, path, item[method])
        for path, item in load_spec()["paths"].items()
        for method in HTTP_METHODS
        if method in item
    ]


def _case(raw: dict[str, Any], method: str, template: str, operation: dict[str, Any]) -> Case:
    return Case(
        operation=str(operation.get("operationId", f"{method}:{template}")),
        method=method.upper(),
        template=template,
        path=str(raw["path"]),
        name=str(raw["name"]),
        expect_status=int(raw["status"]),
        headers=dict(raw.get("headers", {})),
        body=raw.get("body"),
        body_text=raw.get("body_text"),
        repeat_body_bytes=raw.get("repeat_body_bytes"),
        requires_auth=bool(raw.get("requires_auth", False)),
        security=bool(raw.get("security", raw.get("requires_auth", False))),
    )


def conformance_cases() -> list[Case]:
    return [
        _case(raw, method, path, operation)
        for method, path, operation in operations()
        for raw in operation.get("x-conformance", [])
    ]


def documented_statuses(method: str, path_template: str) -> set[int]:
    operation = load_spec()["paths"][path_template][method.lower()]
    return {int(code) for code in operation["responses"] if str(code).isdigit()}


def response_schema_name(method: str, path_template: str, status: int) -> str | None:
    """Nome do schema da resposta documentada (None se a resposta não tem corpo)."""
    operation = load_spec()["paths"][path_template][method.lower()]
    resposta = operation["responses"].get(status) or operation["responses"].get(str(status))
    if resposta is None:
        return None
    ref = resposta.get("content", {}).get("application/json", {}).get("schema", {}).get("$ref")
    return str(ref).rsplit("/", 1)[-1] if ref else None
