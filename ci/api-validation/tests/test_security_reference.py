"""Controles de segurança do serviço (OWASP): headers, limites, smuggling, injeção, autenticação.

Falhas levantam SecurityViolation -> categoria "Violações de Segurança" (bloqueante).
Os ataques de protocolo usam socket cru, porque clientes HTTP normais corrigem/recusam
requisições malformadas antes de enviá-las.
"""

from __future__ import annotations

import os
import socket
from urllib.parse import urlsplit

import pytest
import requests

from apival.checks import expect_status, security_check

pytestmark = [pytest.mark.reference, pytest.mark.security]

SEGREDOS_NO_CORPO = ("Traceback", 'File "', "/home/", "/usr/lib", "site-packages", "BaseHTTP", "Python/")
BODY_JSON = '{"paciente_id":1,"profissional_id":2,"data_hora":"2026-10-10T14:00:00","modalidade":"Online"}'


def raw_http(base_url: str, request: bytes, timeout: float = 5.0) -> tuple[int, str]:
    """Envia bytes crus e devolve (status, resposta completa como texto)."""
    partes = urlsplit(base_url)
    with socket.create_connection((partes.hostname or "127.0.0.1", partes.port or 80), timeout=timeout) as sock:
        sock.sendall(request)
        sock.shutdown(socket.SHUT_WR)
        pedacos: list[bytes] = []
        while True:
            try:
                bloco = sock.recv(65536)
            except TimeoutError:
                break
            if not bloco:
                break
            pedacos.append(bloco)
    texto = b"".join(pedacos).decode("utf-8", "replace")
    status = int(texto.split(" ", 2)[1]) if texto.startswith("HTTP/") else 0
    return status, texto


def _auth_header() -> str:
    token = os.getenv("API_AUTH_TOKEN")
    return f"Authorization: Bearer {token}\r\n" if token else ""


# ----------------------------------------------------------------------------- headers e banner
@pytest.mark.parametrize("caminho", ["/health", "/api/v1/feriados/2026", "/api/v1/nao-existe"])
def test_headers_de_seguranca_em_toda_resposta(api: requests.Session, caminho: str) -> None:
    h = api.get(caminho).headers
    security_check(h.get("X-Content-Type-Options") == "nosniff", f"{caminho}: falta X-Content-Type-Options: nosniff")
    security_check("no-store" in h.get("Cache-Control", ""), f"{caminho}: falta Cache-Control: no-store")
    security_check("default-src 'none'" in h.get("Content-Security-Policy", ""), f"{caminho}: falta CSP restritiva")
    security_check(h.get("X-Frame-Options") == "DENY", f"{caminho}: falta X-Frame-Options: DENY")
    security_check(h.get("Referrer-Policy") == "no-referrer", f"{caminho}: falta Referrer-Policy")
    security_check(bool(h.get("X-Request-Id")), f"{caminho}: falta X-Request-Id (rastreabilidade)")


def test_banner_do_servidor_nao_revela_tecnologia(api: requests.Session) -> None:
    banner = api.get("/health").headers.get("Server", "")
    security_check(not any(t in banner for t in ("Python", "BaseHTTP", "/3.")), f"Server revela tecnologia: '{banner}'")


# ----------------------------------------------------------------------------- request smuggling
def test_transfer_encoding_e_rejeitado(base_url: str) -> None:
    req = (
        f"POST /api/v1/sessoes/validar HTTP/1.1\r\nHost: x\r\n{_auth_header()}Content-Type: application/json\r\n"
        "Transfer-Encoding: chunked\r\n\r\n0\r\n\r\n"
    ).encode()
    status, _ = raw_http(base_url, req)
    security_check(status == 501, f"Transfer-Encoding deveria ser rejeitado (501), veio {status}")


@pytest.mark.parametrize("valor", ["abc", "-5", "1e3", " 12 34", "99999999999"])
def test_content_length_invalido_e_rejeitado(base_url: str, valor: str) -> None:
    req = (
        f"POST /api/v1/sessoes/validar HTTP/1.1\r\nHost: x\r\n{_auth_header()}Content-Type: application/json\r\n"
        f"Content-Length: {valor}\r\n\r\n{{}}"
    ).encode()
    status, _ = raw_http(base_url, req)
    security_check(status in (400, 413), f"Content-Length '{valor}' deveria ser rejeitado, veio {status}")


def test_content_length_duplicado_e_rejeitado(base_url: str) -> None:
    req = (
        f"POST /api/v1/sessoes/validar HTTP/1.1\r\nHost: x\r\n{_auth_header()}Content-Type: application/json\r\n"
        "Content-Length: 2\r\nContent-Length: 40\r\n\r\n{}"
    ).encode()
    status, _ = raw_http(base_url, req)
    security_check(status == 400, f"Content-Length duplicado deveria dar 400, veio {status}")


def test_origin_duplicado_e_rejeitado(base_url: str, allowed_origin: str) -> None:
    req = (
        f"GET /health HTTP/1.1\r\nHost: x\r\nOrigin: {allowed_origin}\r\nOrigin: https://evil.example\r\n\r\n".encode()
    )
    status, _ = raw_http(base_url, req)
    security_check(status == 400, f"Origin duplicado deveria dar 400, veio {status}")


# ----------------------------------------------------------------------------- entradas maliciosas
def test_json_profundamente_aninhado_nao_derruba_o_servico(api: requests.Session) -> None:
    """Pior caso permitido pelo limite de corpo (64 KiB): 32 mil níveis. Deve ser 4xx, nunca 5xx/queda."""
    niveis = 32_000
    resp = api.post(
        "/api/v1/sessoes/validar", data="[" * niveis + "]" * niveis, headers={"Content-Type": "application/json"}
    )
    security_check(resp.status_code in (400, 422), f"JSON aninhado deveria dar 400/422, veio {resp.status_code}")
    security_check(api.get("/health").status_code == 200, "o serviço parou de responder após JSON aninhado")


@pytest.mark.parametrize("constante", ["NaN", "Infinity", "-Infinity"])
def test_constantes_json_nao_padrao_sao_rejeitadas(api: requests.Session, constante: str) -> None:
    corpo = BODY_JSON.replace('"paciente_id":1', f'"paciente_id":{constante}')
    resp = api.post("/api/v1/sessoes/validar", data=corpo, headers={"Content-Type": "application/json"})
    expect_status(resp, 400, f"JSON com {constante}")


def test_caractere_invalido_no_caminho_e_rejeitado(base_url: str) -> None:
    status, _ = raw_http(base_url, b"GET /api\\v1/cep/01001000 HTTP/1.1\r\nHost: x\r\n\r\n")
    security_check(status == 400, f"caminho com barra invertida deveria dar 400, veio {status}")


def test_caminho_com_travessia_nao_expoe_arquivos(base_url: str) -> None:
    status, texto = raw_http(base_url, b"GET /api/v1/../../../../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n")
    security_check(status in (400, 404), f"travessia de diretório deveria dar 400/404, veio {status}")
    security_check("root:" not in texto, "conteúdo de /etc/passwd vazou na resposta")


@pytest.mark.parametrize("entrada", ["<script>alert(1)</script>", "1'%20OR%20'1'='1", "../../etc/passwd", "%00"])
def test_parametros_maliciosos_nao_sao_refletidos(api: requests.Session, entrada: str) -> None:
    resp = api.get(f"/api/v1/cep/{entrada}")
    security_check(resp.status_code in (400, 404), f"entrada maliciosa deveria dar 400/404, veio {resp.status_code}")
    security_check(
        "script" not in resp.text.lower() and "OR" not in resp.text, "a entrada foi refletida na resposta (XSS/injeção)"
    )


def test_erros_nao_vazam_detalhes_internos(api: requests.Session, base_url: str) -> None:
    respostas = [
        api.post("/api/v1/sessoes/validar", data="{", headers={"Content-Type": "application/json"}).text,
        api.get("/api/v1/feriados/abc").text,
        raw_http(base_url, b"GARBAGE\r\n\r\n")[1],
    ]
    for texto in respostas:
        vazados = [t for t in SEGREDOS_NO_CORPO if t in texto]
        security_check(not vazados, f"a resposta de erro vazou detalhes internos: {vazados}")


def test_conexao_ociosa_e_encerrada_pelo_servidor(base_url: str) -> None:
    """Defesa contra slowloris: requisição incompleta não pode prender a conexão para sempre."""
    limite = float(os.getenv("SOCKET_TIMEOUT_S", "10"))
    if limite > 5:
        pytest.skip("defina SOCKET_TIMEOUT_S <= 5 no serviço para exercitar este teste")
    partes = urlsplit(base_url)
    with socket.create_connection((partes.hostname or "127.0.0.1", partes.port or 80), timeout=limite + 4) as sock:
        sock.sendall(b"GET /health HTTP/1.1\r\nHost: x\r\n")  # sem a linha em branco final
        try:
            recebido = sock.recv(1024)
        except TimeoutError:
            pytest.fail("[SECURITY] o servidor manteve a conexão incompleta aberta além do timeout")
    security_check(
        recebido == b"" or recebido.startswith(b"HTTP/1.1 408") or recebido.startswith(b"HTTP/1.1 400"),
        "resposta inesperada para requisição incompleta",
    )


# ----------------------------------------------------------------------------- autenticação
def test_health_e_publico_mesmo_com_autenticacao(anonymous: requests.Session) -> None:
    expect_status(anonymous.get("/health"), 200, "GET /health sem credenciais")


def test_preflight_nao_exige_credenciais(anonymous: requests.Session, allowed_origin: str) -> None:
    """Navegadores nunca enviam credenciais no preflight: exigir token quebraria todo cliente web."""
    resp = anonymous.options(
        "/api/v1/sessoes/validar",
        headers={
            "Origin": allowed_origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    expect_status(resp, (200, 204), "OPTIONS sem credenciais")


def test_401_informa_esquema_e_mantem_cors(
    anonymous: requests.Session, auth_enabled: bool, allowed_origin: str
) -> None:
    if not auth_enabled:
        pytest.skip("o serviço foi iniciado sem autenticação")
    resp = anonymous.get("/api/v1/feriados/2026", headers={"Origin": allowed_origin})
    expect_status(resp, 401, "GET sem credenciais")
    security_check(resp.headers.get("WWW-Authenticate") == "Bearer", "401 deve informar WWW-Authenticate: Bearer")
    security_check(
        resp.headers.get("Access-Control-Allow-Origin") == allowed_origin,
        "401 sem CORS: o front-end não conseguiria ler o erro",
    )


def test_token_invalido_nao_e_refletido(anonymous: requests.Session, auth_enabled: bool) -> None:
    if not auth_enabled:
        pytest.skip("o serviço foi iniciado sem autenticação")
    chute = "Bearer SEGREDO-DE-TESTE-12345"
    resp = anonymous.get("/api/v1/feriados/2026", headers={"Authorization": chute})
    expect_status(resp, 401, "GET com token inválido")
    visivel = resp.text + str(dict(resp.headers))
    security_check("SEGREDO-DE-TESTE-12345" not in visivel, "o token enviado foi refletido na resposta")
