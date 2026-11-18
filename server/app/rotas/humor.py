"""Diário de humor do paciente."""

from datetime import timedelta
from typing import Annotated, Any

from fastapi import APIRouter, Header, HTTPException, Query, Response
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app import schemas, tempo
from app.contexto import Contexto
from app.deps import CHAVE_IDEMPOTENCIA, Db, Eu
from app.erros import exigir_perfil
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
    def registrar_humor(
        body: schemas.HumorIn,
        user: Eu,
        db: Db,
        response: Response,
        chave: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    ) -> dict[str, Any]:
        """Registra o humor. Com `Idempotency-Key`, reenviar o mesmo registro (fila offline do app) devolve
        o que já existe (200) em vez de criar outro."""
        exigir_perfil(user, "paciente")
        if chave is not None and not CHAVE_IDEMPOTENCIA.fullmatch(chave):
            raise HTTPException(422, "Idempotency-Key inválida (8 a 64 letras, números, '-' ou '_').")

        def _existente() -> Humor | None:
            if chave is None:
                return None
            return db.scalar(select(Humor).where(Humor.usuario_id == user.id, Humor.chave_idempotencia == chave))

        if (ja := _existente()) is not None:
            response.status_code = 200
            return humor_out(ja)
        h = Humor(
            usuario_id=user.id,
            nivel=body.nivel,
            nota=body.nota,
            data_hora=body.data_hora or tempo.agora().replace(microsecond=0),
            chave_idempotencia=chave,
        )
        db.add(h)
        try:
            db.commit()
        except IntegrityError:  # duas requisições com a mesma chave ao mesmo tempo: a perdedora devolve a vencedora
            db.rollback()
            if (ja := _existente()) is None:
                raise
            response.status_code = 200
            return humor_out(ja)
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
