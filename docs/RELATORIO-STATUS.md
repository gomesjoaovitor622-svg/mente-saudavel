# Relatório de status — Mente Saudável (para o Gemini)

Data: 2026-10-26 · Branch `dev` → PR #9 para `main` · Repositório `gomesjoaovitor622-svg/mente-saudavel`

## 1. Implementado e pronto
- **App Flutter** (Android + Web/PWA): arquitetura limpa (`SessaoRepository`: local SQLite, remoto, offline), Riverpod nas telas de sessões/painel/perfil, PBKDF2-HMAC-SHA256 100k (hashes antigos migram no login), tokens em armazenamento seguro, Outbox offline com `Idempotency-Key`, cache offline, LGPD (consentimento, exportar, anonimizar), telemetria sem dados pessoais.
- **API FastAPI**: JWT + cookie `ms_sessao` (HttpOnly, Secure, SameSite=Strict, exige `X-Requested-With`), rate limits, logs JSON com request id, `/metricas` com token, 409 em conflito de horário, idempotência por `(paciente_id, chave)`.
- **PostgreSQL**: DDL em `docs/sql/schema_postgres.sql` (gerado do Alembic) com índices parciais `uq_sessao_prof_horario`, `uq_sessao_pac_horario` (`WHERE status <> 'cancelada'`) e `uq_sessao_idempotencia`.
- **Migrações Alembic** (`server/migrations`, baseline `0001`): `SCHEMA_MODE=alembic` em produção — a API não altera o esquema e recusa subir se o banco não estiver no `head`. Teste garante migrações == models.
- **Concorrência/idempotência**: testes com 8 requisições simultâneas no mesmo horário (1×201, 7×409) e 6 reenvios paralelos da mesma chave (1×201, resto 200). O teste achou e corrigiu um bug real (reenvio caía em 409).
- **Produção**: `deploy/docker-compose.prod.yml` (db com tuning e volume, `migrate` one-shot, api read-only/cap_drop, site Flutter, Caddy com HTTPS automático, HSTS, CSP estrita, backup agendado).
- **Backup**: `deploy/backup/` — `pg_dump -Fc -Z9`, verificação com `pg_restore --list`, sha256, rotação 7 diários/4 semanais/12 mensais, script de restauração, teste automatizado.

## 2. Testes e CI/CD (commit mais recente de `dev`)
- Servidor: 57 testes em SQLite + 59 em PostgreSQL 16 (inclui corrida real, migrações). Ruff, mypy `--strict`, pip-audit limpos.
- Verdes no CI: Quality, Reference py3.11/3.12/3.13, Testes (SQLite + PostgreSQL), Imagem Docker, Supply chain (CVE/SBOM/segredos), Auditoria dos workflows, flutter analyze, **Teste de implantação** (pilha completa com `migrate` + Playwright E2E), Gate/Security Gate.
- Com falha por **configuração do repositório** (não por código): CodeQL ("Code scanning is not enabled"), Dependency Review (Dependency graph desligado), atestado de build (recurso indisponível em repositório privado de usuário).
- Build APK: em andamento no momento da escrita; verificar na aba Actions.

## 3. Pendente / atenção antes do lançamento oficial
1. Habilitar no GitHub: Dependency graph, code scanning (ou tornar o repo público), Dependabot alerts, secret scanning. Triar os PRs do Dependabot #1–#6.
2. **Deploy real ainda não feito**: o compose só foi validado no CI. Falta VPS, domínio (DNS A/AAAA), `.env` real (`POSTGRES_PASSWORD`, `JWT_SECRET`, `METRICS_TOKEN`, `DEMO_SEED=false`), firewall 80/443.
3. **Backup**: copiar `deploy/backups/` para fora do servidor e ensaiar uma restauração antes do lançamento.
4. APK sem a variável de repositório `API_URL` roda em modo local; definir `API_URL` e os segredos do keystore; testar em aparelho real (nunca testado em celular físico).
5. Textos legais (termos/privacidade) são modelos: precisam de revisão jurídica. CRP só tem validação de formato.
6. Sem recuperação de senha por e-mail; login Google/Apple não implementado.
7. Service Worker não é registrado por este SDK Flutter (PWA instalável, porém sem cache offline do shell); fontes vêm de `fonts.gstatic.com` (chamada externa).
8. Telas Agenda, Pacientes, Início, Profissionais e Humor ainda usam `setState` (sem Riverpod/testes de widget).
9. Higiene: apagar branches `ci-logs-analise`, `ci-logs-api-validation`, `v2-app`; revogar o token do GitHub colado no chat no início do projeto.
10. Banco já existente criado sem Alembic: rodar `alembic stamp 0001` antes do primeiro `up` em produção.
