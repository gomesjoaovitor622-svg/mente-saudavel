#!/usr/bin/env python3
"""Converte a saída do `flutter analyze` em anotações do GitHub Actions (arquivo/linha/coluna)."""

from __future__ import annotations

import re
import sys

_LINE = re.compile(r"^\s*(error|warning|info)\s+•\s+(.*?)\s+•\s+([^\s:]+):(\d+):(\d+)\s+•\s+(\S+)\s*$")
_LEVEL = {"error": "error", "warning": "warning", "info": "notice"}


def _escape(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A").replace(",", "%2C").replace(":", "%3A")


def main() -> int:
    for linha in sys.stdin:
        achado = _LINE.match(linha)
        if achado:
            nivel, mensagem, arquivo, numero, coluna, regra = achado.groups()
            print(f"::{_LEVEL[nivel]} file={arquivo},line={numero},col={coluna},title={_escape(regra)}::{_escape(mensagem)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
