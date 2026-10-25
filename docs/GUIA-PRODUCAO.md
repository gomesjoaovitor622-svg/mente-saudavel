# Guia de produção: merge, smoke tests e governança

Repositório: `gomesjoaovitor622-svg/mente-saudavel`. Os comandos usam `R=gomesjoaovitor622-svg/mente-saudavel`.

## 1. Merge `dev` → `main` (seguro)

### 1.1 Antes: o que precisa estar verde
```bash
R=gomesjoaovitor622-svg/mente-saudavel
git fetch origin && git switch dev && git pull --ff-only origin dev
SHA=$(git rev-parse HEAD)

# PR aberto, sem conflito?
gh api repos/$R/pulls/7 -q '"state=\(.state) mergeable=\(.mergeable) estado=\(.mergeable_state)"'

# Checks do último commit (nenhum pode estar "failure", exceto o Dependency Review até o item 3.1)
gh api repos/$R/commits/$SHA/check-runs --paginate \
  -q '.check_runs[] | "\(.conclusion // .status)\t\(.name)"' | sort | uniq -c
```
Se algum check falhar, leia as anotações (os logs do Actions podem estar bloqueados):
```bash
gh api repos/$R/check-runs/<ID_DO_CHECK>/annotations -q '.[] | "\(.path):\(.start_line) \(.title) :: \(.message)"'
```
Testes locais rápidos (opcional): `cd server && pytest && ruff check . && mypy --strict app` e `flutter analyze && flutter test`.

### 1.2 O merge (API do GitHub)
Merge commit (preserva o histórico dos 16+ commits). Não use `gh pr merge`: ele usa GraphQL, que fica bloqueado em sessões do Claude Code.
```bash
gh api -X PUT repos/$R/pulls/7/merge \
  -f merge_method=merge \
  -f commit_title="Produção: CSP, PBKDF2, Riverpod, offline-first, LGPD, observabilidade e PWA (#7)"
```
O push na `main` aciona sozinho: Analisar código (Flutter), Servidor (API), API Validation, Security, CodeQL, Build APK e Teste de implantação.

### 1.3 Depois: acompanhar e sincronizar
```bash
gh run list --branch main --limit 10 --json name,status,conclusion,headSha \
  -q '.[] | "\(.name)\t\(.status)\t\(.conclusion)\t\(.headSha[:7])"'

git switch dev && git pull --ff-only origin main && git push origin dev   # dev volta a ser igual à main
```

### 1.4 Limpeza de branches
```bash
# Branches de logs criados por automação (ci-logs-*): já cumpriram o papel.
git push origin --delete ci-logs-analise ci-logs-api-validation

# Branch de trabalho antigo (confira antes: git log origin/main..origin/v2-app deve ficar vazio)
git push origin --delete v2-app

# Mantenha: main (produção) e dev (trabalho). As branches dependabot/* pertencem a PRs abertos (#1 a #6):
# revise cada PR (CI verde = merge); ao fechar o PR, o GitHub remove a branch.
```
Para o GitHub apagar a branch do PR sozinho depois de mesclar: Settings → General → "Automatically delete head branches" (mas não vale para `dev`, que é permanente: não use `dev` como head de PRs com essa opção ligada, ou recrie-a: `git push origin main:dev`).

### 1.5 Versão de produção (APK assinado e Release)
```bash
git switch main && git pull --ff-only origin main
git tag -a v1.0.0 -m "Mente Saudável 1.0.0" && git push origin v1.0.0
```
Tag `vX.Y.Z` = build de PRODUÇÃO (sem contas de demonstração) e Release com `MenteSaudavel.apk` + `.sha256`.
Pré-requisitos (Settings → Secrets and variables → Actions):
- Secrets de assinatura: `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Sem eles o APK sai com chave de TESTE (não atualiza por cima nem vai para a Play Store).
- Variable `API_URL` (ex.: `https://app.seudominio.com.br/api`). **Sem ela o APK roda em modo LOCAL** (SQLite no aparelho): fila offline, telemetria e cookie só existem no modo servidor.

### 1.6 Reverter (se algo der errado)
```bash
M=$(git log origin/main --merges -1 --format=%H)       # o merge do PR #7
git switch -c reverte-pr7 origin/main && git revert -m 1 $M && git push origin reverte-pr7
# abra um PR reverte-pr7 -> main (a API: gh api repos/$R/pulls -f base=main -f head=reverte-pr7 -f title="Reverter PR #7")
```
No servidor: `cd deploy && git pull && docker compose up -d --build` (o volume do banco não é apagado).

## 2. Smoke tests pós-deploy

### 2.1 APK de produção (aparelho real, Android 6.0+ = minSdk 23)
Antes de instalar:
- [ ] Baixe `MenteSaudavel.apk` e `.sha256` da Release e confira: `sha256sum -c MenteSaudavel.apk.sha256`.
- [ ] `aapt dump badging MenteSaudavel.apk | grep -E "sdkVersion|package:"` → `sdkVersion:'23'`.
- [ ] `apksigner verify --print-certs MenteSaudavel.apk` → SHA-256 do certificado = o da sua chave de produção.

No aparelho:
- [ ] Instala sem erro (permita "fontes desconhecidas" para o app usado). Se havia um APK antigo **com a mesma assinatura**, instale por cima e confira que contas e sessões continuaram (migração v2 → v3/v4).
- [ ] Primeira abertura: aparece a tela **"Sua privacidade importa"**; o botão fica desabilitado até marcar a caixa; os links abrem os Termos e a Política.
- [ ] Build de produção: **não** existem contas de demonstração (login `carlos@email.com` deve falhar).
- [ ] Cadastro com senha forte, login, sair e entrar de novo. Fechar e reabrir o app mantém o login.
- [ ] Agendar uma sessão; ela aparece em "Minhas sessões" sem recarregar à mão.
- [ ] Conflito: com 2 aparelhos (ou o site), agende o mesmo horário do mesmo profissional → o segundo vê a mensagem de horário ocupado e o horário some das opções.
- [ ] Só com `API_URL` (modo servidor): ligue o modo avião, agende → mensagem "guardado e será enviado"; desligue o modo avião → a sessão sincroniza sozinha, **uma só vez** (confira no site que não duplicou).
- [ ] Perfil → exportar meus dados; excluir/anonimizar conta (use uma conta de teste): o login deixa de funcionar e o e-mail some do banco.
- [ ] Logout: reabrir o app não mostra dados da conta anterior.

### 2.2 Site / PWA / CSP (Chrome, janela anônima)
Linha de comando:
```bash
D=https://app.seudominio.com.br
curl -sI $D/ | grep -iE "content-security-policy|strict-transport|cache-control|x-frame|x-content-type"
curl -s $D/manifest.json | python3 -m json.tool | head -30
curl -sI $D/icons/Icon-512.png | grep -iE "content-type|cache-control"      # image/png, max-age=86400
curl -s -o /dev/null -w "%{http_code}\n" $D/api/health                         # 200
curl -s -o /dev/null -w "%{http_code}\n" $D/api/docs                           # NÃO pode ser 200
curl -s -o /dev/null -w "%{http_code}\n" $D/api/sessoes                        # 401
```
No navegador (DevTools = F12):
- [ ] **Console sem** mensagens "Refused to load/execute … Content Security Policy" durante: abrir, aceitar termos, cadastrar, entrar, agendar.
- [ ] Application → **Manifest**: nome, ícones 192/512 (any e maskable) sem avisos; "Installability" sem erros.
- [ ] Ícone "Instalar" na barra de endereço; depois de instalado abre em janela própria (standalone) com a cor de tema verde.
- [ ] Application → **Cookies**: `ms_sessao` com `HttpOnly`, `Secure`, `SameSite=Strict`. No Console, `document.cookie` **não** mostra `ms_sessao`; Local Storage **sem** `ms_token`.
- [ ] Entrar, recarregar (F5): continua logado. Sair: recarregar volta ao login.
- [ ] Application → Service Workers: se estiver registrado, "Update on reload" desligado e a versão nova aparece após um deploy.
- [ ] Network: `index.html`, `manifest.json` e `flutter_service_worker.js` com `Cache-Control: no-cache`; ícones e `canvaskit` com `max-age=86400`.
- [ ] Lighthouse (aba Lighthouse, modo "Navigation") → PWA/Installable e Best Practices sem alertas de CSP ou HTTPS.
- [ ] Celular real, Chrome Android: "Adicionar à tela inicial" e abrir pelo ícone.
- [ ] Observabilidade: `docker compose logs api --tail 50` mostra linhas JSON com `request_id`; provoque um erro (ex.: login errado) e confira que **não** há senha, token nem e-mail completo no log.

## 3. Governança do repositório

### 3.1 Ativar o Dependency Graph (corrige o check "Dependency Review")
Esse check falha com "Dependency review is not supported on this repository". Ative:
1. GitHub → repositório → **Settings → Advanced Security** (ou "Code security").
2. **Dependency graph** → *Enable*.
3. Já aproveite: **Dependabot alerts** → Enable; **Dependabot security updates** → Enable; **Secret scanning** e **Push protection** → Enable; **Code scanning (CodeQL)** já roda pelo workflow `codeql.yml`.
4. Reexecute o check do PR: aba Actions → Dependency Review → *Re-run all jobs*.

### 3.2 Proteger a `main` (Settings → Rules → Rulesets → New branch ruleset → alvo: `main`)
- [ ] Require a pull request before merging (1 aprovação, se houver mais de uma pessoa).
- [ ] Require status checks to pass: **Analisar código (Flutter) / flutter analyze**, **Servidor (API)**, **Security Gate**, **CodeQL**, **Teste de implantação** (adicione o Dependency Review depois do item 3.1).
- [ ] Block force pushes e Restrict deletions.
- [ ] Require linear history **desligado** (usamos merge commit).

### 3.3 Rotina
- [ ] **Revogue o token do GitHub que foi colado no chat** (Settings → Developer settings → Personal access tokens). Para a sessão, use sempre o acesso por conexão do app, nunca o token no texto.
- [ ] Dependabot: revisar/mesclar os PRs #1 a #6 (atualizações de actions e do `ruff`); CI verde = pode mesclar.
- [ ] Segredos só em Settings → Secrets (nunca no código); o `detect-secrets` já bloqueia no CI (`.secrets.baseline`).
- [ ] Revisão jurídica dos Termos de Uso e da Política de Privacidade (`lib/legal/textos_legais.dart`) antes de comercializar: controlador, encarregado (DPO), prazos de retenção e CRP.
- [ ] Backup do PostgreSQL agendado (`pg_dump` do volume `dbdata`) e teste de restauração.
- [ ] `JWT_SECRET`, `POSTGRES_PASSWORD` e `METRICS_TOKEN` fortes e guardados em cofre; troque `JWT_SECRET` se vazar (derruba todas as sessões).
- [ ] Fontes do Flutter web: hoje vêm do Google Fonts (aviso do E2E, expõe o IP do visitante). Para eliminar, empacote as fontes `.ttf` no app.
- [ ] Verificação do CRP dos profissionais (hoje só o formato é validado) e fluxo de redefinição de senha por e-mail ainda não existem.
