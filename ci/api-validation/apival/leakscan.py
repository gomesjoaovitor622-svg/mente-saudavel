"""Varredura de vazamento: garante que um segredo NÃO aparece em nenhum relatório/log.

O valor do segredo é lido de uma variável de ambiente (nunca de argumento de linha de
comando, que aparece na lista de processos) e jamais é impresso.

Uso: ``python -m apival.leakscan --env-var API_AUTH_TOKEN --path reports``
Saída: 0 = limpo | 1 = vazamento encontrado | 2 = uso inválido
"""

from __future__ import annotations

import argparse
import base64
import os
import sys
from collections.abc import Iterable, Sequence
from pathlib import Path
from urllib.parse import quote

_MIN_LEN = 8


def _variants(secret: str) -> set[bytes]:
    formas = {
        secret,
        quote(secret, safe=""),
        base64.b64encode(secret.encode()).decode(),
        base64.b64encode(f"Bearer {secret}".encode()).decode(),
    }
    return {forma.encode() for forma in formas}


def scan(secret: str, paths: Iterable[Path]) -> list[str]:
    """Caminhos de arquivos que contêm o segredo (ou sua forma codificada)."""
    formas = _variants(secret)
    achados: list[str] = []
    for raiz in paths:
        arquivos = [raiz] if raiz.is_file() else sorted(p for p in raiz.rglob("*") if p.is_file())
        for arquivo in arquivos:
            try:
                conteudo = arquivo.read_bytes()
            except OSError:
                continue
            if any(forma in conteudo for forma in formas):
                achados.append(str(arquivo))
    return achados


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--env-var", required=True, help="nome da variável de ambiente com o segredo")
    parser.add_argument("--path", action="append", required=True, help="arquivo ou pasta a varrer")
    args = parser.parse_args(argv)
    secret = os.environ.get(args.env_var, "")
    if len(secret) < _MIN_LEN:
        print(f"ERRO: a variável {args.env_var} está vazia ou curta demais para varrer", file=sys.stderr)
        return 2
    achados = scan(secret, [Path(p) for p in args.path])
    if achados:
        print(
            f"::error title=Vazamento de segredo::O valor de {args.env_var} apareceu em {len(achados)} arquivo(s): "
            + ", ".join(achados)
        )
        return 1
    print(f"LEAKSCAN_OK: o valor de {args.env_var} não aparece em {', '.join(args.path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
