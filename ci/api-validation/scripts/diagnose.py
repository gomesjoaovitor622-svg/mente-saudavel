#!/usr/bin/env python3
"""Auto-diagnóstico de execuções de teste: transforma logs/JUnit em um sumário executivo.

Entradas:  relatório(s) JUnit XML, log bruto do console, log do health-check, código de saída.
Saídas:    Markdown no GitHub Step Summary, JSON estruturado, anotações `::error` e
           outputs do step (failed_total, primary_category).

Categorias (nesta ordem de precedência):
  compilation  Erros de Compilação        -> sintaxe/import/coleta quebrada; o código nem executa
  infra        Timeouts de Infraestrutura -> rede, serviço não subiu, health-check, timeout de teste
  cors         Violações de Política CORS -> falhas marcadas [CORS] / CorsPolicyViolation
  contract     Falhas de Contrato de API  -> falhas marcadas [CONTRACT] / ContractViolation / schema
  other        Outras falhas

A precedência evita falso diagnóstico: um teste de CORS que falha por timeout é um
problema de infraestrutura, não de política CORS.

Este script nunca falha o job (sai com 0): quem decide o veredito é o código de saída
original, repassado em --exit-code.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from collections import OrderedDict

CATEGORIAS = OrderedDict([
    ("compilation", ("Erros de Compilação", "🧱",
                     "Corrija a sintaxe/imports apontados. Reproduza localmente com `python -m compileall -q .` e "
                     "`pytest --collect-only`. Nenhum teste foi executado de fato enquanto isto não for resolvido.")),
    ("infra", ("Timeouts de Infraestrutura", "⏱️",
               "Nada indica falha de regra de negócio. Verifique se o serviço subiu (veja `server.log`), aumente "
               "`health_timeout` se o boot é lento e confira DNS/conectividade do runner. Reexecute para descartar instabilidade.")),
    ("cors", ("Violações de Política CORS", "🌐",
              "A política CORS do serviço diverge do esperado. Compare os headers recebidos (mensagem abaixo) com a "
              "allowlist de origens e com o checklist: `Allow-Origin` exato, `Vary: Origin`, `Allow-Methods/Headers`, "
              "`Max-Age`, e nunca `*` com credenciais.")),
    ("contract", ("Falhas de Contrato de API", "📜",
                  "Status HTTP, tipo de dado ou schema divergem do contrato. Compare a resposta real com `schemas.py`; se a "
                  "mudança foi intencional, atualize o schema (e o consumidor); se não, é uma regressão da API.")),
    ("other", ("Outras falhas", "❓", "Falha não classificada. Leia o trecho do erro e o log completo anexado ao artefato.")),
])

RE_COMPILE = re.compile(
    r"(SyntaxError|IndentationError|TabError|ModuleNotFoundError|ImportError|ERROR collecting|"
    r"Compilation failed|FAILURE: Build failed|error TS\d+|\.dart:\d+:\d+: Error:)")
RE_INFRA = re.compile(
    r"(HEALTHCHECK_TIMEOUT|SERVER_EXITED|ConnectTimeout|ReadTimeout|TimeoutError|Timeout >|timed out|"
    r"Max retries exceeded|ConnectionError|ConnectionRefusedError|RemoteDisconnected|NameResolutionError|"
    r"Temporary failure in name resolution|Failed to establish a new connection|Connection aborted)", re.I)
RE_CORS = re.compile(r"(\[CORS\]|CorsPolicyViolation)")
# O serviço recusa subir com configuração CORS proibida (ex.: '*' + credenciais): é política, não infra.
RE_CORS_FATAL = re.compile(r"FATAL:.*(ALLOWED_ORIGINS|ALLOW_CREDENTIALS|CORS)")
RE_CONTRACT = re.compile(r"(\[CONTRACT\]|ContractViolation|jsonschema)")

# (padrão, dica) - dicas específicas anexadas ao detalhe de cada falha
DICAS = [
    (re.compile(r"Access-Control-Allow-Origin"), "Garanta que o serviço ecoa a origem exata autorizada (nunca por sufixo) e não emite o header para origens desconhecidas."),
    (re.compile(r"Vary"), "Adicione `Vary: Origin` (e, no preflight, `Access-Control-Request-Method/Headers`)."),
    (re.compile(r"Allow-Credentials"), "Com credenciais, o `Allow-Origin` precisa ser a origem exata, e o header só vai para origens autorizadas."),
    (re.compile(r"Max-Age"), "Defina `Access-Control-Max-Age` como inteiro entre 1 e 86400 (navegadores limitam a 2 h ou menos)."),
    (re.compile(r"Allow-Methods"), "Revise a lista de métodos anunciados no preflight; não anuncie métodos que a rota não aceita."),
    (re.compile(r"Allow-Headers"), "Anuncie somente os headers realmente aceitos (content-type, authorization...)."),
    (re.compile(r"esperado HTTP"), "O status devolvido difere do contrato. Verifique roteamento, validação de entrada e tratamento de erros."),
    (re.compile(r"schema inválido"), "Um campo obrigatório sumiu ou mudou de tipo. Compare com o schema em `schemas.py`."),
    (re.compile(r"HEALTHCHECK_TIMEOUT"), "O serviço não respondeu em /health dentro do prazo: veja `server.log` e a porta configurada."),
    (re.compile(r"SERVER_EXITED"), "O processo do serviço morreu no boot: veja o traceback em `server.log`."),
    (re.compile(r"ModuleNotFoundError|ImportError"), "Dependência ausente ou nome de módulo errado: confira `requirements.txt` e os imports."),
    (re.compile(r"SyntaxError|IndentationError"), "Erro de sintaxe no arquivo indicado: rode `python -m py_compile <arquivo>`."),
]

SEGREDOS = [
    (re.compile(r"(?i)(authorization:\s*(?:bearer|basic)\s+)[^\s'\"]+"), r"\1***"),
    (re.compile(r"github_pat_[A-Za-z0-9_]{20,}"), "github_pat_***"),
    (re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"), "gh*_***"),
    (re.compile(r"(?i)((?:token|secret|password|apikey|api_key)\s*[=:]\s*)[^\s'\"&]+"), r"\1***"),
]


def redigir(texto: str) -> str:
    """Remove segredos antes de qualquer saída (defesa em profundidade; o runner também mascara)."""
    for padrao, troca in SEGREDOS:
        texto = padrao.sub(troca, texto)
    return texto


def classificar(texto: str) -> str:
    if RE_COMPILE.search(texto):
        return "compilation"
    if RE_CORS_FATAL.search(texto):
        return "cors"
    if RE_INFRA.search(texto):
        return "infra"
    if RE_CORS.search(texto):
        return "cors"
    if RE_CONTRACT.search(texto):
        return "contract"
    return "other"


def dicas_para(texto: str) -> list[str]:
    return [dica for padrao, dica in DICAS if padrao.search(texto)][:2]


def resumir(texto: str, limite: int = 520) -> str:
    texto = redigir(" ".join(texto.split()))
    return texto if len(texto) <= limite else texto[: limite - 1] + "…"


def ler_junit(caminhos: list[str]):
    """Retorna (totais, falhas). Cada falha: dict(teste, categoria, mensagem, dicas)."""
    totais = {"tests": 0, "failures": 0, "errors": 0, "skipped": 0, "time": 0.0}
    falhas = []
    for caminho in caminhos:
        try:
            raiz = ET.parse(caminho).getroot()
        except (ET.ParseError, OSError):
            falhas.append({"teste": os.path.basename(caminho), "categoria": "other",
                           "mensagem": "relatório JUnit ilegível/corrompido", "dicas": []})
            continue
        for suite in raiz.iter("testsuite"):
            for chave in ("tests", "failures", "errors", "skipped"):
                totais[chave] += int(suite.get(chave, 0) or 0)
            totais["time"] += float(suite.get("time", 0) or 0)
        for caso in raiz.iter("testcase"):
            for filho in list(caso):
                if filho.tag not in ("failure", "error"):
                    continue
                bruto = f"{filho.get('type', '')} {filho.get('message', '')}\n{filho.text or ''}"
                nome = f"{caso.get('classname', '')}::{caso.get('name', '')}".strip(":")
                falhas.append({"teste": nome, "categoria": classificar(bruto),
                               "mensagem": resumir(filho.get("message") or filho.text or bruto),
                               "dicas": dicas_para(bruto)})
    return totais, falhas


def achados_no_log(texto: str, limite: int = 4) -> dict[str, list[str]]:
    """Linhas do log bruto que denunciam cada categoria (útil quando não há JUnit)."""
    achados: dict[str, list[str]] = {}
    for linha in texto.splitlines():
        if not linha.strip():
            continue
        chave = classificar(linha)
        if chave != "other" and len(achados.setdefault(chave, [])) < limite:
            achados[chave].append(resumir(linha, 240))
    return achados


def escapar_anotacao(texto: str) -> str:
    return texto.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def montar_markdown(ctx: dict) -> str:
    t, falhas, por_cat = ctx["totais"], ctx["falhas"], ctx["por_categoria"]
    ok = ctx["exit_code"] == 0 and not falhas
    linhas = [f"# 🩺 Diagnóstico automático — `{ctx['leg']}`", ""]
    linhas.append(f"**Veredito:** {'✅ APROVADO' if ok else '❌ REPROVADO'} &nbsp;|&nbsp; código de saída original: `{ctx['exit_code']}`")
    linhas += ["", "| Testes | Aprovados | Falhas | Erros | Pulados | Duração |", "|---:|---:|---:|---:|---:|---:|"]
    aprovados = max(t["tests"] - t["failures"] - t["errors"] - t["skipped"], 0)
    linhas.append(f"| {t['tests']} | {aprovados} | {t['failures']} | {t['errors']} | {t['skipped']} | {t['time']:.1f}s |")

    if ok:
        linhas += ["", "Nenhuma falha detectada. Nada a fazer. 🎉"]
        return "\n".join(linhas) + "\n"

    linhas += ["", "## Resumo por categoria", "", "| Categoria | Ocorrências | O que fazer |", "|---|---:|---|"]
    for chave, (titulo, icone, acao) in CATEGORIAS.items():
        n = len(por_cat.get(chave, [])) or (1 if ctx["achados_log"].get(chave) and not falhas else 0)
        if n:
            linhas.append(f"| {icone} **{titulo}** | {n} | {acao} |")

    for chave, (titulo, icone, _) in CATEGORIAS.items():
        itens = por_cat.get(chave, [])
        extra = ctx["achados_log"].get(chave, [])
        if not itens and not extra:
            continue
        linhas += ["", f"## {icone} {titulo}", ""]
        for f in itens[:15]:
            linhas.append(f"- `{f['teste']}`\n  - {f['mensagem']}")
            for dica in f["dicas"]:
                linhas.append(f"  - 💡 {dica}")
        if len(itens) > 15:
            linhas.append(f"- … e mais {len(itens) - 15} falha(s) (veja o artefato `junit`).")
        if extra and not itens:
            linhas.append("Evidências no log bruto:")
            linhas += [f"- `{e}`" for e in extra]

    if ctx["health_tail"]:
        linhas += ["", "## Health-check do serviço", "", "```text", *ctx["health_tail"], "```"]
    if ctx["server_tail"]:
        linhas += ["", "<details><summary>Últimas linhas do log do serviço</summary>", "", "```text", *ctx["server_tail"], "```", "</details>"]

    linhas += ["", "## Próximos passos", "",
               "1. Comece pela categoria mais acima na lista: ela costuma ser a causa-raiz das demais.",
               "2. Baixe o artefato `failure-dumps-*` (logs brutos) se precisar de contexto adicional.",
               "3. Corrija e reenvie; o pipeline cancela execuções antigas da mesma branch automaticamente."]
    return "\n".join(linhas) + "\n"


def ler_texto(caminho: str | None, max_linhas: int | None = None) -> list[str]:
    if not caminho or not os.path.exists(caminho):
        return []
    with open(caminho, encoding="utf-8", errors="replace") as f:
        linhas = f.read().splitlines()
    return linhas[-max_linhas:] if max_linhas else linhas


def diagnosticar(args) -> dict:
    caminhos = sorted({c for padrao in (args.junit or []) for c in glob.glob(padrao)})
    totais, falhas = ler_junit(caminhos) if caminhos else ({"tests": 0, "failures": 0, "errors": 0, "skipped": 0, "time": 0.0}, [])
    log_bruto = "\n".join(ler_texto(args.log) + ler_texto(args.health_log) + ler_texto(args.server_log, 60))
    achados = achados_no_log(log_bruto)

    # pytest: 5 = nenhum teste coletado (marcador/caminho errado) - caso específico, tratado primeiro
    if args.exit_code == 5:
        falhas.append({"teste": "<seleção de testes>", "categoria": "other",
                       "mensagem": "nenhum teste coletado: verifique o marcador (-m) e os caminhos", "dicas": []})
    # Execução abortada (sem JUnit) com código de erro: classifica pelo log/health-check.
    elif not caminhos and args.exit_code != 0:
        # FATAL de configuração CORS no log do serviço é a causa-raiz: vence o sintoma (SERVER_EXITED).
        if RE_CORS_FATAL.search(log_bruto):
            chave = "cors"
            achados.setdefault("cors", [resumir(l, 240) for l in log_bruto.splitlines() if RE_CORS_FATAL.search(l)][:2])
        else:
            chave = next((c for c in CATEGORIAS if c in achados), "other")
        falhas.append({"teste": "<execução abortada antes dos testes>", "categoria": chave,
                       "mensagem": resumir(" | ".join(achados.get(chave, [])) or f"código de saída {args.exit_code} sem relatório JUnit"),
                       "dicas": dicas_para(log_bruto)})

    por_categoria: dict[str, list] = {}
    for f in falhas:
        por_categoria.setdefault(f["categoria"], []).append(f)

    categorias_ativas = [c for c in CATEGORIAS if por_categoria.get(c)]
    return {
        "leg": args.leg, "exit_code": args.exit_code, "totais": totais, "falhas": falhas,
        "por_categoria": por_categoria, "achados_log": achados,
        "primary_category": categorias_ativas[0] if categorias_ativas else ("none" if args.exit_code == 0 else "other"),
        "health_tail": [redigir(l) for l in ler_texto(args.health_log, 12)] if args.exit_code in (124, 3) or "infra" in por_categoria else [],
        "server_tail": [redigir(l) for l in ler_texto(args.server_log, 25)] if "infra" in por_categoria or "compilation" in por_categoria else [],
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--junit", nargs="*", default=[], help="arquivo(s) ou glob(s) JUnit XML")
    ap.add_argument("--log", help="log bruto do console (pytest)")
    ap.add_argument("--health-log", help="saída do wait_for_http.py")
    ap.add_argument("--server-log", help="log do serviço sob teste")
    ap.add_argument("--exit-code", type=int, default=1, help="código de saída original da execução")
    ap.add_argument("--leg", default="suite", help="nome desta perna da matriz")
    ap.add_argument("--summary", default=os.environ.get("GITHUB_STEP_SUMMARY"), help="arquivo do Step Summary")
    ap.add_argument("--md", help="grava também o Markdown neste arquivo")
    ap.add_argument("--json", help="grava o diagnóstico estruturado neste arquivo")
    args = ap.parse_args(argv)

    ctx = diagnosticar(args)
    markdown = montar_markdown(ctx)

    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as f:
            f.write(markdown + "\n")
    else:
        print(markdown)
    if args.md:
        with open(args.md, "w", encoding="utf-8") as f:
            f.write(markdown)
    if args.json:
        resumo = {k: ctx[k] for k in ("leg", "exit_code", "totais", "primary_category")}
        resumo["categorias"] = {c: len(v) for c, v in ctx["por_categoria"].items()}
        resumo["falhas"] = ctx["falhas"]
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(resumo, f, ensure_ascii=False, indent=2)

    # Anotações visíveis na UI (e pela API de checks): uma por categoria com falhas.
    for chave, itens in ctx["por_categoria"].items():
        titulo = CATEGORIAS[chave][0]
        exemplos = "; ".join(f"{i['teste']}: {i['mensagem']}" for i in itens[:3])
        print(f"::error title={escapar_anotacao(ctx['leg'] + ' | ' + titulo)}::{escapar_anotacao(f'{len(itens)} ocorrência(s). {exemplos}')}")

    saida = os.environ.get("GITHUB_OUTPUT")
    if saida:
        with open(saida, "a", encoding="utf-8") as f:
            f.write(f"failed_total={len(ctx['falhas'])}\nprimary_category={ctx['primary_category']}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
