"""Prontuário do psicólogo: registros clínicos cifrados, com histórico de revisões e registro de acessos.

Regras (veja docs/PRONTUARIO.md):
- Só o PROFISSIONAL lê e escreve, e só de pacientes com quem tem (ou teve) sessão não cancelada. Paciente nunca acessa por aqui.
- O texto é cifrado antes de ir ao banco e NUNCA aparece em logs.
- Não existe DELETE: prontuário tem guarda obrigatória (Resolução CFP 001/2009: 5 anos). Edição guarda a versão anterior.
- Toda leitura, criação e edição é registrada em `prontuario_acessos`.
"""

import logging
from collections.abc import Callable
from datetime import datetime
from typing import Annotated, Any, Literal

from fastapi import Depends, FastAPI, HTTPException, Query, Request
from pydantic import Field
from sqlalchemy import exists, select
from sqlalchemy.orm import Session

from app.cripto import Cofre, ProntuarioIlegivel
from app.models import ProntuarioAcesso, ProntuarioEntrada, ProntuarioRevisao, Sessao, Usuario
from app.schemas import _Base

TipoEntrada = Literal["evolucao", "anamnese", "plano", "observacao"]


class EntradaIn(_Base):
    tipo: TipoEntrada = "evolucao"
    conteudo: str = Field(min_length=1, max_length=20000)
    sessao_id: int | None = None


class EntradaPatch(_Base):
    conteudo: str = Field(min_length=1, max_length=20000)
    versao_esperada: int = Field(ge=1)  # controle de concorrência: evita sobrescrever uma edição feita em outro aparelho


def _agora() -> datetime:
    return datetime.now().replace(microsecond=0)


def registrar_rotas(app: FastAPI, get_db: Callable[..., Any], usuario_atual: Callable[..., Usuario], cofre: Cofre, log: logging.Logger) -> None:
    Db = Annotated[Session, Depends(get_db)]  # noqa: N806
    Eu = Annotated[Usuario, Depends(usuario_atual)]  # noqa: N806

    def exigir_profissional(user: Usuario) -> None:
        if user.perfil != "profissional":
            raise HTTPException(403, "Ação não permitida para o seu perfil.")

    def exigir_vinculo(db: Session, prof: Usuario, paciente_id: int) -> Usuario:
        """404 (e não 403) para quem não tem vínculo: não revela quais pacientes existem."""
        paciente = db.get(Usuario, paciente_id)
        # Vínculo = tem (ou teve) sessão não cancelada com o paciente OU já escreveu prontuário dele. A segunda regra
        # mantém o acesso ao que o próprio profissional escreveu mesmo se as sessões forem canceladas (ex.: anonimização).
        vinculo = db.scalar(
            select(
                exists().where(Sessao.profissional_id == prof.id, Sessao.paciente_id == paciente_id, Sessao.status != "cancelada")
                | exists().where(ProntuarioEntrada.profissional_id == prof.id, ProntuarioEntrada.paciente_id == paciente_id)
            )
        )
        if paciente is None or paciente.perfil != "paciente" or not vinculo:
            raise HTTPException(404, "Paciente não encontrado.")
        return paciente

    def auditar(db: Session, request: Request, prof: Usuario, paciente_id: int, acao: str, entrada_id: int | None = None) -> None:
        db.add(
            ProntuarioAcesso(
                profissional_id=prof.id,
                paciente_id=paciente_id,
                entrada_id=entrada_id,
                acao=acao,
                em=_agora(),
                request_id=getattr(request.state, "request_id", None),
            )
        )

    def abrir(texto_cifrado: str) -> str:
        try:
            return cofre.decifrar(texto_cifrado)
        except ProntuarioIlegivel:
            # Chave errada/dado corrompido: erro claro, sem vazar nada.
            log.error("prontuario_ilegivel")
            raise HTTPException(500, "Não foi possível abrir este registro. Avise o suporte.") from None

    def saida(e: ProntuarioEntrada) -> dict[str, Any]:
        return {
            "id": e.id,
            "paciente_id": e.paciente_id,
            "sessao_id": e.sessao_id,
            "tipo": e.tipo,
            "conteudo": abrir(e.conteudo_cifrado),
            "versao": e.versao,
            "criado_em": e.criado_em.isoformat(),
            "atualizado_em": e.atualizado_em.isoformat(),
        }

    def carregar_entrada(db: Session, prof: Usuario, entrada_id: int) -> ProntuarioEntrada:
        e = db.get(ProntuarioEntrada, entrada_id)
        if e is None or e.profissional_id != prof.id:  # só o autor acessa
            raise HTTPException(404, "Registro não encontrado.")
        return e

    @app.get("/profissional/pacientes/{paciente_id}/prontuario")
    def listar(paciente_id: int, request: Request, user: Eu, db: Db, limite: int = Query(default=100, ge=1, le=500)) -> list[dict[str, Any]]:
        exigir_profissional(user)
        exigir_vinculo(db, user, paciente_id)
        entradas = db.scalars(
            select(ProntuarioEntrada)
            .where(ProntuarioEntrada.profissional_id == user.id, ProntuarioEntrada.paciente_id == paciente_id)
            .order_by(ProntuarioEntrada.criado_em.desc(), ProntuarioEntrada.id.desc())
            .limit(limite)
        ).all()
        resultado = [saida(e) for e in entradas]
        auditar(db, request, user, paciente_id, "leitura")
        db.commit()
        return resultado

    @app.post("/profissional/pacientes/{paciente_id}/prontuario", status_code=201)
    def criar(paciente_id: int, body: EntradaIn, request: Request, user: Eu, db: Db) -> dict[str, Any]:
        exigir_profissional(user)
        paciente = exigir_vinculo(db, user, paciente_id)
        if paciente.anonimizado_em is not None:
            raise HTTPException(409, "Este paciente foi anonimizado: o prontuário existente é mantido, mas não recebe novos registros.")
        if body.sessao_id is not None:
            sessao = db.get(Sessao, body.sessao_id)
            if sessao is None or sessao.profissional_id != user.id or sessao.paciente_id != paciente_id:
                raise HTTPException(422, "A sessão informada não pertence a este paciente.")
        agora = _agora()
        e = ProntuarioEntrada(
            profissional_id=user.id,
            paciente_id=paciente_id,
            sessao_id=body.sessao_id,
            tipo=body.tipo,
            conteudo_cifrado=cofre.cifrar(body.conteudo),
            versao=1,
            criado_em=agora,
            atualizado_em=agora,
        )
        db.add(e)
        db.flush()
        auditar(db, request, user, paciente_id, "criacao", e.id)
        db.commit()
        log.info("prontuario_criado", extra={"campos": {"entrada_id": e.id, "profissional_id": user.id}})
        return saida(e)

    @app.patch("/profissional/prontuario/{entrada_id}")
    def editar(entrada_id: int, body: EntradaPatch, request: Request, user: Eu, db: Db) -> dict[str, Any]:
        exigir_profissional(user)
        e = carregar_entrada(db, user, entrada_id)
        if body.versao_esperada != e.versao:
            raise HTTPException(409, "Este registro foi alterado em outro lugar. Recarregue e edite de novo.")
        db.add(ProntuarioRevisao(entrada_id=e.id, versao=e.versao, conteudo_cifrado=e.conteudo_cifrado, substituida_em=_agora()))
        e.conteudo_cifrado = cofre.cifrar(body.conteudo)  # sempre com a chave principal
        e.versao += 1
        e.atualizado_em = _agora()
        auditar(db, request, user, e.paciente_id, "edicao", e.id)
        db.commit()
        return saida(e)

    @app.get("/profissional/prontuario/{entrada_id}/revisoes")
    def revisoes(entrada_id: int, request: Request, user: Eu, db: Db) -> list[dict[str, Any]]:
        exigir_profissional(user)
        e = carregar_entrada(db, user, entrada_id)
        antigas = db.scalars(select(ProntuarioRevisao).where(ProntuarioRevisao.entrada_id == e.id).order_by(ProntuarioRevisao.versao.desc())).all()
        resultado = [{"versao": r.versao, "conteudo": abrir(r.conteudo_cifrado), "substituida_em": r.substituida_em.isoformat()} for r in antigas]
        auditar(db, request, user, e.paciente_id, "revisoes", e.id)
        db.commit()
        return resultado

    @app.get("/profissional/pacientes/{paciente_id}/prontuario/acessos")
    def acessos(paciente_id: int, user: Eu, db: Db, limite: int = Query(default=100, ge=1, le=500)) -> list[dict[str, Any]]:
        """Trilha de auditoria: quem (o próprio profissional) abriu ou alterou o prontuário deste paciente, e quando."""
        exigir_profissional(user)
        exigir_vinculo(db, user, paciente_id)
        linhas = db.scalars(
            select(ProntuarioAcesso)
            .where(ProntuarioAcesso.profissional_id == user.id, ProntuarioAcesso.paciente_id == paciente_id)
            .order_by(ProntuarioAcesso.em.desc(), ProntuarioAcesso.id.desc())
            .limit(limite)
        ).all()
        return [{"acao": a.acao, "entrada_id": a.entrada_id, "em": a.em.isoformat(), "request_id": a.request_id} for a in linhas]
