# Solução de problemas

Comece sempre pela aba **Summary** da execução: o diagnóstico automático já classifica a falha em uma de cinco
categorias e sugere a ação. Esta tabela detalha as causas mais comuns.

## Pelo sintoma
| Sintoma / mensagem | Categoria | Causa provável | Correção |
|---|---|---|---|
| `HEALTHCHECK_TIMEOUT` | Infra | O serviço não respondeu em `/health` no prazo | Veja `server.log` no artefato `failure-dumps-*`; aumente `health_timeout`; confira porta/endereço |
| `SERVER_EXITED` | Infra | O processo morreu no boot | Traceback ou `FATAL:` em `server.log` |
| `FATAL: ALLOWED_ORIGINS='*' é incompatível…` | CORS | Configuração proibida pela especificação CORS | Liste origens exatas ou desligue `ALLOW_CREDENTIALS` |
| `[CORS] … Access-Control-Allow-Origin` | CORS | Origem autorizada não está em `ALLOWED_ORIGINS`, ou comparação por sufixo | Origem **exata** (esquema + host + porta), sem barra final |
| `[SECURITY] …` | Segurança | Controle ausente (header, limite, autenticação) | **Bloqueante.** Corrija antes do deploy; veja `SECURITY-CONTROLS.md` |
| `[CONTRACT] … esperado HTTP 200, recebido 500` | Contrato | Regressão ou rota quebrada | Compare com `openapi.yaml`; o corpo da resposta vem na mensagem (já sem PII) |
| `status documentado sem caso de conformidade` | Contrato | Resposta nova na especificação sem `x-conformance` | Adicione o caso ou liste em `x-conformance-exempt` com justificativa |
| `ModuleNotFoundError` / `ERROR collecting` | Compilação | Import quebrado ou dependência ausente | `python -m compileall -q .`; `pytest --collect-only` |
| `THESE PACKAGES DO NOT MATCH THE HASHES` | — | Lock desatualizado | `make lock` e commit dos três `requirements*.txt` |
| `Required test coverage of 90% not reached` | Qualidade | Código novo sem teste | Escreva testes em `unit/`; veja `--cov-report=term-missing` |
| `mypy: error` | Qualidade | Tipagem estrita | Anote o código de produto; testes têm anotação opcional |
| `ruff format --check` falha | Qualidade | Formatação | `ruff format .` |
| `pip-audit: found N known vulnerabilities` | Segurança | CVE em dependência | Atualize a dependência (`make lock`); se não houver correção, registre exceção com prazo |
| `zizmor`/`actionlint` com achado | Segurança | Action sem SHA, permissão excessiva, injeção de template | Corrija o workflow; nunca use `${{ … }}` dentro de `run:` — use `env:` |
| `Vazamento de segredo` (leakscan) | Segurança | O token efêmero apareceu em log/relatório | **Trate como incidente** (ver `OPERATIONS.md`); ache a origem na lista de arquivos |

## Suíte `live` (APIs públicas)
| Sintoma | Interpretação |
|---|---|
| Falha só em `live`, `Gate` verde | Esperado: é informativa. Veja se foi mudança de contrato (schema), CORS ou indisponibilidade |
| `Access-Control-Allow-Origin` diferente de `*` ou da sua origem | A API mudou a política CORS: o app **web** deixará de conseguir chamá-la |
| `test_*_user_agent_do_app` falha | A API passou a bloquear o User-Agent do app: o app pode quebrar no celular |
| Teste marcado `xfail` | Comportamento **conhecido** de terceiro, documentado no próprio teste |

## GitHub Actions
| Sintoma | Causa e correção |
|---|---|
| O check `Gate` nunca aparece no PR | Workflow com filtro `paths:` não roda e o check obrigatório fica "pendente" para sempre. Este pipeline **não** usa filtro de caminhos |
| Execução agendada não roda | `schedule` só roda na **branch padrão**, e repositórios públicos sem atividade por 60 dias têm o agendamento desativado — faça um commit ou reative em *Actions* |
| `Resource not accessible by integration` | Falta a permissão no job (veja o bloco `permissions` do job; não suba para o nível do workflow) |
| `Attestation` falha | Atestados exigem repositório público ou plano GitHub Enterprise Cloud; em repositório privado de plano gratuito remova o passo |
| Deploy do Pages `404 … has not been enabled` | *Settings → Pages → Source: GitHub Actions* |
| Execução cancelada sozinha | Comportamento intencional em PRs/branches de trabalho (`cancel-in-progress`); em `main` nunca cancela |
| CodeQL sem permissão em PR de fork | Limitação do GitHub: forks não escrevem em *Security*; o check roda, mas sem upload |

## APK
| Sintoma | Correção |
|---|---|
| "App não instalado" ao atualizar | O APK anterior foi assinado com **outra chave**. Configure os segredos de assinatura (`DEPLOYMENT.md` §3); desinstale uma vez |
| Tela de login sem contas de demonstração | Build de **produção** (tag `vX.Y.Z`) — intencional. Para demo: *Run workflow* com `demo = true` |
| Erro ao chamar APIs no celular | Verifique permissão `INTERNET` (o workflow a injeta) e a suíte `live` |
