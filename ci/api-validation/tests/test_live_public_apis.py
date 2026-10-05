"""Validação das APIs públicas REAIS consumidas pelo app (BrasilAPI, ViaCEP, Jitsi).

Por que existe: o app web roda no navegador, então depende das APIs permitirem CORS
para a origem do GitHub Pages. Estes testes detectam, no CI, mudanças de contrato ou
de política CORS feitas por terceiros ("contract drift"), inclusive no agendamento diário.

O app só faz GET simples (sem headers customizados) => não dispara preflight no navegador.
O teste de preflight é informativo: pula (skip) se a API não suporta OPTIONS.
"""
import pytest

import schemas
from support import (cors_check, expect_json, expect_status, validate_schema)

pytestmark = [pytest.mark.live]

BRASILAPI_FERIADOS = "https://brasilapi.com.br/api/feriados/v1/2026"
BRASILAPI_CEP = "https://brasilapi.com.br/api/cep/v2/{cep}"
VIACEP = "https://viacep.com.br/ws/{cep}/json/"
CEP_VALIDO = "01001000"
CEP_INEXISTENTE = "99999999"


def _allow_origin_ok(resp, origin, api):
    valor = resp.headers.get("Access-Control-Allow-Origin")
    cors_check(valor in ("*", origin),
               f"{api}: o navegador em '{origin}' seria bloqueado "
               f"(Access-Control-Allow-Origin='{valor}'). O app web não conseguiria chamar esta API.")


# ----------------------------------------------------------------------------- BrasilAPI: feriados
@pytest.mark.contract
def test_brasilapi_feriados_contrato(public):
    r = public.get(BRASILAPI_FERIADOS)
    expect_status(r, 200, "BrasilAPI feriados 2026")
    corpo = expect_json(r, "BrasilAPI feriados")
    validate_schema(corpo, schemas.BRASILAPI_FERIADOS, "BrasilAPI feriados")
    datas = {i["date"] for i in corpo}
    assert "2026-12-25" in datas, "Natal ausente: contrato de dados mudou"


@pytest.mark.cors
def test_brasilapi_feriados_cors(public, allowed_origin):
    r = public.get(BRASILAPI_FERIADOS, headers={"Origin": allowed_origin})
    expect_status(r, 200, "BrasilAPI feriados (com Origin)")
    _allow_origin_ok(r, allowed_origin, "BrasilAPI feriados")


@pytest.mark.cors
def test_brasilapi_feriados_preflight_informativo(public, allowed_origin):
    r = public.options(BRASILAPI_FERIADOS, headers={
        "Origin": allowed_origin, "Access-Control-Request-Method": "GET",
        "Access-Control-Request-Headers": "content-type"})
    if r.status_code not in (200, 204):
        pytest.skip(f"OPTIONS retornou {r.status_code}; o app usa GET simples (sem preflight)")
    _allow_origin_ok(r, allowed_origin, "BrasilAPI feriados (preflight)")


# ----------------------------------------------------------------------------- ViaCEP
@pytest.mark.contract
def test_viacep_cep_valido_contrato(public):
    r = public.get(VIACEP.format(cep=CEP_VALIDO))
    expect_status(r, 200, "ViaCEP CEP válido")
    validate_schema(expect_json(r, "ViaCEP"), schemas.VIACEP_OK, "ViaCEP CEP válido")


@pytest.mark.contract
def test_viacep_cep_inexistente_retorna_erro_no_corpo(public):
    """O app trata `dados['erro'] != null` como 'CEP não encontrado'."""
    r = public.get(VIACEP.format(cep=CEP_INEXISTENTE))
    expect_status(r, 200, "ViaCEP CEP inexistente")
    corpo = expect_json(r, "ViaCEP")
    assert isinstance(corpo, dict) and corpo.get("erro") is not None, f"esperado campo 'erro', veio {corpo}"


@pytest.mark.contract
def test_viacep_formato_invalido(public):
    r = public.get(VIACEP.format(cep="123"))
    expect_status(r, 400, "ViaCEP formato inválido")


@pytest.mark.cors
def test_viacep_cors(public, allowed_origin):
    r = public.get(VIACEP.format(cep=CEP_VALIDO), headers={"Origin": allowed_origin})
    expect_status(r, 200, "ViaCEP (com Origin)")
    _allow_origin_ok(r, allowed_origin, "ViaCEP")


# ----------------------------------------------------------------------------- BrasilAPI: CEP v2 (plano B do app)
@pytest.mark.contract
def test_brasilapi_cep_v2_contrato(public):
    r = public.get(BRASILAPI_CEP.format(cep=CEP_VALIDO))
    expect_status(r, 200, "BrasilAPI CEP v2")
    validate_schema(expect_json(r, "BrasilAPI CEP"), schemas.BRASILAPI_CEP_V2, "BrasilAPI CEP v2")


@pytest.mark.cors
def test_brasilapi_cep_v2_cors(public, allowed_origin):
    r = public.get(BRASILAPI_CEP.format(cep=CEP_VALIDO), headers={"Origin": allowed_origin})
    expect_status(r, 200, "BrasilAPI CEP v2 (com Origin)")
    _allow_origin_ok(r, allowed_origin, "BrasilAPI CEP v2")


# ----------------------------------------------------------------------------- Jitsi Meet (videochamada)
@pytest.mark.contract
def test_jitsi_disponivel(public):
    """O app abre https://meet.jit.si/<sala> no navegador (navegação, sem CORS)."""
    r = public.get("https://meet.jit.si/MenteSaudavel-teste-ci", allow_redirects=True)
    expect_status(r, 200, "Jitsi Meet (sala)")


# ----------------------------------------------------------------------------- o app de verdade (User-Agent)
# O app no celular usa o cliente HTTP do Dart ("Dart/x (dart:io)"); na web usa o navegador.
# Alguns WAFs bloqueiam User-Agents desconhecidos, então validamos com os agentes reais do app.
USER_AGENTS = {
    "app-celular-dart": "Dart/3.13 (dart:io)",
    "app-web-chrome": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36",
}
CHAMADAS_DO_APP = {
    "brasilapi-feriados": BRASILAPI_FERIADOS,
    "viacep": VIACEP.format(cep=CEP_VALIDO),
    "brasilapi-cep-v2": BRASILAPI_CEP.format(cep=CEP_VALIDO),
}


@pytest.mark.contract
@pytest.mark.parametrize("agente", sorted(USER_AGENTS))
@pytest.mark.parametrize("chamada", sorted(CHAMADAS_DO_APP))
def test_apis_respondem_ao_user_agent_do_app(chamada, agente):
    import requests
    r = requests.get(CHAMADAS_DO_APP[chamada], headers={"User-Agent": USER_AGENTS[agente]}, timeout=(5, 15))
    expect_status(r, 200, f"{chamada} com User-Agent {agente}")


@pytest.mark.contract
@pytest.mark.xfail(strict=False, reason=(
    "COMPORTAMENTO CONHECIDO: a BrasilAPI v2 responde 200 com um endereço (fonte open-cep) mesmo para CEP "
    "inexistente (ex.: 99999999). Por isso o app só usa a BrasilAPI como plano B quando o ViaCEP FALHA, e "
    "NUNCA depois de o ViaCEP dizer 'CEP não encontrado'. Se a API for corrigida, este teste passa (XPASS)."))
def test_brasilapi_cep_v2_inexistente_nao_devolve_endereco_falso(public):
    """Documenta (sem reprovar o pipeline) que a BrasilAPI v2 não é confiável para detectar CEP inexistente."""
    r = public.get(BRASILAPI_CEP.format(cep=CEP_INEXISTENTE))
    if r.status_code == 404:
        return
    corpo = r.json() if r.headers.get("Content-Type", "").startswith("application/json") else {}
    rua = (corpo.get("street") or "").strip() if isinstance(corpo, dict) else ""
    assert not rua, f"API devolveu 200 com endereço para CEP inexistente: {str(corpo)[:200]}"
