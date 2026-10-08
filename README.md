# Mente Saudável + API Validation

Aplicativo de psicoterapia acessível (Flutter, SQLite local) **e** um pipeline de validação contínua de APIs
(contrato, CORS e segurança) com relatórios de conformidade, pronto para ser reutilizado em outros produtos.

[![API Validation](https://github.com/gomesjoaovitor622-svg/mente-saudavel/actions/workflows/api-validation.yml/badge.svg?branch=dev)](https://github.com/gomesjoaovitor622-svg/mente-saudavel/actions/workflows/api-validation.yml)
[![Security](https://github.com/gomesjoaovitor622-svg/mente-saudavel/actions/workflows/security.yml/badge.svg?branch=dev)](https://github.com/gomesjoaovitor622-svg/mente-saudavel/actions/workflows/security.yml)
[![CodeQL](https://github.com/gomesjoaovitor622-svg/mente-saudavel/actions/workflows/codeql.yml/badge.svg?branch=dev)](https://github.com/gomesjoaovitor622-svg/mente-saudavel/actions/workflows/codeql.yml)

## O que há aqui
| Parte | Descrição | Documentação |
|---|---|---|
| **Pipeline de validação** (`ci/api-validation/`) | Valida OpenAPI, CORS e segurança; diagnostica falhas; gera relatório executivo com atestado SLSA | [README](ci/api-validation/README.md) |
| **App Mente Saudável** (`lib/`) | Cadastro, agenda de sessões, diário de humor; Android e web | [Guia do app](LEIA-ME.md) |
| **CI/CD** (`.github/workflows/`) | 7 workflows com permissões mínimas e actions fixadas por SHA | [Implantação](ci/api-validation/docs/DEPLOYMENT.md) |

## Postura de segurança (resumo)
- Actions **fixadas por SHA**, permissões mínimas por job, zero injeção de template (verificado por `zizmor` e `actionlint`).
- Dependências **com hash** (`--require-hashes`), auditoria de CVEs, SBOM, revisão de dependências, Dependabot com espera.
- Segredos e **dados pessoais mascarados** em todo log e relatório; varredura de vazamento do token efêmero.
- Serviço de teste isolado: `env -i`, somente loopback, token efêmero, timeout de socket.
- Tipagem estrita, SAST, cobertura ≥ 90%, e o teste dos testes (defeitos injetados são todos detectados).

Detalhes, evidências e **riscos residuais** em [SECURITY-CONTROLS.md](ci/api-validation/docs/SECURITY-CONTROLS.md).
Para reportar vulnerabilidades: [SECURITY.md](SECURITY.md).

## Para começar
- Rodar o pipeline localmente: [ci/api-validation/README.md](ci/api-validation/README.md#início-rápido-local).
- Implantar em um cliente: [DEPLOYMENT.md](ci/api-validation/docs/DEPLOYMENT.md).
- Algo falhou? [TROUBLESHOOTING.md](ci/api-validation/docs/TROUBLESHOOTING.md).
- Baixar o app: *Releases* (builds de produção por tag `vX.Y.Z`) ou *Actions → Build APK → Run workflow* (demonstração).

## Status do produto (franqueza comercial)
O **pipeline** está pronto para uso e auditoria técnica. O **app** é um protótipo funcional com limitações que impedem
a venda como produto multiusuário (autenticação local, dados sem criptografia em repouso, sem backend): veja os riscos
R1–R5 em SECURITY-CONTROLS.md e o plano sugerido abaixo.

| Prioridade | Entrega | Resultado |
|---|---|---|
| 1 | Backend (API + banco) validado por este pipeline | Multiusuário real |
| 2 | Hash de senha forte + criptografia em repouso + LGPD (consentimento, política, DPO) | Conformidade de dados sensíveis |
| 3 | Assinatura de produção + testes do app + pentest | Pronto para a loja |

## Licença
A definir pelo titular do projeto (nenhuma licença foi escolhida).
