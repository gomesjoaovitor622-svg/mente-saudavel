# Banco de dados do Mente Saudável

O app usa **SQLite**, um banco em arquivo (`mente_saudavel.db`) que fica **dentro do próprio aparelho**
(no celular) ou **no navegador** (na versão web). Não existe servidor: cada aparelho tem o seu banco.

## Arquivos desta pasta
| Arquivo | O que é |
|---|---|
| `mente_saudavel_exemplo.db` | Banco SQLite pronto, com a mesma estrutura do app e os dados de demonstração |
| `mente_saudavel_schema.sql` | Só a estrutura (CREATE TABLE / INDEX) |
| `mente_saudavel_dados_demo.sql` | Estrutura + dados de demonstração (script completo) |
| `consultas_uteis.sql` | 8 consultas prontas (JOINs, agenda, médias...) |

## Como abrir no computador
1. Instale o **DB Browser for SQLite** (gratuito): https://sqlitebrowser.org
2. *Abrir banco de dados* → escolha `mente_saudavel_exemplo.db`.
3. Aba **Estrutura do banco** (tabelas), **Navegar dados** (linhas) e **Executar SQL** (cole as consultas de `consultas_uteis.sql`).

Sem instalar nada: o site https://sqliteviewer.app abre o `.db` direto no navegador (o arquivo não sai do seu computador).
Alternativas: DBeaver, ou a extensão "SQLite Viewer" do VS Code.

## Ver o banco REAL do seu app
- **Dentro do app:** *Perfil → Ver banco de dados (SQLite)*. Mostra tabelas, estrutura, dados, consultas SELECT e
  o botão **Copiar script SQL completo** (cole no DB Browser: *Arquivo → Importar* ou na aba Executar SQL).
  As senhas (`senha_hash`, `salt`) ficam ocultas.
- O arquivo real do celular fica na pasta privada do app e **não pode ser copiado em um APK de release**
  (só com root ou em build de debug via `adb`). Por isso existe a tela de exportação acima.

## Tabelas
```text
usuarios (id PK, nome, email UNIQUE, senha_hash, salt, perfil, registro, especialidade, endereco, criado_em)
sessoes (id PK, paciente_id FK, profissional_id FK, data_hora, modalidade, status, anotacoes, criado_em)
humor_registros (id PK, usuario_id FK, nivel 1..5, nota, data_hora)
app_sessao (id = 1, usuario_id FK)   -- quem está logado
```
