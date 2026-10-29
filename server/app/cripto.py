"""Cifra do prontuário (criptografia autenticada, Fernet = AES-128-CBC + HMAC-SHA256).

O banco só guarda texto cifrado: quem obtiver um backup ou um dump do PostgreSQL não lê os prontuários sem a chave
(PRONTUARIO_KEYS, fora do banco). Para trocar a chave: ponha a nova PRIMEIRA na lista e mantenha a antiga atrás dela;
os registros antigos continuam legíveis e passam à chave nova quando forem editados (ou com `recifrar`).
"""

from __future__ import annotations

import base64
import hashlib
from collections.abc import Sequence

from cryptography.fernet import Fernet, InvalidToken, MultiFernet

# SOMENTE para desenvolvimento e testes (APP_ENV=development). Em produção a chave é obrigatória.
CHAVE_DEV = base64.urlsafe_b64encode(hashlib.sha256(b"mente-saudavel-chave-so-para-desenvolvimento").digest()).decode()


class ProntuarioIlegivel(Exception):
    """O texto cifrado não abre com nenhuma das chaves configuradas (chave errada ou dado corrompido)."""


class Cofre:
    def __init__(self, chaves: Sequence[str]) -> None:
        if not chaves:
            raise ValueError("Informe ao menos uma chave.")
        self._fernet = MultiFernet([Fernet(c.encode()) for c in chaves])

    def cifrar(self, texto: str) -> str:
        return self._fernet.encrypt(texto.encode()).decode()

    def decifrar(self, token: str) -> str:
        try:
            return self._fernet.decrypt(token.encode()).decode()
        except InvalidToken as e:
            raise ProntuarioIlegivel from e

    def recifrar(self, token: str) -> str:
        """Reescreve o texto cifrado com a chave principal (usada na rotação)."""
        try:
            return self._fernet.rotate(token.encode()).decode()
        except InvalidToken as e:
            raise ProntuarioIlegivel from e
