"""Camada HTTP do serviço de referência (somente biblioteca padrão).

Endurecimentos (OWASP): timeout de socket (slowloris), rejeição de Transfer-Encoding e
de Content-Length inválido/duplicado (request smuggling), limite de corpo e de URL,
banner genérico, erro interno sem detalhes, log estruturado sem PII.

Uso: ``python -m reference_service.server`` (configuração por variáveis de ambiente).
"""

from __future__ import annotations

import json
import logging
import os
import re
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, cast
from urllib.parse import urlsplit

from reference_service.app import ReferenceApp, Request, Response, error
from reference_service.config import ConfigError, ServiceConfig
from reference_service.structured_log import get_logger, log_event

_CONTENT_LENGTH = re.compile(r"^\d{1,9}$")
_DRAIN_LIMIT = 1024 * 1024
_NO_BODY = 204


class _Server(ThreadingHTTPServer):
    app: ReferenceApp
    config: ServiceConfig
    log: logging.Logger


class _Handler(BaseHTTPRequestHandler):
    server_version = "api"  # banner genérico: não revela produto nem versão
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: Any) -> None:  # noqa: ARG002, ANN401  (assinatura da stdlib)
        return  # o log padrão expõe IP do cliente; usamos o log estruturado

    @property
    def _srv(self) -> _Server:
        return cast("_Server", self.server)

    def _send(self, resposta: Response, request_id: str | None = None) -> int:
        corpo = b"" if resposta.payload is None else json.dumps(resposta.payload, ensure_ascii=False).encode("utf-8")
        self.send_response(resposta.status)
        cabecalhos = dict(resposta.headers)
        if resposta.status != _NO_BODY:
            cabecalhos["Content-Type"] = "application/json; charset=utf-8"
        cabecalhos["Content-Length"] = str(len(corpo))
        if request_id:
            cabecalhos.setdefault("X-Request-Id", request_id)
        for nome, valor in cabecalhos.items():
            self.send_header(nome, valor)
        self.end_headers()
        if corpo:
            self.wfile.write(corpo)
        return resposta.status

    def _read_body(self) -> tuple[bytes, Response | None]:
        """Valida Content-Length/Transfer-Encoding e lê o corpo. Retorna (corpo, erro)."""
        if self.headers.get("Transfer-Encoding") is not None:
            self.close_connection = True
            return b"", error(501, "not_implemented", "Transfer-Encoding não suportado.")
        valores = self.headers.get_all("Content-Length") or []
        if len(valores) > 1:
            self.close_connection = True
            return b"", error(400, "invalid_content_length", "Content-Length duplicado.")
        if not valores:
            return b"", None
        if not _CONTENT_LENGTH.match(valores[0].strip()):
            self.close_connection = True
            return b"", error(400, "invalid_content_length", "Content-Length inválido.")
        tamanho = int(valores[0])
        limite = self._srv.config.max_body_bytes
        if tamanho > limite:
            if tamanho <= _DRAIN_LIMIT:
                self.rfile.read(tamanho)
            else:
                self.close_connection = True
            return b"", error(413, "payload_too_large", f"Máximo de {limite} bytes.")
        return (self.rfile.read(tamanho) if tamanho else b""), None

    def _serve(self, method: str) -> None:
        inicio = time.monotonic()
        srv = self._srv
        status = 500
        origin_ok = False
        try:
            if len(self.headers.get_all("Origin") or []) > 1:
                status = self._send(error(400, "invalid_origin", "Header Origin duplicado."))
                return
            corpo, falha = self._read_body()
            headers = {k.lower(): v for k, v in self.headers.items()}
            origin_ok = srv.app.origin_allowed(headers.get("origin"))
            if falha is not None:
                status = self._send(falha)
                return
            cliente = self.client_address[0] if self.client_address else "-"
            resposta = srv.app.handle(Request(method, urlsplit(self.path).path, headers, corpo, cliente))
            status = self._send(resposta)
        except (TimeoutError, ConnectionError):
            self.close_connection = True
            status = 408
        except Exception as exc:
            self.close_connection = True
            log_event(srv.log, "internal_error", logging.ERROR, error_type=type(exc).__name__)
            try:
                status = self._send(error(500, "internal_error", "Erro interno."))
            except OSError:
                status = 500
        finally:
            log_event(
                srv.log,
                "request",
                method=method,
                path=urlsplit(self.path).path,
                status=status,
                ms=round((time.monotonic() - inicio) * 1000, 1),
                origin_allowed=origin_ok,
            )

    def do_GET(self) -> None:
        self._serve("GET")

    def do_POST(self) -> None:
        self._serve("POST")

    def do_OPTIONS(self) -> None:
        self._serve("OPTIONS")

    def do_PUT(self) -> None:
        self._serve("PUT")

    def do_PATCH(self) -> None:
        self._serve("PATCH")

    def do_DELETE(self) -> None:
        self._serve("DELETE")


def create_server(config: ServiceConfig, logger: logging.Logger | None = None) -> _Server:
    handler = type("BoundHandler", (_Handler,), {"timeout": config.socket_timeout_s})
    server = _Server((config.host, config.port), handler)
    server.daemon_threads = True
    server.app = ReferenceApp(config)
    server.config = config
    server.log = logger or get_logger()
    return server


def main() -> int:
    logger = get_logger()
    try:
        config = ServiceConfig.from_env(os.environ)
    except ConfigError as exc:
        print(f"FATAL: {exc}", file=sys.stderr)  # padrão reconhecido pelo auto-diagnóstico
        return 2
    server = create_server(config, logger)

    def stop(_signum: int, _frame: object) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    log_event(
        logger,
        "listening",
        host=config.host,
        port=config.port,
        credentials=config.allow_credentials,
        allowed_origins=",".join(sorted(config.allowed_origins)),
        auth_enabled=config.auth_token is not None,
    )
    server.serve_forever()
    server.server_close()
    log_event(logger, "stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
