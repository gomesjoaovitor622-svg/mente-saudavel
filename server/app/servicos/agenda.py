"""Regras da agenda: acesso a sessões, conflitos, agendamento idempotente, remarcação, cancelamento e avaliação."""

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app import schemas, tempo
from app.erros import ErroDeNegocio, exigir_perfil
from app.models import Avaliacao, Sessao, Usuario


def carregar_sessao(db: Session, sessao_id: int, user: Usuario) -> Sessao:
    s = db.get(Sessao, sessao_id)
    # 404 (e não 403) para não revelar a existência de sessões de outras pessoas.
    if s is None or user.id not in (s.paciente_id, s.profissional_id):
        raise ErroDeNegocio(404, "Sessão não encontrada.")
    return s


def mensagem_conflito(db: Session, prof_id: int, pac_id: int, quando: datetime, ignorar: int) -> str | None:
    def existe(coluna: Any, valor: int) -> bool:
        q = select(func.count()).select_from(Sessao).where(coluna == valor, Sessao.data_hora == quando, Sessao.status != "cancelada", Sessao.id != ignorar)
        return (db.scalar(q) or 0) > 0

    if existe(Sessao.profissional_id, prof_id):
        return "O profissional já tem uma sessão neste horário."
    if existe(Sessao.paciente_id, pac_id):
        return "Você já tem uma sessão neste horário."
    return None


def _por_chave(db: Session, paciente_id: int, chave: str) -> Sessao | None:
    return db.scalar(select(Sessao).where(Sessao.paciente_id == paciente_id, Sessao.chave_idempotencia == chave))


def gravar_sessao(db: Session, prof_id: int, pac_id: int, quando: datetime, ignorar: int, chave: str | None = None) -> Sessao | None:
    """Confirma a gravação. Se o banco recusar por horário duplicado (corrida entre 2 requisições), responde 409.

    Se a recusa foi da CHAVE DE IDEMPOTÊNCIA (o mesmo agendamento chegou duas vezes ao mesmo tempo),
    devolve a sessão que já existe em vez de erro."""
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        texto = str(e.orig).lower()
        if "unique" not in texto and "duplicate" not in texto:
            raise
        if chave:
            existente = _por_chave(db, pac_id, chave)
            if existente is not None:
                return existente
        raise ErroDeNegocio(409, mensagem_conflito(db, prof_id, pac_id, quando, ignorar) or "Este horário acabou de ser ocupado. Escolha outro.") from None
    return None


@dataclass(frozen=True)
class ResultadoAgendamento:
    sessao: Sessao
    criada: bool  # False = o mesmo agendamento já existia (reenvio com a mesma Idempotency-Key)


def agendar(db: Session, paciente: Usuario, body: schemas.SessaoIn, chave: str | None, exigir_email_confirmado: bool) -> ResultadoAgendamento:
    exigir_perfil(paciente, "paciente")
    if chave:
        # Reenvio do mesmo agendamento (ex.: o app estava offline e tentou de novo): devolve o que já existe.
        existente = _por_chave(db, paciente.id, chave)
        if existente is not None:
            return ResultadoAgendamento(existente, False)
    if exigir_email_confirmado and paciente.email_verificado_em is None:
        raise ErroDeNegocio(403, "Confirme seu e-mail antes de agendar uma sessão.")
    prof = db.get(Usuario, body.profissional_id)
    if prof is None or prof.perfil != "profissional" or prof.verificado_em is None:  # só profissional aprovado recebe agendamentos
        raise ErroDeNegocio(404, "Profissional não encontrado.")
    if body.data_hora <= tempo.agora():
        raise ErroDeNegocio(422, "Escolha um horário no futuro.")
    msg = mensagem_conflito(db, prof.id, paciente.id, body.data_hora, -1)
    if msg:
        if chave:
            # Corrida com o próprio reenvio: o 1º envio acabou de gravar. Não é conflito, é a mesma sessão.
            db.rollback()
            existente = _por_chave(db, paciente.id, chave)
            if existente is not None:
                return ResultadoAgendamento(existente, False)
        raise ErroDeNegocio(409, msg)
    s = Sessao(
        paciente_id=paciente.id,
        profissional_id=prof.id,
        data_hora=body.data_hora,
        modalidade=body.modalidade,
        valor_centavos=prof.valor_sessao_centavos or 0,  # congela o preço da hora do agendamento
        chave_idempotencia=chave,
    )
    db.add(s)
    ja_existia = gravar_sessao(db, prof.id, paciente.id, body.data_hora, -1, chave)
    return ResultadoAgendamento(ja_existia, False) if ja_existia is not None else ResultadoAgendamento(s, True)


def alterar(db: Session, s: Sessao, user: Usuario, body: schemas.SessaoPatch) -> Sessao:
    souprof = user.perfil == "profissional"
    if body.anotacoes is not None:
        if not souprof:
            raise ErroDeNegocio(403, "Somente o profissional edita as anotações.")
        s.anotacoes = body.anotacoes
    if body.status is not None:
        permitido = {"concluida", "cancelada"} if souprof else {"cancelada"}
        if body.status not in permitido or s.status != "agendada":
            raise ErroDeNegocio(409, "Mudança de status não permitida.")
        s.status = body.status
    if body.data_hora is not None:
        if souprof:
            raise ErroDeNegocio(403, "Somente o paciente remarca a sessão.")
        if s.status == "cancelada" or body.data_hora <= tempo.agora():
            raise ErroDeNegocio(422, "Escolha um horário no futuro para uma sessão ativa.")
        msg = mensagem_conflito(db, s.profissional_id, s.paciente_id, body.data_hora, s.id)
        if msg:
            raise ErroDeNegocio(409, msg)
        s.data_hora = body.data_hora
        s.status = "agendada"
    gravar_sessao(db, s.profissional_id, s.paciente_id, s.data_hora, s.id)
    return s


def excluir(db: Session, s: Sessao) -> None:
    if s.status == "agendada":
        raise ErroDeNegocio(409, "Cancele a sessão antes de excluí-la do histórico.")
    db.delete(s)
    db.commit()


def avaliar(db: Session, paciente: Usuario, s: Sessao, body: schemas.AvaliacaoIn) -> Avaliacao:
    if s.status != "concluida":
        raise ErroDeNegocio(409, "Só é possível avaliar sessões concluídas.")
    a = db.scalar(select(Avaliacao).where(Avaliacao.sessao_id == s.id))
    if a is None:
        a = Avaliacao(sessao_id=s.id, paciente_id=paciente.id, profissional_id=s.profissional_id, nota=body.nota)
        db.add(a)
    a.nota = body.nota
    a.comentario = body.comentario
    a.criado_em = tempo.agora().replace(microsecond=0)
    db.commit()
    return a
