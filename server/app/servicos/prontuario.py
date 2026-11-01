"""Prontuário do psicólogo: registros clínicos cifrados, com histórico de revisões e registro de acessos.

Regras (veja docs/PRONTUARIO.md):
- Só o PROFISSIONAL lê e escreve, e só de pacientes com quem tem (ou teve) sessão não cancelada. Paciente nunca acessa por aqui.
- O texto é cifrado antes de ir ao banco e NUNCA aparece em logs.
- Não existe DELETE: prontuário tem guarda obrigatória (Resolução CFP 001/2009: 5 anos). Edição guarda a versão anterior.
- Toda leitura, criação e edição é registrada em `prontuario_acessos`.
"""

import logging
from datetime import datetime
from typing import Any

from sqlalchemy import exists, select
from sqlalchemy.orm import Session

from app import schemas, tempo
from app.cripto import Cofre, ProntuarioIlegivel
from app.erros import ErroDeNegocio, exigir_perfil
from app.models import ProntuarioAcesso, ProntuarioEntrada, ProntuarioRevisao, Sessao, Usuario


def _agora() -> datetime:
    return tempo.agora().replace(microsecond=0)


class ServicoProntuario:
    def __init__(self, cofre: Cofre, log: logging.Logger) -> None:
        self.cofre = cofre
        self.log = log

    # ---------------------------------------------------------------- acesso
    def exigir_vinculo(self, db: Session, prof: Usuario, paciente_id: int) -> Usuario:
        """404 (e não 403) para quem não tem vínculo: não revela quais pacientes existem."""
        exigir_perfil(prof, "profissional")
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
            raise ErroDeNegocio(404, "Paciente não encontrado.")
        return paciente

    def _entrada_do_autor(self, db: Session, prof: Usuario, entrada_id: int) -> ProntuarioEntrada:
        exigir_perfil(prof, "profissional")
        e = db.get(ProntuarioEntrada, entrada_id)
        if e is None or e.profissional_id != prof.id:  # só o autor acessa
            raise ErroDeNegocio(404, "Registro não encontrado.")
        return e

    # ---------------------------------------------------------------- auditoria e cifra
    def _auditar(self, db: Session, request_id: str | None, prof: Usuario, paciente_id: int, acao: str, entrada_id: int | None = None) -> None:
        db.add(ProntuarioAcesso(profissional_id=prof.id, paciente_id=paciente_id, entrada_id=entrada_id, acao=acao, em=_agora(), request_id=request_id))

    def _abrir(self, texto_cifrado: str) -> str:
        try:
            return self.cofre.decifrar(texto_cifrado)
        except ProntuarioIlegivel:
            # Chave errada/dado corrompido: erro claro, sem vazar nada.
            self.log.error("prontuario_ilegivel")
            raise ErroDeNegocio(500, "Não foi possível abrir este registro. Avise o suporte.") from None

    def saida(self, e: ProntuarioEntrada) -> dict[str, Any]:
        return {
            "id": e.id,
            "paciente_id": e.paciente_id,
            "sessao_id": e.sessao_id,
            "tipo": e.tipo,
            "conteudo": self._abrir(e.conteudo_cifrado),
            "versao": e.versao,
            "criado_em": e.criado_em.isoformat(),
            "atualizado_em": e.atualizado_em.isoformat(),
        }

    # ---------------------------------------------------------------- casos de uso
    def listar(self, db: Session, prof: Usuario, paciente_id: int, limite: int, request_id: str | None) -> list[dict[str, Any]]:
        self.exigir_vinculo(db, prof, paciente_id)
        entradas = db.scalars(
            select(ProntuarioEntrada)
            .where(ProntuarioEntrada.profissional_id == prof.id, ProntuarioEntrada.paciente_id == paciente_id)
            .order_by(ProntuarioEntrada.criado_em.desc(), ProntuarioEntrada.id.desc())
            .limit(limite)
        ).all()
        resultado = [self.saida(e) for e in entradas]
        self._auditar(db, request_id, prof, paciente_id, "leitura")
        db.commit()
        return resultado

    def criar(self, db: Session, prof: Usuario, paciente_id: int, body: schemas.EntradaIn, request_id: str | None) -> dict[str, Any]:
        paciente = self.exigir_vinculo(db, prof, paciente_id)
        if paciente.anonimizado_em is not None:
            raise ErroDeNegocio(409, "Este paciente foi anonimizado: o prontuário existente é mantido, mas não recebe novos registros.")
        if body.sessao_id is not None:
            sessao = db.get(Sessao, body.sessao_id)
            if sessao is None or sessao.profissional_id != prof.id or sessao.paciente_id != paciente_id:
                raise ErroDeNegocio(422, "A sessão informada não pertence a este paciente.")
        agora = _agora()
        e = ProntuarioEntrada(
            profissional_id=prof.id,
            paciente_id=paciente_id,
            sessao_id=body.sessao_id,
            tipo=body.tipo,
            conteudo_cifrado=self.cofre.cifrar(body.conteudo),
            versao=1,
            criado_em=agora,
            atualizado_em=agora,
        )
        db.add(e)
        db.flush()
        self._auditar(db, request_id, prof, paciente_id, "criacao", e.id)
        db.commit()
        self.log.info("prontuario_criado", extra={"campos": {"entrada_id": e.id, "profissional_id": prof.id}})
        return self.saida(e)

    def editar(self, db: Session, prof: Usuario, entrada_id: int, body: schemas.EntradaPatch, request_id: str | None) -> dict[str, Any]:
        e = self._entrada_do_autor(db, prof, entrada_id)
        if body.versao_esperada != e.versao:
            raise ErroDeNegocio(409, "Este registro foi alterado em outro lugar. Recarregue e edite de novo.")
        db.add(ProntuarioRevisao(entrada_id=e.id, versao=e.versao, conteudo_cifrado=e.conteudo_cifrado, substituida_em=_agora()))
        e.conteudo_cifrado = self.cofre.cifrar(body.conteudo)  # sempre com a chave principal
        e.versao += 1
        e.atualizado_em = _agora()
        self._auditar(db, request_id, prof, e.paciente_id, "edicao", e.id)
        db.commit()
        return self.saida(e)

    def revisoes(self, db: Session, prof: Usuario, entrada_id: int, request_id: str | None) -> list[dict[str, Any]]:
        e = self._entrada_do_autor(db, prof, entrada_id)
        antigas = db.scalars(select(ProntuarioRevisao).where(ProntuarioRevisao.entrada_id == e.id).order_by(ProntuarioRevisao.versao.desc())).all()
        resultado = [{"versao": r.versao, "conteudo": self._abrir(r.conteudo_cifrado), "substituida_em": r.substituida_em.isoformat()} for r in antigas]
        self._auditar(db, request_id, prof, e.paciente_id, "revisoes", e.id)
        db.commit()
        return resultado

    def acessos(self, db: Session, prof: Usuario, paciente_id: int, limite: int) -> list[dict[str, Any]]:
        """Trilha de auditoria: quem (o próprio profissional) abriu ou alterou o prontuário deste paciente, e quando."""
        self.exigir_vinculo(db, prof, paciente_id)
        linhas = db.scalars(
            select(ProntuarioAcesso)
            .where(ProntuarioAcesso.profissional_id == prof.id, ProntuarioAcesso.paciente_id == paciente_id)
            .order_by(ProntuarioAcesso.em.desc(), ProntuarioAcesso.id.desc())
            .limit(limite)
        ).all()
        return [{"acao": a.acao, "entrada_id": a.entrada_id, "em": a.em.isoformat(), "request_id": a.request_id} for a in linhas]
