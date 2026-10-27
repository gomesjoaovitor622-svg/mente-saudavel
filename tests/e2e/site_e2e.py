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


def ver_ou_aceitar(page: Page, esperado: str, timeout: int = 30_000) -> None:
    """Espera `esperado` na tela. Contas sem aceite gravado (ex.: as de demonstração) veem antes a tela
    de aceite dos Termos: aceita e segue, como uma pessoa faria (LGPD: o aceite é por conta)."""
    fim = time.time() + timeout / 1000
    aceitou = False
    while time.time() < fim:
        if page.locator(f'[aria-label*="{esperado}"], flt-semantics:has-text("{esperado}")').count() > 0:
            return
        if not aceitou and page.locator('[aria-label*="Aceitar e continuar"], flt-semantics:has-text("Aceitar e continuar")').count() > 0:
            tocar(page, "Li e aceito")
            tocar(page, "Aceitar e continuar")
            aceitou = True
            ok("conta sem aceite registrado pede o aceite após o login (LGPD)")
        page.wait_for_timeout(500)
    ver(page, esperado, 2_000)  # estoura com a mensagem padrão de timeout


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
    ver_ou_aceitar(page, "Buscar")
    ok("login do paciente entra no app")

    # Sessão por cookie HttpOnly: o JavaScript da página não enxerga o token e o login sobrevive ao recarregar.
    assert "ms_sessao" not in page.evaluate("document.cookie"), "cookie de sessão está legível pelo JavaScript"
    assert "ms_token" not in page.evaluate("JSON.stringify(localStorage)"), "token guardado no localStorage"
    page.reload(wait_until="load")
    page.wait_for_selector("flt-glass-pane", state="attached", timeout=60_000)
    page.locator("flt-semantics-placeholder").dispatch_event("click")
    ver(page, "Buscar", 60_000)
    ok("cookie HttpOnly mantém o login ao recarregar (sem token no JavaScript)")
    registrou = False
    for _ in range(20):  # o Service Worker do Flutter registra logo após o carregamento
        registrou = page.evaluate("navigator.serviceWorker ? navigator.serviceWorker.getRegistration().then(r => !!r) : false")
        if registrou:
            break
        page.wait_for_timeout(1000)
    if registrou:
        ok("Service Worker registrado (PWA com cache offline)")
    else:
        # Aviso, não reprovação: versões novas do Flutter estão aposentando o Service Worker padrão, e o
        # app continua instalável (manifest + HTTPS). O cache offline dos dados é feito pelo Outbox/cache local.
        print("::warning title=PWA::Service Worker não registrado: sem cache offline dos arquivos do site")

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
    ver_ou_aceitar(page, "Painel do Profissional")
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
    ver_ou_aceitar(page, aguardar)


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


def baixar(caminho: str) -> tuple[int, dict[str, str], bytes]:
    """GET direto no site (sem navegador): status, cabeçalhos (minúsculos) e corpo."""
    req = urllib.request.Request(f"{BASE}{caminho}")
    with urllib.request.urlopen(req, context=ssl._create_unverified_context(), timeout=20) as r:  # noqa: S310
        return r.status, {k.lower(): v for k, v in r.headers.items()}, r.read()


def verificar_pwa() -> None:
    """PWA instalável: manifest válido, ícones, metadados, cache correto."""
    _, _, corpo = baixar("/")
    html = corpo.decode()
    for trecho in ('<html lang="pt-BR"', 'rel="manifest"', 'name="theme-color"', 'name="description"', 'property="og:title"', 'rel="apple-touch-icon"'):
        assert trecho in html, f"index.html sem {trecho}"
    assert "A new Flutter project" not in html, "descrição padrão do Flutter ainda no index.html"

    status, cab, corpo = baixar("/manifest.json")
    assert status == 200 and "json" in cab.get("content-type", ""), f"manifest.json: HTTP {status} {cab.get('content-type')}"
    m = json.loads(corpo)
    assert m["display"] in ("standalone", "fullscreen", "minimal-ui"), m["display"]
    assert m["start_url"] and m["name"] and m["short_name"] and m["theme_color"] and m["background_color"], "manifest incompleto"
    tamanhos = {(i["sizes"], i.get("purpose", "any")) for i in m["icons"]}
    for exigido in (("192x192", "any"), ("512x512", "any"), ("512x512", "maskable")):
        assert exigido in tamanhos, f"manifest sem o ícone {exigido}"
    for icone in m["icons"]:
        st, cab_i, dados = baixar("/" + icone["src"])
        assert st == 200 and cab_i.get("content-type") == "image/png" and dados[:8] == b"\x89PNG\r\n\x1a\n", f"ícone inválido: {icone['src']}"
    ok("PWA: manifest válido, ícones 192/512 (any e maskable) e metadados no index.html")

    # Cache: entrada e service worker sempre revalidam; CanvasKit e ícones ficam em cache.
    for caminho in ("/", "/flutter_service_worker.js", "/manifest.json"):
        cab_c = baixar(caminho)[1]
        assert "no-cache" in cab_c.get("cache-control", ""), f"{caminho}: Cache-Control={cab_c.get('cache-control')!r} (esperado no-cache)"
    cab_i = baixar("/icons/Icon-192.png")[1]
    assert "max-age=86400" in cab_i.get("cache-control", ""), f"ícone sem cache longo: {cab_i.get('cache-control')!r}"
    ok("PWA: cache correto (entrada e service worker revalidam; ícones em cache)")


def fluxo_conflito(page: Page) -> None:
    """Conflito de horário (HTTP 409): outra pessoa pega o horário enquanto o paciente está na tela."""
    abrir_site(page)
    digitar(page, "E-mail", "carlos@email.com")
    digitar(page, "Senha", "123456")
    tocar(page, "Entrar")
    ver_ou_aceitar(page, "Buscar")
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
    ver_ou_aceitar(page, "Buscar")
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


# ------------------------------------------------------------------ vídeo e prontuário (API + navegador)
VIDEO_DOMINIO = "video.exemplo.test"  # o mesmo VIDEO_DOMAIN que o workflow grava no .env de teste
sessao_video: dict[str, int] = {}


def entrar_api(email: str, senha: str) -> str:
    status, dados = api("POST", "/auth/entrar", {"email": email, "senha": senha})
    assert status == 200 and isinstance(dados, dict), f"login por API de {email}: HTTP {status}"
    return str(dados["token"])


def agora_sp() -> dt.datetime:
    return dt.datetime.now(ZoneInfo("America/Sao_Paulo")).replace(tzinfo=None, second=0, microsecond=0)


def verificar_video_e_prontuario_api() -> None:
    """Contrato das duas APIs pela pilha real (Caddy -> API -> PostgreSQL), sem navegador."""
    carlos = entrar_api("carlos@email.com", "123456")
    helena = entrar_api("helena@mentesaudavel.app", "mente123")
    status, profs = api("GET", "/profissionais", token=carlos)
    assert status == 200 and isinstance(profs, list)
    helena_id = next(p["id"] for p in profs if "Helena" in p["nome"])

    # --- vídeo: sessão online que começa em 10 min (dentro da janela de 15 min antes) ---
    quando = agora_sp() + dt.timedelta(minutes=10)
    status, sessao = api("POST", "/sessoes", {"profissional_id": helena_id, "data_hora": quando.isoformat(), "modalidade": "Online"}, carlos)
    assert status == 201 and isinstance(sessao, dict), f"agendar sessão de vídeo: HTTP {status} {sessao}"
    sid = int(sessao["id"])
    sessao_video["id"] = sid
    sessao_video["dia"] = quando.day

    status, sala = api("GET", f"/sessoes/{sid}/video", token=carlos)
    assert status == 200 and isinstance(sala, dict), f"sala de vídeo do paciente: HTTP {status} {sala}"
    assert sala["url"].startswith(f"https://{VIDEO_DOMINIO}/ms-") and "jwt=" in sala["url"], "link de vídeo fora do formato"
    assert sala["moderador"] is False
    status, sala_pro = api("GET", f"/sessoes/{sid}/video", token=helena)
    assert status == 200 and isinstance(sala_pro, dict) and sala_pro["moderador"] is True and sala_pro["sala"] == sala["sala"]
    ok("API de vídeo: paciente e profissional recebem a mesma sala (profissional é moderador)")

    cadastro = {"nome": "Outro Profissional", "email": f"outro-{int(time.time())}@teste.com", "senha": "senha-forte-1", "perfil": "profissional", "registro": "06/99999"}
    status, novo = api("POST", "/auth/cadastro", cadastro)
    assert status == 201 and isinstance(novo, dict)
    estranho = str(novo["token"])
    assert api("GET", f"/sessoes/{sid}/video", token=estranho)[0] == 404, "quem não participa da sessão não pode receber a sala"
    assert api("GET", f"/sessoes/{sid}/video")[0] == 401, "sem login não há sala"
    ok("API de vídeo: estranho recebe 404 e visitante 401")

    # --- prontuário: só o profissional com vínculo ---
    status, pacientes = api("GET", "/profissional/pacientes", token=helena)
    assert status == 200 and isinstance(pacientes, list)
    carlos_id = next(p["id"] for p in pacientes if "Carlos" in p["nome"])
    base = f"/profissional/pacientes/{carlos_id}/prontuario"
    status, e1 = api("POST", base, {"tipo": "evolucao", "conteudo": "Registro E2E: paciente relata melhora do sono."}, helena)
    assert status == 201 and isinstance(e1, dict) and e1["versao"] == 1, f"criar prontuário: HTTP {status} {e1}"
    status, e2 = api("PATCH", f"/profissional/prontuario/{e1['id']}", {"conteudo": "Registro E2E (revisado).", "versao_esperada": 1}, helena)
    assert status == 200 and isinstance(e2, dict) and e2["versao"] == 2
    assert api("PATCH", f"/profissional/prontuario/{e1['id']}", {"conteudo": "x", "versao_esperada": 1}, helena)[0] == 409, "versão antiga deveria dar conflito"
    status, revs = api("GET", f"/profissional/prontuario/{e1['id']}/revisoes", token=helena)
    assert status == 200 and isinstance(revs, list) and revs[0]["conteudo"].startswith("Registro E2E: paciente")
    status, acessos = api("GET", f"{base}/acessos", token=helena)
    assert status == 200 and isinstance(acessos, list) and {a["acao"] for a in acessos} >= {"criacao", "edicao"}
    ok("API de prontuário: criar, editar com versão, conflito 409, revisões e auditoria")

    assert api("GET", base, token=carlos)[0] == 403, "paciente não pode ler prontuário"
    assert api("GET", base, token=estranho)[0] == 404, "profissional sem vínculo não pode ler prontuário"
    assert api("GET", base)[0] == 401
    ok("API de prontuário: paciente 403, profissional sem vínculo 404, visitante 401")


def fluxo_video_web(page: Page) -> None:
    """No site: o profissional abre a sessão online e o botão pede o link ao servidor e o abre numa nova aba."""
    # A API é verificada AQUI (e não no início) porque ela cria uma sessão para hoje, e os fluxos
    # anteriores esperam a agenda de hoje vazia.
    try:
        verificar_video_e_prontuario_api()
    except (KeyError, StopIteration, ValueError, urllib.error.URLError) as exc:
        raise AssertionError(f"API de vídeo/prontuário: {exc!r}") from exc
    page.context.route(f"**/{VIDEO_DOMINIO}/**", lambda rota: rota.fulfill(status=200, content_type="text/html", body="<html>sala de teste</html>"))
    entrar(page, "helena@mentesaudavel.app", "mente123", "Painel do Profissional")
    tocar(page, "Agenda")
    if sessao_video["dia"] != HOJE().day:
        tocar(page, "Próximo dia")  # o teste rodou perto da meia-noite
    page.get_by_role("button", name=re.compile("Carlos")).first.click(timeout=TIMEOUT)
    ver(page, "Entrar na videochamada")
    ok("web: sessão online mostra o botão \"Entrar na videochamada\"")
    with page.context.expect_page(timeout=TIMEOUT) as nova_aba:
        tocar(page, "Entrar na videochamada")
    aba = nova_aba.value
    aba.wait_for_load_state("domcontentloaded", timeout=TIMEOUT)
    assert VIDEO_DOMINIO in aba.url and "/ms-" in aba.url and "jwt=" in aba.url, f"a aba abriu {aba.url[:80]!r}"
    ok("web: o botão abre o link com token emitido pelo servidor")
    aba.close()


def fluxo_prontuario_web(page: Page) -> None:
    """No site: o profissional abre o prontuário de um paciente, cria um registro e o vê na lista."""
    entrar(page, "helena@mentesaudavel.app", "mente123", "Painel do Profissional")
    tocar(page, "Pacientes")
    ver(page, "Buscar paciente")
    page.get_by_role("button", name=re.compile("Carlos")).first.click(timeout=TIMEOUT)
    ver(page, "Prontuário")
    tocar(page, "Prontuário")
    ver(page, "Só você vê estes registros")
    ok("web: ícone Prontuário abre a tela com o aviso de sigilo")
    ver(page, "Registro E2E (revisado)")  # criado pela API na etapa anterior: a tela lista o que o servidor decifrou
    ok("web: a tela lista o registro cifrado no servidor (versão revisada)")
    tocar(page, "Novo registro")
    ver(page, "Registro clínico")
    digitar(page, "Registro clínico", "Registro pela tela do site.")
    tocar(page, "Salvar")
    ver(page, "Registro salvo")
    ver(page, "Registro pela tela do site.")
    ok("web: criar registro pela tela grava e aparece na lista")


def main() -> int:
    inicio = time.time()
    falhas: list[str] = []
    with sync_playwright() as pw:
        try:
            verificar_pwa()
        except (AssertionError, urllib.error.URLError, KeyError, ValueError) as exc:
            print(f"::error title=PWA::{exc}")
            falhas.append("pwa")
        browser = pw.chromium.launch()
        fluxos = (
            ("paciente", fluxo_paciente, False),
            ("profissional", fluxo_cadastro_e_profissional, False),
            ("acoes", fluxo_acoes_paciente, False),
            ("cadastro", fluxo_cadastro_novo, False),
            ("conflito", fluxo_conflito, False),
            ("celular", fluxo_celular, True),
            ("video-web", fluxo_video_web, False),
            ("prontuario-web", fluxo_prontuario_web, False),
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
