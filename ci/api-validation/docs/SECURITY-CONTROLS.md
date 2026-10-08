# Mapa de controles de segurança

Cada controle abaixo tem **evidência automatizada** (teste ou verificação de CI). Nada aqui é uma certificação:
é o mapeamento honesto entre o que o projeto implementa, como é verificado e o que **não** está coberto.

## 1. OWASP Top 10 (2021) × controles
| Categoria | Controle implementado | Evidência automatizada |
|---|---|---|
| **A01 Controle de acesso** | Bearer obrigatório em `/api/*`; preflight público (navegadores não enviam credenciais nele); CORS por origem exata | `test_caso_de_conformidade[… sem credenciais / token inválido]`, `test_preflight_nao_exige_credenciais`, `test_401_informa_esquema_e_mantem_cors`, 7 casos de origem forjada em `test_cors_reference.py` |
| **A02 Falhas criptográficas** | Token comparado em tempo constante (`hmac.compare_digest`); segredos nunca em log/relatório; token efêmero por execução | `test_app_autenticacao_em_tempo_constante…`, `leakscan` (passo do pipeline), `test_redaction.py` (12 formatos de segredo) |
| **A03 Injeção** | Validação rígida de entrada; nenhuma entrada é refletida; JSON sem `NaN/Infinity`; limite de aninhamento; workflows sem `${{ }}` em scripts | `test_parametros_maliciosos_nao_sao_refletidos`, `test_constantes_json_nao_padrao…`, `test_json_profundamente_aninhado…` (32 mil níveis), `zizmor` (template-injection) |
| **A04 Design inseguro** | Rate limit (429 + `Retry-After`); limite de corpo (64 KiB) e de URL; falha rápida em configuração insegura | `test_app_responde_429_com_retry_after`, caso `corpo acima do limite`, `test_config_insegura_e_recusada` (10 casos) |
| **A05 Configuração incorreta** | Headers de segurança em toda resposta; banner genérico; bind só em loopback por padrão; `*`+credenciais proibido; permissões mínimas nos workflows | `test_headers_de_seguranca_em_toda_resposta`, `test_banner_do_servidor_nao_revela_tecnologia`, `zizmor` + `actionlint` |
| **A06 Componentes vulneráveis** | Dependências travadas com hash; auditoria de CVEs; revisão de dependências em PR; Dependabot com espera de 7 dias; SBOM | job `supply-chain` (`pip-audit`), `Dependency Review`, artefato `sbom` |
| **A07 Falhas de autenticação** | `WWW-Authenticate`; credencial inválida não é refletida; token mínimo de 16 caracteres | `test_token_invalido_nao_e_refletido`, `test_config_insegura…` |
| **A08 Integridade de software e dados** | Actions fixadas por **SHA**; binário do actionlint verificado por SHA-256; atestado de procedência (SLSA) do relatório e do APK; XML de relatório lido com `defusedxml` | `zizmor` (unpinned-uses), `test_xml_malicioso_billion_laughs_e_recusado`, `actions/attest-build-provenance` |
| **A09 Logs e monitoramento** | Log JSON estruturado com lista fechada de campos; **sem IP, User-Agent, corpo, query string ou cabeçalhos**; `X-Request-Id`; diagnóstico automático | `test_log_estruturado_so_grava_campos_permitidos_e_sem_pii` |
| **A10 SSRF** | O serviço não faz requisições de saída; o health-check só aceita `http/https` | `test_healthcheck_recusa_esquema_nao_http` |

## 2. Proteções de protocolo (request smuggling, slowloris)
| Ameaça | Controle | Teste |
|---|---|---|
| `Transfer-Encoding` ambíguo | Recusa (501) | `test_transfer_encoding_e_rejeitado` |
| `Content-Length` inválido/negativo/duplicado | Recusa (400) | `test_content_length_invalido…` (5 valores), `…duplicado…` |
| `Origin` duplicado | Recusa (400) | `test_origin_duplicado_e_rejeitado` |
| Conexão lenta/incompleta | Timeout de socket (configurável) | `test_conexao_ociosa_e_encerrada_pelo_servidor` |
| Travessia de diretório | Caminho validado por lista de caracteres | `test_caminho_com_travessia_nao_expoe_arquivos` |
| Vazamento de erro interno | Barreira final devolve 500 genérico | `test_http_erro_interno_nao_vaza_detalhes`, `test_erros_nao_vazam_detalhes_internos` |

## 3. Mascaramento automático de dados sensíveis
`apival/redaction.py` é a **única** saída de texto livre. Cobre: tokens GitHub/AWS/Google/Slack, JWT, chaves PEM,
cabeçalho `Authorization`, pares `chave=valor` (token, senha, api_key…), **e-mail, CPF, CNPJ, telefone brasileiro e IPs**
(exceto loopback). Segredos conhecidos em execução (o token efêmero) também são mascarados nas formas literal e codificada.
Verificação adicional independente: `leakscan` varre `reports/` procurando o valor do token (inclusive base64/URL-encoded).

## 4. Qualidade como controle
`ruff` (regras de segurança `S`), `mypy --strict`, `bandit`, cobertura ≥ 90% (atual: 96,4%), `filterwarnings = error`
(qualquer aviso do Python derruba o teste: já pegou um vazamento de socket durante o desenvolvimento).

## 5. Teste dos testes (mutação manual)
Foram injetados defeitos no serviço e a suíte **reprovou em todos** (8 de 8 de segurança/CORS; 7 de 7 de contrato/CORS na rodada anterior):
sem `nosniff`, sem `Vary: Origin`, origem por sufixo, sem checagem de token, `Transfer-Encoding` aceito, sem limite de corpo,
banner revelador, token refletido no 401. Cada um caiu na categoria certa do diagnóstico.

## 6. Riscos residuais e limites (leia antes de contratar/auditar)
| # | Risco / limite | Impacto | Recomendação |
|---|---|---|---|
| R1 | O app usa autenticação **somente local** (sem servidor): paciente e profissional em aparelhos diferentes **não compartilham dados** | Produto não é multiusuário real | Backend com banco central e API (alvo natural deste pipeline) |
| R2 | Senhas do app com SHA-256 + sal (rápido demais) | Vulnerável a força bruta se o aparelho for comprometido | Argon2id/bcrypt/PBKDF2 com custo alto, ou delegar a um provedor de identidade |
| R3 | SQLite do app **sem criptografia em repouso**; dados de saúde são dado pessoal **sensível** (LGPD, art. 5º, II) | Exposição em caso de perda do aparelho | SQLCipher/criptografia, base legal e consentimento, política de privacidade, DPO |
| R4 | Sem assinatura de produção até configurar os segredos (`DEPLOYMENT.md` §3) | APK não atualizável / não publicável | Configurar a keystore |
| R5 | O app Flutter não tem testes automatizados (só `flutter analyze`); CodeQL não suporta Dart | Regressões do app só aparecem manualmente | Testes de widget/integração |
| R6 | CORS validado por cabeçalhos HTTP, não por navegador real | Falsos negativos teóricos | Teste Playwright contra o site publicado |
| R7 | Sem teste de carga nem pentest independente | Desempenho/robustez em escala desconhecidos | Pentest externo antes de venda enterprise |
| R8 | Serviço de referência ≠ backend do cliente | Cobertura só vale para o que for apontado | Usar `service_start_command` com o backend real |
| R9 | Rate limit em memória e por processo | Não escala horizontalmente | Gateway/WAF em produção |
| R10 | Pipeline depende de GitHub (Actions, Sigstore) | Indisponibilidade do provedor | Aceitável; documentar plano de contingência |

> Nenhuma certificação (SOC 2, ISO 27001, LGPD) é alegada. Este material é insumo técnico para essas auditorias.
