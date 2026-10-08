# apival — validação contínua de APIs (contrato · CORS · segurança)

Toolkit + pipeline que prova, a cada commit, que uma API respeita o **contrato (OpenAPI)**, a **política CORS** e os
**controles de segurança** esperados, e que explica cada falha em linguagem acionável.

| | |
|---|---|
| Testes | 104 unitários (cobertura 96,4%) · 97 de sistema por versão do Python (3.11, 3.12, 3.13) · 17 contra APIs reais |
| Qualidade | ruff · `mypy --strict` · bandit · formatação · cobertura ≥ 90% |
| Segurança | dependências com hash · pip-audit · SBOM · detect-secrets · zizmor · actionlint · CodeQL |
| Evidência | relatório executivo (MD/HTML) + manifesto SHA-256 + atestado SLSA |

## Documentação
| Documento | Para quem |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Arquitetos e revisores técnicos |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Quem vai implantar no cliente |
| [docs/API-CONTRACTS.md](docs/API-CONTRACTS.md) + [contracts/openapi.yaml](contracts/openapi.yaml) | Quem integra e quem testa |
| [docs/SECURITY-CONTROLS.md](docs/SECURITY-CONTROLS.md) | Segurança, compliance e auditoria externa |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Operação, releases e resposta a incidente |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Suporte |

## Início rápido (local)
```bash
cd ci/api-validation
python -m venv .venv && source .venv/bin/activate
make install        # instala com --require-hashes
make all            # lint + tipos + SAST + unit + sistema (sobe o serviço com autenticação)
```
Alvos: `lint`, `typecheck`, `sast`, `unit`, `system`, `audit`, `lock`.

## Estrutura
```text
apival/             toolkit: redaction, classification, junit, diagnose, markdown, executive, healthcheck, leakscan, contracts, checks
reference_service/  serviço sob teste: config → app (pura) → server (HTTP endurecido)
contracts/          openapi.yaml (fonte única da verdade do contrato)
tests/              sistema: contrato, conformidade OpenAPI, CORS, segurança, APIs reais
unit/               unitários do toolkit e do serviço
docs/               documentação
requirements*.txt   dependências travadas com hash (gerados a partir dos *.in)
```
