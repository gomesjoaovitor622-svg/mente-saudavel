"""Relatório executivo de conformidade (Markdown + HTML + manifesto de integridade).

Consolida os diagnósticos das suítes e o resultado dos jobs em um documento legível por
gestão e por auditoria: veredito, evidências por controle, metadados de rastreabilidade
(commit, run, versões) e SHA-256 de cada artefato. Não contém segredos nem PII.

Uso:
  python -m apival.executive --diagnosis 'in/**/diagnosis.json' --out-dir reports/executive
  (o resultado dos jobs vem em NEEDS_JSON = toJSON(needs) do workflow)
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import html
import json
import os
import platform
import sys
from collections.abc import Mapping, Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from apival import __version__
from apival.redaction import redact

# Controle auditável -> job do workflow que o comprova.
CONTROLS: tuple[tuple[str, str, str], ...] = (
    (
        "C-01",
        "quality",
        "Qualidade estática: lint (ruff), tipagem estrita (mypy --strict), SAST (bandit), cobertura ≥ 90%",
    ),
    (
        "C-02",
        "reference-suite",
        "Contrato de API (OpenAPI), CORS e controles de segurança contra o serviço de referência",
    ),
    ("C-03", "live-suite", "Contrato e CORS das APIs públicas reais usadas pelo produto (informativo)"),
    (
        "C-04",
        "supply-chain",
        "Cadeia de suprimentos: dependências com hash, auditoria de vulnerabilidades, SBOM, varredura de segredos",
    ),
    (
        "C-05",
        "workflow-audit",
        "Auditoria dos workflows: actions fixadas por SHA, permissões mínimas, injeção de template",
    ),
)
_REQUIRED = {"quality", "reference-suite"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as arquivo:
        for bloco in iter(lambda: arquivo.read(65536), b""):
            digest.update(bloco)
    return digest.hexdigest()


def load_diagnoses(pattern: str) -> list[dict[str, Any]]:
    resultado: list[dict[str, Any]] = []
    for caminho in sorted(glob.glob(pattern, recursive=True)):
        try:
            dados = json.loads(Path(caminho).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(dados, dict) and "leg" in dados:
            resultado.append(dados)
    return resultado


def job_results(needs_json: str) -> dict[str, str]:
    try:
        bruto = json.loads(needs_json or "{}")
    except ValueError:
        return {}
    return {str(job): str(info.get("result", "unknown")) for job, info in bruto.items() if isinstance(info, dict)}


def overall(jobs: Mapping[str, str]) -> bool:
    """Aprovado se todos os jobs obrigatórios passaram (skipped conta como não aplicável)."""
    return all(jobs.get(job, "skipped") in ("success", "skipped") for job in _REQUIRED) and all(
        resultado != "cancelled" for resultado in jobs.values()
    )


def metadata(env: Mapping[str, str]) -> dict[str, str]:
    repo = env.get("GITHUB_REPOSITORY", "(local)")
    run_id = env.get("GITHUB_RUN_ID", "")
    server = env.get("GITHUB_SERVER_URL", "https://github.com")
    return {
        "Repositório": repo,
        "Commit": env.get("GITHUB_SHA", "(local)"),
        "Branch/Tag": env.get("GITHUB_REF_NAME", "(local)"),
        "Evento": env.get("GITHUB_EVENT_NAME", "(local)"),
        "Workflow": env.get("GITHUB_WORKFLOW", "(local)"),
        "Execução": f"{server}/{repo}/actions/runs/{run_id}" if run_id else "(local)",
        "Tentativa": env.get("GITHUB_RUN_ATTEMPT", "1"),
        "Gerado em (UTC)": datetime.now(UTC).strftime("%Y-%m-%d %H:%M:%S"),
        "Toolkit apival": __version__,
        "Python do relatório": platform.python_version(),
    }


def render_markdown(
    meta: Mapping[str, str], diagnoses: Sequence[Mapping[str, Any]], jobs: Mapping[str, str], title: str
) -> str:
    ok = overall(jobs)
    linhas = [f"# {title}", "", f"## Veredito executivo: {'✅ APROVADO' if ok else '❌ REPROVADO'}", ""]
    linhas += ["| Item | Valor |", "|---|---|", *[f"| {k} | {v} |" for k, v in meta.items()], ""]

    linhas += ["## Controles verificados", "", "| ID | Controle | Resultado | Obrigatório |", "|---|---|---|:-:|"]
    for cid, job, descricao in CONTROLS:
        resultado = jobs.get(job, "não executado")
        marca = {
            "success": "✅ aprovado",
            "failure": "❌ reprovado",
            "skipped": "n/a (não aplicável)",
            "cancelled": "⚠️ cancelado",
        }.get(resultado, f"❔ {resultado}")
        linhas.append(f"| {cid} | {descricao} | {marca} | {'sim' if job in _REQUIRED else 'não'} |")

    linhas += [
        "",
        "## Suítes de teste",
        "",
        "| Suíte | Testes | Aprovados | Falhas | Erros | Pulados | Duração | Resultado |",
        "|---|---:|---:|---:|---:|---:|---:|---|",
    ]
    for d in diagnoses:
        t = d.get("totals", {})
        linhas.append(
            f"| `{d['leg']}` | {t.get('tests', 0)} | {t.get('passed', 0)} | {t.get('failures', 0)} | "
            f"{t.get('errors', 0)} | {t.get('skipped', 0)} | {t.get('time', 0)}s | {'✅' if d.get('ok') else '❌'} |"
        )

    falhas = [(d["leg"], f) for d in diagnoses for f in d.get("failures", [])]
    if falhas:
        linhas += ["", "## Achados (falhas)", "", "| Suíte | Categoria | Teste | Descrição |", "|---|---|---|---|"]
        for leg, f in falhas[:50]:
            linhas.append(f"| `{leg}` | {f['category']} | `{f['test']}` | {f['message']} |")
    else:
        linhas += ["", "## Achados", "", "Nenhuma falha registrada nas suítes."]

    linhas += [
        "",
        "## Notas e limites",
        "",
        "- A suíte `live` é informativa por padrão: APIs de terceiros podem oscilar sem que o produto tenha defeito.",
        "- Este relatório é **evidência técnica automatizada**; não substitui auditoria independente nem certificação.",
        "- Os testes de CORS validam os cabeçalhos HTTP; não substituem teste com navegador real.",
        "- O manifesto `manifest.json` lista o SHA-256 de cada artefato para verificação de integridade.",
    ]
    return redact("\n".join(linhas)) + "\n"


def render_html(markdown: str, title: str) -> str:
    """HTML autocontido (sem JavaScript, sem recursos externos). Todo o texto é escapado."""
    corpo = "<br>\n".join(html.escape(linha) for linha in markdown.splitlines())
    return (
        '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">'
        "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'\">"
        f"<title>{html.escape(title)}</title>"
        "<style>body{font:15px/1.5 system-ui,sans-serif;max-width:960px;margin:2rem auto;padding:0 1rem;color:#1b1f23}"
        '</style></head><body><pre style="white-space:pre-wrap;font:inherit">'
        f"{corpo}</pre></body></html>\n"
    )


def write_outputs(out_dir: Path, markdown: str, title: str, extra_files: Sequence[Path]) -> dict[str, str]:
    out_dir.mkdir(parents=True, exist_ok=True)
    md = out_dir / "executive-report.md"
    htm = out_dir / "executive-report.html"
    md.write_text(markdown, encoding="utf-8")
    htm.write_text(render_html(markdown, title), encoding="utf-8")
    manifesto = {p.name: sha256(p) for p in [md, htm, *extra_files] if p.is_file()}
    (out_dir / "manifest.json").write_text(
        json.dumps({"algorithm": "sha256", "files": manifesto}, indent=2, sort_keys=True), encoding="utf-8"
    )
    return manifesto


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--diagnosis", default="**/diagnosis.json", help="glob dos diagnosis.json")
    parser.add_argument("--out-dir", default="reports/executive")
    parser.add_argument("--title", default="Relatório Executivo de Conformidade - API Validation")
    parser.add_argument("--extra", action="append", default=[], help="arquivo adicional para o manifesto (ex.: SBOM)")
    parser.add_argument("--summary", default=os.environ.get("GITHUB_STEP_SUMMARY"))
    args = parser.parse_args(argv)

    jobs = job_results(os.environ.get("NEEDS_JSON", ""))
    markdown = render_markdown(metadata(os.environ), load_diagnoses(args.diagnosis), jobs, args.title)
    manifesto = write_outputs(Path(args.out_dir), markdown, args.title, [Path(p) for p in args.extra])
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as arquivo:
            arquivo.write(markdown + "\n")
    print(f"relatório gerado em {args.out_dir} ({len(manifesto)} arquivo(s) no manifesto)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
