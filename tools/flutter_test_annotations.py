#!/usr/bin/env python3
"""Lê a saída `flutter test --reporter json` (stdin) e imprime anotações do GitHub para cada teste que falhou.

Uso:  flutter test --reporter json | tee saida.json | python3 tools/flutter_test_annotations.py
Os logs do Actions nem sempre ficam acessíveis; as anotações (nome do teste + mensagem) sim.
"""

from __future__ import annotations

import json
import sys


def limpar(texto: str, limite: int = 600) -> str:
    return " ".join(texto.split())[:limite].replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def main() -> int:
    nomes: dict[int, str] = {}
    arquivos: dict[int, str] = {}
    erros: dict[int, list[str]] = {}
    total = falhas = 0
    for linha in sys.stdin:
        try:
            ev = json.loads(linha)
        except ValueError:
            continue
        tipo = ev.get("type")
        if tipo == "testStart":
            t = ev["test"]
            nomes[t["id"]] = t.get("name", "?")
            arquivos[t["id"]] = (t.get("url") or "").replace("file://", "").split("/test/")[-1]
        elif tipo == "testDone" and not ev.get("hidden"):
            total += 1
            if ev.get("result") != "success" and not ev.get("skipped"):
                falhas += 1
        elif tipo == "error":
            erros.setdefault(ev["testID"], []).append(ev.get("error", ""))
    for tid, msgs in erros.items():
        arq = arquivos.get(tid, "")
        nome = nomes.get(tid, "?")
        print(f"::error title=Teste falhou ({arq or 'test'})::{limpar(nome, 160)} :: {limpar(msgs[0])}")
    print(f"resumo: {total} testes, {falhas} falharam")
    return 0


if __name__ == "__main__":
    sys.exit(main())
