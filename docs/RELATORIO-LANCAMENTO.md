# Relatório de lançamento — Mente Saudável (site na web no próximo mês)

Data: 2026-10-28 · Estado analisado: branch `dev` (commit `e14f96a`), 14 commits à frente da `main`; PR #9 (dev → main) aguardando autorização.

## 1. Resposta direta: videochamada e prontuário

| | Site (web) | APK (Android) |
|---|---|---|
| **Videochamada** | **Implementada e testada no CI** (E2E no navegador: botão abre nova aba com link + token do servidor) | **Código incluído**, mas **só aparece se o APK for compilado com `API_URL`**. Hoje o CI gera o APK sem ela (modo local: sem vídeo seguro, sem prontuário). Não testado em celular |
| **Prontuário** | **Implementado e testado no CI** (API: criar/editar/versões/409/auditoria/permissões; navegador: lista o registro cifrado e cria outro) | Idem: depende do `API_URL`. Não testado em celular |
| **Servidor Jitsi real** | **Não existe ainda.** O link e o token seguem o formato Jitsi/JWT e têm testes de contrato; nenhum vídeo real foi transmitido | Idem |

## 2. O que foi executado hoje (resultados reais)
- Servidor: **85 testes (SQLite) e 87 (PostgreSQL 16)** passando; ruff, formatação e mypy `--strict` limpos; `pip-audit` sem vulnerabilidades; migrações Alembic 0001→0003 ok; teste de backup/rotação ok; `docker compose config` do compose de produção ok.
- CI do último commit de código: **verde** em Servidor (API), Analisar código (Flutter: análise + todos os testes de widget/unidade), Build APK, Build do site, Security (CVEs/segredos/SBOM), Teste de implantação (pilha completa + E2E; passou na 2ª tentativa, veja risco R9).
- **Falham por configuração do GitHub, não por código:** CodeQL (code scanning desligado), Dependency Review (Dependency graph desligado), atestado de procedência (indisponível em repositório privado de usuário).
- **Não executado** (depende da sua máquina/infra): ensaio de restauração com Docker (`tools/run_local_tests.sh dr`), LAN + APK no celular, Jitsi real, deploy real em VPS/domínio.

## 3. Bloqueadores para o lançamento (P0 — não lance sem resolver)
| # | Item | Por quê | O que fazer |
|---|---|---|---|
| 1 | **Verificação de profissional (CRP)** | Qualquer pessoa cria conta de "profissional" digitando qualquer texto no campo CRP e passa a aparecer na busca; pacientes agendam e compartilham dados de saúde | Aprovação manual de novos profissionais (flag `verificado`, só aparecem na busca depois de validados) e conferência do CRP no CFP; no mínimo, antes do lançamento, cadastre os profissionais você mesmo |
| 2 | **Recuperação de senha e verificação de e-mail** | Não existe envio de e-mail no sistema. Quem esquece a senha perde a conta; e-mails falsos são aceitos | Provedor SMTP (ex.: Amazon SES/Brevo/Resend), fluxo "esqueci a senha" com token de uso único e expiração curta; verificação de e-mail no cadastro |
| 3 | **Textos legais revisados** | Termos e Política são modelos; app trata dados sensíveis de saúde (LGPD art. 11) | Revisão por advogado/encarregado (DPO); definir controlador/operador, bases legais, prazos de retenção, canal do titular; RIPD/DPIA |
| 4 | **Infra real e ensaios** | O deploy só foi provado no CI | VPS + domínio + DNS + HTTPS, `.env` real (`POSTGRES_PASSWORD`, `JWT_SECRET`, `PRONTUARIO_KEYS`, `METRICS_TOKEN`, `DEMO_SEED=false`); rodar o ensaio de restauração e **mover cópias do backup para fora do servidor** |
| 5 | **Chave dos prontuários** | Sem `PRONTUARIO_KEYS`, nem o backup abre os prontuários | Guardar em gerenciador de senhas (2 pessoas), testar restauração com a chave |
| 6 | **Jitsi próprio testado (se vídeo entra no lançamento)** | Nunca transmitiu vídeo de verdade | VPS separada (portas 443/TCP e 10000/UDP), JWT habilitado, teste com 2 aparelhos em redes diferentes (4G x Wi-Fi) por `docs/VIDEO.md`. Se não der tempo: lançar **sem** vídeo (deixar `VIDEO_DOMAIN` vazio — o botão responde 503) |
| 7 | **Fuso horário** | Todas as datas são "locais sem fuso". Quem está em outro fuso (ex.: Manaus x São Paulo) vê/marca horários errados, inclusive a janela do vídeo | Decidir: (a) tudo em um fuso fixo exibido claramente, ou (b) armazenar em UTC + fuso do profissional. (a) é rápido; (b) é o correto |
| 8 | **Configurações do GitHub e segredos** | Alertas de segurança e proteção de branch desligados; token antigo possivelmente ativo | Habilitar Dependency graph, code scanning, secret scanning, Dependabot alerts; proteger `main` (PR + checks obrigatórios); **revogar o token do GitHub colado no chat no início** |
| 9 | **Merge dev → main** | Produção deve sair da `main` com tag `vX.Y.Z` | Após seus ensaios: autorizar o merge do PR #9, tag de release (veja `docs/GUIA-PRODUCAO.md`) |

## 4. Importante (P1 — idealmente antes; no máximo 2 semanas depois)
1. **APK sempre em modo servidor.** Decidir o produto: o modo local (SQLite sem servidor) é confuso em produção. Defina a variável de repositório `API_URL` e, nos builds de release, exija `API_URL` (falhar o build se vazio).
2. **Publicação do APK**: assinatura com keystore própria (segredos `ANDROID_KEYSTORE_*`), conta Play Console, formulário de Segurança de Dados e URL da política de privacidade. Sem a Play Store, o APK é por download direto (instrução ao usuário para permitir instalação).
3. **Lembretes de sessão** por e-mail (reaproveita o SMTP do item P0-2) e notificações; hoje ninguém é avisado.
4. **Autenticação em duas etapas (2FA)** para profissionais (acesso a prontuários).
5. **Bloqueio de captura de tela** (`FLAG_SECURE`) na tela de prontuário do APK; aviso de sessão inativa e bloqueio automático.
6. **Prontuário — requisitos clínicos/legais** (validar com o conselho regional): fechar/assinar registros, exportação em PDF, pedido de cópia pelo paciente, prazo de guarda (5 anos é o referencial usual, confirmar), inclusão do prontuário no fluxo de exportação do profissional (hoje não entra no `GET /auth/eu/exportar`).
7. **Monitoramento e alertas**: o servidor já expõe `/metricas` e logs JSON; falta alguém olhando. Ligar uptime check externo (ex.: UptimeRobot/Better Stack, tem plano gratuito), alerta de disco/erros 5xx, e rotina de verificar o backup do dia.
8. **Limitadores de tentativas em memória** (login, senha, cadastro): reiniciar o contêiner zera; com mais de uma réplica, vale por réplica. Para uma VPS e um processo é aceitável; ao escalar, mover para PostgreSQL/Redis.
9. **Testes de carga e de segurança**: teste de carga simples (ex.: 50 usuários simultâneos agendando) e um pentest/checklist OWASP antes de abrir ao público.
10. **Pagamento**: o sistema só registra valores (financeiro); não cobra. Decidir se o lançamento exige cobrança on-line (Pix/cartão) — é um projeto à parte.
11. **Landing page / SEO**: o Flutter web desenha em canvas, com pouco conteúdo indexável. Para captar pacientes, criar uma página pública simples (HTML) com a entrada para o app.

## 5. Melhorias de qualidade (P2)
- **Telas ainda com `setState` e lógica dentro** (sem testes de widget): Profissionais, Humor, Login, Cadastro, Perfil, Termos, detalhe do paciente. Migrar para Riverpod uma por vez, com testes (padrão já pronto).
- **Fixar a versão do Flutter** nos workflows (hoje `channel: stable` sem versão: um build pode quebrar sozinho quando sai versão nova).
- **E2E instável**: o fluxo "acoes" (humor) falhou uma vez e passou ao repetir. Tornar a espera mais robusta (aguardar a mensagem/linha em vez de tempo fixo).
- **Service Worker não registrado**: o site é instalável (PWA) mas sem cache offline do shell. Fontes de reserva vêm de `fonts.gstatic.com` (chamada externa ao Google): empacotar as fontes e fechar a CSP.
- **Acessibilidade**: revisão com leitor de tela, contraste, tamanhos de fonte e navegação por teclado no site.
- **Paginação por cursor** nas listagens (hoje só há teto de linhas).
- Limpar branches `ci-logs-*`, `v2-app`; resolver PR #8 (docs/`api_url` do APK) e os 6 PRs do Dependabot.

## 6. Plano sugerido até o lançamento (≈ 4 semanas; ajuste à data real)
| Semana | Foco | Entregas |
|---|---|---|
| **1** (28/10–03/11) | Decisões e infra | Escolher domínio/VPS; rodar `tools/run_local_tests.sh dr` e `lan`/`android` e enviar logs; habilitar recursos de segurança do GitHub; revogar token antigo; decidir fuso (P0-7), vídeo no lançamento (sim/não) e modelo de verificação de profissionais (P0-1); contratar revisão jurídica |
| **2** (04–10/11) | Staging real | Deploy em staging com domínio e HTTPS; Jitsi + teste com 2 redes (se entrar); backup offsite + restauração testada; SMTP configurado |
| **3** (11–17/11) | Funcionalidades bloqueadoras | Recuperação de senha + verificação de e-mail; aprovação de profissionais; ajuste de fuso; `API_URL` + APK assinado de release; textos legais aplicados |
| **4** (18–24/11) | Beta fechado | 3–5 profissionais e alguns pacientes reais (com termo de teste); monitoramento e alertas ligados; correções; teste de carga e checklist OWASP |
| **5** (25/11–01/12) | Go/no-go e lançamento | Merge para `main`, tag `v1.0.0`, deploy, plano de rollback ensaiado (`docs/GUIA-PRODUCAO.md`), acompanhamento diário na 1ª semana |

**Critérios de go/no-go:** todos os P0 fechados; ensaio de restauração concluído com sucesso; revisão jurídica dos textos; zero falhas críticas no beta; backup do dia verificado; alguém de plantão na primeira semana.

## 7. Riscos que podem atrasar
- Revisão jurídica e validação dos requisitos de prontuário (depende de terceiros; comece já).
- Jitsi: exige servidor próprio e rede (UDP 10000); se falhar, lançar sem vídeo.
- Verificação de profissionais: processo manual no início; planeje quem faz.
- A pilha só foi testada em CI: o primeiro deploy real costuma revelar ajustes (DNS, firewall, proxy).
