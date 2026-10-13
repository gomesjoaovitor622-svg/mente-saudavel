# API Mente Saudável

FastAPI + SQLAlchemy. Banco: PostgreSQL (produção) ou SQLite (testes).

```bash
cd server
python -m pip install --require-hashes -r requirements-dev.txt
python -m pytest -q                                   # testes em SQLite
TEST_DATABASE_URL=postgresql+psycopg://user:pw@localhost/ms python -m pytest -q   # em PostgreSQL

# rodar localmente (modo desenvolvimento: docs em /docs, segredo de teste)
APP_ENV=development DEMO_SEED=true uvicorn app.main:create_app --factory --reload
```

Segurança já aplicada: senhas com **scrypt**; JWT HS256 com expiração; `JWT_SECRET` obrigatório e validado;
CORS por origem exata; limite de tentativas de login; mesma resposta/tempo para e-mail inexistente;
**404 (não 403)** para recursos de outras pessoas; anotações clínicas **nunca** enviadas ao paciente;
validação estrita (`extra=forbid`) e docs desligados em produção.

Rotas principais: `POST /auth/cadastro|entrar`, `GET|PATCH|DELETE /auth/eu`, `GET /profissionais`,
`GET|POST|PATCH|DELETE /sessoes`, `PUT /sessoes/{id}/avaliacao`, `GET|POST|DELETE /humor`, `GET /health`.
Em desenvolvimento a lista completa está em `/docs`.
