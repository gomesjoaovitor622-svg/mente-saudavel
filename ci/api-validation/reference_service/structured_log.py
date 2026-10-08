"""Logs estruturados (JSON, uma linha por evento) sem segredos nem PII.

Somente campos de uma lista permitida são gravados; todo texto passa por ``redact``.
Não registramos IP do cliente, User-Agent, corpo, query string nem cabeçalhos.
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import UTC, datetime
from typing import IO, Any, Final

from apival.redaction import redact

ALLOWED_FIELDS: Final = frozenset(
    {
        "id",
        "method",
        "path",
        "status",
        "ms",
        "origin_allowed",
        "host",
        "port",
        "credentials",
        "allowed_origins",
        "auth_enabled",
        "error_type",
        "reason",
    }
)
_MAX_TEXT = 200


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": datetime.fromtimestamp(record.created, UTC).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "event": record.getMessage(),
        }
        fields = getattr(record, "fields", {})
        for chave, valor in fields.items():
            if chave not in ALLOWED_FIELDS:
                continue
            payload[chave] = redact(valor)[:_MAX_TEXT] if isinstance(valor, str) else valor
        return json.dumps(payload, ensure_ascii=False)


def get_logger(stream: IO[str] | None = None, name: str = "reference_service") -> logging.Logger:
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    logger.propagate = False
    for handler in list(logger.handlers):
        logger.removeHandler(handler)
    handler = logging.StreamHandler(stream or sys.stdout)
    handler.setFormatter(JsonFormatter())
    logger.addHandler(handler)
    return logger


def log_event(logger: logging.Logger, event: str, level: int = logging.INFO, **fields: Any) -> None:  # noqa: ANN401
    logger.log(level, event, extra={"fields": fields})
