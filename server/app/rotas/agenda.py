"""Busca de profissionais, sessões e avaliações."""

from datetime import datetime, timedelta
from typing import Annotated, Any

from fastapi import APIRouter, Header, HTTPException, Query, Response
from sqlalchemy import func, select

from app import schemas, tempo
from app.contexto import Contexto
from app.deps import CHAVE_IDEMPOTENCIA, Db, Eu, carregar_sessao, exigir_perfil, gravar_sessao, mensagem_conflito
from app.models import Avaliacao, Sessao, Usuario
from app.saidas import avaliacao_out, sessao_out


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
        return {"mensagem": mensagem_conflito(db, profissional_id, pac_id, data_hora, ignorar_id)}

    @router.post("/sessoes", status_code=201)
    def criar_sessao(
        body: schemas.SessaoIn,
        user: Eu,
        db: Db,
        response: Response,
        chave: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    ) -> dict[str, Any]:
        exigir_perfil(user, "paciente")
        if chave is not None and not CHAVE_IDEMPOTENCIA.fullmatch(chave):
            raise HTTPException(422, "Idempotency-Key inválida (8 a 64 letras, números, '-' ou '_').")
        if chave:
            # Reenvio do mesmo agendamento (ex.: o app estava offline e tentou de novo): devolve o que já existe.
            existente = db.scalar(select(Sessao).where(Sessao.paciente_id == user.id, Sessao.chave_idempotencia == chave))
            if existente is not None:
                response.status_code = 200
                return sessao_out(existente, ver_anotacoes=False)
        if cfg.email_ativo and user.email_verificado_em is None:
            raise HTTPException(403, "Confirme seu e-mail antes de agendar uma sessão.")
        prof = db.get(Usuario, body.profissional_id)
        if prof is None or prof.perfil != "profissional" or prof.verificado_em is None:  # só profissional aprovado recebe agendamentos
            raise HTTPException(404, "Profissional não encontrado.")
        if body.data_hora <= tempo.agora():
            raise HTTPException(422, "Escolha um horário no futuro.")
        msg = mensagem_conflito(db, prof.id, user.id, body.data_hora, -1)
        if msg:
            if chave:
                # Corrida com o próprio reenvio: o 1º envio acabou de gravar. Não é conflito, é a mesma sessão.
                db.rollback()
                existente = db.scalar(select(Sessao).where(Sessao.paciente_id == user.id, Sessao.chave_idempotencia == chave))
                if existente is not None:
                    response.status_code = 200
                    return sessao_out(existente, ver_anotacoes=False)
            raise HTTPException(409, msg)
        s = Sessao(
            paciente_id=user.id,
            profissional_id=prof.id,
            data_hora=body.data_hora,
            modalidade=body.modalidade,
            valor_centavos=prof.valor_sessao_centavos or 0,  # congela o preço da hora do agendamento
            chave_idempotencia=chave,
        )
        db.add(s)
        ja_existia = gravar_sessao(db, prof.id, user.id, body.data_hora, -1, chave)
        if ja_existia is not None:
            response.status_code = 200
            return sessao_out(ja_existia, ver_anotacoes=False)
        return sessao_out(s, ver_anotacoes=False)

    @router.patch("/sessoes/{sessao_id}")
    def alterar_sessao(sessao_id: int, body: schemas.SessaoPatch, user: Eu, db: Db) -> dict[str, Any]:
        s = carregar_sessao(db, sessao_id, user)
        souprof = user.perfil == "profissional"
        if body.anotacoes is not None:
            if not souprof:
                raise HTTPException(403, "Somente o profissional edita as anotações.")
            s.anotacoes = body.anotacoes
        if body.status is not None:
            permitido = {"concluida", "cancelada"} if souprof else {"cancelada"}
            if body.status not in permitido or s.status != "agendada":
                raise HTTPException(409, "Mudança de status não permitida.")
            s.status = body.status
        if body.data_hora is not None:
            if souprof:
                raise HTTPException(403, "Somente o paciente remarca a sessão.")
            if s.status == "cancelada" or body.data_hora <= tempo.agora():
                raise HTTPException(422, "Escolha um horário no futuro para uma sessão ativa.")
            msg = mensagem_conflito(db, s.profissional_id, s.paciente_id, body.data_hora, s.id)
            if msg:
                raise HTTPException(409, msg)
            s.data_hora = body.data_hora
            s.status = "agendada"
        gravar_sessao(db, s.profissional_id, s.paciente_id, s.data_hora, s.id)
        return sessao_out(s, ver_anotacoes=souprof)

    @router.delete("/sessoes/{sessao_id}", status_code=204)
    def excluir_sessao(sessao_id: int, user: Eu, db: Db) -> Response:
        s = carregar_sessao(db, sessao_id, user)
        if s.status == "agendada":
            raise HTTPException(409, "Cancele a sessão antes de excluí-la do histórico.")
        db.delete(s)
        db.commit()
        return Response(status_code=204)

    # --------------------------------------------------------------- avaliação
    @router.get("/sessoes/{sessao_id}/avaliacao")
    def ver_avaliacao(sessao_id: int, user: Eu, db: Db) -> dict[str, Any] | None:
        s = carregar_sessao(db, sessao_id, user)
        a = db.scalar(select(Avaliacao).where(Avaliacao.sessao_id == s.id))
        return avaliacao_out(a, True) if a else None

    @router.put("/sessoes/{sessao_id}/avaliacao")
    def avaliar(sessao_id: int, body: schemas.AvaliacaoIn, user: Eu, db: Db) -> dict[str, Any]:
        exigir_perfil(user, "paciente")
        s = carregar_sessao(db, sessao_id, user)
        if s.status != "concluida":
            raise HTTPException(409, "Só é possível avaliar sessões concluídas.")
        a = db.scalar(select(Avaliacao).where(Avaliacao.sessao_id == s.id))
        if a is None:
            a = Avaliacao(sessao_id=s.id, paciente_id=user.id, profissional_id=s.profissional_id, nota=body.nota)
            db.add(a)
        a.nota = body.nota
        a.comentario = body.comentario
        a.criado_em = tempo.agora().replace(microsecond=0)
        db.commit()
        return avaliacao_out(a, True)

    return router
