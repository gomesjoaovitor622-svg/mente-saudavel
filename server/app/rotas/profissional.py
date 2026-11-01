"""Painel financeiro, lista de pacientes e prontuário eletrônico do profissional."""

from typing import Any

from fastapi import APIRouter, Query, Request

from app import schemas, tempo
from app.contexto import Contexto
from app.deps import Db, Eu
from app.erros import exigir_perfil
from app.servicos import financeiro as fin
from app.servicos.prontuario import ServicoProntuario


def criar_rotas(ctx: Contexto) -> APIRouter:
    router = APIRouter()
    prontuario = ServicoProntuario(ctx.cofre, ctx.log)

    @router.get("/profissional/financeiro")
    def financeiro(user: Eu, db: Db, mes: str | None = Query(default=None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$")) -> dict[str, Any]:
        """Faturamento do mês (YYYY-MM; padrão: mês atual): recebido (concluídas) e a receber (agendadas)."""
        exigir_perfil(user, "profissional")
        hoje = tempo.agora()
        ano, num = (int(mes[:4]), int(mes[5:])) if mes else (hoje.year, hoje.month)
        return {**fin.faturamento_do_mes(db, user.id, ano, num), "valor_sessao_centavos": user.valor_sessao_centavos}

    @router.get("/profissional/financeiro/historico")
    def historico_financeiro(user: Eu, db: Db, meses: int = Query(default=6, ge=1, le=24)) -> list[dict[str, Any]]:
        """Faturamento dos últimos `meses` meses (o mais recente primeiro), para a tela de histórico."""
        exigir_perfil(user, "profissional")
        return fin.historico(db, user.id, meses, tempo.agora())

    @router.get("/profissional/pacientes")
    def pacientes(user: Eu, db: Db) -> list[dict[str, Any]]:
        exigir_perfil(user, "profissional")
        return fin.pacientes_do_profissional(db, user.id, tempo.agora())

    # ------------------------------------------------------------- prontuário eletrônico
    def _rid(request: Request) -> str | None:
        return getattr(request.state, "request_id", None)

    @router.get("/profissional/pacientes/{paciente_id}/prontuario")
    def listar(paciente_id: int, request: Request, user: Eu, db: Db, limite: int = Query(default=100, ge=1, le=500)) -> list[dict[str, Any]]:
        exigir_perfil(user, "profissional")
        return prontuario.listar(db, user, paciente_id, limite, _rid(request))

    @router.post("/profissional/pacientes/{paciente_id}/prontuario", status_code=201)
    def criar(paciente_id: int, body: schemas.EntradaIn, request: Request, user: Eu, db: Db) -> dict[str, Any]:
        exigir_perfil(user, "profissional")
        return prontuario.criar(db, user, paciente_id, body, _rid(request))

    @router.patch("/profissional/prontuario/{entrada_id}")
    def editar(entrada_id: int, body: schemas.EntradaPatch, request: Request, user: Eu, db: Db) -> dict[str, Any]:
        return prontuario.editar(db, user, entrada_id, body, _rid(request))

    @router.get("/profissional/prontuario/{entrada_id}/revisoes")
    def revisoes(entrada_id: int, request: Request, user: Eu, db: Db) -> list[dict[str, Any]]:
        return prontuario.revisoes(db, user, entrada_id, _rid(request))

    @router.get("/profissional/pacientes/{paciente_id}/prontuario/acessos")
    def acessos(paciente_id: int, user: Eu, db: Db, limite: int = Query(default=100, ge=1, le=500)) -> list[dict[str, Any]]:
        """Trilha de auditoria: quem (o próprio profissional) abriu ou alterou o prontuário deste paciente, e quando."""
        return prontuario.acessos(db, user, paciente_id, limite)

    return router
