"""Mascaramento de segredos e dados pessoais (PII) em qualquer texto que sai do sistema.

Princípio: nenhum log, relatório, anotação ou sumário pode conter credenciais nem dados
pessoais (LGPD/GDPR). Este módulo é a ÚNICA porta de saída de texto livre do toolkit.

Cobertura:
  segredos  -> tokens GitHub/AWS/Google/Slack, JWT, chaves privadas PEM, cabeçalho
               Authorization, pares chave=valor (token, senha, api_key...) e segredos
               conhecidos informados em tempo de execução (ex.: token efêmero do pipeline)
  PII       -> e-mail, CPF, CNPJ, telefone brasileiro e endereços IPv4 (exceto loopback)
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from urllib.parse import quote

_MASK = "***"

_PEM = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.DOTALL)
_JWT = re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b")
_TOKEN_PREFIXES = re.compile(
    r"\b(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}"
    r"|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,})\b"
)
_AUTH_HEADER = re.compile(r"(?i)(authorization\s*[:=]\s*(?:bearer|basic|token)\s+)[^\s'\"]+")
_KEY_VALUE = re.compile(
    r"(?i)(\b[\w-]*(?:token|secret|passw(?:or)?d|pwd|api[_-]?key)\b\s*[=:]\s*)(?!\*\*\*)(\"?)[^\s\"'&,;]+"
)
_EMAIL = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
_CNPJ = re.compile(r"\b\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\b")
_CPF = re.compile(r"\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b")
_PHONE_BR = re.compile(r"(?<!\d)(?:\+?55\s?)?\(?\d{2}\)?\s?9?\d{4}[-\s]?\d{4}(?!\d)")
_IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")

_MIN_SECRET_LEN = 6


def _mask_ip(match: re.Match[str]) -> str:
    texto = match.group(0)
    octetos = texto.split(".")
    if not all(o.isdigit() and int(o) <= 255 for o in octetos):  # noqa: PLR2004
        return texto
    if texto.startswith("127.") or texto == "0.0.0.0":  # noqa: S104  # nosec B104 - comparação de texto, não é bind
        return texto  # loopback é essencial para diagnóstico e não identifica ninguém
    return "[IP]"


def redact(text: str, extra_secrets: Iterable[str] = ()) -> str:
    """Devolve ``text`` sem segredos nem PII. ``extra_secrets`` são valores literais a mascarar."""
    for segredo in extra_secrets:
        if len(segredo) >= _MIN_SECRET_LEN:
            for forma in {segredo, quote(segredo, safe="")}:
                text = text.replace(forma, _MASK)
    text = _PEM.sub("[CHAVE-PRIVADA]", text)
    text = _JWT.sub("[JWT]", text)
    text = _TOKEN_PREFIXES.sub("[TOKEN]", text)
    text = _AUTH_HEADER.sub(rf"\1{_MASK}", text)
    text = _KEY_VALUE.sub(rf"\1{_MASK}", text)
    text = _EMAIL.sub("[E-MAIL]", text)
    text = _CNPJ.sub("[CNPJ]", text)
    text = _CPF.sub("[CPF]", text)
    text = _PHONE_BR.sub("[TELEFONE]", text)
    return _IPV4.sub(_mask_ip, text)
