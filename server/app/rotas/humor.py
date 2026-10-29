"""Diário de humor do paciente."""

from datetime import timedelta
from typing import Any

from fastapi import APIRouter, HTTPException, Query, Response
from sqlalchemy import select

from app import schemas, tempo
from app.contexto import Contexto
from app.deps import Db, Eu, exigir_perfil
from app.models import Humor
from app.saidas import humor_out


def criar_rotas(ctx: Contexto) -> APIRouter:
    router = APIRouter()

    # ------------------------------------------------------------------- humor
    @router.get("/humor")
    def listar_humor(user: Eu, db: Db, limite: int = Query(default=50, ge=1, le=1000), dias: int | None = Query(default=None, ge=1, le=3650)) -> list[dict[str, Any]]:
        exigir_perfil(user, "paciente")
        stmt = select(Humor).where(Humor.usuario_id == user.id)
        if dias:
            stmt = stmt.where(Humor.data_hora >= tempo.agora() - timedelta(days=dias))
        stmt = stmt.order_by(Humor.data_hora.desc()).limit(limite)
        return [humor_out(h) for h in db.scalars(stmt)]

    @router.post("/humor", status_code=201)
    def registrar_humor(body: schemas.HumorIn, user: Eu, db: Db) -> dict[str, Any]:
        exigir_perfil(user, "paciente")
        h = Humor(usuario_id=user.id, nivel=body.nivel, nota=body.nota, data_hora=body.data_hora or tempo.agora().replace(microsecond=0))
        db.add(h)
        db.commit()
        return humor_out(h)

    @router.delete("/humor/{humor_id}", status_code=204)
    def excluir_humor(humor_id: int, user: Eu, db: Db) -> Response:
        h = db.get(Humor, humor_id)
        if h is None or h.usuario_id != user.id:
            raise HTTPException(404, "Registro não encontrado.")
        db.delete(h)
        db.commit()
        return Response(status_code=204)

    return router
