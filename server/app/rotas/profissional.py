"""Painel financeiro e lista de pacientes do profissional."""

from typing import Any

from fastapi import APIRouter, Query

from app import tempo
from app.contexto import Contexto
from app.deps import Db, Eu
from app.erros import exigir_perfil
from app.servicos import financeiro as fin


def criar_rotas(ctx: Contexto) -> APIRouter:
    router = APIRouter()

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

    return router
