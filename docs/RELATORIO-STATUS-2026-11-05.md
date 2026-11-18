# Relatório técnico executivo — evolução contínua (05/11/2026)

Base: `dev` (inclui o PR #16, ainda aberto, e esta rodada). Repositório: `gomesjoaovitor622-svg/mente-saudavel`.

## 1. Entregue nesta rodada
| Frente | Entrega | Onde |
|---|---|---|
| Observabilidade | `GET /health/ready` (readiness: banco + versão do esquema; 503 sem vazar erro) · métricas novas: erros não tratados, banco no ar/latência, requisições em andamento, início do processo, **telemetria do app** (eventos e latência de rede por plataforma, rótulos de conjunto fechado) · falhas de saúde passam a ser logadas | `app/saude.py`, `app/observabilidade.py`, `rotas/operacao.py`, `main.py` |
| Alertas | contêiner `monitor` (POSIX sh): alerta após N falhas seguidas, taxa de 5xx na janela, aviso de recuperação, webhook opcional; rotação de logs do Docker (10 MB x 5) | `deploy/monitor/`, `docker-compose.prod.yml` |
| Offline-first | **humor** e **atualização cadastral** entram na fila (Outbox). Humor com `Idempotency-Key` ponta a ponta (servidor: coluna + índice único parcial, migração `0005`; reenvio devolve 200 com o registro existente, inclusive sob corrida). Cadastro: só a alteração mais recente fica na fila. Lista de humor offline = cache + pendentes marcados "Aguardando internet" | `lib/database/humor_dao.dart`, `lib/data/remote/{humor_perfil_remoto,perfil_offline}.dart`, `sincronizador_outbox.dart`, `rotas/humor.py`, `migrations/0005` |
| Testes E2E | jornada completa na API (cadastro → confirmação por e-mail → agendar/humor com chave → sair → 401 → entrar → reenvio sem duplicar); humor idempotente (inclusive **6 requisições paralelas em PostgreSQL**); readiness 200/503; métricas; fallback de rede no Flutter | `tests/test_jornada_e_observabilidade.py`, `test/humor_perfil_offline_test.dart` |
| Qualidade estática | mypy **`strict = true`** (já passava: 0 erros) · Ruff + `RET, PERF, PIE, BLE` (0 achados) | `server/pyproject.toml` |

## 2. Resultado da verificação (o que foi e o que não foi executado)
- Backend: **150 passed / 3 skipped (SQLite)** e **153 passed (PostgreSQL 16)**; cobertura 96,6 %; `ruff check`, `ruff format --check` e `mypy --strict app` limpos; migração `0005` coberta pelo teste de paridade modelo × Alembic.
- `docker compose config` valida o compose (serviço `monitor`, rotação de logs); `deploy/monitor/test-alerta.sh` passa (5 cenários).
- **Não executado aqui:** `flutter analyze/test` (SDK não baixa neste ambiente; validação fica no CI do PR) e o contêiner `monitor` dentro do Docker (`up` real: validado pelo `deploy-smoke` do CI). O script foi testado com `sh` (dash) e curl; no Alpine usa `wget` do busybox.

## 3. Orientação para evoluir Ruff e Mypy (com números medidos hoje)
**Mypy.** `--strict` já passa em `app/` → mantido como padrão (qualquer função sem tipo ou `# type: ignore` inútil quebra o CI). Próximo passo: rodar `mypy` também em `tests/` com `--check-untyped-defs` e, quando houver Pydantic v2 plugin no ambiente, ativar `plugins = ["pydantic.mypy"]`.

**Ruff.** Regras já ativas: `E,F,I,B,S,UP,SIM,RUF,C4,PT,DTZ,RET,PERF,PIE,BLE`. Candidatas medidas em `app/` (`ruff --isolated --select ...`):
| Regra | Achados | Recomendação |
|---|---|---|
| `ARG` (argumentos não usados) | 6 | ativar após corrigir (muitos são dependências do FastAPI: usar `Depends` sem nome ou `# noqa: ARG001` com motivo) |
| `TC001/2/3` (imports só de tipo) | 14 | ativar com `--fix`; reduz tempo de import |
| `PLR2004` (número mágico) | 11 | ativar e extrair constantes (`MAX_TENTATIVAS` etc.) |
| `TRY003` | 12 | **não ativar** (ruído: mensagens longas em `raise` são o estilo do projeto) |
| `C901` (complexidade) | 6 | ativar com `max-complexity = 12` e refatorar as 6 funções por camada (`servicos/`) |
| `FBT` (booleano posicional) | 18 | ativar só em `servicos/` (API interna); exigir `*, flag=True` |
| `ANN401` (`Any`) | 5 | ativar; trocar por `object`/tipos concretos |
| `T201` (`print`) | 4 | ativar (os 4 são da CLI `admin.py`: `per-file-ignores`) |

Método: **uma regra por PR**, `ruff check --select REGRA --fix`, rodar a suíte, subir. O CI já impede regressão (os arquivos de teste só ignoram `S`, `E501`, `DTZ`).

## 4. Limites conhecidos
- **Offline de humor:** excluir um registro **já enviado** exige internet (só o pendente é cancelável offline). Edição de humor não existe no app.
- **Perfil offline:** última gravação vence; se o servidor recusar depois (ex.: validação), o item fica "com falha" na tela de Pendências, e o app já exibiu o valor novo até a próxima recarga do usuário.
- Métricas, limitadores e o monitor interno são de **1 processo/1 servidor**; o monitor externo gratuito é complementar obrigatório (`docs/OBSERVABILIDADE.md`).
- Sessões ainda encerradas em **todos** os aparelhos no logout (sem refresh token / sessão por aparelho).

## 5. Roadmap proposto
| Prioridade | Entrega | Esforço | Critério de pronto |
|---|---|---|---|
| P0 (antes do go-live) | Servidor real no ar + `.env` de produção + SMTP + monitor externo apontando para `/api/health/ready` + `ALERTA_WEBHOOK_URL` | 1–2 dias | alerta de teste chega no canal; `ms_db_up 1` |
| P0 | Keystore Android + 4 segredos + primeiro APK de release assinado | 0,5 dia | `build-apk.yml release=true` verde; APK instala por cima |
| P0 | Teste de restauração do backup num banco vazio + custódia das `PRONTUARIO_KEYS` | 0,5 dia | `ensaio-dr.sh` verde com dados reais de teste |
| P1 | Refresh token rotativo + sessão por aparelho (logout só do atual) | 3–4 dias | tabela `sessoes_auth`, detecção de reuso, testes de rotação |
| P1 | Dashboard Grafana/Prometheus opcional (compose `--profile obs`) lendo `/metricas` | 1 dia | painéis de latência p95, 5xx, banco |
| P1 | Ruff `ARG`, `TC`, `PLR2004`, `C901`, `ANN401` (1 por PR) | 2 dias | CI verde com as regras |
| P2 | `integration_test` do Flutter em emulador no CI (instalar APK, login, humor offline → online) | 3 dias | workflow noturno verde |
| P2 | Rate limit e métricas compartilhados (Redis) para mais de 1 réplica | 2–3 dias | 2 réplicas com limites consistentes |
| P2 | Edição/exclusão de humor offline (fila de `PATCH/DELETE` com ids temporários) | 2 dias | testes de ordem e conflito |

## 6. Git: comandos e passos do merge
```bash
git checkout dev && git pull --ff-only origin dev
git add -A
git commit -F mensagem.txt          # ver mensagem estruturada usada na rodada
git push origin dev                 # o PR #16 (dev → main) é atualizado sozinho
gh api repos/gomesjoaovitor622-svg/mente-saudavel/pulls/16 --jq '.state, .mergeable_state'   # acompanhar
```
Merge final: (1) aguardar CI verde em `flutter analyze` (inclui os novos testes), Server CI (SQLite + PostgreSQL), Deploy smoke (sobe a pilha **com** o `monitor`), CodeQL; (2) ativar o *Dependency graph* para o Dependency Review deixar de falhar por configuração; (3) merge do PR e apagar a branch remota; (4) no servidor, `docker compose run --rm migrate` aplica a migração `0005` antes de subir a API nova (obrigatório em `SCHEMA_MODE=alembic`).
