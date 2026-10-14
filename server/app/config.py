"""Configuração por variáveis de ambiente (nada de segredo no código)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field

_INSECURE_DEV_SECRET = "dev-only-secret-change-me-0123456789abcdef"  # pragma: allowlist secret


def _bool(name: str, default: bool) -> bool:
    return os.environ.get(name, str(default)).strip().lower() in {"1", "true", "yes", "sim"}


@dataclass(frozen=True)
class Settings:
    env: str = "production"
    database_url: str = "sqlite:///./data/mente_saudavel.db"
    jwt_secret: str = ""
    jwt_ttl_hours: int = 24 * 7
    cors_origins: tuple[str, ...] = field(default_factory=tuple)
    demo_seed: bool = False
    password_min: int = 8
    login_max_attempts: int = 10  # por minuto, por e-mail + IP
    signup_max_attempts: int = 10  # cadastros por minuto, por IP

    @property
    def is_dev(self) -> bool:
        return self.env == "development"


def load_settings() -> Settings:
    env = os.environ.get("APP_ENV", "production").strip().lower()
    secret = os.environ.get("JWT_SECRET", "")
    if env != "development" and (len(secret) < 32 or secret == _INSECURE_DEV_SECRET):
        raise RuntimeError(
            "JWT_SECRET ausente ou fraco. Defina uma chave aleatória com 32+ caracteres (ex.: `openssl rand -hex 32`) ou use APP_ENV=development apenas em testes locais."
        )
    if env == "development" and not secret:
        secret = _INSECURE_DEV_SECRET
    origins = tuple(o.strip() for o in os.environ.get("CORS_ORIGINS", "").split(",") if o.strip())
    if "*" in origins:
        raise RuntimeError("CORS_ORIGINS não pode conter '*': liste as origens exatas.")
    db_url = os.environ.get("DATABASE_URL", "sqlite:///./data/mente_saudavel.db")
    # Aceita o formato antigo "postgres://" de algumas plataformas.
    if db_url.startswith("postgres://"):
        db_url = "postgresql+psycopg://" + db_url[len("postgres://") :]
    elif db_url.startswith("postgresql://"):
        db_url = "postgresql+psycopg://" + db_url[len("postgresql://") :]
    return Settings(
        env=env,
        database_url=db_url,
        jwt_secret=secret,
        jwt_ttl_hours=int(os.environ.get("JWT_TTL_HOURS", str(24 * 7))),
        cors_origins=origins,
        demo_seed=_bool("DEMO_SEED", False),
        password_min=int(os.environ.get("PASSWORD_MIN", "8")),
        signup_max_attempts=int(os.environ.get("SIGNUP_MAX_ATTEMPTS", "10")),
    )
