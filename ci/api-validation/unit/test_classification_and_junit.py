"""Classificação de falhas e leitura de JUnit (inclui XML malicioso)."""

from pathlib import Path

import pytest

from apival.classification import CATEGORY_INFO, Category, classify, has_cors_fatal, hints_for
from apival.junit import Totals, parse_reports, summarize

JUNIT = """<?xml version="1.0"?>
<testsuites><testsuite tests="7" failures="4" errors="1" skipped="1" time="2.5">
<testcase classname="t.a" name="ok"/>
<testcase classname="t.a" name="skip"><skipped/></testcase>
<testcase classname="t.c" name="contrato"><failure type="ContractViolation" message="[CONTRACT] x: esperado HTTP 200, recebido 500">tb</failure></testcase>
<testcase classname="t.c" name="cors"><failure type="CorsPolicyViolation" message="[CORS] Access-Control-Allow-Origin ausente">tb</failure></testcase>
<testcase classname="t.c" name="sec"><failure message="[SECURITY] falta nosniff">tb</failure></testcase>
<testcase classname="t.c" name="rede"><failure message="requests.exceptions.ReadTimeout: Read timed out">tb</failure></testcase>
<testcase classname="" name="t.quebrado"><error message="collection failure">ModuleNotFoundError: No module named 'xyz'</error></testcase>
</testsuite></testsuites>"""


@pytest.mark.parametrize(
    ("texto", "esperada"),
    [
        ("ImportError while importing", Category.COMPILATION),
        ("lib/x.dart:3:4: Error: algo", Category.COMPILATION),
        ("FATAL: ALLOWED_ORIGINS='*' é incompatível", Category.CORS),
        ("ReadTimeout em /health", Category.INFRA),
        ("HEALTHCHECK_TIMEOUT http://x após 30s", Category.INFRA),
        ("[SECURITY] falta nosniff", Category.SECURITY),
        ("[CORS] Allow-Origin ausente", Category.CORS),
        ("[CONTRACT] schema inválido", Category.CONTRACT),
        ("assert 1 == 2", Category.OTHER),
    ],
)
def test_classificacao(texto: str, esperada: Category) -> None:
    assert classify(texto) is esperada


def test_precedencia_compilacao_vence_infra() -> None:
    assert classify("ImportError ... ConnectTimeout") is Category.COMPILATION


def test_precedencia_infra_vence_cors() -> None:
    assert classify("[CORS] falhou: ReadTimeout") is Category.INFRA


def test_fatal_cors_e_dicas() -> None:
    assert has_cors_fatal("FATAL: CORS inválido")
    assert hints_for("Access-Control-Allow-Origin e Vary", limit=5)
    assert hints_for("sem relação") == ()


def test_toda_categoria_tem_texto_para_o_usuario() -> None:
    assert set(CATEGORY_INFO) == set(Category)
    assert all(info.title and info.action for info in CATEGORY_INFO.values())


def test_parse_reports_classifica_cada_falha(tmp_path: Path) -> None:
    xml = tmp_path / "j.xml"
    xml.write_text(JUNIT)
    totais, falhas = parse_reports([str(xml)])
    por_nome = {f.test: f.category for f in falhas}
    assert por_nome["t.c::contrato"] is Category.CONTRACT
    assert por_nome["t.c::cors"] is Category.CORS
    assert por_nome["t.c::sec"] is Category.SECURITY
    assert por_nome["t.c::rede"] is Category.INFRA
    assert por_nome["t.quebrado"] is Category.COMPILATION
    assert (totais.tests, totais.passed, totais.skipped) == (7, 1, 1)
    assert (Totals(1) + Totals(2)).tests == 3


def test_xml_malicioso_billion_laughs_e_recusado(tmp_path: Path) -> None:
    bomba = tmp_path / "bomba.xml"
    bomba.write_text('<?xml version="1.0"?><!DOCTYPE l [<!ENTITY a "aaaa"><!ENTITY b "&a;&a;&a;&a;">]><r>&b;</r>')
    _, falhas = parse_reports([str(bomba)])
    assert falhas and "ilegível ou malicioso" in falhas[0].message


def test_xml_corrompido_e_arquivo_inexistente(tmp_path: Path) -> None:
    ruim = tmp_path / "ruim.xml"
    ruim.write_text("<testsuites><oops")
    _, falhas = parse_reports([str(ruim), str(tmp_path / "nao-existe.xml")])
    assert len(falhas) == 2


def test_atributos_numericos_invalidos_viram_zero(tmp_path: Path) -> None:
    xml = tmp_path / "n.xml"
    xml.write_text(
        '<testsuites><testsuite tests="x" failures="" time="abc"><testcase name="a"/></testsuite></testsuites>'
    )
    totais, _ = parse_reports([str(xml)])
    assert (totais.tests, totais.time) == (0, 0.0)


def test_resumo_remove_pii_e_limita_tamanho() -> None:
    saida = summarize("erro com joao@x.com " + "a" * 1000)
    assert "joao@x.com" not in saida
    assert len(saida) <= 520
