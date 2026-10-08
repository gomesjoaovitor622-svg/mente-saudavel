# Especificação dos contratos de API

A especificação formal e executável é **`contracts/openapi.yaml`** (OpenAPI 3.1). Este documento é o resumo
legível; em caso de divergência, **o arquivo OpenAPI vale** (é o que os testes executam).

## 1. Convenções
- Corpo e erros em JSON UTF-8 (`Content-Type: application/json; charset=utf-8`).
- Autenticação: `Authorization: Bearer <token>` nas rotas `/api/*` quando o serviço exige token. `/health` é público.
- Todo response traz `X-Request-Id` (12 hex) para rastreabilidade, e os cabeçalhos de segurança da seção 5.
- Limite de corpo: **64 KiB**. URL: **2048** caracteres. Rate limit: padrão 20 req/s por cliente, rajada 200.

## 2. Modelo de erro
```json
{ "error": { "code": "validation_error", "message": "Payload inválido.", "details": [ { "field": "modalidade", "message": "deve ser Online ou Presencial" } ] } }
```
`details` aparece somente em erros de validação (422). Mensagens **nunca** incluem detalhes internos, stack trace nem eco da entrada.

## 3. Endpoints
| Método e caminho | Auth | Sucesso | Erros documentados |
|---|:-:|---|---|
| `GET /health` | não | 200 `Health` | — |
| `GET /api/v1/feriados/{ano}` | sim | 200 lista de `Feriado` | 400, 401, 429 |
| `GET /api/v1/cep/{cep}` | sim | 200 `Cep` | 400, 401, 404, 429 |
| `POST /api/v1/sessoes/validar` | sim | 200 `ValidarOk` | 400, 401, 413, 415, 422, 429 |

### Matriz de status
| Status | Quando |
|---|---|
| 400 | Parâmetro inválido (`ano` fora de 1900–2100, `cep` ≠ 8 dígitos), JSON malformado/NaN/aninhamento extremo, `Content-Length` inválido ou duplicado, `Origin` duplicado, caminho com caracteres inválidos |
| 401 | Token ausente/inválido (`WWW-Authenticate: Bearer`) |
| 404 | Rota ou CEP inexistente |
| 405 | Método não permitido (`Allow` informado) |
| 413 | Corpo acima de 64 KiB |
| 414 | URL acima de 2048 caracteres |
| 415 | `Content-Type` diferente de `application/json` |
| 422 | JSON válido, porém com campos inválidos (`details` aponta cada campo) |
| 429 | Rate limit (`Retry-After` em segundos) |
| 501 | `Transfer-Encoding` (não suportado, previne request smuggling) |

### `POST /api/v1/sessoes/validar`
Requisição:
```json
{ "paciente_id": 1, "profissional_id": 2, "data_hora": "2026-10-10T14:00:00", "modalidade": "Online" }
```
| Campo | Tipo | Regra |
|---|---|---|
| `paciente_id`, `profissional_id` | inteiro | ≥ 1 (booleano e texto são recusados) |
| `data_hora` | string | ISO 8601 |
| `modalidade` | string | `Online` ou `Presencial` |

Resposta 200: `{ "valid": true, "sala": "MenteSaudavel-<12 hex>" }`. A sala é **determinística**: a mesma sessão gera sempre a mesma sala.

## 4. Política CORS
| Item | Regra |
|---|---|
| Origens | Lista **exata** (`ALLOWED_ORIGINS`); comparação por igualdade. Sufixo, prefixo, outro esquema/porta, `null`, barra final e maiúsculas são recusados |
| `Access-Control-Allow-Origin` | Ecoa a origem autorizada; **nunca** `*` com credenciais (o serviço recusa subir assim) |
| `Vary` | `Origin` sempre; no preflight também `Access-Control-Request-Method` e `-Headers` |
| Métodos | `GET, POST, OPTIONS` (por rota) |
| Headers permitidos | `content-type, authorization, x-requested-with` |
| `Access-Control-Max-Age` | 600 s (1–86400) |
| Credenciais | `Access-Control-Allow-Credentials: true` somente para origens autorizadas |
| Expostos | `X-Request-Id` |
| Preflight | Público (sem token), responde 204; origem/método/header não autorizados → 403/405 sem headers CORS |
| Erros | 4xx também carregam CORS para origens autorizadas (o front-end precisa ler o erro) |

## 5. Cabeçalhos de segurança (toda resposta)
`X-Content-Type-Options: nosniff` · `Cache-Control: no-store` · `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'` ·
`X-Frame-Options: DENY` · `Referrer-Policy: no-referrer` · `Server: api` (banner genérico).

## 6. APIs de terceiros consumidas pelo app (validadas na suíte `live`)
| API | Uso | Contrato observado | Observação |
|---|---|---|---|
| BrasilAPI `/api/feriados/v1/{ano}` | Aviso de feriado ao agendar | Lista `{date, name, type}` | CORS aceita a origem do site (verificado: `*` ou eco da origem) |
| ViaCEP `/ws/{cep}/json/` | Endereço do consultório | `{cep, logradouro, bairro, localidade, uf}`; CEP inexistente → 200 com `erro` | CORS aceita a origem do site (verificado); fonte da verdade para "não encontrado" |
| BrasilAPI `/api/cep/v2/{cep}` | Plano B do CEP | `{cep, state, city, neighborhood, street}` | **Responde 200 com endereço inventado para CEP inexistente** (teste `xfail` documenta); por isso só é consultada se o ViaCEP **falhar** |
| Jitsi Meet `meet.jit.si/{sala}` | Videochamada | Navegação (200) | Sem CORS (abre no navegador) |

## 7. Como estender
1. Acrescente a rota em `paths` com `responses` e `x-conformance` (casos de sucesso e de erro).
2. Implemente no serviço (ou no seu backend).
3. `make system` — falha se algum status documentado não tiver caso (`x-conformance-exempt` exige justificativa).
