"""Teste de ponta a ponta do SITE no navegador (Chromium), clicando nas telas de verdade.

Uso:  python tests/e2e/site_e2e.py https://localhost [pasta_de_capturas]

O Flutter web desenha em <canvas>; para o navegador "enxergar" botões e campos é preciso
ligar a árvore de acessibilidade (o mesmo que um leitor de tela faz). O teste faz isso.
Falhas viram anotações `::error::` no GitHub e deixam capturas de tela na pasta indicada.
"""

from __future__ import annotations

import datetime as dt
import json
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo

from playwright.sync_api import Page, sync_playwright
from playwright.sync_api import TimeoutError as PWTimeout

BASE = sys.argv[1] if len(sys.argv) > 1 else "https://localhost"
SHOTS = Path(sys.argv[2] if len(sys.argv) > 2 else "e2e-shots")
SHOTS.mkdir(parents=True, exist_ok=True)
TIMEOUT = 30_000
PERMITIDOS = {"localhost", "brasilapi.com.br", "viacep.com.br"}  # APIs públicas usadas de propósito pelo app
externos: set[str] = set()
etapas: list[str] = []


def HOJE() -> dt.date:
    return dt.datetime.now(ZoneInfo("America/Sao_Paulo")).date()



def ver(page: Page, texto: str, timeout: int = TIMEOUT) -> None:
    """Espera um texto/rótulo aparecer na tela (na árvore de acessibilidade)."""
    alvo = page.locator(f'[aria-label*="{texto}"], flt-semantics:has-text("{texto}")').first
    alvo.wait_for(state="attached", timeout=timeout)


def tocar(page: Page, rotulo: str) -> None:
    """Clica num botão/aba/chip pelo rótulo (aceita parte do texto)."""
    por_papel = (
        page.get_by_role("button", name=rotulo)
        .or_(page.get_by_role("tab", name=rotulo))
        .or_(page.get_by_role("radio", name=rotulo))
        .or_(page.get_by_role("checkbox", name=rotulo))
    )
    por_rotulo = page.locator(f'[aria-label*="{rotulo}"]')
    texto_exato = page.get_by_text(rotulo, exact=True)  # só folhas: nunca um contêiner inteiro
    # O Flutter troca de tela com animação: espera o botão aparecer (papel/rótulo) antes de cair no texto.
    fim = time.time() + TIMEOUT / 1000
    alvo = por_papel.first
    while time.time() < fim:
        achado = por_papel if por_papel.count() > 0 else (por_rotulo if por_rotulo.count() > 0 else None)
        if achado is None and time.time() > fim - 8 and texto_exato.count() > 0:
            achado = texto_exato
        if achado is not None:
            alvo = achado.first
            break
        page.wait_for_timeout(250)
    try:
        alvo.click(timeout=8_000)
    except PWTimeout:
        # Botões do Flutter às vezes ficam "instáveis" durante a animação de troca de tela:
        # tenta de novo forçando o clique e, por último, disparando o evento direto.
        print(f"  (clique normal em {rotulo!r} falhou — forçando)", flush=True)
        try:
            alvo.click(timeout=8_000, force=True)
        except PWTimeout:
            alvo.dispatch_event("click", timeout=8_000)


def digitar(page: Page, rotulo: str, valor: str) -> None:
    """Digita como uma pessoa e confere o que realmente entrou no campo (tenta de novo se falhar)."""
    campo = page.get_by_label(rotulo).first
    atual = None
    for _ in range(5):
        campo.click(timeout=TIMEOUT)
        page.wait_for_timeout(400)  # o Flutter cria o campo de edição de forma assíncrona
        page.keyboard.press("Control+A")
        page.keyboard.press("Delete")
        page.keyboard.type(valor, delay=30)
        page.wait_for_timeout(200)
        atual = page.evaluate("document.activeElement && document.activeElement.value")
        if atual == valor:
            return
    raise AssertionError(f"campo {rotulo!r}: digitado {len(valor)} caracteres, ficou com {len(atual or '')}")


def ok(nome: str) -> None:
    etapas.append(nome)
    print(f"  ok  {nome}", flush=True)


def abrir_site(page: Page) -> None:
    page.goto(BASE, wait_until="load", timeout=60_000)
    page.wait_for_selector("flt-glass-pane", state="attached", timeout=60_000)
    # Liga a acessibilidade do Flutter (botão invisível fora da tela).
    page.locator("flt-semantics-placeholder").dispatch_event("click")
    # LGPD: no primeiro acesso o aceite dos Termos e da Política é obrigatório, ANTES do login.
    ver(page, "Aceitar e continuar", 60_000)
    assert page.get_by_role("button", name="Aceitar e continuar").first.is_disabled(), "botão de aceite deveria começar desabilitado"
    tocar(page, "Li e aceito")
    tocar(page, "Aceitar e continuar")
    ver(page, "Entrar", 60_000)
    ok("primeiro acesso exige o aceite dos Termos e da Política (LGPD)")


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

    # Sessão por cookie HttpOnly: o JavaScript da página não enxerga o token e o login sobrevive ao recarregar.
    assert "ms_sessao" not in page.evaluate("document.cookie"), "cookie de sessão está legível pelo JavaScript"
    assert "ms_token" not in page.evaluate("JSON.stringify(localStorage)"), "token guardado no localStorage"
    page.reload(wait_until="load")
    page.wait_for_selector("flt-glass-pane", state="attached", timeout=60_000)
    page.locator("flt-semantics-placeholder").dispatch_event("click")
    ver(page, "Buscar", 60_000)
    ok("cookie HttpOnly mantém o login ao recarregar (sem token no JavaScript)")

    tocar(page, "Buscar")
    ver(page, "Dra. Helena Marques")
    ver(page, "Dr. Rafael Andrade")
    ver(page, "R$ 150,00 por sessão")
    ok("aba Buscar lista os profissionais com o preço da sessão (vindos do servidor)")

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
    ver(page, "Deseja sair da sua conta")
    # O diálogo de confirmação tem outro botão "Sair" (é o último da tela).
    page.get_by_role("button", name="Sair").last.click(timeout=TIMEOUT)
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
    ver(page, "recebido neste mês")
    ver(page, "a receber")
    ok("painel mostra o faturamento (recebido e a receber)")

    tocar(page, "Agenda")
    ver(page, "Nenhuma sessão neste dia")
    tocar(page, "Próximo dia")  # a sessão de demonstração está marcada para amanhã
    page.get_by_role("button", name=re.compile("Carlos")).first.click(timeout=TIMEOUT)
    ver(page, "Marcar como concluída")
    tocar(page, "Marcar como concluída")
    ver(page, "marcada como concluída")
    ok("profissional conclui uma sessão")


def entrar(page: Page, email: str, senha: str, aguardar: str) -> None:
    abrir_site(page)
    digitar(page, "E-mail", email)
    digitar(page, "Senha", senha)
    tocar(page, "Entrar")
    ver(page, aguardar)


def fluxo_acoes_paciente(page: Page) -> None:
    """Escreve no banco pelo navegador: humor, avaliação e agendamento."""
    entrar(page, "carlos@email.com", "123456", "Buscar")

    # --- registrar humor ---
    tocar(page, "Humor")
    ver(page, "Diário de humor")
    tocar(page, "😄")
    tocar(page, "Registrar humor")
    ver(page, "Humor registrado")
    ver(page, "Muito bem")
    ok("registrar humor grava e aparece no histórico")

    # --- avaliar uma sessão concluída ---
    tocar(page, "Sessões")
    ver(page, "Minhas sessões")
    tocar(page, "Concluídas")
    page.get_by_role("button", name=re.compile("Helena")).first.click(timeout=TIMEOUT)
    ver(page, "Avaliar atendimento")
    tocar(page, "Avaliar atendimento")
    ver(page, "Avaliar Dra")
    tocar(page, "5 estrelas")
    tocar(page, "Enviar")
    ver(page, "Avaliação enviada")
    ok("avaliar sessão concluída (5 estrelas)")

    # --- agendar uma nova sessão (amanhã) ---
    tocar(page, "Todas")
    tocar(page, "Agendar")
    ver(page, "Agendar sessão")
    tocar(page, "Dr. Rafael Andrade")
    tocar(page, "Escolher data")
    amanha = HOJE() + dt.timedelta(days=1)
    if amanha.month != HOJE().month:
        tocar(page, "Próximo mês")
    page.get_by_role("button", name=re.compile(rf"^{amanha.day}\b")).first.click(timeout=TIMEOUT)
    tocar(page, "OK")
    ver(page, "10:00")
    tocar(page, "10:00")
    tocar(page, "Confirmar agendamento")
    ver(page, "Sessão agendada com sucesso")
    ver(page, "Rafael Andrade")
    ok("agendar nova sessão aparece na lista")

    # --- cancelar a sessão recém-criada ---
    page.get_by_role("button", name=re.compile("Rafael Andrade")).first.click(timeout=TIMEOUT)
    ver(page, "Remarcar")
    tocar(page, "Cancelar sessão")
    ver(page, "Deseja realmente cancelar")
    page.get_by_role("button", name="Cancelar sessão").last.click(timeout=TIMEOUT)
    ver(page, "Sessão cancelada")
    ok("cancelar sessão")


def api(metodo: str, caminho: str, corpo: dict | None = None, token: str | None = None) -> tuple[int, dict | list | None]:
    """Chama a API direto (como outro usuário, em paralelo ao navegador)."""
    cab = {"Content-Type": "application/json"}
    if token:
        cab["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(f"{BASE}/api{caminho}", method=metodo, headers=cab, data=json.dumps(corpo).encode() if corpo is not None else None)
    try:
        with urllib.request.urlopen(req, context=ssl._create_unverified_context(), timeout=20) as r:  # noqa: S310 (certificado de teste do Caddy)
            texto = r.read().decode()
            return r.status, json.loads(texto) if texto else None
    except urllib.error.HTTPError as e:
        texto = e.read().decode()
        return e.code, json.loads(texto) if texto else None


def fluxo_conflito(page: Page) -> None:
    """Conflito de horário (HTTP 409): outra pessoa pega o horário enquanto o paciente está na tela."""
    abrir_site(page)
    digitar(page, "E-mail", "carlos@email.com")
    digitar(page, "Senha", "123456")
    tocar(page, "Entrar")
    ver(page, "Buscar")
    tocar(page, "Sessões")
    tocar(page, "Agendar")
    ver(page, "Agendar sessão")
    tocar(page, "Dr. Rafael Andrade")
    tocar(page, "Escolher data")
    dia = HOJE() + dt.timedelta(days=2)
    if dia.month != HOJE().month:
        tocar(page, "Próximo mês")
    page.get_by_role("button", name=re.compile(rf"^{dia.day}\b")).first.click(timeout=TIMEOUT)
    tocar(page, "OK")
    ver(page, "14:00")
    tocar(page, "14:00")
    ok("paciente escolheu o horário das 14:00")

    # Enquanto a tela está aberta, outra pessoa agenda o MESMO horário com o mesmo profissional.
    email = f"rival{int(time.time())}@teste.com"
    status, _ = api("POST", "/auth/cadastro", {"nome": "Rival Teste", "email": email, "senha": "senhasegura1", "perfil": "paciente", "aceite_termos_versao": "teste"})
    assert status == 201, f"cadastro do rival: HTTP {status}"
    _, login = api("POST", "/auth/entrar", {"email": email, "senha": "senhasegura1"})
    token = login["token"]  # type: ignore[index]
    _, profissionais = api("GET", "/profissionais", token=token)
    rafael = next(p for p in profissionais if "Rafael" in p["nome"])  # type: ignore[union-attr]
    status, _ = api("POST", "/sessoes", {"profissional_id": rafael["id"], "data_hora": f"{dia.isoformat()}T14:00:00", "modalidade": "Online"}, token)
    assert status == 201, f"rival não conseguiu agendar: HTTP {status}"
    ok("outra pessoa ocupou o mesmo horário (pela API)")

    tocar(page, "Confirmar agendamento")
    ver(page, "já tem uma sessão")  # mensagem do HTTP 409, mostrada pelo app
    ok("conflito 409: o app avisa que o horário foi ocupado")
    assert "Sessão agendada com sucesso" not in page.evaluate("document.querySelector('flt-semantics-host')?.innerText || ''"), "agendou mesmo com conflito"

    # O horário ocupado some das opções e outro horário funciona.
    tocar(page, "15:00")
    tocar(page, "Confirmar agendamento")
    ver(page, "Sessão agendada com sucesso")
    ok("depois do conflito, outro horário é agendado e a lista atualiza")


def fluxo_cadastro_novo(page: Page) -> None:
    """Cria uma conta de paciente pelo site, usa o app e exclui a conta."""
    email = f"e2e{int(time.time())}@teste.com"
    abrir_site(page)
    tocar(page, "Criar uma conta")
    digitar(page, "E-mail", email)
    digitar(page, "Senha", "senhasegura1")
    tocar(page, "Continuar")
    digitar(page, "Seu nome", "Pessoa de Teste")
    tocar(page, "Continuar")
    tocar(page, "Paciente")
    ver(page, "Buscar")
    ok("cadastro de nova conta de paciente entra no app")
    tocar(page, "Perfil")
    ver(page, email)  # o nome fica dentro de um campo de texto (sem rótulo); o e-mail aparece como texto
    ok("perfil mostra os dados da conta cadastrada")
    tocar(page, "Excluir minha conta")
    ver(page, "não pode ser desfeita")
    page.get_by_role("button", name="Excluir conta").last.click(timeout=TIMEOUT)
    ver(page, "Criar uma conta")
    ok("excluir a própria conta volta ao login")


def fluxo_celular(page: Page) -> None:
    """Tela de celular (390x844, toque): login, abas e agendamento cabem na tela."""
    entrar(page, "carlos@email.com", "123456", "Buscar")
    for aba, texto in (("Buscar", "Profissionais"), ("Sessões", "Minhas sessões"), ("Humor", "Diário de humor"), ("Perfil", "Sair")):
        tocar(page, aba)
        ver(page, texto)
        page.screenshot(path=str(SHOTS / f"celular-{aba}.png"))
    largura = page.evaluate("document.documentElement.scrollWidth")
    assert largura <= 390 + 1, f"rolagem horizontal no celular (largura {largura})"
    ok("celular: login e as 4 abas funcionam sem rolagem horizontal")
    tocar(page, "Sessões")
    tocar(page, "Agendar")
    ver(page, "Agendar sessão")
    page.screenshot(path=str(SHOTS / "celular-agendar.png"))
    ok("celular: tela de agendamento abre")


def main() -> int:
    inicio = time.time()
    falhas: list[str] = []
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        fluxos = (
            ("paciente", fluxo_paciente, False),
            ("profissional", fluxo_cadastro_e_profissional, False),
            ("acoes", fluxo_acoes_paciente, False),
            ("cadastro", fluxo_cadastro_novo, False),
            ("conflito", fluxo_conflito, False),
            ("celular", fluxo_celular, True),
        )
        for nome, fluxo, celular in fluxos:
            opcoes: dict = {"ignore_https_errors": True, "locale": "pt-BR", "timezone_id": "America/Sao_Paulo"}
            if celular:
                opcoes.update(viewport={"width": 390, "height": 844}, device_scale_factor=2, is_mobile=True, has_touch=True)
            else:
                opcoes.update(viewport={"width": 1100, "height": 800})
            ctx = browser.new_context(**opcoes)
            # Registra qualquer bloqueio da Política de Segurança de Conteúdo (CSP) da página.
            ctx.add_init_script(
                "window.__csp = []; document.addEventListener('securitypolicyviolation', e => "
                "window.__csp.push(e.violatedDirective + ' <- ' + (e.blockedURI || 'inline')));"
            )
            page = ctx.new_page()
            erros_console: list[str] = []
            page.on(
                "request",
                lambda r, e=erros_console: e.append(f"REQ {r.method} {r.url.split('/api')[-1]} {r.post_data_json.get('email') if r.post_data and r.url.endswith('/auth/entrar') else ''}")
                if "/auth/entrar" in r.url
                else None,
            )
            page.on("request", lambda r: externos.add(urlsplit(r.url).hostname or "") if urlsplit(r.url).scheme in ("http", "https") else None)
            page.on("console", lambda m, e=erros_console: e.append(m.text) if m.type == "error" else None)
            print(f"== fluxo: {nome}", flush=True)
            try:
                fluxo(page)
                violacoes = page.evaluate("window.__csp || []")
                assert not violacoes, f"CSP bloqueou recursos: {sorted(set(violacoes))[:8]}"
                ok(f"nenhuma violação de CSP no fluxo {nome}")
            except (PWTimeout, AssertionError) as exc:
                page.screenshot(path=str(SHOTS / f"falha-{nome}.png"))
                arvore = page.evaluate("document.querySelector('flt-semantics-host')?.innerText || '(sem árvore de acessibilidade)'")
                html = page.evaluate("(document.querySelector('flt-semantics-host')?.innerHTML || '').slice(0, 700)")
                print(f"::error title=E2E falhou no fluxo {nome}::{str(exc).splitlines()[0][:300]} | etapas ok: {len(etapas)} | tela: {str(arvore)[:600]!r} | html: {html!r} | console: {erros_console[:6]!r}")
                falhas.append(nome)
            finally:
                ctx.close()
        browser.close()
    indevidos = sorted(h for h in externos if h not in PERMITIDOS)
    if indevidos:
        # Aviso, não reprovação: o Flutter web baixa fontes de reserva (texto/emoji) do Google Fonts.
        # Isso expõe o IP do visitante ao Google; a correção é empacotar as fontes (veja README-DEPLOY).
        print(f"::warning title=Site chama servidores externos::{indevidos}")
    if falhas:
        print(f"\nE2E FALHOU nos fluxos: {', '.join(falhas)}")
        return 1
    print(f"\nE2E ok: {len(etapas)} verificações em {time.time() - inicio:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
