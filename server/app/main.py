"""API REST do Mente Saudável. Toda regra de acesso fica aqui, no servidor."""

import logging
import time
import uuid
from collections.abc import Callable
from typing import Any

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import Engine
from sqlalchemy.orm import Session, sessionmaker

from app import prontuario as prontuario_api
from app import tempo
from app import video as video_api
from app.config import Settings, load_settings
from app.conta import Conta
from app.conta import registrar_rotas as registrar_rotas_conta
from app.contexto import Contexto
from app.cripto import CHAVE_DEV, Cofre
from app.db import Base, garantir_colunas, garantir_indices, make_engine, make_session_factory
from app.deps import LimiteLogin, get_db, usuario_atual
from app.emailer import Mailer, NenhumMailer, SmtpMailer
from app.migracoes import exigir_banco_migrado
from app.models import Usuario
from app.observabilidade import REQUEST_ID_RE, Metricas, configurar_logs
from app.rotas import agenda, auth, humor, operacao, profissional


def create_app(settings: Settings | None = None, engine: Engine | None = None, mailer: Mailer | None = None) -> FastAPI:
    cfg = settings or load_settings()
    tempo.definir_fuso(cfg.app_tz)
    eng = engine or make_engine(cfg.database_url)
    if cfg.schema_mode == "alembic":
        # Produção: o esquema só muda por migrações versionadas. Falha ao subir se o banco estiver em outra versão.
        exigir_banco_migrado(eng)
    else:
        Base.metadata.create_all(eng)
        garantir_colunas(eng)
        indices_faltando = garantir_indices(eng)
        if indices_faltando:
            logging.getLogger("mente_saudavel").warning(
                "Há sessões ativas duplicadas: não foi possível criar os índices %s. Cancele as duplicadas e reinicie.", indices_faltando
            )
    factory: sessionmaker[Session] = make_session_factory(eng)
    limite = LimiteLogin(cfg.login_max_attempts)
    limite_cadastro = LimiteLogin(cfg.signup_max_attempts)  # por IP: evita criação em massa de contas
    limite_esqueci_ip = LimiteLogin(10)  # "esqueci a senha" e "redefinir": por IP
    limite_esqueci_email = LimiteLogin(3)  # e-mails de recuperação por endereço (não vira ferramenta de spam)
    limite_codigo_usuario = LimiteLogin(5)  # reenvio/verificação de código por usuário
    mailer = mailer or (SmtpMailer(cfg) if cfg.email_ativo else NenhumMailer())

    app = FastAPI(
        title="Mente Saudável API", version="1.0.0", docs_url="/docs" if cfg.is_dev else None, redoc_url=None, openapi_url="/openapi.json" if cfg.is_dev else None
    )
    app.state.settings = cfg
    app.state.session_factory = factory

    if cfg.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=list(cfg.cors_origins),
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type", "X-Requested-With", "Idempotency-Key", "X-Request-ID"],
            max_age=600,
        )

    log = configurar_logs(cfg.log_level)
    metricas = Metricas()

    @app.middleware("http")
    async def _observar(request: Request, call_next: Callable[..., Any]) -> Response:
        """Cabeçalhos de segurança + id da requisição + 1 linha de log JSON + métricas (sem dados pessoais)."""
        rid = request.headers.get("X-Request-ID", "")
        if not REQUEST_ID_RE.fullmatch(rid):
            rid = uuid.uuid4().hex
        request.state.request_id = rid
        inicio = time.perf_counter()
        try:
            resp: Response = await call_next(request)
        except Exception:  # erro não tratado: registra com a pilha e devolve 500 sem detalhes internos
            log.error("erro_nao_tratado", extra={"campos": {"request_id": rid, "metodo": request.method}}, exc_info=True)
            resp = JSONResponse({"detail": f"Erro interno. Informe o código {rid} ao suporte."}, status_code=500)
        segundos = time.perf_counter() - inicio
        rota = getattr(request.scope.get("route"), "path", None) or "(sem rota)"
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["Cache-Control"] = "no-store"
        resp.headers["Referrer-Policy"] = "no-referrer"
        resp.headers["X-Request-ID"] = rid
        resp.headers["Server-Timing"] = f"app;dur={segundos * 1000:.1f}"
        metricas.observar(request.method, rota, resp.status_code, segundos)
        if rota != "/health":  # o healthcheck do Docker enche o log à toa
            nivel = logging.ERROR if resp.status_code >= 500 else logging.INFO
            log.log(
                nivel,
                "requisicao",
                extra={"campos": {"request_id": rid, "metodo": request.method, "rota": rota, "status": resp.status_code, "duracao_ms": round(segundos * 1000, 1)}},
            )
        return resp

    conta = Conta(cfg, mailer, log)
    registrar_rotas_conta(app, cfg, conta, get_db, usuario_atual, limite_esqueci_ip, limite_esqueci_email, limite_codigo_usuario)

    def _aprovar_por_id(uid: int) -> None:  # usado pelos testes (equivale a `python -m app.admin aprovar`)
        with factory() as s:
            u = s.get(Usuario, uid)
            if u is not None:
                u.verificado_em = tempo.agora()
                s.commit()

    app.state.aprovar = _aprovar_por_id

    ctx = Contexto(cfg, log, metricas, conta, limite, limite_cadastro, LimiteLogin(cfg.telemetry_max_per_minute))
    for modulo in (operacao, auth, agenda, profissional, humor):
        app.include_router(modulo.criar_rotas(ctx))

    cofre = Cofre(cfg.prontuario_chaves or ((CHAVE_DEV,) if cfg.is_dev else ()))
    prontuario_api.registrar_rotas(app, get_db, usuario_atual, cofre, log)
    video_api.registrar_rotas(app, cfg, get_db, usuario_atual, log)

    if cfg.demo_seed:
        from app.seed import popular_demo

        with factory() as db:
            popular_demo(db)

    return app
