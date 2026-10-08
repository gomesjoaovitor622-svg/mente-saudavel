"""Auto-diagnóstico (cada categoria, execução abortada) e relatório executivo."""

import json
from pathlib import Path

import pytest

from apival import diagnose, executive
from apival.classification import Category
from apival.markdown import render


def _escreve(tmp_path: Path, nome: str, conteudo: str) -> str:
    caminho = tmp_path / nome
    caminho.write_text(conteudo, encoding="utf-8")
    return str(caminho)


XML_FALHAS = """<testsuites><testsuite tests="3" failures="3" errors="0" skipped="0" time="1.0">
<testcase classname="t" name="a"><failure message="[CONTRACT] GET /x: esperado HTTP 200, recebido 500">tb</failure></testcase>
<testcase classname="t" name="b"><failure message="[CORS] Access-Control-Allow-Origin ausente">tb</failure></testcase>
<testcase classname="t" name="c"><failure message="ReadTimeout: Read timed out">tb</failure></testcase>
</testsuite></testsuites>"""
XML_OK = '<testsuites><testsuite tests="2" failures="0" errors="0" skipped="0" time="0.2"><testcase name="a"/><testcase name="b"/></testsuite></testsuites>'


def test_diagnostico_com_falhas_gera_resumo_por_categoria(tmp_path: Path) -> None:
    xml = _escreve(tmp_path, "j.xml", XML_FALHAS)
    diag = diagnose.build(leg="t", exit_code=1, junit_patterns=[xml])
    md = render(diag)
    assert diag.primary_category == "infra"
    assert not diag.ok
    for titulo in ("Falhas de Contrato de API", "Violações de Política CORS", "Timeouts de Infraestrutura"):
        assert titulo in md
    assert "❌ REPROVADO" in md and "💡" in md


def test_diagnostico_aprovado(tmp_path: Path) -> None:
    diag = diagnose.build(leg="ok", exit_code=0, junit_patterns=[_escreve(tmp_path, "j.xml", XML_OK)])
    assert diag.ok and diag.primary_category == "none"
    assert "✅ APROVADO" in render(diag)


def test_sem_junit_e_healthcheck_timeout_vira_infra(tmp_path: Path) -> None:
    health = _escreve(
        tmp_path, "h.log", "tentativa 1: URLError\nHEALTHCHECK_TIMEOUT http://127.0.0.1:8765/health após 30s\n"
    )
    diag = diagnose.build(leg="t", exit_code=124, health_log=health)
    assert diag.primary_category == "infra"
    assert diag.health_tail


def test_fatal_de_config_cors_vence_o_sintoma_de_servidor_morto(tmp_path: Path) -> None:
    server = _escreve(tmp_path, "s.log", "FATAL: ALLOWED_ORIGINS='*' é incompatível com ALLOW_CREDENTIALS=true\n")
    health = _escreve(tmp_path, "h.log", "SERVER_EXITED: o processo terminou\n")
    diag = diagnose.build(leg="t", exit_code=3, health_log=health, server_log=server)
    assert diag.primary_category == "cors"


def test_execucao_abortada_sem_pistas_e_classificada_como_outra(tmp_path: Path) -> None:
    diag = diagnose.build(leg="t", exit_code=9)
    assert diag.failures[0].category is Category.OTHER


def test_codigo_5_nenhum_teste_coletado() -> None:
    diag = diagnose.build(leg="t", exit_code=5)
    assert "nenhum teste coletado" in diag.failures[0].message


def test_sem_falhas_mas_com_codigo_de_erro_mostra_evidencias_do_log(tmp_path: Path) -> None:
    log = _escreve(tmp_path, "p.log", "ReadTimeout durante o teardown\n")
    diag = diagnose.build(leg="t", exit_code=1, junit_patterns=[_escreve(tmp_path, "j.xml", XML_OK)], log=log)
    diag.failures.clear()
    assert "Evidências no log bruto" in render(diag)


def test_log_com_segredo_nao_aparece_no_diagnostico(tmp_path: Path) -> None:
    log = _escreve(tmp_path, "p.log", "ReadTimeout Authorization: Bearer SEGREDO123456 para joao@x.com\n")
    diag = diagnose.build(leg="t", exit_code=1, log=log)
    saida = render(diag) + json.dumps(diag.to_json())
    assert "SEGREDO123456" not in saida and "joao@x.com" not in saida


def test_cli_grava_summary_json_markdown_e_anotacoes(
    tmp_path: Path, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    saida = tmp_path / "out.txt"
    monkeypatch.setenv("GITHUB_OUTPUT", str(saida))
    summary, js, md = tmp_path / "s.md", tmp_path / "d.json", tmp_path / "d.md"
    code = diagnose.main(
        [
            "--junit",
            _escreve(tmp_path, "j.xml", XML_FALHAS),
            "--exit-code",
            "1",
            "--leg",
            "l",
            "--summary",
            str(summary),
            "--json",
            str(js),
            "--md",
            str(md),
        ]
    )
    assert code == 0
    assert "Diagnóstico automático" in summary.read_text() and md.read_text()
    assert json.loads(js.read_text())["categories"]["cors"] == 1
    out = capsys.readouterr().out
    assert "::error title=" in out and "::notice title=l" in out
    assert "failed_total=3" in saida.read_text()


def test_cli_sem_summary_imprime_na_saida_padrao(
    tmp_path: Path, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("GITHUB_STEP_SUMMARY", raising=False)
    diagnose.main(["--exit-code", "0", "--leg", "x"])
    assert "Diagnóstico automático" in capsys.readouterr().out


# ----------------------------------------------------------------------------- relatório executivo
def test_relatorio_executivo_aprovado_e_reprovado() -> None:
    meta = executive.metadata({"GITHUB_REPOSITORY": "o/r", "GITHUB_RUN_ID": "7", "GITHUB_SHA": "abc"})
    diag = [{"leg": "ref", "ok": True, "totals": {"tests": 3, "passed": 3}, "failures": []}]
    bom = executive.render_markdown(
        meta, diag, {"quality": "success", "reference-suite": "success", "live-suite": "failure"}, "T"
    )
    assert "✅ APROVADO" in bom and "o/r/actions/runs/7" in bom and "❌ reprovado" in bom
    ruim = executive.render_markdown(meta, [], {"quality": "failure", "reference-suite": "success"}, "T")
    assert "❌ REPROVADO" in ruim


def test_job_cancelado_reprova_o_veredito() -> None:
    assert not executive.overall({"quality": "success", "reference-suite": "success", "live-suite": "cancelled"})
    assert executive.overall({"quality": "success", "reference-suite": "skipped"})


def test_relatorio_lista_achados_e_nao_vaza_pii() -> None:
    diag = [
        {
            "leg": "ref",
            "ok": False,
            "totals": {},
            "failures": [{"test": "t", "category": "cors", "message": "falhou para joao@x.com"}],
        }
    ]
    md = executive.render_markdown({}, diag, {}, "T")
    assert "Achados (falhas)" in md and "joao@x.com" not in md


def test_html_e_escapado_e_sem_recursos_externos() -> None:
    html = executive.render_html("<script>alert(1)</script> & mais", "t<i>")
    assert "<script>" not in html and "&lt;script&gt;" in html
    assert "http://" not in html and "https://" not in html


def test_saidas_e_manifesto_com_sha256(tmp_path: Path) -> None:
    extra = tmp_path / "sbom.json"
    extra.write_text("{}")
    manifesto = executive.write_outputs(tmp_path / "out", "# x\n", "t", [extra, tmp_path / "ausente"])
    assert set(manifesto) == {"executive-report.md", "executive-report.html", "sbom.json"}
    assert manifesto["sbom.json"] == executive.sha256(extra)
    assert json.loads((tmp_path / "out" / "manifest.json").read_text())["algorithm"] == "sha256"


def test_job_results_e_diagnosis_loader(tmp_path: Path) -> None:
    assert executive.job_results('{"a": {"result": "success"}, "b": 1}') == {"a": "success"}
    assert executive.job_results("não-é-json") == {}
    (tmp_path / "x").mkdir()
    (tmp_path / "x" / "diagnosis.json").write_text('{"leg": "a"}')
    (tmp_path / "x" / "ruim.json").write_text("{")
    assert len(executive.load_diagnoses(str(tmp_path / "**" / "*.json"))) == 1


def test_cli_executivo_gera_arquivos(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setenv("NEEDS_JSON", '{"quality": {"result": "success"}, "reference-suite": {"result": "success"}}')
    summary = tmp_path / "s.md"
    code = executive.main(
        ["--diagnosis", str(tmp_path / "*.json"), "--out-dir", str(tmp_path / "o"), "--summary", str(summary)]
    )
    assert code == 0 and (tmp_path / "o" / "executive-report.html").exists()
    assert "APROVADO" in summary.read_text()
    assert "relatório gerado" in capsys.readouterr().out
