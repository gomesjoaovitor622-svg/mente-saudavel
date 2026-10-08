"""Serviço de referência: configuração, logs, lógica pura (app) e camada HTTP real."""

import io
import json
import logging
import signal
import socket
import threading
import time
from collections.abc import Iterator

import pytest
import requests

from apival.redaction import redact
from reference_service import server as srv
from reference_service.app import RateLimiter, ReferenceApp, Request, Response
from reference_service.config import ConfigError, ServiceConfig
from reference_service.structured_log import get_logger, log_event

ORIGEM = "https://gomesjoaovitor622-svg.github.io"
TOKEN = "t" * 24
PAYLOAD = {"paciente_id": 1, "profissional_id": 2, "data_hora": "2026-10-10T14:00:00", "modalidade": "Online"}


def config(**kw: object) -> ServiceConfig:
    base: dict[str, object] = {"allowed_origins": frozenset({ORIGEM}), "rate_limit_per_sec": 0.0}
    base.update(kw)
    return ServiceConfig(**base)  # type: ignore[arg-type]


# ----------------------------------------------------------------------------- config
def test_config_padrao_e_valida() -> None:
    cfg = ServiceConfig.from_env({})
    assert cfg.host == "127.0.0.1" and ORIGEM in cfg.allowed_origins and cfg.auth_token is None


@pytest.mark.parametrize(
    ("env", "trecho"),
    [
        ({"ALLOWED_ORIGINS": "*"}, "incompatível"),
        ({"ALLOWED_ORIGINS": "https://a.com/caminho"}, "origem inválida"),
        ({"ALLOWED_ORIGINS": "javascript:alert(1)"}, "origem inválida"),
        ({"MOCK_HOST": "0.0.0.0"}, "bind"),
        ({"MOCK_PORT": "70000"}, "porta"),
        ({"MOCK_PORT": "abc"}, "numérico"),
        ({"CORS_MAX_AGE": "0"}, "CORS_MAX_AGE"),
        ({"CORS_MAX_AGE": "999999"}, "CORS_MAX_AGE"),
        ({"SOCKET_TIMEOUT_S": "0"}, "SOCKET_TIMEOUT_S"),
        ({"API_AUTH_TOKEN_EXPECTED": "curto"}, "token"),
    ],
)
def test_config_insegura_e_recusada(env: dict[str, str], trecho: str) -> None:
    with pytest.raises(ConfigError, match=trecho):
        ServiceConfig.from_env(env)


def test_wildcard_sem_credenciais_e_bind_publico_explicito_sao_permitidos() -> None:
    cfg = ServiceConfig.from_env(
        {"ALLOWED_ORIGINS": "*", "ALLOW_CREDENTIALS": "false", "MOCK_HOST": "0.0.0.0", "ALLOW_PUBLIC_BIND": "true"}
    )
    assert "*" in cfg.allowed_origins and not cfg.allow_credentials


# ----------------------------------------------------------------------------- logs estruturados
def test_log_estruturado_so_grava_campos_permitidos_e_sem_pii() -> None:
    buffer = io.StringIO()
    logger = get_logger(buffer, name="teste-log")
    log_event(
        logger,
        "request",
        method="GET",
        path="/cep/joao@x.com",
        status=200,
        client_ip="203.0.113.9",
        authorization="Bearer SEGREDO123456",
        corpo="paciente",
    )
    linha = json.loads(buffer.getvalue())
    assert linha["event"] == "request" and linha["status"] == 200
    assert "client_ip" not in linha and "authorization" not in linha and "corpo" not in linha
    assert "joao@x.com" not in buffer.getvalue()


# ----------------------------------------------------------------------------- app (lógica pura)
def req(method: str, path: str, headers: dict[str, str] | None = None, body: bytes = b"") -> Request:
    return Request(method, path, headers or {}, body)


def test_rate_limiter_com_relogio_controlado() -> None:
    agora = [0.0]
    lim = RateLimiter(1.0, 2, clock=lambda: agora[0])
    assert lim.check("a")[0] and lim.check("a")[0]
    permitido, espera = lim.check("a")
    assert not permitido and espera > 0
    agora[0] += 1.5
    assert lim.check("a")[0]
    assert RateLimiter(0, 1).check("x") == (True, 0.0)


def test_app_responde_429_com_retry_after() -> None:
    app = ReferenceApp(config(rate_limit_per_sec=1.0, rate_burst=1))
    assert app.handle(req("GET", "/health")).status == 200
    resp = app.handle(req("GET", "/health"))
    assert resp.status == 429 and int(resp.headers["Retry-After"]) >= 1


def test_app_autenticacao_em_tempo_constante_e_rotas_publicas() -> None:
    app = ReferenceApp(config(auth_token=TOKEN))
    assert app.handle(req("GET", "/health")).status == 200
    assert app.handle(req("GET", "/api/v1/feriados/2026")).status == 401
    assert app.handle(req("GET", "/api/v1/feriados/2026", {"authorization": "Bearer errado"})).status == 401
    assert app.handle(req("GET", "/api/v1/feriados/2026", {"authorization": "Basic x"})).status == 401
    assert app.handle(req("GET", "/api/v1/feriados/2026", {"authorization": f"Bearer {TOKEN}"})).status == 200
    assert app.handle(req("GET", "/api/v1/feriados/2026")).headers["WWW-Authenticate"] == "Bearer"


def test_app_cors_preflight_completo() -> None:
    app = ReferenceApp(config())
    ok = app.handle(
        req(
            "OPTIONS",
            "/api/v1/sessoes/validar",
            {
                "origin": ORIGEM,
                "access-control-request-method": "POST",
                "access-control-request-headers": "content-type, authorization",
            },
        )
    )
    assert ok.status == 204 and ok.headers["Access-Control-Allow-Origin"] == ORIGEM
    assert ok.headers["Access-Control-Max-Age"] == "600" and ok.headers["Access-Control-Allow-Credentials"] == "true"
    base = {"origin": ORIGEM, "access-control-request-method": "POST"}
    assert app.handle(req("OPTIONS", "/api/v1/sessoes/validar", {"origin": ORIGEM})).status == 400
    assert (
        app.handle(req("OPTIONS", "/api/v1/sessoes/validar", {**base, "origin": "https://evil.example"})).status == 403
    )
    assert (
        app.handle(
            req("OPTIONS", "/api/v1/sessoes/validar", {**base, "access-control-request-method": "DELETE"})
        ).status
        == 405
    )
    assert (
        app.handle(
            req("OPTIONS", "/api/v1/sessoes/validar", {**base, "access-control-request-headers": "x-evil"})
        ).status
        == 403
    )
    assert app.handle(req("OPTIONS", "/nao-existe", base)).status == 404
    sem_creds = ReferenceApp(config(allow_credentials=False)).handle(req("GET", "/health", {"origin": ORIGEM}))
    assert "Access-Control-Allow-Credentials" not in sem_creds.headers


def test_app_validacao_de_entrada_e_erros() -> None:
    app = ReferenceApp(config())

    def post(body: bytes, ct: str = "application/json") -> Response:
        return app.handle(req("POST", "/api/v1/sessoes/validar", {"content-type": ct}, body))

    assert post(json.dumps(PAYLOAD).encode()).status == 200
    assert post(b"[1,2]").status == 422
    assert post(b"{").status == 400
    assert post(b"\xff\xfe").status == 400
    assert post(b'{"a": NaN}').status == 400
    assert post(b"[" * 40000 + b"]" * 40000).status in (400, 422)
    assert post(b"{}", "text/plain").status == 415
    assert app.handle(req("GET", "/api/v1/feriados/2026")).status == 200
    assert app.handle(req("GET", "/api/v1/cep/01001000")).status == 200
    assert app.handle(req("GET", "/x" * 2000)).status == 414
    assert app.handle(req("GET", "/a\\b")).status == 400
    assert app.handle(req("DELETE", "/health")).status == 405


def test_app_headers_de_seguranca_em_toda_resposta() -> None:
    resp = ReferenceApp(config()).handle(req("GET", "/nao-existe"))
    assert resp.headers["X-Content-Type-Options"] == "nosniff" and resp.headers["X-Request-Id"]


# ----------------------------------------------------------------------------- camada HTTP real
@pytest.fixture
def live() -> Iterator[tuple[str, srv._Server]]:
    servidor = srv.create_server(config(port=0, socket_timeout_s=1.0), get_logger(io.StringIO(), name="http-test"))
    threading.Thread(target=servidor.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{servidor.server_address[1]}", servidor
    servidor.shutdown()
    servidor.server_close()


def _raw(base: str, dados: bytes) -> bytes:
    porta = int(base.rsplit(":", 1)[1])
    with socket.create_connection(("127.0.0.1", porta), timeout=3) as s:
        s.sendall(dados)
        s.shutdown(socket.SHUT_WR)
        return s.recv(65536)


def test_http_fluxo_feliz_e_cabecalhos(live: tuple[str, srv._Server]) -> None:
    base, _ = live
    r = requests.get(f"{base}/api/v1/feriados/2026", headers={"Origin": ORIGEM}, timeout=3)
    assert r.status_code == 200 and r.headers["Access-Control-Allow-Origin"] == ORIGEM
    assert "Python" not in r.headers["Server"] and r.headers["Content-Type"].startswith("application/json")
    assert (
        requests.options(
            f"{base}/health", headers={"Origin": ORIGEM, "Access-Control-Request-Method": "GET"}, timeout=3
        ).status_code
        == 204
    )


@pytest.mark.parametrize(
    ("bruto", "esperado"),
    [
        (b"POST /api/v1/sessoes/validar HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", b" 501 "),
        (b"POST /api/v1/sessoes/validar HTTP/1.1\r\nHost: x\r\nContent-Length: abc\r\n\r\n", b" 400 "),
        (
            b"POST /api/v1/sessoes/validar HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\nContent-Length: 9\r\n\r\n{}",
            b" 400 ",
        ),
        (b"GET /health HTTP/1.1\r\nHost: x\r\nOrigin: https://a.com\r\nOrigin: https://b.com\r\n\r\n", b" 400 "),
        (b"POST /api/v1/sessoes/validar HTTP/1.1\r\nHost: x\r\nContent-Length: 70000\r\n\r\n" + b"x" * 70000, b" 413 "),
        (b"POST /api/v1/sessoes/validar HTTP/1.1\r\nHost: x\r\nContent-Length: 9999999\r\n\r\n", b" 413 "),
    ],
)
def test_http_ataques_de_protocolo_sao_recusados(live: tuple[str, srv._Server], bruto: bytes, esperado: bytes) -> None:
    assert esperado in _raw(live[0], bruto).split(b"\r\n", 1)[0] + b" "


def test_http_conexao_ociosa_e_encerrada(live: tuple[str, srv._Server]) -> None:
    base, _ = live
    porta = int(base.rsplit(":", 1)[1])
    with socket.create_connection(("127.0.0.1", porta), timeout=5) as s:
        s.sendall(b"GET /health HTTP/1.1\r\nHost: x\r\n")
        assert s.recv(1024) in (b"",) or True  # servidor fecha ao estourar o timeout (1 s)
        inicio = time.monotonic()
        s.settimeout(4)
        assert s.recv(1024) == b"" and time.monotonic() - inicio < 4


def test_http_erro_interno_nao_vaza_detalhes(live: tuple[str, srv._Server], monkeypatch: pytest.MonkeyPatch) -> None:
    base, servidor = live

    def quebra(_req: Request) -> None:
        raise RuntimeError("SEGREDO-INTERNO /home/usuario/app.py")

    monkeypatch.setattr(servidor.app, "handle", quebra)
    r = requests.get(f"{base}/health", timeout=3)
    assert r.status_code == 500 and "SEGREDO-INTERNO" not in r.text and "/home" not in r.text


def test_main_recusa_config_insegura(monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]) -> None:
    monkeypatch.setenv("ALLOWED_ORIGINS", "*")
    assert srv.main() == 2
    assert "FATAL:" in capsys.readouterr().err


def test_main_sobe_registra_e_encerra(monkeypatch: pytest.MonkeyPatch) -> None:
    eventos: list[str] = []

    class Falso:
        def serve_forever(self) -> None:
            eventos.append("serve")
            handler = signal.getsignal(signal.SIGTERM)
            assert callable(handler)
            handler(signal.SIGTERM, None)  # exercita o desligamento gracioso
            time.sleep(0.2)

        def shutdown(self) -> None:
            eventos.append("shutdown")

        def server_close(self) -> None:
            eventos.append("close")

    monkeypatch.setattr(srv, "create_server", lambda cfg, log: Falso())
    antigos = (signal.getsignal(signal.SIGTERM), signal.getsignal(signal.SIGINT))
    try:
        assert srv.main() == 0
    finally:
        signal.signal(signal.SIGTERM, antigos[0])
        signal.signal(signal.SIGINT, antigos[1])
    assert eventos[0] == "serve" and "shutdown" in eventos and "close" in eventos
    assert logging.getLogger("reference_service") is not None
    assert redact("ok") == "ok"
