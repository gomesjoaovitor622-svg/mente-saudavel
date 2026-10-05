"""Testes do PRÓPRIO harness (auto-diagnóstico e health-check). Rodam offline e rápido.

"Quem vigia os vigias": se o diagnóstico classificasse errado, o time seria
mandado ao lugar errado. Estes testes travam o comportamento de cada categoria.
"""
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "scripts"))
import diagnose  # noqa: E402

JUNIT = """<?xml version="1.0" encoding="utf-8"?>
<testsuites><testsuite name="api-validation" tests="6" failures="3" errors="1" skipped="0" time="1.5">
<testcase classname="tests.test_ok" name="test_passa" time="0.1"/>
<testcase classname="tests.test_contract_mock" name="test_status"><failure type="support.ContractViolation" message="[CONTRACT] GET /x: esperado HTTP 200, recebido 500">tb</failure></testcase>
<testcase classname="tests.test_cors_mock" name="test_origin"><failure type="support.CorsPolicyViolation" message="[CORS] Allow-Origin deveria ser 'a', veio 'None'">tb</failure></testcase>
<testcase classname="tests.test_cors_mock" name="test_timeout"><failure message="requests.exceptions.ReadTimeout: HTTPConnectionPool: Read timed out">tb</failure></testcase>
<testcase classname="" name="tests.test_quebrado"><error message="collection failure">ImportError while importing test module: ModuleNotFoundError: No module named 'xyz'</error></testcase>
<testcase classname="tests.test_x" name="test_outro"><failure message="assert 1 == 2">tb</failure></testcase>
</testsuite></testsuites>"""


def args_para(tmp_path, **kw):
    ns = diagnose.argparse.Namespace(junit=[], log=None, health_log=None, server_log=None,
                                     exit_code=1, leg="t", summary=None, md=None, json=None)
    for k, v in kw.items():
        setattr(ns, k, v)
    return ns


def test_classifica_cada_categoria(tmp_path):
    xml = tmp_path / "j.xml"
    xml.write_text(JUNIT)
    ctx = diagnose.diagnosticar(args_para(tmp_path, junit=[str(xml)]))
    nomes = {f["teste"]: f["categoria"] for f in ctx["falhas"]}
    assert nomes["tests.test_contract_mock::test_status"] == "contract"
    assert nomes["tests.test_cors_mock::test_origin"] == "cors"
    assert nomes["tests.test_cors_mock::test_timeout"] == "infra"      # timeout de teste CORS = infra
    assert nomes["tests.test_quebrado"] == "compilation"
    assert nomes["tests.test_x::test_outro"] == "other"
    assert ctx["totais"]["tests"] == 6


def test_precedencia_compilacao_antes_de_infra():
    assert diagnose.classificar("ImportError ... ConnectTimeout") == "compilation"


def test_markdown_tem_secoes_e_dicas(tmp_path):
    xml = tmp_path / "j.xml"
    xml.write_text(JUNIT)
    ctx = diagnose.diagnosticar(args_para(tmp_path, junit=[str(xml)]))
    md = diagnose.montar_markdown(ctx)
    for titulo in ("Erros de Compilação", "Falhas de Contrato de API", "Violações de Política CORS", "Timeouts de Infraestrutura"):
        assert titulo in md
    assert "❌ REPROVADO" in md and "💡" in md


def test_execucao_limpa_gera_aprovado(tmp_path):
    xml = tmp_path / "ok.xml"
    xml.write_text('<testsuites><testsuite tests="2" failures="0" errors="0" skipped="0" time="0.2"><testcase name="a"/><testcase name="b"/></testsuite></testsuites>')
    ctx = diagnose.diagnosticar(args_para(tmp_path, junit=[str(xml)], exit_code=0))
    assert "✅ APROVADO" in diagnose.montar_markdown(ctx)
    assert ctx["primary_category"] == "none"


def test_sem_junit_com_healthcheck_timeout_vira_infra(tmp_path):
    health = tmp_path / "health.log"
    health.write_text("[ 1.0s] tentativa 1: URLError\nHEALTHCHECK_TIMEOUT http://127.0.0.1:8765/health após 30s\n")
    ctx = diagnose.diagnosticar(args_para(tmp_path, health_log=str(health), exit_code=124))
    assert ctx["primary_category"] == "infra"
    assert "Health-check" in diagnose.montar_markdown(ctx)


def test_codigo_5_nenhum_teste_coletado(tmp_path):
    ctx = diagnose.diagnosticar(args_para(tmp_path, exit_code=5))
    assert any("nenhum teste coletado" in f["mensagem"] for f in ctx["falhas"])


def test_segredos_sao_redigidos():
    texto = "Authorization: Bearer abc123SEGREDO token=xyz789 github_pat_" + "A" * 30
    saida = diagnose.redigir(texto)
    assert "abc123SEGREDO" not in saida and "xyz789" not in saida and "A" * 30 not in saida


def test_cli_grava_summary_json_e_anotacoes(tmp_path, capsys):
    xml = tmp_path / "j.xml"
    xml.write_text(JUNIT)
    summary, js, out = tmp_path / "s.md", tmp_path / "d.json", tmp_path / "o.txt"
    import os
    os.environ["GITHUB_OUTPUT"] = str(out)
    assert diagnose.main(["--junit", str(xml), "--exit-code", "1", "--summary", str(summary), "--json", str(js)]) == 0
    assert "Diagnóstico automático" in summary.read_text()
    assert json.loads(js.read_text())["categorias"]["cors"] == 1
    assert "::error title=" in capsys.readouterr().out
    assert "failed_total=5" in out.read_text()


# ----------------------------------------------------------------------------- wait_for_http
def rodar_wait(*args):
    return subprocess.run([sys.executable, str(RAIZ / "scripts" / "wait_for_http.py"), *args],
                          capture_output=True, text=True, timeout=30)


def test_wait_for_http_timeout_retorna_124():
    r = rodar_wait("http://127.0.0.1:9/health", "--timeout", "2", "--interval", "0.2")
    assert r.returncode == 124 and "HEALTHCHECK_TIMEOUT" in r.stdout


def test_wait_for_http_sucesso():
    class H(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200); self.end_headers(); self.wfile.write(b'{"status": "ok"}')
        def log_message(self, *a): pass

    srv = HTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        r = rodar_wait(f"http://127.0.0.1:{srv.server_port}/", "--timeout", "5", "--contains", '"status": "ok"')
        assert r.returncode == 0 and "HEALTHCHECK_OK" in r.stdout
    finally:
        srv.shutdown()


def test_wait_for_http_detecta_processo_morto(tmp_path):
    pid = tmp_path / "x.pid"
    pid.write_text("999999")  # PID inexistente
    r = rodar_wait("http://127.0.0.1:9/health", "--timeout", "5", "--pid-file", str(pid))
    assert r.returncode == 3 and "SERVER_EXITED" in r.stdout


def test_fatal_de_configuracao_cors_no_servidor_vira_cors(tmp_path):
    server = tmp_path / "server.log"
    server.write_text("FATAL: ALLOWED_ORIGINS='*' é incompatível com ALLOW_CREDENTIALS=true\n")
    health = tmp_path / "health.log"
    health.write_text("SERVER_EXITED: o processo do serviço terminou antes de ficar saudável\n")
    ctx = diagnose.diagnosticar(args_para(tmp_path, health_log=str(health), server_log=str(server), exit_code=3))
    assert ctx["primary_category"] == "cors"


def test_wait_for_http_processo_zumbi_conta_como_morto(tmp_path):
    import os
    pid_file = tmp_path / "z.pid"
    filho = subprocess.Popen([sys.executable, "-c", "pass"])  # termina na hora; fica zumbi até wait()
    pid_file.write_text(str(filho.pid))
    import time
    time.sleep(0.5)
    r = rodar_wait("http://127.0.0.1:9/health", "--timeout", "5", "--pid-file", str(pid_file))
    filho.wait()
    assert r.returncode == 3 and "SERVER_EXITED" in r.stdout
