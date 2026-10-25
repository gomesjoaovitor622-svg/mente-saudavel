# Mente Saudável — app Flutter, modo local e modo servidor

Aplicativo de **psicoterapia acessível** com perfis de **Paciente** e **Profissional**, agenda de sessões e diário de humor.
O projeto oferece dois modos: **local**, usando SQLite no aparelho, e **servidor**, usando a API FastAPI e o banco PostgreSQL
configurados em `server/` e `deploy/`. O modo usado depende da flag de compilação `API_URL`. A existência do código e dos
builds de CI não significa que o servidor já esteja publicado na internet.

## 1. Como obter o APK

O APK é compilado na nuvem (GitHub Actions). Há dois tipos de build:

| Tipo | Como gerar | Contas/dados de demonstração |
|---|---|---|
| **Demonstração** | *Actions → Build APK → Run workflow* (`demo = true`; marque `release = true` para publicar) ou qualquer push em `dev`/`main` (fica como artefato) | Sim (login mostra as contas de teste) |
| **Produção** | Criar uma tag: `git tag v1.0.0 && git push origin v1.0.0` | **Não** (sem contas, sem dados de exemplo) |

Onde baixar: aba **Releases** do repositório (builds publicados) ou, no run do workflow, o artefato `MenteSaudavel-APK`
(contém o `.apk` e o `.sha256` para conferir a integridade).

Instalação: baixe no celular, abra o arquivo e permita "Instalar apps desconhecidos". O Play Protect pode avisar
quando o APK está com assinatura de **teste**; configure a assinatura de produção
(`ci/api-validation/docs/DEPLOYMENT.md`, §3) para que o app possa ser **atualizado por cima** de versões anteriores.

> Rodar localmente com dados de exemplo: `flutter run --dart-define=DEMO_MODE=true`.

## 2. Versão Web (aplicativo completo)

O aplicativo completo é compilado pelo workflow **Site para servidor** (`.github/workflows/build-site.yml`) e pelo serviço `site`
em `deploy/docker-compose.yml`. O artefato `site-web` é um pacote de arquivos estáticos; ele não inclui a API nem o banco.

**Implantação recomendada:** sirva o site e a API no **mesmo domínio** usando o Caddy e Docker Compose descritos em
[`deploy/README-DEPLOY.md`](deploy/README-DEPLOY.md). A API fica em `/api`, e o site em `/`. Isso é importante porque a
sessão Web usa cookie HttpOnly/Secure e proteção anti-CSRF.

**Atenção:** o workflow **Publicar versão Web** (`.github/workflows/deploy-web.yml`) publica apenas o exemplo
`exercicios/crud_jsonplaceholder/`; ele **não publica** o Mente Saudável completo. Não use o endereço do GitHub Pages desse
exemplo como se fosse o sistema de psicoterapia. Para publicar o aplicativo real, configure o servidor e o domínio conforme
o guia de implantação.

O APK Android é independente do site. Para conectá-lo à mesma API, ao executar manualmente o workflow Build APK informe
`api_url` como URL HTTPS completa terminada em `/api`, ou configure a variável de repositório `API_URL`. Se ambas estiverem vazias,
o APK é compilado no modo local SQLite.

## 3. Como rodar no computador (opcional)

```bash
flutter create --platforms=android --project-name mente_saudavel .
# no AndroidManifest.xml (android/app/src/main/), antes de <application>, adicione:
#   <uses-permission android:name="android.permission.INTERNET"/>
flutter pub get
flutter run
```

## 4. Contas de demonstração (criadas automaticamente na 1ª execução)

| Perfil | E-mail | Senha |
|---|---|---|
| Profissional | `helena@mentesaudavel.app` | `mente123` |
| Profissional | `rafael@mentesaudavel.app` / `beatriz@mentesaudavel.app` | `mente123` |
| Paciente | `carlos@email.com` | `123456` |

Você também pode criar sua própria conta (fluxo do vídeo). Uma conta nova começa vazia; para ver o painel do
profissional com dados, crie um paciente e agende uma sessão com o profissional.

## 5. Funcionalidades

**Conta (CRUD de usuários)**
- Criar conta em 3 passos (e-mail/senha → nome → Paciente ou Profissional; profissional informa CRP e especialidade).
- Entrar / sair; o login fica salvo no SQLite e o app abre direto no painel certo.
- Editar perfil, alterar senha, **excluir conta** (apaga em cascata sessões e humor).

**Paciente**
- *Início:* próxima sessão (nome, CRP, data, modalidade), sessões concluídas, dias até a próxima, ações rápidas, frase do dia.
- *Agendar sessão:* escolhe profissional, data, horário e Online/Presencial. Horários ocupados ficam bloqueados (consulta ao banco).
- *Sessões:* lista com filtro (todas/agendadas/concluídas/canceladas), **remarcar**, **cancelar**, **excluir do histórico**.
- *Humor:* diário (1 a 5 + nota), média dos últimos 7 dias, histórico com exclusão.

**Profissional**
- *Painel:* atendimentos hoje, pacientes ativos, agenda de hoje (números calculados no banco).
- *Agenda:* navegação dia a dia; abrir sessão → **concluir**, **cancelar**, **anotações privadas**.
- *Pacientes:* lista com busca, total/concluídas/próxima sessão e histórico individual.
- *Perfil:* CRP, especialidade e endereço do consultório (com busca por CEP).

**APIs (opcionais, sem chave; se falharem o app segue normal)**
- **BrasilAPI** — avisa quando a data escolhida é feriado nacional.
- **ViaCEP** — preenche o endereço do consultório a partir do CEP.

## 6. Banco de dados (SQLite)

```text
usuarios (id PK, nome, email UNIQUE NOCASE, senha_hash, salt, perfil, registro, especialidade, endereco, criado_em)
   │1                                  │1
   └──< sessoes (id PK, paciente_id FK, profissional_id FK, data_hora, modalidade, status, anotacoes, criado_em)
   └──< humor_registros (id PK, usuario_id FK, nivel 1..5, nota, data_hora)
   └──< app_sessao (id=1, usuario_id FK)   -- quem está logado
```
- `CHECK` garante perfil, status e nível válidos; `FOREIGN KEY ... ON DELETE CASCADE` mantém a integridade.
- Senhas do modo local são gravadas como **PBKDF2-HMAC-SHA256 (100 mil iterações, sal por usuário)** (nunca em texto puro). Contas antigas com SHA-256 entram normalmente e são convertidas no primeiro login. No modo servidor a senha usa scrypt, no servidor.
- Banco criado e populado no `onCreate`; `onOpen` roda o script `IF NOT EXISTS` (auto-correção).

### Como ver e usar o banco
- **No app:** *Perfil → Ver banco de dados (SQLite)*: tabelas, estrutura, dados, consultas SELECT (somente leitura) e
  botão **Copiar script SQL completo**. As senhas ficam ocultas. Funciona no celular e na web.
- **No computador:** a pasta `banco_de_dados/` tem um `.db` de exemplo, o script SQL e consultas prontas
  (abra no DB Browser for SQLite ou em sqliteviewer.app). Veja `banco_de_dados/LEIA-ME_BANCO.md`.

## 7. Estrutura do código (para explicar na apresentação)

```text
lib/
├── main.dart                 tema, idioma pt-BR e AuthGate (decide login / painel paciente / painel profissional)
├── models/                   Usuario, Sessao (+PacienteResumo), HumorRegistro: toMap()/fromMap()
├── database/
│   ├── database_helper.dart  Singleton: abre o banco, ativa foreign_keys, chama schema e seed
│   ├── database_schema.dart  scripts CREATE TABLE / INDEX
│   ├── database_seed.dart    dados de demonstração
│   └── *_dao.dart            CRUD e consultas (INSERT, SELECT/JOIN, UPDATE, DELETE)
├── services/                 auth_service (login/cadastro), seguranca (hash), api_service (BrasilAPI, ViaCEP)
├── widgets/                  componentes reutilizáveis e o painel de detalhes da sessão
├── utils/                    formatação de datas em português, validadores
└── screens/                  login, cadastro, perfil, paciente/*, profissional/*
```

Padrão: **Tela → Service/DAO → SQLite**. As telas nunca escrevem SQL.

## 8. Pendências e limitações (honestidade técnica)

| Item | Situação |
|---|---|
| Build APK no GitHub Actions | **Executado com sucesso** em uma execução recente. Isso não substitui teste de instalação em aparelho Android real. |
| Build Web para servidor | **Executado com sucesso** em uma execução recente; o artefato é gerado, mas precisa ser implantado no servidor. |
| Testes da API | Jobs recentes passaram em SQLite e PostgreSQL no CI; isso não confirma que há uma instância pública ativa. |
| Publicação pública do app completo | **Ainda não confirmada.** É necessário configurar servidor, domínio, DNS e HTTPS. |
| Login com Google/Apple | Não deve ser considerado implementado sem configuração e validação específicas. |
| Assinatura do APK | Sem os segredos de keystore configurados, o workflow usa assinatura de teste; não é adequado para Play Store nem garante atualização sobre outra assinatura. |

As execuções recentes podem ser consultadas na aba [Actions](https://github.com/gomesjoaovitor622-svg/mente-saudavel/actions).
Consulte também [deploy/README-DEPLOY.md](deploy/README-DEPLOY.md) antes de configurar um servidor.
