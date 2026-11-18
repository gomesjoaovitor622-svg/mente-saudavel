# Observabilidade e alertas em produção

Tudo abaixo roda na própria pilha (Docker Compose), **sem serviço pago e sem dependência nova** no backend.

## 1. Logs estruturados (JSON)
Uma linha JSON por evento em `docker compose logs api`. Campos: `ts`, `nivel`, `msg`, `request_id`, `metodo`, `rota`
(o **modelo** da rota, `/sessoes/{sessao_id}`, nunca o valor), `status`, `duracao_ms`. Nunca entram corpo da
requisição, query string, `Authorization` nem e-mails. O `X-Request-ID` volta no cabeçalho e na mensagem do erro 500
("Informe o código ..."): com ele se acha a pilha completa no log.

```bash
docker compose logs --no-log-prefix api | jq -c 'select(.nivel=="ERROR")'                 # erros
docker compose logs --no-log-prefix api | jq -c 'select(.duracao_ms > 1000)'              # requisições lentas
docker compose logs --no-log-prefix api | jq -c 'select(.request_id=="<codigo do erro>")' # uma requisição
docker compose logs --no-log-prefix api | jq -c 'select(.msg=="evento_cliente" and .tipo=="erro")'  # erros do app
```
Falhas do `/health` e `/health/ready` (status >= 400) **são** registradas; as respostas 200 não (enchem o log).

## 2. Saúde: liveness x readiness
| Rota | Pergunta | Resposta |
|---|---|---|
| `GET /api/health` | A API está de pé? (healthcheck do Docker) | `200 {"status":"ok"}` |
| `GET /api/health/ready` | Ela **consegue trabalhar**? (banco responde e, com `SCHEMA_MODE=alembic`, está na versão do esquema) | `200` ou `503 {"status":"degradado","checks":{"banco":{"ok":false,...}}}` |

A resposta pública traz só ok/falha e a latência do banco em ms: a mensagem do erro do banco vai **só para o log**
(`prontidao_banco_falhou`). Use `/api/health/ready` em monitores externos gratuitos (UptimeRobot, Better Stack free,
healthchecks.io): eles testam também o caminho Internet → Caddy → API → PostgreSQL.

## 3. Métricas (formato Prometheus)
`GET /api/metricas` com `Authorization: Bearer $METRICS_TOKEN` (404 se o token não estiver definido).

| Métrica | Tipo | Uso |
|---|---|---|
| `ms_http_requests_total{metodo,rota,status}` | contador | volume e taxa de 5xx por rota |
| `ms_http_request_duration_seconds_*` | histograma | latência p50/p95 por rota |
| `ms_http_requests_in_flight` | medidor | requisições em andamento (saturação) |
| `ms_erros_nao_tratados_total` | contador | exceções que viraram 500 (telemetria de erro global) |
| `ms_db_up`, `ms_db_latency_seconds` | medidor | atualizados a cada `/health/ready` |
| `ms_process_start_time_seconds` | medidor | detectar reinício (`time() - valor`) |
| `ms_cliente_eventos_total{tipo,plataforma}` | contador | erros/telas/chamadas **medidos pelo app** |
| `ms_cliente_rede_duracao_ms_sum/_count{plataforma}` | contador | latência de rede **vista pelo usuário** (média = sum/count) |
| `ms_cliente_rede_erros_5xx_total{plataforma}` | contador | respostas 5xx vistas pelo app |

Rótulos de telemetria do app são de **conjunto fechado** (`tipo` é um enum; `plataforma` ∈ android/ios/web/outra): texto
livre do cliente nunca vira rótulo (evita explosão de cardinalidade e injeção no formato de exposição).
Os contadores ficam em memória: reiniciar a API zera (é o comportamento normal de contador Prometheus). Um processo só.

```bash
curl -s -H "Authorization: Bearer $METRICS_TOKEN" https://SEU-DOMINIO/api/metricas | grep -E 'ms_db_up|erros_nao_tratados|5xx'
```

## 4. Alertas automáticos (contêiner `monitor`)
`deploy/monitor/alerta.sh` (POSIX sh, ~100 linhas) roda como serviço no `docker-compose.prod.yml`:

1. `GET /health/ready` a cada `ALERTA_INTERVALO` s; **`ALERTA_FALHAS` falhas seguidas** → alerta CRÍTICO (uma vez);
2. com `METRICS_TOKEN`, compara duas leituras e alerta se a taxa de 5xx na janela passar de `ALERTA_TAXA_5XX`
   (com ao menos `ALERTA_MIN_REQ` requisições, para não alarmar com 1 erro em 2 requisições);
3. avisa **uma vez** quando volta ao normal ("RECUPERADO").

O alerta sempre vai para `docker compose logs monitor`. Com `ALERTA_WEBHOOK_URL` (Slack, Discord, Teams ou qualquer
endpoint que aceite JSON), também é enviado lá. Testado sem Docker por `deploy/monitor/test-alerta.sh` (API e webhook
falsos; roda no CI em `deploy-smoke.yml`).

**O que o monitor interno NÃO cobre:** se o servidor inteiro cair, o monitor cai junto. Por isso, além dele, cadastre
**um monitor externo gratuito** apontando para `https://SEU-DOMINIO/api/health/ready` (alerta por e-mail/Telegram).

## 5. Runbook rápido
| Sintoma | Primeiro passo |
|---|---|
| Alerta CRÍTICO / `ms_db_up 0` | `docker compose ps`; `docker compose logs db api`; espaço em disco (`df -h`) |
| `/health/ready` 503 só em `migracoes` | banco em outra versão do esquema: `docker compose run --rm migrate` |
| Taxa de 5xx alta | `jq 'select(.nivel=="ERROR")'` nos logs; ver o `request_id` citado pelo usuário |
| Latência alta | `jq 'select(.duracao_ms>1000)'`; histograma por rota; `ms_http_requests_in_flight` perto do limite de threads |
| Muitos `ms_cliente_rede_erros_5xx_total` mas poucos `5xx` no servidor | problema entre o app e o servidor (Caddy, DNS, rede móvel) |

## 6. Limites conhecidos
- Métricas e limitadores em memória: válidos para **1 processo** (uma réplica da API). Mais de uma réplica exige
  armazenamento compartilhado (Redis) ou um coletor por réplica.
- Sem tracing distribuído (basta o `request_id` enquanto houver 1 serviço).
- Retenção de logs: configure `logging` do Docker (`max-size`/`max-file`) no servidor para não encher o disco.
