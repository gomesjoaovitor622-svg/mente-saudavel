# Guia de implantação (para clientes e equipes)

Tempo estimado: 30–45 minutos. Pré-requisito: conta GitHub com permissão de administração no repositório.

## 1. Obter o código
- **Organização do cliente:** *Use this template* / importe o repositório para a organização.
- Mantenha as pastas `.github/`, `ci/api-validation/` e os arquivos `.secrets.baseline` e `SECURITY.md`.

## 2. Endurecer o repositório (Settings)
| Onde | Ação | Por quê |
|---|---|---|
| *Actions → General → Workflow permissions* | **Read repository contents** (padrão somente leitura) | Cada job já pede só o que precisa |
| *Actions → General → Actions permissions* | Marque **Require actions to be pinned to a full-length commit SHA** | Impede que alguém adicione action sem SHA |
| *Code security* | Ative **Dependabot alerts**, **Dependabot security updates**, **Secret scanning** e **Push protection** | Camadas adicionais às do pipeline |
| *Code security* | Ative **Private vulnerability reporting** | Canal descrito em `SECURITY.md` |
| *Rules → Rulesets → Import* | Importe `.github/rulesets/main-protection.json` | Exige PR, 1 aprovação de dono do código e os checks `Gate`, `Security Gate`, `flutter analyze`, `Analyze (python)` |
| *Settings → Pages → Source* | **GitHub Actions** (somente se for publicar o site) | Necessário para `deploy-web.yml` |

> Repositório de uma pessoa só? No ruleset, troque `required_approving_review_count` para `0` e
> `require_code_owner_review` para `false`, senão ninguém consegue aprovar o próprio PR.

## 3. Segredos (opcionais)
| Segredo | Quando | Como obter |
|---|---|---|
| `API_AUTH_TOKEN` | Só se **o seu backend** exigir token e você apontar o pipeline para ele | Gere um token de uso exclusivo para testes; o pipeline nunca o envia a terceiros |
| `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Para APK **assinado com a sua chave** (atualizável e publicável) | `keytool -genkeypair -v -keystore release.jks -alias app -keyalg RSA -keysize 2048 -validity 10000` e `base64 -w0 release.jks` |

Guarde o `release.jks` em cofre. **Se perder a chave, não será possível atualizar o app já instalado.**

## 4. Apontar o pipeline para o SEU backend
1. Descreva as rotas e os casos em `contracts/openapi.yaml` (`paths`, `components`, `x-conformance`, `x-cors`).
2. Rode manualmente: *Actions → API Validation → Run workflow* com:
   - `service_start_command`: `python caminho/seu_servico.py` (apenas `python [-m] caminho`; qualquer outro formato é recusado);
   - `target_origin`: a origem do seu front-end (`https://app.seudominio.com`);
   - `health_timeout`: segundos de boot do seu serviço.
3. Para um backend que **não** é Python, inicie-o em um passo anterior e use `service_start_command` com um script curto que o aguarde, ou adapte o passo "Iniciar o serviço" (ele já faz health-check, isolamento e encerramento).

## 5. Verificação pós-implantação (checklist)
- [ ] Abra um PR de teste: devem rodar `Quality`, `Reference (py3.11/3.12/3.13)`, `Gate`, `Security Gate`, `CodeQL`, `Dependency Review`.
- [ ] O PR não pode ser mesclado com `Gate` vermelho.
- [ ] Em *Actions → (execução) → Summary* aparece o **Diagnóstico automático** e o **Relatório Executivo**.
- [ ] O artefato `executive-report` existe (retenção 90 dias) e `gh attestation verify` valida (ver `OPERATIONS.md`).
- [ ] *Security → Code scanning* mostra a análise CodeQL.

## 6. Atualizar dependências
`make lock` (requer `uv`) regenera os arquivos com hash; o Dependabot abre PRs de actions e pip com espera de 7 dias.
