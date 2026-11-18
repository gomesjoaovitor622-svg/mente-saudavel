# Relatório executivo — endurecimento final (03/11/2026)

Base: `main` @ `227642e` (auditoria de 03/11). Branch de trabalho: `dev`. Repositório: `gomesjoaovitor622-svg/mente-saudavel`.

## 1. Corrigido nesta rodada
| # | Achado da auditoria | Correção | Onde |
|---|---|---|---|
| 2.1 | "Sair" não revogava o token (Bearer do celular valia até 7 dias) | `/auth/sair` sobe `token_versao` e apaga o cookie: token antigo e outros aparelhos dão **401**. Sem sessão válida (expirada, ou cookie sem o cabeçalho anti-CSRF) só limpa o cookie e responde 204, então sair nunca falha e um site de fora não consegue deslogar ninguém | `server/app/rotas/auth.py` |
| 2.2 | TTL de 7 dias | padrão **24 h** (`JWT_TTL_HOURS`) no código, no `.env.example` e no compose | `config.py`, `deploy/` |
| 1.3 / 1.7 | IP lido em 5 pontos com chave `"?"`; Uvicorn confiava em `X-Forwarded-For` de qualquer origem (`*`) | `ip_do_cliente(request)` único em `deps.py` (chave fixa `desconhecido`); Uvicorn lê `FORWARDED_ALLOW_IPS`: padrão da imagem `127.0.0.1`, produção = IP fixo do Caddy `172.31.250.10` | `deps.py`, `Dockerfile`, `docker-compose.prod.yml` |
| 1.5 | Itens do outbox que estouraram 20 tentativas ficavam "falhou" sem a pessoa saber nem reenviar | tela **Pendências de envio** (aguardando / com falha / precisam de decisão) com Reenviar, Reenviar todas e Descartar (com confirmação); acessível pelo aviso da aba Sessões e pelo Perfil (com contador). `SincronizadorOutbox.reenviar()` reativa só itens `falhou`, zera tentativas e mantém a **mesma chave de idempotência** | `lib/screens/pendencias_screen.dart`, `sincronizador_outbox.dart`, `outbox_repository.dart` |
| 3.4 | Release podia sair com assinatura de teste | `build-apk.yml` falha **antes de compilar** se `release=true`/tag `v*` e faltar qualquer `ANDROID_KEYSTORE_*`/`ANDROID_KEY_*`; segunda trava no passo de assinatura | `.github/workflows/build-apk.yml` |
| 3.1 / 3.2 | mypy permissivo; Ruff sem regras de qualidade | mypy `disallow_untyped_defs` (+ `warn_unused_ignores`, `warn_redundant_casts`); Ruff `E,F,I,B,S,UP,SIM,RUF,C4,PT,DTZ` (89 achados corrigidos; `DTZ001` isento só em `servicos/financeiro.py`, por causa do relógio naive de Brasília) | `server/pyproject.toml` |
| 3.3 | Sem gate de cobertura | `pytest --cov=app --cov-fail-under=85` no CI (medido: **97,6 %**); `pytest-cov` entrou em `requirements-dev` com hashes | `server-ci.yml`, `requirements-dev.*` |

## 2. Testes adicionados
Backend (+5): `test_sair_revoga_o_token_em_todos_os_aparelhos`, `test_sair_com_sessao_expirada_ou_sem_sessao_nao_falha`, `test_sair_pelo_site_revoga_e_cookie_sem_csrf_nao_revoga`, `test_ip_do_cliente_usa_chave_fixa_quando_nao_ha_cliente`, `test_ttl_padrao_da_sessao_e_24_horas`.
Flutter (+14): 7 em `test/outbox_offline_test.dart` (retransmissão manual: mesma chave, contador zerado, sem internet, servidor ainda fora, item específico, conflito intocado, isolamento entre usuários) e 7 widgets em `test/pendencias_screen_test.dart`.

## 3. Resultado da verificação
- Backend: **141 passed / 2 skipped (SQLite)** e **143 passed (PostgreSQL 16)**; cobertura 97,6 %; `ruff check`, `ruff format --check` e `mypy app` limpos.
- Flutter: **não foi executado neste ambiente** (o SDK não pôde ser baixado: o proxy bloqueia o download do engine). A validação (`flutter analyze` + `flutter test`) fica a cargo do CI do PR.
- Workflows YAML validados sintaticamente; o comportamento do guard de release só é provado ao disparar o workflow.

## 4. Limites conhecidos (não resolvidos aqui)
- O outbox cobre **sessões** (agendar, status, remarcar). Registros de **humor não passam pelo outbox** (exigem conexão): estendê-lo é uma mudança à parte.
- `/auth/sair` encerra **todos** os aparelhos (não só o atual). Sessão por aparelho exige refresh token rotativo (`jti`/tabela de sessões): próxima iteração.
- Rate limit continua em memória (1 processo).
- Mudar a sub-rede do compose é necessário se `172.31.250.0/24` colidir com a do servidor.

## 5. Passos para o merge final
1. Abrir o PR `dev → main` e aguardar CI verde (**analyze/flutter test**, server CI, deploy smoke, CodeQL).
2. Conferir no deploy smoke que a pilha sobe com a rede de IP fixo e que `/auth/*` responde atrás do Caddy.
3. Merge (squash ou merge commit) e apagar a branch remota.
4. Antes de qualquer release de produção: cadastrar os 4 segredos `ANDROID_KEYSTORE_*`/`ANDROID_KEY_*`, ativar Dependency graph, definir `.env` real (`JWT_TTL_HOURS=24`, `PRONTUARIO_KEYS`, SMTP, domínio), depois `gh workflow run build-apk.yml --ref main -f api_url=https://SEU-DOMINIO/api -f release=true -f demo=false`.
