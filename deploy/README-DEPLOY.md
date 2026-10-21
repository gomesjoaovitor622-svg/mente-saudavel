# Colocar o Mente Saudável no ar (servidor + site)

Arquitetura: **navegador/celular → Caddy (HTTPS) → API FastAPI → PostgreSQL**.
O site (Flutter web) e a API ficam no **mesmo domínio**: o site em `/`, a API em `/api`.

## O que você precisa
- Um servidor Linux (VPS) com **Docker** e **Docker Compose** (Ubuntu 22.04/24.04 serve).
- Um **domínio** apontando (registro `A`) para o IP do servidor. Portas **80 e 443** abertas.

## Passo a passo
1. **Baixe o projeto no servidor**
   ```bash
   git clone https://github.com/gomesjoaovitor622-svg/mente-saudavel.git /opt/mente-saudavel
   cd /opt/mente-saudavel/deploy
   ```
2. **Configure** (nunca suba o `.env` para o GitHub):
   ```bash
   cp .env.example .env
   nano .env        # DOMAIN, POSTGRES_PASSWORD e JWT_SECRET (openssl rand -hex 32)
   ```
3. **Suba tudo** (o próprio Docker compila o site Flutter; a 1ª vez leva ~5–10 min):
   ```bash
   docker compose up -d --build
   docker compose ps          # db, api e caddy devem estar "running/healthy"
   ```
4. **Teste:** abra `https://SEU_DOMINIO` (o certificado HTTPS é emitido sozinho) e `https://SEU_DOMINIO/api/health` → `{"status":"ok"}`.

## Rotina
| Tarefa | Comando |
|---|---|
| Ver logs | `docker compose logs -f api` |
| Atualizar a API | `git pull && docker compose up -d --build api` |
| Atualizar o site | `git pull && docker compose up -d --build site caddy` (recompila e republica) |
| **Backup** | `./backup.sh` (agende no cron: `0 3 * * * cd /opt/mente-saudavel/deploy && ./backup.sh`) |
| Restaurar | `gunzip -c backups/ARQUIVO.sql.gz \| docker compose exec -T db psql -U mente -d mente_saudavel` |

> **Teste os backups.** Um backup que nunca foi restaurado é só uma esperança. Copie os arquivos de `backups/` para fora do servidor.

## Dados de demonstração
`DEMO_SEED=true` no `.env` cria 3 profissionais e 1 paciente de exemplo (senhas conhecidas, públicas no código). **Use só para testar; em produção deixe `false`.**

## Variáveis (API)
| Variável | Descrição |
|---|---|
| `JWT_SECRET` | Obrigatória, 32+ caracteres. A API **recusa iniciar** sem ela (ou com valor fraco). |
| `DATABASE_URL` | Já montada no compose. Aceita também `sqlite:///caminho.db` (apenas testes). |
| `CORS_ORIGINS` | Origens permitidas, separadas por vírgula. Nunca `*`. |
| `TZ` | Fuso do servidor (padrão `America/Sao_Paulo`). Os horários das sessões são "horário local sem fuso". |
| `PASSWORD_MIN` | Tamanho mínimo da senha (padrão 8). |

## Problemas comuns
- **Site abre mas login falha / "Sem conexão com o servidor"**: o site é compilado com `API_URL=/api` pelo serviço `site` (`docker compose logs site`). Teste `/api/health`.
- **HTTPS não emite**: o domínio já aponta para o IP? Portas 80/443 liberadas no firewall do provedor? `docker compose logs caddy`.
- **API reinicia sem parar**: `docker compose logs api` — geralmente `JWT_SECRET` ausente/fraco.
- **Horário errado nas sessões**: ajuste `TZ` no `.env` e rode `docker compose up -d api`.

## Limitações conhecidas (leia antes de ir a produção real)
1. **Rate limit de login em memória** (por processo): serve para 1 instância. Com várias réplicas, use Redis ou limite no proxy.
2. **Cadastro de profissional é aberto**: qualquer pessoa pode informar um CRP. Falta verificar o CRP (manual ou integração com o conselho).
3. **LGPD**: dados de saúde mental são *dados sensíveis*. Antes de operar com pacientes reais: política de privacidade, termo de consentimento, DPO/encarregado, criptografia em repouso (disco do servidor/volume do banco), retenção e exclusão. A exclusão de conta já apaga tudo em cascata.
4. **Sessão no navegador**: agora é um cookie `HttpOnly` + `Secure` + `SameSite=Strict` (o JavaScript não lê o token) e as ações exigem o cabeçalho `X-Requested-With` (anti-CSRF). Requer que site e API estejam no MESMO domínio (como no Caddy deste projeto). Falta ainda uma CSP estrita (Content-Security-Policy), que precisa ser testada com o Flutter web antes de ativar. No celular o token fica no Android Keystore / iOS Keychain (`flutter_secure_storage`).
5. **Sem e-mail** (recuperar senha, confirmar cadastro) e **sem moderação** de avaliações.
6. **Imagens Docker** (`python`, `postgres`, `caddy`) usam tags, não digests. Em produção, fixe por digest e atualize regularmente.
7. **Videochamada**: o link Jitsi é derivado do ID da sessão (qualquer um com o link entra). Para sigilo clínico, use sala com senha/lobby.
8. **Fontes do Google**: o Flutter web baixa fontes de reserva (emoji e caracteres especiais) de `fonts.gstatic.com`. Isso expõe o IP do visitante ao Google (relevante para a LGPD). Correção futura: empacotar as fontes no app (`flutter: fonts:`) e compilar com as fontes locais. O teste de implantação lista os domínios externos como aviso.
