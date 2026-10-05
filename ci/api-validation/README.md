# Pipeline de validação de APIs e CORS

Valida **contrato** (status HTTP + JSON Schema) e **CORS** (requisição simples, preflight, credenciais) em
ambiente isolado do GitHub Actions, e gera um **diagnóstico automático** de cada falha.

```text
push / PR / agendamento / manual
        │
        ▼
  selftest ──► mock-suite (py3.11, py3.12) ─┐
        │        sobe o serviço em 2º plano │
        │        health-check → pytest      ├──► gate  ──► publish-report
        └────► live-suite (APIs públicas) ──┘
                 informativo por padrão
```

| Pasta/arquivo | Função |
|---|---|
| `.github/workflows/api-validation.yml` | O pipeline |
| `mock_server/server.py` | Serviço de referência (stdlib) com CORS estrito. Troque pelo seu backend via `service_start_command` |
| `tests/test_contract_mock.py` | Contrato: status, tipos, schemas, erros 4xx, headers de segurança |
| `tests/test_cors_mock.py` | CORS: origem autorizada x negada, preflight, Max-Age, credenciais, ataques de origem |
| `tests/test_live_public_apis.py` | BrasilAPI, ViaCEP e Jitsi reais (detecta mudança de contrato/CORS de terceiros) |
| `scripts/wait_for_http.py` | Health-check com backoff exponencial, timeout e detecção de processo morto |
| `scripts/diagnose.py` | Auto-diagnóstico → Step Summary, JSON e anotações `::error` |
| `selftest/` | Testes do próprio harness |

## Como rodar localmente
```bash
cd ci/api-validation
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pytest selftest -q                                   # testa o harness
python mock_server/server.py &                       # sobe o serviço (porta 8765)
python scripts/wait_for_http.py http://127.0.0.1:8765/health
pytest -m mock                                       # contrato + CORS
pytest -m live                                       # APIs reais (precisa de internet)
```

## Como o diagnóstico classifica (precedência)
1. **Erros de Compilação**: `SyntaxError`, `ImportError`, `ERROR collecting`... (o código nem executa)
2. **Timeouts de Infraestrutura**: `HEALTHCHECK_TIMEOUT`, `SERVER_EXITED`, `ReadTimeout`, `ConnectionError`...
3. **Violações de Política CORS**: testes que levantam `CorsPolicyViolation` (`[CORS]`) e `FATAL` de config CORS no serviço
4. **Falhas de Contrato de API**: `ContractViolation` (`[CONTRACT]`), schema inválido, status inesperado
5. **Outras falhas**

A precedência evita falso diagnóstico: um teste de CORS que falha por timeout é *infraestrutura*, não política.

## Segurança aplicada
- `permissions: {}` global; cada job declara o mínimo. Só `publish-report` tem `contents: write` (não roda em PR).
- Actions fixadas por **SHA de commit**; Dependabot propõe atualizações.
- `pull_request` (nunca `pull_request_target`); `persist-credentials: false` no checkout.
- Entradas do `workflow_dispatch` passam por **variáveis de ambiente + validação por regex** (sem injeção de script).
- Serviço sobe com `env -i` (sem herdar variáveis/segredos do runner) e escuta só em `127.0.0.1`.
- `API_AUTH_TOKEN` (opcional) só existe no step de testes e **nunca** é enviado a APIs de terceiros.
- O diagnóstico **redige** tokens/senhas antes de escrever qualquer saída.

## Guia de implantação
1. Mantenha esta pasta e os arquivos `.github/workflows/api-validation.yml` e `.github/dependabot.yml` no repositório.
2. (Opcional) *Settings → Secrets and variables → Actions*: segredo `API_AUTH_TOKEN` se o seu serviço exigir autenticação.
3. *Settings → Branches → Branch protection*: exija o check **Gate**.
4. Rodar manualmente: *Actions → API Validation → Run workflow* e ajuste suíte, origem, timeout e reexecuções.
5. Ler o resultado: aba **Summary** da execução (diagnóstico), anotações vermelhas na execução e artefatos
   `reports-*` (7 dias) e `failure-dumps-*` (14 dias, só em falha).
6. Validar outro backend: preencha `service_start_command` (`python caminho/servidor.py`) e adapte `schemas.py`/testes.
7. Desligar a publicação de relatórios: variável de repositório `PUBLISH_REPORTS=false`.
