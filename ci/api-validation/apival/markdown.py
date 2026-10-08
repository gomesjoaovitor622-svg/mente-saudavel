"""Renderização do diagnóstico em Markdown (GitHub Step Summary / relatórios)."""

from __future__ import annotations

from typing import TYPE_CHECKING

from apival.classification import CATEGORY_INFO, Category

if TYPE_CHECKING:
    from apival.diagnose import Diagnosis

_MAX_ITEMS = 15


def render(diag: Diagnosis) -> str:
    t = diag.totals
    linhas = [f"# 🩺 Diagnóstico automático — `{diag.leg}`", ""]
    veredito = "✅ APROVADO" if diag.ok else "❌ REPROVADO"
    linhas.append(f"**Veredito:** {veredito} &nbsp;|&nbsp; código de saída original: `{diag.exit_code}`")
    linhas += ["", "| Testes | Aprovados | Falhas | Erros | Pulados | Duração |", "|---:|---:|---:|---:|---:|---:|"]
    linhas.append(f"| {t.tests} | {t.passed} | {t.failures} | {t.errors} | {t.skipped} | {t.time:.1f}s |")

    if diag.ok:
        return "\n".join([*linhas, "", "Nenhuma falha detectada. Nada a fazer. 🎉"]) + "\n"

    grupos = diag.by_category
    linhas += ["", "## Resumo por categoria", "", "| Categoria | Ocorrências | O que fazer |", "|---|---:|---|"]
    for categoria in Category:
        if grupos.get(categoria):
            info = CATEGORY_INFO[categoria]
            linhas.append(f"| {info.icon} **{info.title}** | {len(grupos[categoria])} | {info.action} |")

    for categoria in Category:
        itens = grupos.get(categoria, [])
        if not itens:
            continue
        info = CATEGORY_INFO[categoria]
        linhas += ["", f"## {info.icon} {info.title}", ""]
        for falha in itens[:_MAX_ITEMS]:
            linhas.append(f"- `{falha.test}`\n  - {falha.message}")
            linhas += [f"  - 💡 {dica}" for dica in falha.hints]
        if len(itens) > _MAX_ITEMS:
            linhas.append(f"- … e mais {len(itens) - _MAX_ITEMS} falha(s) (veja o artefato `junit`).")

    if not diag.failures:  # sem falhas de teste, mas com código de saída != 0: mostra evidências do log
        for categoria, evidencias in diag.log_findings.items():
            linhas += [
                "",
                f"## {CATEGORY_INFO[categoria].icon} {CATEGORY_INFO[categoria].title}",
                "",
                "Evidências no log bruto:",
            ]
            linhas += [f"- `{e}`" for e in evidencias]

    if diag.health_tail:
        linhas += ["", "## Health-check do serviço", "", "```text", *diag.health_tail, "```"]
    if diag.server_tail:
        linhas += [
            "",
            "<details><summary>Últimas linhas do log do serviço</summary>",
            "",
            "```text",
            *diag.server_tail,
            "```",
            "</details>",
        ]

    linhas += [
        "",
        "## Próximos passos",
        "",
        "1. Comece pela categoria mais acima na lista: costuma ser a causa-raiz das demais.",
        "2. Baixe o artefato `failure-dumps-*` (logs brutos) se precisar de contexto.",
        "3. Corrija e reenvie; o pipeline cancela execuções antigas da mesma branch.",
    ]
    return "\n".join(linhas) + "\n"
