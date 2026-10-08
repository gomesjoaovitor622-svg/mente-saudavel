"""Health-check com polling, backoff exponencial e timeout total configurável.

Uso: ``python -m apival.healthcheck URL [--timeout 30] [--pid-file arq.pid] ...``

Códigos de saída (consumidos pelo auto-diagnóstico):
  0    serviço saudável
  124  HEALTHCHECK_TIMEOUT  (tempo esgotado sem resposta saudável)
  3    SERVER_EXITED        (o processo do serviço morreu durante a espera)
  2    uso inválido (URL fora de http/https)
"""

from __future__ import annotations

import argparse
import os
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Sequence
from urllib.parse import urlsplit

EXIT_OK = 0
EXIT_BAD_USAGE = 2
EXIT_SERVER_EXITED = 3
EXIT_TIMEOUT = 124
_ALLOWED_SCHEMES = frozenset({"http", "https"})
_REQUEST_TIMEOUT_S = 5
_BODY_LIMIT = 65536


def process_alive(pid_file: str | None) -> bool:
    """Falso se o PID informado morreu (inclui processo zumbi no Linux)."""
    if not pid_file or not os.path.exists(pid_file):
        return True  # sem pid-file não dá para saber: assume vivo
    try:
        with open(pid_file, encoding="utf-8") as arquivo:
            pid = int(arquivo.read().strip())
        os.kill(pid, 0)  # sinal 0 só verifica a existência
    except (ValueError, ProcessLookupError):
        return False
    except PermissionError:
        return True
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8") as stat:
            return stat.read().rsplit(")", 1)[1].split()[0] != "Z"
    except (OSError, IndexError):
        return True


def probe(url: str, expected_status: int, contains: str | None, user_agent: str) -> str | None:
    """None se saudável; caso contrário, a descrição do problema."""
    if urlsplit(url).scheme not in _ALLOWED_SCHEMES:
        raise ValueError("somente http/https são permitidos")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": user_agent})  # noqa: S310 (esquema validado acima)
        with urllib.request.urlopen(req, timeout=_REQUEST_TIMEOUT_S) as resp:  # noqa: S310  # nosec B310 - esquema http/https validado acima
            body = resp.read(_BODY_LIMIT).decode("utf-8", "replace")
            if resp.status != expected_status:
                return f"HTTP {resp.status} (esperado {expected_status})"
            if contains and contains not in body:
                return f"corpo sem o trecho esperado {contains!r}"
            return None
    except urllib.error.HTTPError as exc:
        return f"HTTP {exc.code}"
    except (urllib.error.URLError, ConnectionError, TimeoutError, OSError) as exc:
        return f"{type(exc).__name__}: {getattr(exc, 'reason', exc)}"


def wait(
    url: str,
    *,
    timeout: float,
    interval: float = 0.5,
    max_interval: float = 4.0,
    expected_status: int = 200,
    contains: str | None = None,
    pid_file: str | None = None,
    user_agent: str = "api-validation-healthcheck/1.0",
) -> int:
    start = time.monotonic()
    pause = interval
    attempt = 0
    while True:
        attempt += 1
        if not process_alive(pid_file):
            print(f"SERVER_EXITED: o processo do serviço terminou antes de ficar saudável (tentativa {attempt})")
            return EXIT_SERVER_EXITED
        problem = probe(url, expected_status, contains, user_agent)
        elapsed = time.monotonic() - start
        if problem is None:
            print(f"HEALTHCHECK_OK {url} após {elapsed:.1f}s ({attempt} tentativa(s))")
            return EXIT_OK
        print(f"[{elapsed:5.1f}s] tentativa {attempt}: {problem}", flush=True)
        if elapsed + pause >= timeout:
            print(f"HEALTHCHECK_TIMEOUT {url} após {timeout:.0f}s ({attempt} tentativa(s)); último erro: {problem}")
            return EXIT_TIMEOUT
        time.sleep(pause)
        pause = min(pause * 2, max_interval)  # backoff exponencial limitado


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("url")
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--interval", type=float, default=0.5)
    parser.add_argument("--max-interval", type=float, default=4.0)
    parser.add_argument("--expect-status", type=int, default=200)
    parser.add_argument("--contains", default=None)
    parser.add_argument("--pid-file", default=None)
    parser.add_argument("--user-agent", default="api-validation-healthcheck/1.0")
    args = parser.parse_args(argv)
    if urlsplit(args.url).scheme not in _ALLOWED_SCHEMES:
        print("ERRO: a URL deve usar http ou https", file=sys.stderr)
        return EXIT_BAD_USAGE
    return wait(
        args.url,
        timeout=args.timeout,
        interval=args.interval,
        max_interval=args.max_interval,
        expected_status=args.expect_status,
        contains=args.contains,
        pid_file=args.pid_file,
        user_agent=args.user_agent,
    )


if __name__ == "__main__":
    sys.exit(main())
