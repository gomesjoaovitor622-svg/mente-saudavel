# Mente Saudável

Aplicação de psicoterapia acessível com Flutter/Dart, API FastAPI e banco PostgreSQL para implantação multiusuário. O app também mantém um modo local com SQLite. O código existente foi preservado; este repositório contém o aplicativo, backend, testes, CI e arquivos de implantação.

## Componentes

| Componente | Caminho | Finalidade |
|---|---|---|
| App Flutter | `lib/` | Cadastro, perfis de paciente/profissional, sessões e diário de humor |
| Backend FastAPI | `server/` | Autenticação, autorização, sessões e registros de humor |
| Implantação | `deploy/` | Docker Compose, PostgreSQL, Caddy/HTTPS e build do site |
| Testes | `test/`, `server/tests/`, `tests/e2e/` | Testes Flutter, API e fluxos de implantação |
| CI/CD | `.github/workflows/` | Análise, testes, build APK, build Web e verificações de segurança |

## Escolha o modo de execução

- **Modo local:** `API_URL` vazio. O aplicativo usa SQLite local; dados não sincronizam entre aparelhos.
- **Modo servidor:** configure `API_URL` para a API. No site hospedado pelo Docker, o build usa `/api` e Caddy encaminha esse caminho ao FastAPI no mesmo domínio.
- **Android com servidor:** compile com `--dart-define=API_URL=https://SEU_DOMINIO/api` ou configure a variável de repositório `API_URL` no GitHub para o workflow Build APK.

## Colocar o sistema no ar

O projeto já tem configuração de implantação, mas **um workflow de build bem-sucedido não significa que o sistema esteja publicado na internet**.

1. Leia o [guia de implantação do site + API + PostgreSQL](deploy/README-DEPLOY.md).
2. É necessário um servidor Linux com Docker/Compose, um domínio apontando para ele e as portas 80/443 acessíveis. Configure o arquivo `deploy/.env` no servidor; nunca envie esse arquivo ao GitHub.
3. Suba a pilha com `docker compose up -d --build` a partir da pasta `deploy/`.
4. Confirme `https://SEU_DOMINIO/api/health` e faça testes reais de cadastro, login, agendamento e diário de humor antes de usar dados reais.
5. Para gerar o site que será servido pelo Caddy, use o serviço `site` do Compose ou o artefato `site-web` do workflow [Site para servidor](.github/workflows/build-site.yml).

### Importante sobre GitHub Pages

O workflow [Publicar versão Web](.github/workflows/deploy-web.yml) publica o exemplo em `exercicios/crud_jsonplaceholder/`; **ele não publica o aplicativo Mente Saudável completo**. O app completo foi projetado para ser servido no mesmo domínio da API por meio de Caddy, porque a sessão Web usa cookie HttpOnly/Secure e proteção anti-CSRF. Não configure o app de produção no GitHub Pages separado da API sem projetar e testar explicitamente outro modelo de autenticação.

## Android (APK)

O workflow [Build APK](.github/workflows/build-apk.yml) compila o APK e publica o artefato `MenteSaudavel-APK` na execução do workflow. Um build de demonstração pode conter contas de teste e pode estar assinado com chave de teste. Para distribuição pública, configure uma chave de assinatura própria e teste atualização/instalação. Para conectar o APK à API, configure `API_URL` no GitHub para a URL HTTPS completa terminada em `/api`, e execute novamente o workflow.

## Validação observada

Em execuções recentes do GitHub Actions (commit `f1085d541679f9997f159d5ae9d6a4f952af11a3`), os jobs de análise Flutter, testes da API com SQLite/PostgreSQL, build Docker, health-check da API, build Web para servidor e build APK terminaram com sucesso. Isso valida os jobs executados naquele commit; não confirma DNS, HTTPS, instalação Android em aparelho real, funcionamento de todos os fluxos ou implantação pública.

- [Execuções do GitHub Actions](https://github.com/gomesjoaovitor622-svg/mente-saudavel/actions)
- [Guia completo do app](LEIA-ME.md)
- [Limitações e riscos residuais de implantação](deploy/README-DEPLOY.md)

## Segurança e privacidade

O projeto lida com informações potencialmente sensíveis de saúde mental. Antes de usar com pacientes reais, revise a política de privacidade, consentimento, retenção e exclusão de dados, controles de acesso, backups e recuperação. Não use as contas de demonstração em produção; mantenha `DEMO_SEED=false` no servidor real.

O pipeline de validação de API em `ci/api-validation/` é uma ferramenta auxiliar de teste e auditoria; não é uma certificação de segurança ou conformidade legal.

## Licença

A licença do projeto ainda precisa ser definida pelo titular.
