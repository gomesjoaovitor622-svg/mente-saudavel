# Política de Segurança

## Versões com suporte
Recebem correções de segurança a última versão publicada (tag `vX.Y.Z`) e a branch padrão.

## Como reportar uma vulnerabilidade
**Não abra issue pública.** Use *Security → Report a vulnerability* neste repositório (relato privado do GitHub).
Inclua: componente afetado, passos para reproduzir, impacto e, se possível, uma sugestão de correção.

## Metas de atendimento (política interna)
| Etapa | Meta |
|---|---|
| Confirmação de recebimento | até 3 dias úteis |
| Triagem e classificação de severidade | até 7 dias úteis |
| Correção de severidade alta/crítica | até 30 dias, com divulgação coordenada |

## Escopo
Dentro do escopo: código deste repositório, workflows de CI/CD, scripts e configurações.
Fora do escopo: ataques de negação de serviço volumétricos, engenharia social, vulnerabilidades em
serviços de terceiros (BrasilAPI, ViaCEP, Jitsi) — reporte-as aos respectivos mantenedores.

## O que o projeto já faz por você
Veja `ci/api-validation/docs/SECURITY-CONTROLS.md` (mapa OWASP Top 10, evidências automatizadas e riscos residuais).

## Se você expôs um segredo
Revogue-o **imediatamente** no provedor (GitHub: *Settings → Developer settings → Tokens*) e só depois
investigue. Remover o texto de um commit não invalida a credencial.
