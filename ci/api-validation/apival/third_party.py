"""Contratos das APIs públicas de terceiros consumidas pelo app (BrasilAPI, ViaCEP)."""

from __future__ import annotations

from typing import Any, Final

_DATA_ISO: Final[dict[str, Any]] = {"type": "string", "pattern": r"^\d{4}-\d{2}-\d{2}$"}

BRASILAPI_FERIADOS: Final[dict[str, Any]] = {
    "type": "array",
    "minItems": 5,
    "items": {
        "type": "object",
        "required": ["date", "name"],
        "properties": {"date": _DATA_ISO, "name": {"type": "string", "minLength": 1}},
    },
}

VIACEP_OK: Final[dict[str, Any]] = {
    "type": "object",
    "required": ["cep", "logradouro", "bairro", "localidade", "uf"],
    "properties": {
        "cep": {"type": "string", "pattern": r"^\d{5}-\d{3}$"},
        "uf": {"type": "string", "minLength": 2, "maxLength": 2},
    },
}

BRASILAPI_CEP_V2: Final[dict[str, Any]] = {
    "type": "object",
    "required": ["cep", "state", "city", "neighborhood", "street"],
    "properties": {
        "cep": {"type": "string"},
        "state": {"type": "string", "minLength": 2, "maxLength": 2},
        "city": {"type": "string"},
    },
}
