"""Configuração por variáveis de ambiente (nada de segredo no código)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

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
    metrics_token: str = ""  # vazio = endpoint /metricas desligado (404)
    telemetry_max_per_minute: int = 30  # eventos enviados pelo app, por IP
    log_level: str = "INFO"
    cookie_secure: bool = True  # cookie de sessão só por HTTPS (desligue apenas em desenvolvimento local)
    # "auto": cria/ajusta tabelas ao subir (desenvolvimento e testes). "alembic": o esquema só muda por migrações
    # versionadas (`alembic upgrade head`); a API recusa subir se o banco não estiver na versão esperada.
    schema_mode: str = "auto"
    # Chaves Fernet (separadas por vírgula) que cifram o prontuário. A PRIMEIRA cifra; todas decifram (rotação de chaves).
    prontuario_chaves: tuple[str, ...] = field(default_factory=tuple)
    # Videochamada (Jitsi com JWT). Sem VIDEO_DOMAIN o recurso fica desligado (503).
    video_domain: str = ""
    video_app_id: str = ""
    video_app_secret: str = ""
    video_antes_min: int = 15  # a sala abre tantos minutos antes do horário
    video_depois_min: int = 120  # e fecha tantos minutos depois do horário

    # Fuso da clínica: todos os horários do sistema são "horário de parede" nele (veja app/tempo.py).
    app_tz: str = "America/Sao_Paulo"
    # E-mail (SMTP). Sem SMTP_HOST e SMTP_FROM o envio fica desligado: sem recuperação de senha nem verificação de e-mail.
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    smtp_seguranca: str = "starttls"  # starttls | ssl | none
    codigo_validade_min: int = 15  # validade dos códigos de 6 dígitos enviados por e-mail

    @property
    def email_ativo(self) -> bool:
        return bool(self.smtp_host and self.smtp_from)

    @property
    def is_dev(self) -> bool:
        return self.env == "development"


def normalizar_url_banco(url: str) -> str:
    """Aceita `postgres://` e `postgresql://` (formatos comuns em hospedagens) e usa o driver psycopg 3."""
    if url.startswith("postgres://"):
        return "postgresql+psycopg://" + url[len("postgres://") :]
    if url.startswith("postgresql://"):
        return "postgresql+psycopg://" + url[len("postgresql://") :]
    return url


def url_do_banco() -> str:
    return normalizar_url_banco(os.environ.get("DATABASE_URL", "sqlite:///./data/mente_saudavel.db"))


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
    db_url = url_do_banco()
    schema_mode = os.environ.get("SCHEMA_MODE", "auto").strip().lower()
    if schema_mode not in {"auto", "alembic"}:
        raise RuntimeError("SCHEMA_MODE deve ser 'auto' ou 'alembic'.")
    chaves = tuple(k.strip() for k in os.environ.get("PRONTUARIO_KEYS", "").split(",") if k.strip())
    if not chaves and env != "development":
        raise RuntimeError(
            'PRONTUARIO_KEYS ausente. Gere uma chave com: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" '
            "e guarde-a em local seguro (sem ela os prontuários não podem ser lidos)."
        )
    app_tz = os.environ.get("APP_TZ", "America/Sao_Paulo").strip()
    try:
        ZoneInfo(app_tz)
    except (ZoneInfoNotFoundError, ValueError):
        raise RuntimeError(f"APP_TZ inválido: {app_tz!r} (ex.: America/Sao_Paulo).") from None
    smtp_seguranca = os.environ.get("SMTP_SECURITY", "starttls").strip().lower()
    if smtp_seguranca not in {"starttls", "ssl", "none"}:
        raise RuntimeError("SMTP_SECURITY deve ser starttls, ssl ou none.")
    video_domain = os.environ.get("VIDEO_DOMAIN", "").strip().lower().removeprefix("https://").strip("/")
    return Settings(
        env=env,
        database_url=db_url,
        jwt_secret=secret,
        jwt_ttl_hours=int(os.environ.get("JWT_TTL_HOURS", str(24 * 7))),
        cors_origins=origins,
        demo_seed=_bool("DEMO_SEED", False),
        password_min=int(os.environ.get("PASSWORD_MIN", "8")),
        signup_max_attempts=int(os.environ.get("SIGNUP_MAX_ATTEMPTS", "10")),
        metrics_token=os.environ.get("METRICS_TOKEN", ""),
        telemetry_max_per_minute=int(os.environ.get("TELEMETRY_MAX_PER_MINUTE", "30")),
        log_level=os.environ.get("LOG_LEVEL", "INFO"),
        cookie_secure=_bool("COOKIE_SECURE", env != "development"),
        schema_mode=schema_mode,
        prontuario_chaves=chaves,
        video_domain=video_domain,
        video_app_id=os.environ.get("VIDEO_APP_ID", "mente-saudavel"),
        video_app_secret=os.environ.get("VIDEO_APP_SECRET", ""),
        video_antes_min=int(os.environ.get("VIDEO_ANTES_MIN", "15")),
        video_depois_min=int(os.environ.get("VIDEO_DEPOIS_MIN", "120")),
        app_tz=app_tz,
        smtp_host=os.environ.get("SMTP_HOST", "").strip(),
        smtp_port=int(os.environ.get("SMTP_PORT", "587")),
        smtp_user=os.environ.get("SMTP_USER", "").strip(),
        smtp_password=os.environ.get("SMTP_PASSWORD", ""),
        smtp_from=os.environ.get("SMTP_FROM", "").strip(),
        smtp_seguranca=smtp_seguranca,
        codigo_validade_min=int(os.environ.get("CODIGO_VALIDADE_MIN", "15")),
    )
