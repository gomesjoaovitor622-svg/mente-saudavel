#!/usr/bin/env python3
"""Serviço de referência para o pipeline de validação de APIs (somente biblioteca padrão).

Para que serve: ser o "sistema sob teste" determinístico do pipeline. Ele implementa
uma API pequena com política CORS ESTRITA, então a suite de testes pode provar que
(1) detecta violações e (2) aprova uma configuração correta, sem depender de internet.
Em um projeto real, troque este serviço pelo seu backend (input `service_start_command`).

Configuração por variáveis de ambiente (nenhuma é segredo):
  MOCK_HOST         interface de rede (padrão 127.0.0.1: NÃO expõe o serviço fora do runner)
  MOCK_PORT         porta (padrão 8765)
  ALLOWED_ORIGINS   origens autorizadas, separadas por vírgula
  ALLOW_CREDENTIALS "true"/"false" (padrão true)
  CORS_MAX_AGE      segundos de cache do preflight (padrão 600)

Endpoints:
  GET  /health
  GET  /api/v1/feriados/{ano}
  GET  /api/v1/cep/{cep}
  POST /api/v1/sessoes/validar
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import signal
import sys
import threading
import time
import uuid
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HOST = os.environ.get("MOCK_HOST", "127.0.0.1")
PORT = int(os.environ.get("MOCK_PORT", "8765"))
ALLOWED_ORIGINS = frozenset(
    o.strip()
    for o in os.environ.get(
        "ALLOWED_ORIGINS", "https://gomesjoaovitor622-svg.github.io,http://localhost:8080"
    ).split(",")
    if o.strip()
)
ALLOW_CREDENTIALS = os.environ.get("ALLOW_CREDENTIALS", "true").lower() == "true"
ALLOWED_HEADERS = frozenset({"content-type", "authorization", "x-requested-with"})
EXPOSED_HEADERS = "X-Request-Id"
MAX_AGE = int(os.environ.get("CORS_MAX_AGE", "600"))
MAX_BODY = 64 * 1024  # limite do corpo de requisições
DRAIN_LIMIT = 1024 * 1024  # só "descarta" corpos recusados até 1 MiB
STARTED = time.monotonic()

FERIADOS_FIXOS = [
    ("01-01", "Confraternização Universal"), ("04-21", "Tiradentes"), ("05-01", "Dia do Trabalho"),
    ("09-07", "Independência do Brasil"), ("10-12", "Nossa Senhora Aparecida"), ("11-02", "Finados"),
    ("11-15", "Proclamação da República"), ("11-20", "Dia da Consciência Negra"), ("12-25", "Natal"),
]
CEPS = {
    "01001000": {"cep": "01001000", "logradouro": "Praça da Sé", "bairro": "Sé",
                 "localidade": "São Paulo", "uf": "SP"},
}
MODALIDADES = {"Online", "Presencial"}


# --------------------------------------------------------------------------- handlers
def h_health(_req):
    return 200, {"status": "ok", "version": "1.0.0", "uptime_s": round(time.monotonic() - STARTED, 3)}


def h_feriados(req, ano):
    if not re.fullmatch(r"\d{4}", ano) or not 1900 <= int(ano) <= 2100:
        return 400, _err("invalid_year", "O ano deve ter 4 dígitos e estar entre 1900 e 2100.")
    return 200, [{"date": f"{ano}-{dia}", "name": nome, "type": "national"} for dia, nome in FERIADOS_FIXOS]


def h_cep(req, cep):
    if not re.fullmatch(r"\d{8}", cep):
        return 400, _err("invalid_cep", "O CEP deve ter exatamente 8 dígitos.")
    if cep not in CEPS:
        return 404, _err("cep_not_found", "CEP não encontrado.")
    return 200, CEPS[cep]


def h_validar(req):
    tipo = (req.headers.get("Content-Type") or "").split(";")[0].strip().lower()
    if tipo != "application/json":
        return 415, _err("unsupported_media_type", "Use Content-Type: application/json.")
    try:
        dados = json.loads(req.body or b"")
    except (ValueError, UnicodeDecodeError):
        return 400, _err("invalid_json", "O corpo não é um JSON válido.")
    if not isinstance(dados, dict):
        return 422, _err("validation_error", "O corpo deve ser um objeto JSON.", [])

    erros = []
    for campo in ("paciente_id", "profissional_id"):
        valor = dados.get(campo)
        if not isinstance(valor, int) or isinstance(valor, bool) or valor <= 0:
            erros.append({"field": campo, "message": "deve ser um inteiro positivo"})
    try:
        datetime.fromisoformat(str(dados.get("data_hora", "")))
    except ValueError:
        erros.append({"field": "data_hora", "message": "deve ser uma data/hora ISO 8601"})
    if dados.get("modalidade") not in MODALIDADES:
        erros.append({"field": "modalidade", "message": "deve ser Online ou Presencial"})
    if erros:
        return 422, _err("validation_error", "Payload inválido.", erros)

    base = f"{dados['paciente_id']}-{dados['profissional_id']}-{dados['data_hora']}"
    sala = "MenteSaudavel-" + hashlib.sha256(base.encode()).hexdigest()[:12]
    return 200, {"valid": True, "sala": sala}


ROUTES = [
    (re.compile(r"^/health$"), {"GET": h_health}),
    (re.compile(r"^/api/v1/feriados/(?P<ano>[^/]+)$"), {"GET": h_feriados}),
    (re.compile(r"^/api/v1/cep/(?P<cep>[^/]+)$"), {"GET": h_cep}),
    (re.compile(r"^/api/v1/sessoes/validar$"), {"POST": h_validar}),
]


def _err(code, message, details=None):
    corpo = {"code": code, "message": message}
    if details is not None:
        corpo["details"] = details
    return {"error": corpo}


# --------------------------------------------------------------------------- servidor
class Handler(BaseHTTPRequestHandler):
    server_version = "ReferenceAPI/1.0"
    protocol_version = "HTTP/1.1"
    body = b""

    def log_message(self, fmt, *args):  # desliga o log padrão; usamos log JSON próprio
        pass

    # ---- CORS
    def _cors(self):
        """Headers CORS para a origem da requisição (vazio de ACAO se não autorizada)."""
        origem = self.headers.get("Origin")
        cabecalhos = {"Vary": "Origin"}
        if origem is not None and origem in ALLOWED_ORIGINS:  # comparação EXATA, nunca por sufixo
            cabecalhos["Access-Control-Allow-Origin"] = origem  # ecoa a origem; nunca "*"
            cabecalhos["Access-Control-Expose-Headers"] = EXPOSED_HEADERS
            if ALLOW_CREDENTIALS:
                cabecalhos["Access-Control-Allow-Credentials"] = "true"
        return cabecalhos

    # ---- resposta
    def _send(self, status, payload=None, headers=None):
        corpo = b"" if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        base = {"X-Content-Type-Options": "nosniff", "Cache-Control": "no-store", "X-Request-Id": self.request_id}
        if status != 204:
            base["Content-Type"] = "application/json; charset=utf-8"
            base["Content-Length"] = str(len(corpo))
        else:
            base["Content-Length"] = "0"
        base.update(headers or {})
        for chave, valor in base.items():
            self.send_header(chave, valor)
        self.end_headers()
        if corpo:
            self.wfile.write(corpo)
        return status

    def _find_route(self, path):
        for padrao, metodos in ROUTES:
            m = padrao.match(path)
            if m:
                return m.groupdict(), metodos
        return None, None

    # ---- preflight
    def _preflight(self, path):
        origem = self.headers.get("Origin")
        metodo = self.headers.get("Access-Control-Request-Method")
        if origem is None or metodo is None:
            return self._send(400, _err("not_a_preflight", "Faltam Origin e/ou Access-Control-Request-Method."), self._cors())
        if origem not in ALLOWED_ORIGINS:
            return self._send(403, _err("origin_not_allowed", "Origem não autorizada."), {"Vary": "Origin"})
        _, metodos = self._find_route(path)
        if metodos is None:
            return self._send(404, _err("not_found", "Rota inexistente."), self._cors())
        permitidos = set(metodos) | {"OPTIONS"}
        if metodo.upper() not in permitidos:
            return self._send(405, _err("method_not_allowed", "Método não permitido."), {"Allow": ", ".join(sorted(permitidos)), "Vary": "Origin"})
        pedidos = [h.strip().lower() for h in (self.headers.get("Access-Control-Request-Headers") or "").split(",") if h.strip()]
        invalidos = [h for h in pedidos if h not in ALLOWED_HEADERS]
        if invalidos:
            return self._send(403, _err("header_not_allowed", f"Header não permitido: {', '.join(invalidos)}"), {"Vary": "Origin"})
        cab = self._cors()
        cab.update({
            "Access-Control-Allow-Methods": ", ".join(sorted(permitidos)),
            "Access-Control-Allow-Headers": ", ".join(pedidos) if pedidos else "content-type",
            "Access-Control-Max-Age": str(MAX_AGE),
            "Vary": "Origin, Access-Control-Request-Method, Access-Control-Request-Headers",
        })
        return self._send(204, None, cab)

    # ---- despacho
    def _handle(self, metodo):
        caminho = urlparse(self.path).path
        if metodo == "OPTIONS":
            return self._preflight(caminho)

        if metodo == "POST":  # lê o corpo antes de qualquer resposta (mantém o keep-alive consistente)
            tamanho = int(self.headers.get("Content-Length") or 0)
            if tamanho > MAX_BODY:
                if tamanho <= DRAIN_LIMIT:
                    self.rfile.read(tamanho)
                else:
                    self.close_connection = True
                return self._send(413, _err("payload_too_large", f"Máximo de {MAX_BODY} bytes."), self._cors())
            self.body = self.rfile.read(tamanho) if tamanho else b""

        params, metodos = self._find_route(caminho)
        if metodos is None:
            return self._send(404, _err("not_found", "Rota inexistente."), self._cors())
        if metodo not in metodos:
            cab = self._cors()
            cab["Allow"] = ", ".join(sorted(set(metodos) | {"OPTIONS"}))
            return self._send(405, _err("method_not_allowed", "Método não permitido."), cab)
        status, payload = metodos[metodo](self, **params)
        return self._send(status, payload, self._cors())

    def _dispatch(self, metodo):
        self.request_id = uuid.uuid4().hex[:12]
        inicio = time.monotonic()
        try:
            status = self._handle(metodo)
        except Exception:  # nunca vaza stack trace para o cliente
            status = self._send(500, _err("internal_error", "Erro interno."), self._cors())
        print(json.dumps({  # log estruturado; não registra Authorization nem corpo
            "ts": datetime.utcnow().isoformat(timespec="milliseconds") + "Z", "id": self.request_id,
            "method": metodo, "path": urlparse(self.path).path, "origin": self.headers.get("Origin"),
            "status": status, "ms": round((time.monotonic() - inicio) * 1000, 1),
        }), flush=True)

    def do_GET(self): self._dispatch("GET")
    def do_POST(self): self._dispatch("POST")
    def do_OPTIONS(self): self._dispatch("OPTIONS")
    def do_PUT(self): self._dispatch("PUT")
    def do_PATCH(self): self._dispatch("PATCH")
    def do_DELETE(self): self._dispatch("DELETE")


def main() -> int:
    # Falha rápida: "*" com credenciais é uma configuração proibida pela especificação CORS.
    if "*" in ALLOWED_ORIGINS and ALLOW_CREDENTIALS:
        print("FATAL: ALLOWED_ORIGINS='*' é incompatível com ALLOW_CREDENTIALS=true", file=sys.stderr)
        return 2
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    httpd.daemon_threads = True

    def parar(_sig, _frm):
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, parar)
    signal.signal(signal.SIGINT, parar)
    print(json.dumps({"event": "listening", "host": HOST, "port": PORT,
                      "allowed_origins": sorted(ALLOWED_ORIGINS), "credentials": ALLOW_CREDENTIALS}), flush=True)
    httpd.serve_forever()
    httpd.server_close()
    print(json.dumps({"event": "stopped"}), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
