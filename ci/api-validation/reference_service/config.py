"""Configuração validada do serviço (falha rápida em qualquer valor inseguro).

Toda configuração vem de variáveis de ambiente. Nenhuma é segredo, exceto
``API_AUTH_TOKEN_EXPECTED``, que nunca é registrado em log.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from dataclasses import dataclass

DEFAULT_ORIGINS = "https://gomesjoaovitor622-svg.github.io,http://localhost:8080"
_ORIGIN = re.compile(r"^https?://[A-Za-z0-9.-]+(:\d{1,5})?$")
_LOOPBACK = frozenset({"127.0.0.1", "localhost", "::1"})
_MIN_TOKEN_LEN = 16
_MAX_PORT = 65535
_MAX_AGE_LIMIT = 86400


class ConfigError(Exception):
    """Configuração proibida ou inválida (o serviço recusa subir)."""


def _bool(value: str) -> bool:
    return value.strip().lower() == "true"


@dataclass(frozen=True)
class ServiceConfig:
    host: str = "127.0.0.1"
    port: int = 8765
    allowed_origins: frozenset[str] = frozenset()
    allow_credentials: bool = True
    cors_max_age: int = 600
    auth_token: str | None = None
    rate_limit_per_sec: float = 20.0
    rate_burst: int = 200
    max_body_bytes: int = 64 * 1024
    socket_timeout_s: float = 10.0

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> ServiceConfig:
        host = env.get("MOCK_HOST", env.get("SERVICE_HOST", "127.0.0.1"))
        if host not in _LOOPBACK and not _bool(env.get("ALLOW_PUBLIC_BIND", "false")):
            raise ConfigError(f"bind em '{host}' recusado: use loopback ou ALLOW_PUBLIC_BIND=true")
        try:
            port = int(env.get("MOCK_PORT", env.get("SERVICE_PORT", "8765")))
            max_age = int(env.get("CORS_MAX_AGE", "600"))
            rate = float(env.get("RATE_LIMIT_PER_SEC", "20"))
            timeout = float(env.get("SOCKET_TIMEOUT_S", "10"))
        except ValueError as exc:
            raise ConfigError(f"valor numérico inválido: {exc}") from exc
        if not 1 <= port <= _MAX_PORT:
            raise ConfigError("porta fora do intervalo 1-65535")
        if not 0.5 <= timeout <= 60:  # noqa: PLR2004
            raise ConfigError("SOCKET_TIMEOUT_S deve estar entre 0.5 e 60")
        if not 1 <= max_age <= _MAX_AGE_LIMIT:
            raise ConfigError("CORS_MAX_AGE deve estar entre 1 e 86400")

        origins = frozenset(o.strip() for o in env.get("ALLOWED_ORIGINS", DEFAULT_ORIGINS).split(",") if o.strip())
        invalid = sorted(o for o in origins if o != "*" and not _ORIGIN.match(o))
        if invalid:
            raise ConfigError(f"ALLOWED_ORIGINS contém origem inválida: {invalid[0]!r}")
        credentials = _bool(env.get("ALLOW_CREDENTIALS", "true"))
        if "*" in origins and credentials:
            raise ConfigError("ALLOWED_ORIGINS='*' é incompatível com ALLOW_CREDENTIALS=true")

        token = env.get("API_AUTH_TOKEN_EXPECTED") or None
        if token is not None and len(token) < _MIN_TOKEN_LEN:
            raise ConfigError(f"o token de autenticação deve ter ao menos {_MIN_TOKEN_LEN} caracteres")
        return cls(host, port, origins, credentials, max_age, token, rate, socket_timeout_s=timeout)
