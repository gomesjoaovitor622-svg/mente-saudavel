"""Teste de ponta a ponta do SITE no navegador (Chromium), clicando nas telas de verdade.

Uso:  python tests/e2e/site_e2e.py https://localhost [pasta_de_capturas]

O Flutter web desenha em <canvas>; para o navegador "enxergar" botões e campos é preciso
ligar a árvore de acessibilidade (o mesmo que um leitor de tela faz). O teste faz isso.
Falhas viram anotações `::error::` no GitHub e deixam capturas de tela na pasta indicada.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

from playwright.sync_api import Page, sync_playwright
from playwright.sync_api import TimeoutError as PWTimeout

BASE = sys.argv[1] if len(sys.argv) > 1 else "https://localhost"
SHOTS = Path(sys.argv[2] if len(sys.argv) > 2 else "e2e-shots")
SHOTS.mkdir(parents=True, exist_ok=True)
TIMEOUT = 30_000
etapas: list[str] = []


def ver(page: Page, texto: str, timeout: int = TIMEOUT) -> None:
    """Espera um texto/rótulo aparecer na tela (na árvore de acessibilidade)."""
    alvo = page.locator(f'[aria-label*="{texto}"], flt-semantics:has-text("{texto}")').first
    alvo.wait_for(state="attached", timeout=timeout)


def tocar(page: Page, rotulo: str) -> None:
    """Clica num botão/aba pelo rótulo."""
    page.get_by_role("button", name=rotulo).or_(page.get_by_role("tab", name=rotulo)).first.click(timeout=TIMEOUT)


def digitar(page: Page, rotulo: str, valor: str) -> None:
    campo = page.get_by_label(rotulo).first
    campo.click(timeout=TIMEOUT)
    # Digita como uma pessoa (o Flutter só atualiza o campo com eventos de teclado reais).
    page.keyboard.press("Control+A")
    page.keyboard.press("Delete")
    page.keyboard.type(valor, delay=20)


def ok(nome: str) -> None:
    etapas.append(nome)
    print(f"  ok  {nome}", flush=True)


def abrir_site(page: Page) -> None:
    page.goto(BASE, wait_until="load", timeout=60_000)
    page.wait_for_selector("flt-glass-pane", state="attached", timeout=60_000)
    # Liga a acessibilidade do Flutter (botão invisível fora da tela).
    page.locator("flt-semantics-placeholder").dispatch_event("click")
    ver(page, "Entrar", 60_000)


def fluxo_paciente(page: Page) -> None:
    abrir_site(page)
    ok("site abre e mostra a tela de login")

    # Senha errada deve ser recusada com mensagem clara.
    digitar(page, "E-mail", "carlos@email.com")
    digitar(page, "Senha", "senha-errada")
    tocar(page, "Entrar")
    ver(page, "incorretos")
    ok("login com senha errada é recusado")

    # Login correto.
    digitar(page, "Senha", "123456")
    tocar(page, "Entrar")
    ver(page, "Buscar")
    ok("login do paciente entra no app")

    tocar(page, "Buscar")
    ver(page, "Dra. Helena Marques")
    ver(page, "Dr. Rafael Andrade")
    ok("aba Buscar lista os profissionais (vindos do servidor)")

    tocar(page, "Sessões")
    ver(page, "Minhas sessões")
    ok("aba Sessões abre")

    tocar(page, "Humor")
    ver(page, "Diário de humor")
    ok("aba Humor abre")

    tocar(page, "Perfil")
    ver(page, "Sair")
    ok("aba Perfil abre")
    assert page.locator('[aria-label*="Ver banco de dados"]').count() == 0, "inspetor SQLite não deve aparecer"
    ok("inspetor do SQLite local não aparece no modo servidor")

    tocar(page, "Sair")
    ver(page, "Criar uma conta")
    ok("sair volta para o login")


def fluxo_cadastro_e_profissional(page: Page) -> None:
    abrir_site(page)
    digitar(page, "E-mail", "helena@mentesaudavel.app")
    digitar(page, "Senha", "mente123")
    tocar(page, "Entrar")
    ver(page, "Painel do Profissional")
    ok("login do profissional abre o painel")
    ver(page, "avaliação média")
    ok("painel mostra a avaliação média")


def main() -> int:
    inicio = time.time()
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        for nome, fluxo in (("paciente", fluxo_paciente), ("profissional", fluxo_cadastro_e_profissional)):
            ctx = browser.new_context(ignore_https_errors=True, viewport={"width": 1100, "height": 800}, locale="pt-BR")
            page = ctx.new_page()
            erros_console: list[str] = []
            page.on("console", lambda m, e=erros_console: e.append(m.text) if m.type == "error" else None)
            print(f"== fluxo: {nome}", flush=True)
            try:
                fluxo(page)
            except (PWTimeout, AssertionError) as exc:
                page.screenshot(path=str(SHOTS / f"falha-{nome}.png"))
                arvore = page.evaluate("document.querySelector('flt-semantics-host')?.innerText || '(sem árvore de acessibilidade)'")
                print(f"::error title=E2E falhou no fluxo {nome}::{str(exc).splitlines()[0][:300]} | etapas ok: {len(etapas)} | tela: {str(arvore)[:600]!r} | console: {erros_console[:3]!r}")
                browser.close()
                return 1
            finally:
                ctx.close()
        browser.close()
    print(f"\nE2E ok: {len(etapas)} verificações em {time.time() - inicio:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
