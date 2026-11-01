# Arquitetura do servidor (FastAPI)

```
server/app/
  main.py          monta o app: CORS, middlewares (segurança, limite de corpo, log), handlers de erro, rotas
  config.py        lê e valida o ambiente (falha ao subir se faltar segredo)
  contexto.py      o que as rotas recebem do servidor (config, log, métricas, limites, e-mail)
  deps.py          dependências HTTP: sessão do banco, usuário logado (JWT/cookie), limite de tentativas
  erros.py         ErroDeNegocio (sem HTTP) + exigir_perfil; main.py traduz para o mesmo JSON de sempre
  schemas.py       validação de entrada (Pydantic, extra=forbid, sem NUL, tamanhos máximos)
  saidas.py        formato das respostas
  rotas/           só HTTP: operacao, auth, agenda, profissional (inclui prontuário), humor  (+ conta, video)
  servicos/        regras de negócio, sem HTTP: agenda, financeiro, prontuario (cifrado, com revisões e auditoria)
  models.py        tabelas;  db.py/migracoes.py  banco e migrações Alembic;  admin.py  CLI de aprovação
```

Regras de estilo: rota fina (valida, chama serviço, monta resposta); serviço levanta `ErroDeNegocio`;
nenhuma consulta por linha (relacionamentos `lazy="joined"`, agregações no banco); datas sempre via `app.tempo`.

Segurança na borda: 422 sem o valor enviado; corpo máximo (`MAX_BODY_BYTES`, e `max_size` no Caddy);
CORS só com origens listadas (sem `*`, sem credenciais); 500 sem detalhes (só o código da requisição);
toda variável lida em `config.py` precisa estar no `deploy/.env.example` e no compose (teste automático).
