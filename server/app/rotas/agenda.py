"""Busca de profissionais, sessões e avaliações."""

from datetime import datetime, timedelta
from typing import Annotated, Any

from fastapi import APIRouter, Header, HTTPException, Query, Response
from sqlalchemy import func, select

from app import schemas
from app.contexto import Contexto
from app.deps import CHAVE_IDEMPOTENCIA, Db, Eu
from app.erros import exigir_perfil
from app.models import Avaliacao, Sessao, Usuario
from app.saidas import avaliacao_out, sessao_out
from app.servicos import agenda as svc


def criar_rotas(ctx: Contexto) -> APIRouter:
    router = APIRouter()
    cfg = ctx.cfg

    # ----------------------------------------------------------- profissionais
    @router.get("/profissionais")
    def profissionais(user: Eu, db: Db, q: str = Query(default="", max_length=80)) -> list[dict[str, Any]]:
        termo = f"%{q.strip()}%"
        media = func.avg(Avaliacao.nota)
        stmt = (
            select(Usuario, media.label("media"), func.count(Avaliacao.id).label("total"))
            .outerjoin(Avaliacao, Avaliacao.profissional_id == Usuario.id)
            .where(Usuario.perfil == "profissional", Usuario.verificado_em.is_not(None))  # só profissionais aprovados
            .where(Usuario.nome.ilike(termo) | func.coalesce(Usuario.especialidade, "").ilike(termo))
            .group_by(Usuario.id)
            .order_by(media.is_(None), media.desc(), func.lower(Usuario.nome))
        )
        return [
            {
                "id": u.id,
                "nome": u.nome,
                "registro": u.registro,
                "especialidade": u.especialidade,
                "endereco": u.endereco,
                "valor_sessao_centavos": u.valor_sessao_centavos,
                "media": float(m) if m is not None else None,
                "total": int(t),
            }
            for u, m, t in db.execute(stmt).all()
        ]

    @router.get("/profissionais/{prof_id}/avaliacoes")
    def avaliacoes_do_profissional(prof_id: int, user: Eu, db: Db, limite: int = Query(default=30, ge=1, le=1000)) -> list[dict[str, Any]]:
        stmt = select(Avaliacao).where(Avaliacao.profissional_id == prof_id).order_by(Avaliacao.criado_em.desc()).limit(limite)
        # O nome completo do paciente só aparece para ele mesmo e para o profissional avaliado.
        return [avaliacao_out(a, user.id in (prof_id, a.paciente_id)) for a in db.scalars(stmt)]

    @router.get("/profissionais/{prof_id}/horas-ocupadas")
    def horas_ocupadas(prof_id: int, user: Eu, db: Db, dia: datetime) -> list[int]:
        inicio = dia.replace(hour=0, minute=0, second=0, microsecond=0)
        stmt = select(Sessao.data_hora).where(
            Sessao.profissional_id == prof_id,
            Sessao.status != "cancelada",
            Sessao.data_hora >= inicio,
            Sessao.data_hora < inicio + timedelta(days=1),
        )
        return sorted({d.hour for d in db.scalars(stmt)})

    # ----------------------------------------------------------------- sessões
    @router.get("/sessoes")
    def listar_sessoes(
        user: Eu,
        db: Db,
        status: schemas.StatusSessao | None = None,
        de: datetime | None = None,
        ate: datetime | None = None,
        nao_canceladas: bool = False,
        paciente_id: int | None = None,
        limite: int = Query(default=1000, ge=1, le=5000),  # teto de segurança: uma conta não devolve milhões de linhas
    ) -> list[dict[str, Any]]:
        souprof = user.perfil == "profissional"
        stmt = select(Sessao).where((Sessao.profissional_id if souprof else Sessao.paciente_id) == user.id)
        if status:
            stmt = stmt.where(Sessao.status == status)
        if nao_canceladas:
            stmt = stmt.where(Sessao.status != "cancelada")
        if de:
            stmt = stmt.where(Sessao.data_hora >= de)
        if ate:
            stmt = stmt.where(Sessao.data_hora < ate)
        if paciente_id is not None and souprof:
            stmt = stmt.where(Sessao.paciente_id == paciente_id)
        stmt = stmt.order_by(Sessao.data_hora.asc() if (de or ate) else Sessao.data_hora.desc())
        return [sessao_out(s, ver_anotacoes=souprof) for s in db.scalars(stmt.limit(limite))]

    @router.get("/sessoes/conflito")
    def conflito(user: Eu, db: Db, profissional_id: int, data_hora: datetime, ignorar_id: int = -1) -> dict[str, str | None]:
        pac_id = user.id if user.perfil == "paciente" else -1
        return {"mensagem": svc.mensagem_conflito(db, profissional_id, pac_id, data_hora, ignorar_id)}

    @router.post("/sessoes", status_code=201)
    def criar_sessao(
        body: schemas.SessaoIn,
        user: Eu,
        db: Db,
        response: Response,
        chave: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    ) -> dict[str, Any]:
        if chave is not None and not CHAVE_IDEMPOTENCIA.fullmatch(chave):
            raise HTTPException(422, "Idempotency-Key inválida (8 a 64 letras, números, '-' ou '_').")
        r = svc.agendar(db, user, body, chave, exigir_email_confirmado=cfg.email_ativo)
        if not r.criada:
            response.status_code = 200  # mesmo agendamento reenviado: devolve o que já existe
        return sessao_out(r.sessao, ver_anotacoes=False)

    @router.patch("/sessoes/{sessao_id}")
    def alterar_sessao(sessao_id: int, body: schemas.SessaoPatch, user: Eu, db: Db) -> dict[str, Any]:
        s = svc.alterar(db, svc.carregar_sessao(db, sessao_id, user), user, body)
        return sessao_out(s, ver_anotacoes=user.perfil == "profissional")

    @router.delete("/sessoes/{sessao_id}", status_code=204)
    def excluir_sessao(sessao_id: int, user: Eu, db: Db) -> Response:
        svc.excluir(db, svc.carregar_sessao(db, sessao_id, user))
        return Response(status_code=204)

    # --------------------------------------------------------------- avaliação
    @router.get("/sessoes/{sessao_id}/avaliacao")
    def ver_avaliacao(sessao_id: int, user: Eu, db: Db) -> dict[str, Any] | None:
        s = svc.carregar_sessao(db, sessao_id, user)
        a = db.scalar(select(Avaliacao).where(Avaliacao.sessao_id == s.id))
        return avaliacao_out(a, True) if a else None

    @router.put("/sessoes/{sessao_id}/avaliacao")
    def avaliar(sessao_id: int, body: schemas.AvaliacaoIn, user: Eu, db: Db) -> dict[str, Any]:
        exigir_perfil(user, "paciente")
        a = svc.avaliar(db, user, svc.carregar_sessao(db, sessao_id, user), body)
        return avaliacao_out(a, True)

    return router
