# Prontuário do psicólogo

Registros clínicos por paciente, **visíveis só para o profissional autor**, guardados **cifrados** no servidor.

## Regras
- Tipos: `evolucao`, `anamnese`, `plano`, `observacao`. Cada registro pode apontar para uma sessão (`sessao_id`).
- **Acesso**: só profissional com vínculo (já tem/teve sessão com o paciente). Sem vínculo ou de outro profissional → 404. O paciente **nunca** recebe o prontuário pela API.
- **Sem exclusão**: não existe `DELETE`. Editar cria uma nova versão e guarda a anterior (`/revisoes`). Edição com versão desatualizada → 409 (evita sobrescrever o que foi alterado em outro aparelho).
- **Auditoria**: toda leitura, criação, edição e consulta de revisões grava `quem/quando/ação/request_id` (nunca o conteúdo). Consulta: `GET /profissional/pacientes/{id}/prontuario/acessos`.
- **Paciente anonimizado** (LGPD): o prontuário existente é mantido (guarda legal), mas não recebe novos registros. Conta de profissional **com prontuário não pode ser apagada** (409).
- Sem registros de conteúdo em logs, métricas ou telemetria. No app, o conteúdo não fica em disco e sai da memória ao fechar a tela.

## Endpoints (profissional autenticado)
| Método e caminho | Função |
|---|---|
| `GET /profissional/pacientes/{id}/prontuario` | Lista os registros |
| `POST /profissional/pacientes/{id}/prontuario` | Cria `{tipo, conteudo, sessao_id?}` |
| `PATCH /profissional/prontuario/{entrada_id}` | Edita `{conteudo, versao_esperada}` |
| `GET /profissional/prontuario/{entrada_id}/revisoes` | Versões anteriores |
| `GET /profissional/pacientes/{id}/prontuario/acessos` | Trilha de auditoria |

## Chaves de cifragem (`PRONTUARIO_KEYS`) — ATENÇÃO
- Cifragem no aplicativo (Fernet: AES-128-CBC + HMAC-SHA256). O banco e os backups só têm texto cifrado.
- **Sem a chave, os prontuários são irrecuperáveis**, inclusive a partir do backup. Guarde uma cópia em gerenciador de senhas, **fora do servidor e fora do backup do banco**.
- Rotação: `PRONTUARIO_KEYS=NOVA,ANTIGA` (a primeira cifra; todas decifram). Depois de re-salvar ou migrar os registros antigos, remova a antiga.
- Obrigatória em produção (a API não sobe sem ela).

## Pontos para validação profissional (não são aconselhamento jurídico)
- Prazo de guarda do prontuário, conteúdo mínimo e direito de acesso do paciente seguem normas do Conselho Federal de Psicologia (ex.: Resoluções CFP 001/2009 e 06/2019) e a LGPD. **Confirme com o conselho regional e um responsável jurídico** antes de operar: por exemplo, como o paciente solicita cópia do documento.
- Cifragem no aplicativo protege contra vazamento do banco/backup, mas o servidor (com a chave) lê o conteúdo; não é cifragem ponta a ponta.

## Nada disso foi testado em uso real
Há testes automatizados (SQLite e PostgreSQL) para permissões, versões, auditoria e cifragem (`server/tests/test_prontuario.py`) e testes de tela no app; falta o teste de usuário com psicólogos reais.
