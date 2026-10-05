"""Exceções e helpers compartilhados pelos testes.

As exceções tipadas (ContractViolation / CorsPolicyViolation) e os prefixos
"[CONTRACT]" / "[CORS]" nas mensagens permitem que o auto-diagnóstico
(scripts/diagnose.py) classifique cada falha com precisão.
"""
from __future__ import annotations

from typing import Iterable

from jsonschema import Draft202012Validator


class ContractViolation(AssertionError):
    """Resposta/requisição fora do contrato (status, tipo ou schema)."""


class CorsPolicyViolation(AssertionError):
    """Política CORS violada (header ausente, errado ou permissivo demais)."""


def expect_status(resp, expected: int | Iterable[int], label: str) -> None:
    esperados = (expected,) if isinstance(expected, int) else tuple(expected)
    if resp.status_code not in esperados:
        raise ContractViolation(
            f"[CONTRACT] {label}: esperado HTTP {'/'.join(map(str, esperados))}, "
            f"recebido {resp.status_code}"
        )


def expect_json(resp, label: str = "resposta"):
    try:
        return resp.json()
    except ValueError as exc:
        raise ContractViolation(f"[CONTRACT] {label}: corpo não é JSON válido ({exc})") from exc


def expect_json_content_type(resp, label: str) -> None:
    tipo = resp.headers.get("Content-Type", "")
    if "application/json" not in tipo.lower():
        raise ContractViolation(f"[CONTRACT] {label}: Content-Type esperado application/json, recebido '{tipo}'")


def validate_schema(instance, schema: dict, label: str) -> None:
    erros = sorted(Draft202012Validator(schema).iter_errors(instance), key=lambda e: list(e.absolute_path))
    if erros:
        detalhes = "; ".join(
            f"{'/'.join(map(str, e.absolute_path)) or '<raiz>'}: {e.message}" for e in erros[:5]
        )
        raise ContractViolation(f"[CONTRACT] {label}: schema inválido -> {detalhes}")


def cors_check(condition: bool, message: str) -> None:
    if not condition:
        raise CorsPolicyViolation(f"[CORS] {message}")


def header_tokens(resp, name: str) -> set[str]:
    """Valor de um header de lista ("GET, POST") como conjunto em minúsculas."""
    bruto = resp.headers.get(name, "")
    return {parte.strip().lower() for parte in bruto.split(",") if parte.strip()}
