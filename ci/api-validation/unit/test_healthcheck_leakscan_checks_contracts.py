"""Health-check, varredura de vazamento, asserções e contratos."""

import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

from apival import contracts, healthcheck, leakscan
from apival.checks import (
    ContractViolation,
    CorsPolicyViolation,
    SecurityViolation,
    cors_check,
    expect_json,
    expect_json_content_type,
    expect_status,
    header_tokens,
    security_check,
    validate_schema,
)


class FakeResponse:
    def __init__(self, status: int = 200, text: str = "{}", headers: dict[str, str] | None = None) -> None:
        self.status_code, self.text, self.headers = status, text, headers or {}

    def json(self) -> object:
        import json

        return json.loads(self.text)


# ----------------------------------------------------------------------------- health-check
class _Handler(BaseHTTPRequestHandler):
    status = 200

    def do_GET(self) -> None:
        self.send_response(self.status)
        self.end_headers()
        self.wfile.write(b'{"status": "ok"}')

    def log_message(self, format: str, *args: object) -> None:
        return


def _server(status: int = 200) -> tuple[HTTPServer, str]:
    handler = type("H", (_Handler,), {"status": status})
    srv = HTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, f"http://127.0.0.1:{srv.server_port}/"


def _stop(srv: HTTPServer) -> None:
    srv.shutdown()
    srv.server_close()


def test_healthcheck_sucesso_e_corpo_esperado(capsys: pytest.CaptureFixture[str]) -> None:
    srv, url = _server()
    try:
        assert healthcheck.main([url, "--timeout", "5", "--contains", '"status": "ok"']) == 0
        assert "HEALTHCHECK_OK" in capsys.readouterr().out
    finally:
        _stop(srv)


def test_healthcheck_status_inesperado_e_trecho_ausente() -> None:
    srv, url = _server(503)
    try:
        assert healthcheck.probe(url, 200, None, "ua") == "HTTP 503"
        assert healthcheck.probe(url, 503, "nao-existe", "ua") is not None
    finally:
        _stop(srv)


def test_healthcheck_timeout_retorna_124(capsys: pytest.CaptureFixture[str]) -> None:
    assert (
        healthcheck.main(["http://127.0.0.1:9/health", "--timeout", "1", "--interval", "0.2"])
        == healthcheck.EXIT_TIMEOUT
    )
    assert "HEALTHCHECK_TIMEOUT" in capsys.readouterr().out


def test_healthcheck_recusa_esquema_nao_http(capsys: pytest.CaptureFixture[str]) -> None:
    assert healthcheck.main(["file:///etc/passwd"]) == healthcheck.EXIT_BAD_USAGE
    with pytest.raises(ValueError, match="http/https"):
        healthcheck.probe("ftp://x/y", 200, None, "ua")


def test_healthcheck_detecta_processo_morto_e_zumbi(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    pid = tmp_path / "x.pid"
    pid.write_text("999999")
    assert healthcheck.wait("http://127.0.0.1:9/", timeout=3, pid_file=str(pid)) == healthcheck.EXIT_SERVER_EXITED
    filho = subprocess.Popen([sys.executable, "-c", "pass"])
    pid.write_text(str(filho.pid))
    time.sleep(0.5)  # termina e vira zumbi até o wait()
    assert not healthcheck.process_alive(str(pid))
    filho.wait()
    assert "SERVER_EXITED" in capsys.readouterr().out


def test_process_alive_casos_de_borda(tmp_path: Path) -> None:
    assert healthcheck.process_alive(None)
    assert healthcheck.process_alive(str(tmp_path / "nao-existe.pid"))
    ruim = tmp_path / "ruim.pid"
    ruim.write_text("não-é-número")
    assert not healthcheck.process_alive(str(ruim))
    vivo = tmp_path / "vivo.pid"
    vivo.write_text(str(__import__("os").getpid()))
    assert healthcheck.process_alive(str(vivo))


# ----------------------------------------------------------------------------- leakscan
def test_leakscan_encontra_segredo_e_formas_codificadas(tmp_path: Path) -> None:
    (tmp_path / "a.log").write_text("tudo certo")
    (tmp_path / "b.log").write_text("Authorization: Bearer segredo-super-12345")
    assert leakscan.scan("segredo-super-12345", [tmp_path]) == [str(tmp_path / "b.log")]
    (tmp_path / "c.log").write_text("q=segredo%20com%20espaco")
    assert leakscan.scan("segredo com espaco", [tmp_path / "c.log"])


def test_leakscan_cli_codigos_de_saida(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    (tmp_path / "r.log").write_text("vazou: token-de-teste-123456")
    monkeypatch.setenv("TOK", "token-de-teste-123456")
    assert leakscan.main(["--env-var", "TOK", "--path", str(tmp_path)]) == 1
    assert "token-de-teste-123456" not in capsys.readouterr().out  # nunca imprime o segredo
    monkeypatch.setenv("TOK", "outro-valor-qualquer")
    assert leakscan.main(["--env-var", "TOK", "--path", str(tmp_path)]) == 0
    monkeypatch.setenv("TOK", "curto")
    assert leakscan.main(["--env-var", "TOK", "--path", str(tmp_path)]) == 2


# ----------------------------------------------------------------------------- asserções
def test_expect_status_inclui_corpo_sem_pii() -> None:
    with pytest.raises(ContractViolation, match=r"esperado HTTP 200.*recebido 500") as exc:
        expect_status(FakeResponse(500, "erro joao@x.com"), 200, "GET /x")
    assert "joao@x.com" not in str(exc.value)
    expect_status(FakeResponse(204), (200, 204), "ok")


def test_expect_json_e_content_type() -> None:
    assert expect_json(FakeResponse(text='{"a": 1}')) == {"a": 1}
    with pytest.raises(ContractViolation):
        expect_json(FakeResponse(text="não é json"))
    with pytest.raises(ContractViolation):
        expect_json_content_type(FakeResponse(headers={"Content-Type": "text/html"}), "x")
    expect_json_content_type(FakeResponse(headers={"Content-Type": "application/json; charset=utf-8"}), "x")


def test_validate_schema_e_cors_security_check() -> None:
    validate_schema({"a": 1}, {"type": "object", "required": ["a"]}, "ok")
    with pytest.raises(ContractViolation, match="schema inválido"):
        validate_schema({}, {"type": "object", "required": ["a"]}, "x")
    with pytest.raises(CorsPolicyViolation, match=r"\[CORS\]"):
        cors_check(False, "falhou")
    with pytest.raises(SecurityViolation, match=r"\[SECURITY\]"):
        security_check(False, "falhou")
    cors_check(True, "x")
    security_check(True, "x")
    assert header_tokens(FakeResponse(headers={"Vary": "Origin, Accept"}), "Vary") == {"origin", "accept"}


# ----------------------------------------------------------------------------- contratos
def test_spec_carrega_e_tem_casos() -> None:
    assert contracts.load_spec()["openapi"].startswith("3.1")
    assert len(contracts.conformance_cases()) >= 20
    assert contracts.documented_statuses("GET", "/health") == {200}
    assert contracts.response_schema_name("GET", "/health", 200) == "Health"
    assert contracts.response_schema_name("GET", "/health", 500) is None
    assert contracts.conformance_cases()[0].id.startswith("GET /health")


def test_validate_named_aceita_e_recusa() -> None:
    contracts.validate_named({"status": "ok", "version": "1", "uptime_s": 1.5}, "Health", "h")
    with pytest.raises(ContractViolation):
        contracts.validate_named({"status": "down"}, "Health", "h")


def test_spec_invalida_e_recusada(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    ruim = tmp_path / "openapi.yaml"
    ruim.write_text("foo: bar")
    monkeypatch.setattr(contracts, "SPEC_PATH", ruim)
    contracts.load_spec.cache_clear()
    try:
        with pytest.raises(ContractViolation):
            contracts.load_spec()
    finally:
        contracts.load_spec.cache_clear()


def test_schemas_de_terceiros_sao_json_schema_validos() -> None:
    from jsonschema import Draft202012Validator

    from apival import third_party

    for schema in (third_party.BRASILAPI_FERIADOS, third_party.VIACEP_OK, third_party.BRASILAPI_CEP_V2):
        Draft202012Validator.check_schema(schema)
