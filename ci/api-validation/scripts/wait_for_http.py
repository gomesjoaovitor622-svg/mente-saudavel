#!/usr/bin/env python3
"""Health-check com polling, backoff exponencial e timeout total configurável.

Uso:
  wait_for_http.py URL [--timeout 30] [--interval 0.5] [--max-interval 4]
                       [--expect-status 200] [--contains '"status": "ok"'] [--pid-file arq.pid]

Códigos de saída (consumidos pelo auto-diagnóstico):
  0    serviço saudável
  124  HEALTHCHECK_TIMEOUT  (tempo esgotado sem resposta saudável)
  3    SERVER_EXITED        (o processo do serviço morreu durante a espera)
"""
from __future__ import annotations

import argparse
import os
import sys
import time
import urllib.error
import urllib.request


def processo_vivo(pid_file: str | None) -> bool:
    if not pid_file or not os.path.exists(pid_file):
        return True  # sem pid-file não dá para saber: assume vivo
    try:
        pid = int(open(pid_file).read().strip())
        os.kill(pid, 0)  # sinal 0 = só verifica existência
        try:  # Linux: processo "zumbi" (morto, ainda não coletado) também conta como morto
            with open(f"/proc/{pid}/stat") as f:
                if f.read().rsplit(")", 1)[1].split()[0] == "Z":
                    return False
        except (OSError, IndexError):
            pass
        return True
    except (ValueError, ProcessLookupError):
        return False
    except PermissionError:
        return True


def tentar(url: str, esperado: int, trecho: str | None) -> str | None:
    """Retorna None se saudável, ou a descrição do problema."""
    try:
        with urllib.request.urlopen(url, timeout=2) as resp:  # noqa: S310 (URL controlada pelo workflow)
            corpo = resp.read(65536).decode("utf-8", "replace")
            if resp.status != esperado:
                return f"HTTP {resp.status} (esperado {esperado})"
            if trecho and trecho not in corpo:
                return f"corpo sem o trecho esperado {trecho!r}"
            return None
    except urllib.error.HTTPError as exc:
        return f"HTTP {exc.code}"
    except (urllib.error.URLError, ConnectionError, TimeoutError, OSError) as exc:
        return f"{type(exc).__name__}: {getattr(exc, 'reason', exc)}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("url")
    ap.add_argument("--timeout", type=float, default=30.0)
    ap.add_argument("--interval", type=float, default=0.5)
    ap.add_argument("--max-interval", type=float, default=4.0)
    ap.add_argument("--expect-status", type=int, default=200)
    ap.add_argument("--contains", default=None)
    ap.add_argument("--pid-file", default=None)
    args = ap.parse_args()

    inicio = time.monotonic()
    espera = args.interval
    tentativa = 0
    ultimo_erro = "nenhuma tentativa"

    while True:
        tentativa += 1
        if not processo_vivo(args.pid_file):
            print(f"SERVER_EXITED: o processo do serviço terminou antes de ficar saudável (tentativa {tentativa})")
            return 3
        problema = tentar(args.url, args.expect_status, args.contains)
        decorrido = time.monotonic() - inicio
        if problema is None:
            print(f"HEALTHCHECK_OK {args.url} após {decorrido:.1f}s ({tentativa} tentativa(s))")
            return 0
        ultimo_erro = problema
        print(f"[{decorrido:5.1f}s] tentativa {tentativa}: {problema}", flush=True)
        if decorrido + espera >= args.timeout:
            print(f"HEALTHCHECK_TIMEOUT {args.url} após {args.timeout:.0f}s "
                  f"({tentativa} tentativa(s)); último erro: {ultimo_erro}")
            return 124
        time.sleep(espera)
        espera = min(espera * 2, args.max_interval)  # backoff exponencial limitado


if __name__ == "__main__":
    sys.exit(main())
