# Relatório de status — Mente Saudável (01/11/2026)

Documento de passagem para qualquer pessoa ou assistente que continue o projeto. Repositório: `gomesjoaovitor622-svg/mente-saudavel`.
Branches: `dev` (trabalho) e `main` (estável). Fuso do sistema: horário de Brasília (`APP_TZ`).

## 1. Concluído
| Área | Situação | Onde |
|---|---|---|
| Backend modular | `main.py` 807 → ~130 linhas; `rotas/` (HTTP) + `servicos/` (regra) + `deps`/`saidas`/`erros`/`contexto`; contrato OpenAPI idêntico ao original | `server/app/`, `docs/ARQUITETURA-SERVIDOR.md` |
| Prontuário eletrônico | cifrado (Fernet, rotação de chaves), só o autor com vínculo lê/escreve, sem DELETE, revisões e trilha de acessos | `servicos/prontuario.py`, `rotas/profissional.py`, `docs/PRONTUARIO.md` |
| Autenticação | JWT com revogação (`token_versao`), cookie HttpOnly + CSRF na web, limites de tentativa, LGPD (exportar/anonimizar/aceite) | `deps.py`, `rotas/auth.py` |
| E-mail | código de 6 dígitos (HMAC, 15 min, 5 tentativas), recuperação de senha, confirmação de e-mail, SMTP opcional | `conta.py`, `emailer.py` |
| Aprovação de profissional | novo profissional fica "em análise" até `python -m app.admin aprovar EMAIL` | `admin.py`, migração 0004 |
| Videochamada | Jitsi com JWT (sala HMAC por sessão, janela de horário, moderador = profissional) | `video.py`, `docs/VIDEO.md` |
| Segurança na borda | 422 sem eco do valor, limite de corpo, NUL → 422, CORS sem `*`, 500 sem detalhes, `.env` validado por teste | `main.py`, `schemas.py`, `config.py` |
| Desempenho | N+1 removido (`lazy="joined"`), agregações no banco | `models.py`, `servicos/financeiro.py` |
| App Flutter | prontuário, botão de vídeo, avisos de e-mail/aprovação, recuperar senha, outbox offline resiliente, **sem** inspetor de banco, sem backup Android | `lib/` |
| Testes | backend 136 (SQLite) e 138 (PostgreSQL); Flutter no CI; widgets de vídeo/prontuário | `server/tests/`, `test/` |
| CI/CD | análise, testes, build do site, build do APK arm64, teste de implantação (Docker + navegador) | `.github/workflows/` |

## 2. Em execução / aberto no repositório
- PR `dev` → `main` com os commits desta rodada (testes, prontuário em camadas, docs).
- CodeQL / Dependency Review falham por **configuração do repositório** (ativar *Code scanning* e *Dependency graph* em Settings → Code security). Não é defeito de código.
- Atestado de procedência do APK é opcional (não bloqueia a publicação).

## 3. Falta para o lançamento oficial (nada disso é código)
1. **Servidor real**: VPS + domínio + `deploy/.env` (`POSTGRES_PASSWORD`, `JWT_SECRET`, `PRONTUARIO_KEYS`, `DOMAIN`, `SMTP_*`, `VIDEO_*`) e `docker compose -f docker-compose.prod.yml up -d`.
2. **Backup**: ensaio de restauração (`deploy/backup/ensaio-dr.sh`) e cópia **fora do servidor**; guardar `PRONTUARIO_KEYS` fora também.
3. **Jitsi próprio** (ou lançar sem vídeo com `VIDEO_DOMAIN` vazio) — testar com 2 aparelhos antes de ligar.
4. **SMTP** contratado e domínio com SPF/DKIM/DMARC.
5. **Revisão jurídica** dos Termos e da Política (dados de saúde; LGPD; guarda de prontuário) e subir `kVersaoTermos`.
6. **Chave de assinatura Android** e APK com `api_url` (`docs/RELEASE-MOBILE.md`).
7. **GitHub**: ativar code scanning/secret scanning, proteger `main`, revogar o token antigo colado no chat.
8. Teste com psicólogos reais (prontuário) e validação clínica/ética do fluxo.

## 4. Riscos conhecidos
- Sem servidor, o APK é **modo local**: cada celular tem seu banco; não existe paciente↔profissional, vídeo nem prontuário.
- Limites de tentativa são em memória (1 processo da API); se escalar para vários processos, mover para Redis/banco.
- Smoke E2E já teve 1 falha intermitente (fluxo de humor) que passou ao reexecutar; Playwright às vezes trava na instalação do navegador (reexecutar).
- Sem chave própria, o Android não atualiza o app por cima (desinstalar antes).

## 5. Comandos úteis
```bash
cd server && pytest -q                                   # SQLite
TEST_DATABASE_URL=postgresql+psycopg://USER@HOST/DB pytest -q   # PostgreSQL
ruff check . && ruff format --check . && mypy app
gh workflow run build-apk.yml --ref dev -f release=true -f demo=false -f api_url=https://SEU-DOMINIO/api
```
