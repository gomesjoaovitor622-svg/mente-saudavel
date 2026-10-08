"""Auto-diagnóstico: transforma JUnit + logs + código de saída em um sumário executivo.

Saídas: Markdown (GitHub Step Summary), JSON estruturado, anotações ``::error``/``::notice``
e outputs do step. Todo texto passa por ``redact`` antes de sair.

Este comando nunca falha o job (sai com 0): o veredito é o código de saída original,
repassado em ``--exit-code``.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

from apival.classification import CATEGORY_INFO, Category, classify, has_cors_fatal, hints_for
from apival.junit import Failure, Totals, parse_reports, summarize
from apival.markdown import render
from apival.redaction import redact

PYTEST_NO_TESTS_COLLECTED = 5
_FINDINGS_PER_CATEGORY = 4


@dataclass
class Diagnosis:
    leg: str
    exit_code: int
    totals: Totals
    failures: list[Failure]
    log_findings: dict[Category, list[str]] = field(default_factory=dict)
    health_tail: list[str] = field(default_factory=list)
    server_tail: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return self.exit_code == 0 and not self.failures

    @property
    def by_category(self) -> dict[Category, list[Failure]]:
        grupos: dict[Category, list[Failure]] = {}
        for falha in self.failures:
            grupos.setdefault(falha.category, []).append(falha)
        return grupos

    @property
    def primary_category(self) -> str:
        grupos = self.by_category
        for categoria in Category:
            if grupos.get(categoria):
                return categoria.value
        return "none" if self.exit_code == 0 else Category.OTHER.value

    def to_json(self) -> dict[str, object]:
        return {
            "leg": self.leg,
            "exit_code": self.exit_code,
            "ok": self.ok,
            "primary_category": self.primary_category,
            "totals": {
                "tests": self.totals.tests,
                "passed": self.totals.passed,
                "failures": self.totals.failures,
                "errors": self.totals.errors,
                "skipped": self.totals.skipped,
                "time": round(self.totals.time, 2),
            },
            "categories": {c.value: len(v) for c, v in self.by_category.items()},
            "failures": [
                {"test": f.test, "category": f.category.value, "message": f.message, "hints": list(f.hints)}
                for f in self.failures
            ],
        }


def _read_lines(path: str | None, tail: int | None = None) -> list[str]:
    if not path or not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", errors="replace") as arquivo:
        linhas = arquivo.read().splitlines()
    return linhas[-tail:] if tail else linhas


def _findings(text: str) -> dict[Category, list[str]]:
    achados: dict[Category, list[str]] = {}
    for linha in text.splitlines():
        if not linha.strip():
            continue
        categoria = classify(linha)
        if categoria is not Category.OTHER and len(achados.setdefault(categoria, [])) < _FINDINGS_PER_CATEGORY:
            achados[categoria].append(summarize(linha, 240))
    return achados


def build(
    *,
    leg: str,
    exit_code: int,
    junit_patterns: Sequence[str] = (),
    log: str | None = None,
    health_log: str | None = None,
    server_log: str | None = None,
) -> Diagnosis:
    paths = sorted({p for pattern in junit_patterns for p in glob.glob(pattern)})
    totals, failures = parse_reports(paths) if paths else (Totals(), [])
    raw_log = "\n".join(_read_lines(log) + _read_lines(health_log) + _read_lines(server_log, 60))
    findings = _findings(raw_log)

    if exit_code == PYTEST_NO_TESTS_COLLECTED:
        failures.append(
            Failure(
                "<seleção de testes>", Category.OTHER, "nenhum teste coletado: verifique o marcador (-m) e os caminhos"
            )
        )
    elif not paths and exit_code != 0:
        # Execução abortada antes dos testes. FATAL de config CORS é a causa-raiz: vence o sintoma.
        if has_cors_fatal(raw_log):
            category = Category.CORS
            fatal = [summarize(x, 240) for x in raw_log.splitlines() if has_cors_fatal(x)][:2]
            findings.setdefault(Category.CORS, fatal)
        else:
            category = next((c for c in Category if c in findings), Category.OTHER)
        message = " | ".join(findings.get(category, [])) or f"código de saída {exit_code} sem relatório JUnit"
        failures.append(
            Failure("<execução abortada antes dos testes>", category, summarize(message), hints_for(raw_log))
        )

    grupos = {f.category for f in failures}
    show_health = exit_code in (124, 3) or Category.INFRA in grupos
    show_server = bool(grupos & {Category.INFRA, Category.COMPILATION, Category.CORS}) and not paths
    return Diagnosis(
        leg,
        exit_code,
        totals,
        failures,
        findings,
        [redact(x) for x in _read_lines(health_log, 12)] if show_health else [],
        [redact(x) for x in _read_lines(server_log, 25)] if show_server or Category.INFRA in grupos else [],
    )


def _escape_annotation(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def github_annotations(diagnosis: Diagnosis) -> list[str]:
    """Linhas ``::error``/``::notice`` do GitHub Actions (visíveis na UI e pela API de checks)."""
    linhas: list[str] = []
    for categoria, itens in diagnosis.by_category.items():
        titulo = f"{diagnosis.leg} | {CATEGORY_INFO[categoria].title}"
        exemplos = "; ".join(f"{i.test}: {i.message}" for i in itens[:3])
        corpo = f"{len(itens)} ocorrência(s). {exemplos}"
        linhas.append(f"::error title={_escape_annotation(titulo)}::{_escape_annotation(corpo)}")
    t = diagnosis.totals
    resumo = (
        f"testes={t.tests} aprovados={t.passed} falhas={t.failures} erros={t.errors} "
        f"pulados={t.skipped} saida={diagnosis.exit_code}"
    )
    linhas.append(f"::notice title={_escape_annotation(diagnosis.leg)}::{_escape_annotation(resumo)}")
    return linhas


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--junit", nargs="*", default=[], help="arquivo(s) ou glob(s) JUnit XML")
    parser.add_argument("--log")
    parser.add_argument("--health-log")
    parser.add_argument("--server-log")
    parser.add_argument("--exit-code", type=int, default=1)
    parser.add_argument("--leg", default="suite")
    parser.add_argument("--summary", default=os.environ.get("GITHUB_STEP_SUMMARY"))
    parser.add_argument("--md")
    parser.add_argument("--json")
    args = parser.parse_args(argv)

    diagnosis = build(
        leg=args.leg,
        exit_code=args.exit_code,
        junit_patterns=args.junit,
        log=args.log,
        health_log=args.health_log,
        server_log=args.server_log,
    )
    markdown = render(diagnosis)

    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as arquivo:
            arquivo.write(markdown + "\n")
    else:
        print(markdown)
    if args.md:
        Path(args.md).write_text(markdown, encoding="utf-8")
    if args.json:
        Path(args.json).write_text(json.dumps(diagnosis.to_json(), ensure_ascii=False, indent=2), encoding="utf-8")

    for linha in github_annotations(diagnosis):
        print(linha)
    saida = os.environ.get("GITHUB_OUTPUT")
    if saida:
        with open(saida, "a", encoding="utf-8") as arquivo:
            arquivo.write(f"failed_total={len(diagnosis.failures)}\nprimary_category={diagnosis.primary_category}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
