"""Exceções tipadas e asserções usadas pelos testes.

Cada falha carrega um prefixo ([CONTRACT], [CORS], [SECURITY]) e uma classe própria, o que
permite ao auto-diagnóstico classificar sem adivinhar a partir do texto.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any, Protocol

from jsonschema import Draft202012Validator

from apival.redaction import redact


class ContractViolation(AssertionError):
    """Resposta/requisição fora do contrato (status, tipo ou schema)."""


class CorsPolicyViolation(AssertionError):
    """Política CORS violada (header ausente, errado ou permissivo demais)."""


class SecurityViolation(AssertionError):
    """Controle de segurança ausente ou contornável."""


class HttpResponse(Protocol):
    """Subconjunto somente leitura de ``requests.Response`` (facilita testar sem rede)."""

    @property
    def status_code(self) -> int: ...

    @property
    def text(self) -> str: ...

    @property
    def headers(self) -> Mapping[str, str]: ...

    def json(self) -> Any: ...  # noqa: ANN401


def expect_status(resp: HttpResponse, expected: int | Iterable[int], label: str) -> None:
    esperados = (expected,) if isinstance(expected, int) else tuple(expected)
    if resp.status_code not in esperados:
        trecho = redact(" ".join((resp.text or "").split()))[:160]
        raise ContractViolation(
            f"[CONTRACT] {label}: esperado HTTP {'/'.join(map(str, esperados))}, "
            f"recebido {resp.status_code} | corpo: {trecho or '(vazio)'}"
        )


def expect_json(resp: HttpResponse, label: str = "resposta") -> Any:  # noqa: ANN401
    try:
        return resp.json()
    except ValueError as exc:
        raise ContractViolation(f"[CONTRACT] {label}: corpo não é JSON válido ({exc})") from exc


def expect_json_content_type(resp: HttpResponse, label: str) -> None:
    tipo = resp.headers.get("Content-Type", "")
    if "application/json" not in tipo.lower():
        raise ContractViolation(f"[CONTRACT] {label}: Content-Type esperado application/json, recebido '{tipo}'")


def validate_schema(instance: object, schema: dict[str, Any], label: str) -> None:
    erros = sorted(Draft202012Validator(schema).iter_errors(instance), key=lambda e: list(e.absolute_path))
    if erros:
        detalhes = "; ".join(f"{'/'.join(map(str, e.absolute_path)) or '<raiz>'}: {e.message}" for e in erros[:5])
        raise ContractViolation(f"[CONTRACT] {label}: schema inválido -> {redact(detalhes)}")


def cors_check(condition: bool, message: str) -> None:
    if not condition:
        raise CorsPolicyViolation(f"[CORS] {message}")


def security_check(condition: bool, message: str) -> None:
    if not condition:
        raise SecurityViolation(f"[SECURITY] {message}")


def header_tokens(resp: HttpResponse, name: str) -> set[str]:
    """Valor de um header de lista ("GET, POST") como conjunto em minúsculas."""
    bruto = resp.headers.get(name, "")
    return {parte.strip().lower() for parte in bruto.split(",") if parte.strip()}
