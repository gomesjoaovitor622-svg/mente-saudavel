"""Hash de senha (scrypt, só biblioteca padrão) e tokens JWT."""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import time
from typing import Any

import jwt

# Parâmetros scrypt (OWASP: N=2^15, r=8, p=1 ≈ 32 MiB). maxmem folgado para o OpenSSL.
_N, _R, _P = 2**15, 8, 1
_MAXMEM = 128 * 1024 * 1024


def hash_senha(senha: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(senha.encode(), salt=salt, n=_N, r=_R, p=_P, maxmem=_MAXMEM, dklen=32)
    return f"scrypt${_N}${_R}${_P}${base64.b64encode(salt).decode()}${base64.b64encode(dk).decode()}"


def verificar_senha(senha: str, armazenado: str) -> bool:
    try:
        esquema, n, r, p, salt_b64, dk_b64 = armazenado.split("$")
        if esquema != "scrypt":
            return False
        salt = base64.b64decode(salt_b64)
        esperado = base64.b64decode(dk_b64)
        dk = hashlib.scrypt(senha.encode(), salt=salt, n=int(n), r=int(r), p=int(p), maxmem=_MAXMEM, dklen=len(esperado))
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(dk, esperado)


# Hash falso para igualar o tempo de resposta quando o e-mail não existe.
HASH_FALSO = hash_senha(secrets.token_urlsafe(16))


def criar_token(user_id: int, segredo: str, ttl_horas: int, versao: int = 0) -> str:
    """`versao` (claim "tv") permite revogar todos os tokens de uma pessoa: basta aumentá-la no banco."""
    agora = int(time.time())
    return jwt.encode({"sub": str(user_id), "tv": versao, "iat": agora, "exp": agora + ttl_horas * 3600}, segredo, algorithm="HS256")


def ler_token_com_versao(token: str, segredo: str) -> tuple[int, int] | None:
    """(id do usuário, versão do token). Tokens antigos, sem "tv", valem como versão 0."""
    try:
        dados: dict[str, Any] = jwt.decode(token, segredo, algorithms=["HS256"], options={"require": ["exp", "sub"]})
        return int(dados["sub"]), int(dados.get("tv", 0))
    except (jwt.PyJWTError, ValueError, KeyError, TypeError):
        return None


def ler_token(token: str, segredo: str) -> int | None:
    lido = ler_token_com_versao(token, segredo)
    return lido[0] if lido else None
