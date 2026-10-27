# Auditoria técnica — Mente Saudável (2026-10-26)

Escopo: servidor (FastAPI/PostgreSQL), cliente Flutter, CI/CD e deploy. Método: leitura do código, testes automatizados e reprodução local (PostgreSQL 16 real). **Não há Flutter SDK, Docker daemon nem celular no ambiente de desenvolvimento do assistente**: o que depende deles está marcado como *não verificado aqui*.

## Corrigido neste lote (branch `dev`, com testes de regressão)
| # | Prioridade | Problema | Correção |
|---|---|---|---|
| 1 | Alta | Tokens não eram revogáveis: trocar a senha não derrubava outros aparelhos/tokens roubados (validade de 7 dias) | Coluna `usuarios.token_versao` (migração `0002`) + claim `tv` no JWT; trocar a senha incrementa a versão e devolve um token novo só para o aparelho atual. Tokens antigos sem `tv` continuam valendo (compatível) |
| 2 | Alta | `POST /auth/senha` sem limite de tentativas: token roubado permitia adivinhar a senha atual | Mesmo limitador do login, por usuário (429) |
| 3 | Média (LGPD) | `/profissionais/{id}/avaliacoes` mostrava o **nome completo** do paciente a qualquer usuário logado | Terceiros veem "Maria S."; o próprio paciente e o profissional avaliado veem o nome completo |
| 4 | Média | Editar perfil sem enviar `registro` apagava o CRP; enviar vazio também | Omitido = mantém; vazio = 422 |
| 5 | Média | `GET /sessoes` sem teto de linhas | Parâmetro `limite` (padrão 1000, máx. 5000) |
| 6 | Baixa | Limitador de login crescia sem fim com chaves que nunca voltam (memória) | Limpeza periódica de chaves expiradas |
| 7 | Alta (já corrigido antes) | Reenvio paralelo com a mesma `Idempotency-Key` podia dar 409 | Devolve a sessão existente (200) |

Validação: 64 testes no SQLite e 66 no PostgreSQL 16 passando; ruff e mypy `--strict` limpos; migração `0002` testada com dados existentes (upgrade e downgrade sem perda).

## Encontrado e ainda NÃO corrigido (por prioridade)
**Alta**
- Videochamada: o modo servidor usa link da API (docs/VIDEO.md); no modo local o link continua previsível (somente demo). Jitsi real ainda não testado.
- Limitadores de tentativas ficam em memória do processo: reiniciar o contêiner zera, e mais de um worker multiplica o limite. Para produção real com mais de uma réplica, mover para Redis/PostgreSQL.
- Textos legais são modelos e precisam de revisão jurídica/DPO; CRP só tem validação de formato; **sem recuperação de senha por e-mail**.
- Profissional pode marcar uma sessão **futura** como `concluida` (infla o "recebido" do financeiro). Regra de negócio a decidir com você antes de mudar.

**Média**
- (Agenda, Pacientes e Início do paciente já migradas para Riverpod.) Telas Profissionais, Humor, Cadastro, Login e Perfil ainda usam `setState` com lógica de negócio dentro; sem testes de widget. Migração gradual para Riverpod recomendada, uma tela por vez, com `flutter analyze` e testes no CI (não é possível compilar Flutter no ambiente do assistente).
- (`BancoScreen` só aparece no modo local, lendo o SQLite do próprio aparelho: sem exposição no modo servidor.)
- Sem paginação real (cursor) em listagens; o teto de 1000 linhas é só proteção.
- (`financeiro/historico` agora usa uma única consulta agrupada.)
- Service Worker não registrado (PWA sem cache offline do shell); fontes do Google (chamada externa).

**Baixa / operação**
- Dependency Graph, code scanning e atestados desligados no GitHub (falhas de CI são de configuração).
- Branches `ci-logs-*`, `v2-app`, PRs do Dependabot #1–#6 e PR #8 (docs/APK `api_url`) abertos; PR #8 ainda não incorporado.
- Nunca testado em celular físico; ensaio de DR e LAN a executar localmente (`tools/run_local_tests.sh`).
