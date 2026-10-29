"""Saúde, configuração pública, telemetria do app e métricas."""

import hmac
from typing import Any

from fastapi import APIRouter, HTTPException, Request, Response
from fastapi.responses import PlainTextResponse
from sqlalchemy import select

from app import schemas, tempo
from app.contexto import Contexto
from app.deps import Db
from app.observabilidade import limpar_texto_cliente


def criar_rotas(ctx: Contexto) -> APIRouter:
    router = APIRouter()
    cfg = ctx.cfg
    log = ctx.log
    metricas = ctx.metricas
    limite_telemetria = ctx.limite_telemetria

    # ------------------------------------------------------------------ saúde
    @router.get("/health")
    def health(db: Db) -> dict[str, str]:
        db.execute(select(1))
        return {"status": "ok"}

    @router.get("/config")
    def configuracao() -> dict[str, Any]:
        """Informações públicas para o app (sem segredos): fuso dos horários e recursos ligados."""
        return {"fuso": tempo.nome_do_fuso(), "fuso_rotulo": tempo.rotulo_do_fuso(), "email_ativo": cfg.email_ativo, "video_ativo": bool(cfg.video_domain)}

    # ----------------------------------------------------------- telemetria e métricas
    @router.post("/telemetria", status_code=204)
    def receber_telemetria(body: schemas.TelemetriaIn, request: Request) -> Response:
        """Erros e tempos medidos pelo app, gravados como logs JSON. Aberto (o erro pode ocorrer antes do
        login), por isso tem limite por IP, tamanho máximo e remove e-mails dos textos."""
        limite_telemetria.checar(request.client.host if request.client else "?")
        for e in body.eventos:
            log.info(
                "evento_cliente",
                extra={
                    "campos": {
                        "request_id": request.state.request_id,
                        "origem": "app",
                        "tipo": limpar_texto_cliente(e.tipo, 20),
                        "nome": limpar_texto_cliente(e.nome, 80),
                        "duracao_ms": e.duracao_ms,
                        "status": e.status,
                        "mensagem": limpar_texto_cliente(e.mensagem, 300),
                        "pilha": limpar_texto_cliente(e.pilha, 4000),
                        "versao_app": limpar_texto_cliente(body.versao_app, 20),
                        "plataforma": limpar_texto_cliente(body.plataforma, 20),
                    }
                },
            )
        return Response(status_code=204)

    @router.get("/metricas", response_class=PlainTextResponse)
    def exportar_metricas(request: Request) -> Response:
        """Formato Prometheus. Desligado (404) sem METRICS_TOKEN; com ele exige `Authorization: Bearer`."""
        if not cfg.metrics_token:
            raise HTTPException(404, "Não encontrado.")
        enviado = request.headers.get("Authorization", "").removeprefix("Bearer ")
        if not hmac.compare_digest(enviado.encode(), cfg.metrics_token.encode()):
            raise HTTPException(401, "Não autenticado.")
        return PlainTextResponse(metricas.texto())

    return router
