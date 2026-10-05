"""Conformidade CORS do serviço de referência.

Camadas validadas:
  1. requisições simples cross-origin (origem autorizada x não autorizada)
  2. preflight (OPTIONS): Allow-Origin / Allow-Methods / Allow-Headers / Max-Age
  3. credenciais: Allow-Credentials e a regra "nunca '*' com credenciais"
  4. ataques clássicos de validação de origem (sufixo, esquema, null, barra final)

Falhas levantam CorsPolicyViolation -> categoria "Violações de Política CORS".
"""
import pytest

from support import cors_check, expect_status, header_tokens

pytestmark = [pytest.mark.mock, pytest.mark.cors]

ENDPOINTS_GET = ["/health", "/api/v1/feriados/2026", "/api/v1/cep/01001000"]
PREFLIGHT_PATH = "/api/v1/sessoes/validar"


def preflight(api, origin, method="POST", headers="content-type", path=PREFLIGHT_PATH):
    h = {"Origin": origin, "Access-Control-Request-Method": method}
    if headers:
        h["Access-Control-Request-Headers"] = headers
    return api.options(path, headers=h)


# ----------------------------------------------------------------------------- 1) simple requests
@pytest.mark.parametrize("caminho", ENDPOINTS_GET)
def test_origem_autorizada_recebe_allow_origin_exato(api, allowed_origin, caminho):
    r = api.get(caminho, headers={"Origin": allowed_origin})
    cors_check(r.headers.get("Access-Control-Allow-Origin") == allowed_origin,
               f"{caminho}: Access-Control-Allow-Origin deveria ser '{allowed_origin}', "
               f"veio '{r.headers.get('Access-Control-Allow-Origin')}'")


@pytest.mark.parametrize("caminho", ENDPOINTS_GET)
def test_resposta_varia_por_origem(api, allowed_origin, caminho):
    r = api.get(caminho, headers={"Origin": allowed_origin})
    cors_check("origin" in header_tokens(r, "Vary"),
               f"{caminho}: falta 'Vary: Origin' (caches poderiam servir a origem errada)")


def test_origem_nao_autorizada_nao_recebe_allow_origin(api, denied_origin):
    r = api.get("/api/v1/feriados/2026", headers={"Origin": denied_origin})
    valor = r.headers.get("Access-Control-Allow-Origin")
    cors_check(valor is None, f"origem não autorizada '{denied_origin}' recebeu Allow-Origin='{valor}'")
    cors_check("Access-Control-Allow-Credentials" not in r.headers,
               "origem não autorizada recebeu Access-Control-Allow-Credentials")


def test_sem_header_origin_nao_emite_cors(api):
    r = api.get("/api/v1/feriados/2026")
    expect_status(r, 200, "GET sem Origin")
    cors_check("Access-Control-Allow-Origin" not in r.headers, "resposta sem Origin não deveria ter Allow-Origin")


def test_erros_tambem_carregam_cors_para_origem_autorizada(api, allowed_origin):
    """Sem isso o navegador esconde o corpo do erro do JavaScript do front-end."""
    r = api.get("/api/v1/feriados/abc", headers={"Origin": allowed_origin})
    expect_status(r, 400, "GET feriados/abc")
    cors_check(r.headers.get("Access-Control-Allow-Origin") == allowed_origin,
               "resposta de erro (400) sem Access-Control-Allow-Origin para origem autorizada")


def test_expose_headers_para_rastreabilidade(api, allowed_origin):
    r = api.get("/health", headers={"Origin": allowed_origin})
    cors_check("x-request-id" in header_tokens(r, "Access-Control-Expose-Headers"),
               "Access-Control-Expose-Headers deveria incluir X-Request-Id")


# ----------------------------------------------------------------------------- 2) preflight
def test_preflight_autorizado_headers_completos(api, allowed_origin):
    r = preflight(api, allowed_origin, method="POST", headers="content-type,authorization")
    expect_status(r, (200, 204), "OPTIONS preflight autorizado")
    cors_check(r.headers.get("Access-Control-Allow-Origin") == allowed_origin,
               f"preflight: Allow-Origin deveria ser '{allowed_origin}', veio '{r.headers.get('Access-Control-Allow-Origin')}'")
    cors_check("post" in header_tokens(r, "Access-Control-Allow-Methods"),
               f"preflight: Allow-Methods sem POST ('{r.headers.get('Access-Control-Allow-Methods')}')")
    permitidos = header_tokens(r, "Access-Control-Allow-Headers")
    cors_check({"content-type", "authorization"} <= permitidos,
               f"preflight: Allow-Headers deveria conter content-type e authorization, veio {sorted(permitidos)}")


def test_preflight_max_age_valido(api, allowed_origin):
    r = preflight(api, allowed_origin)
    bruto = r.headers.get("Access-Control-Max-Age")
    cors_check(bruto is not None, "preflight sem Access-Control-Max-Age (cada chamada geraria novo preflight)")
    cors_check(bruto.isdigit(), f"Access-Control-Max-Age deve ser inteiro, veio '{bruto}'")
    cors_check(0 < int(bruto) <= 86400, f"Access-Control-Max-Age fora do intervalo razoável (1..86400): {bruto}")


def test_preflight_varia_por_origem_metodo_e_headers(api, allowed_origin):
    r = preflight(api, allowed_origin)
    vary = header_tokens(r, "Vary")
    cors_check({"origin", "access-control-request-method", "access-control-request-headers"} <= vary,
               f"preflight: Vary incompleto ({sorted(vary)})")


def test_preflight_nao_autorizado_e_recusado(api, denied_origin):
    r = preflight(api, denied_origin)
    cors_check(r.status_code == 403, f"preflight de origem não autorizada deveria dar 403, deu {r.status_code}")
    cors_check("Access-Control-Allow-Origin" not in r.headers, "preflight recusado vazou Allow-Origin")
    cors_check("Access-Control-Allow-Methods" not in r.headers, "preflight recusado vazou Allow-Methods")


@pytest.mark.parametrize("metodo", ["DELETE", "PUT", "PATCH"])
def test_preflight_metodo_nao_permitido_e_recusado(api, allowed_origin, metodo):
    r = preflight(api, allowed_origin, method=metodo)
    cors_check(r.status_code in (403, 405), f"preflight de {metodo} deveria ser recusado (403/405), deu {r.status_code}")
    cors_check(metodo.lower() not in header_tokens(r, "Access-Control-Allow-Methods"),
               f"Allow-Methods anuncia {metodo}, que não é permitido")


def test_preflight_header_nao_permitido_e_recusado(api, allowed_origin):
    r = preflight(api, allowed_origin, headers="content-type,x-evil")
    cors_check(r.status_code == 403, f"preflight com header proibido deveria dar 403, deu {r.status_code}")
    cors_check("Access-Control-Allow-Headers" not in r.headers, "preflight recusado vazou Allow-Headers")


def test_options_sem_request_method_nao_e_preflight(api, allowed_origin):
    r = api.options(PREFLIGHT_PATH, headers={"Origin": allowed_origin})
    cors_check(r.status_code == 400, f"OPTIONS sem Access-Control-Request-Method deveria dar 400, deu {r.status_code}")


# ----------------------------------------------------------------------------- 3) credenciais
def test_credenciais_permitidas_para_origem_autorizada(api, allowed_origin):
    for r in (api.get("/health", headers={"Origin": allowed_origin}), preflight(api, allowed_origin)):
        cors_check(r.headers.get("Access-Control-Allow-Credentials") == "true",
                   f"Access-Control-Allow-Credentials deveria ser 'true' (veio '{r.headers.get('Access-Control-Allow-Credentials')}')")


@pytest.mark.parametrize("caminho", ENDPOINTS_GET)
def test_nunca_wildcard_com_credenciais(api, allowed_origin, caminho):
    """Regra da especificação: com credenciais, Allow-Origin não pode ser '*'."""
    r = api.get(caminho, headers={"Origin": allowed_origin})
    if r.headers.get("Access-Control-Allow-Credentials") == "true":
        cors_check(r.headers.get("Access-Control-Allow-Origin") != "*",
                   f"{caminho}: Allow-Origin='*' combinado com Allow-Credentials=true")


# ----------------------------------------------------------------------------- 4) ataques de validação de origem
@pytest.mark.parametrize("descricao,origem", [
    ("sufixo (evil.example colado ao domínio autorizado)", "https://gomesjoaovitor622-svg.github.io.evil.example"),
    ("prefixo (domínio autorizado como subdomínio de outro)", "https://evil.gomesjoaovitor622-svg.github.io"),
    ("esquema diferente (http em vez de https)", "http://gomesjoaovitor622-svg.github.io"),
    ("porta diferente", "https://gomesjoaovitor622-svg.github.io:8443"),
    ("origem 'null' (iframe sandbox / arquivo local)", "null"),
    ("barra final (não é uma origem válida)", "https://gomesjoaovitor622-svg.github.io/"),
    ("maiúsculas no host", "https://GOMESJOAOVITOR622-SVG.github.io"),
])
def test_origens_falsas_sao_recusadas(api, allowed_origin, descricao, origem):
    if allowed_origin != "https://gomesjoaovitor622-svg.github.io":
        pytest.skip("casos construídos a partir da origem padrão do projeto")
    r = api.get("/api/v1/feriados/2026", headers={"Origin": origem})
    valor = r.headers.get("Access-Control-Allow-Origin")
    cors_check(valor is None, f"origem forjada [{descricao}] '{origem}' foi aceita (Allow-Origin='{valor}')")
    p = preflight(api, origem)
    cors_check(p.status_code == 403 and "Access-Control-Allow-Origin" not in p.headers,
               f"preflight de origem forjada [{descricao}] não foi recusado (HTTP {p.status_code})")
