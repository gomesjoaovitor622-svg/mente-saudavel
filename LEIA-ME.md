# Mente Saudável — app Flutter com SQLite (CRUD completo)

App de **psicoterapia acessível** baseado no vídeo enviado: criar conta em passos, escolher **Paciente** ou
**Profissional**, painel de cada perfil, agendamento de sessões. **Todos os dados ficam em um banco SQLite local**
no celular (`mente_saudavel.db`), e o app funciona offline. As APIs (feriados e CEP) são opcionais.

## 1. Como baixar o APK no celular (sem instalar nada no PC)

O APK é compilado na nuvem pelo **GitHub Actions** (gratuito). Passo a passo:

1. No GitHub, crie um repositório novo (sugestão: **público**, minutos de Actions ilimitados). Ex.: `mente-saudavel`.
2. Envie **todo o conteúdo desta pasta** para o repositório (inclusive a pasta oculta `.github`).
   - Pelo site: *Add file → Upload files*, arraste as pastas `lib`, `.github` e os arquivos `pubspec.yaml`, `.gitignore`, `LEIA-ME.md`.
   - Ou pelo terminal:
     ```bash
     git init && git add . && git commit -m "Mente Saudavel"
     git branch -M main
     git remote add origin https://github.com/SEU_USUARIO/mente-saudavel.git
     git push -u origin main
     ```
3. Abra a aba **Actions**. O workflow **Gerar APK** começa sozinho (leva ~5 a 10 min). Se não começar:
   *Actions → Gerar APK → Run workflow*.
4. Quando ficar verde ✓, abra **Releases** (coluna da direita do repositório): lá está o `app-release.apk`.
   - No **celular**, abra a página do repositório no navegador, entre em Releases e toque no APK para baixar.
   - Ou baixe no PC, em *Actions → (execução) → Artifacts → MenteSaudavel-APK*, e passe para o celular.
5. Abra o arquivo baixado e permita **"Instalar apps desconhecidos"** para o navegador/gerenciador de arquivos.
   O Play Protect pode avisar que o app não é conhecido: é normal, o APK é assinado com a chave de debug.

> Se o build falhar, abra a execução em Actions, clique no passo vermelho e me envie o texto do erro.

## 2. Versão Web (site no GitHub Pages)

O mesmo código roda no navegador, com o SQLite compilado para WebAssembly (os dados ficam no **IndexedDB do
navegador**, separados por aparelho/navegador). O workflow `Publicar versão Web` faz tudo sozinho:

1. No repositório: **Settings → Pages → Build and deployment → Source: GitHub Actions** (faça isso uma vez).
2. Envie o código (ou rode *Actions → Publicar versão Web → Run workflow*).
3. Ao terminar (✓), o endereço aparece no próprio workflow e em *Settings → Pages*:
   `https://SEU_USUARIO.github.io/NOME_DO_REPOSITORIO/`

Observações:
- O GitHub Pages é gratuito para repositórios **públicos** (em privados exige plano pago).
- O código do celular **não muda**: o suporte web é aplicado só durante o build do site
  (`web_overrides/database_factory_setup.web.txt` + pacote `sqflite_common_ffi_web`), então o APK não é afetado.
- Se o repositório se chamar `SEU_USUARIO.github.io`, troque `--base-href` no workflow por `"/"`.
- BrasilAPI e ViaCEP, no navegador, dependem de permitirem chamadas de outro site (CORS). Isso **não foi testado**;
  se não permitirem, o app continua funcionando e apenas some o aviso de feriado / a busca de CEP.

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
- Senhas são gravadas como **SHA-256 com sal** (nunca em texto puro).
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
| Compilar o APK | **Não foi executado.** O workflow está pronto, mas só o primeiro build no GitHub Actions confirma que compila. |
| Compilar o site (web) | **Não foi executado**, pelo mesmo motivo. |
| BrasilAPI / ViaCEP | **Não testadas** (sem acesso à internet no ambiente de desenvolvimento), nem no celular nem no navegador (CORS). |
| Login com Google/Apple (do vídeo) | **Não implementado.** Exige conta no Google Cloud (OAuth), SHA-1 de uma chave de assinatura fixa e, para Apple, conta de desenvolvedor paga. |
| Autenticação | **Local** (sem servidor). Serve para o trabalho, não para produção; dados não sincronizam entre aparelhos. |
| Assinatura do APK | Chave de debug. Instala normalmente, mas não serve para a Play Store. |

Verificado: sintaxe dos 32 arquivos Dart (parser), uso correto de `const`, e todo o SQL do app executado em SQLite real
(criação das tabelas, restrições, conflito de horário, cascata e números dos painéis).
