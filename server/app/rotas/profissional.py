"""Painel financeiro e lista de pacientes do profissional."""

from datetime import datetime
from typing import Any

from fastapi import APIRouter, Query
from sqlalchemy import case, extract, func, select
from sqlalchemy.orm import Session

from app import tempo
from app.contexto import Contexto
from app.deps import Db, Eu, exigir_perfil
from app.models import Sessao, Usuario


def criar_rotas(ctx: Contexto) -> APIRouter:
    router = APIRouter()

    def faturamento_do_mes(db: Session, user: Usuario, ano: int, num: int) -> dict[str, Any]:
        inicio = datetime(ano, num, 1)
        fim = datetime(ano + (num == 12), 1 if num == 12 else num + 1, 1)

        def somar(status: str) -> tuple[int, int]:
            total, qtd = db.execute(
                select(func.coalesce(func.sum(Sessao.valor_centavos), 0), func.count(Sessao.id)).where(
                    Sessao.profissional_id == user.id,
                    Sessao.status == status,
                    Sessao.data_hora >= inicio,
                    Sessao.data_hora < fim,
                )
            ).one()
            return int(total), int(qtd)

        recebido, concluidas = somar("concluida")
        a_receber, agendadas = somar("agendada")
        return {
            "mes": f"{ano:04d}-{num:02d}",
            "recebido_centavos": recebido,
            "sessoes_concluidas": concluidas,
            "a_receber_centavos": a_receber,
            "sessoes_agendadas": agendadas,
        }

    @router.get("/profissional/financeiro")
    def financeiro(user: Eu, db: Db, mes: str | None = Query(default=None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$")) -> dict[str, Any]:
        """Faturamento do mês (YYYY-MM; padrão: mês atual): recebido (concluídas) e a receber (agendadas)."""
        exigir_perfil(user, "profissional")
        hoje = tempo.agora()
        ano, num = (int(mes[:4]), int(mes[5:])) if mes else (hoje.year, hoje.month)
        return {**faturamento_do_mes(db, user, ano, num), "valor_sessao_centavos": user.valor_sessao_centavos}

    @router.get("/profissional/financeiro/historico")
    def historico_financeiro(user: Eu, db: Db, meses: int = Query(default=6, ge=1, le=24)) -> list[dict[str, Any]]:
        """Faturamento dos últimos `meses` meses (o mais recente primeiro), para a tela de histórico."""
        exigir_perfil(user, "profissional")
        hoje = tempo.agora()
        meses_pedidos: list[tuple[int, int]] = []
        ano, num = hoje.year, hoje.month
        for _ in range(meses):
            meses_pedidos.append((ano, num))
            ano, num = (ano - 1, 12) if num == 1 else (ano, num - 1)
        # UMA consulta agrupada por mês e status (antes eram 2 consultas por mês).
        ano_ini, mes_ini = meses_pedidos[-1]
        ano_fim, mes_fim = meses_pedidos[0]
        inicio = datetime(ano_ini, mes_ini, 1)
        fim = datetime(ano_fim + (mes_fim == 12), 1 if mes_fim == 12 else mes_fim + 1, 1)
        ano_col, mes_col = extract("year", Sessao.data_hora), extract("month", Sessao.data_hora)
        linhas = db.execute(
            select(ano_col, mes_col, Sessao.status, func.coalesce(func.sum(Sessao.valor_centavos), 0), func.count(Sessao.id))
            .where(Sessao.profissional_id == user.id, Sessao.status.in_(("concluida", "agendada")), Sessao.data_hora >= inicio, Sessao.data_hora < fim)
            .group_by(ano_col, mes_col, Sessao.status)
        ).all()
        totais = {(int(a), int(m), st): (int(v), int(q)) for a, m, st, v, q in linhas}
        saida: list[dict[str, Any]] = []
        for a, m in meses_pedidos:
            recebido, concluidas = totais.get((a, m, "concluida"), (0, 0))
            a_receber, agendadas = totais.get((a, m, "agendada"), (0, 0))
            saida.append(
                {
                    "mes": f"{a:04d}-{m:02d}",
                    "recebido_centavos": recebido,
                    "sessoes_concluidas": concluidas,
                    "a_receber_centavos": a_receber,
                    "sessoes_agendadas": agendadas,
                }
            )
        return saida

    @router.get("/profissional/pacientes")
    def pacientes(user: Eu, db: Db) -> list[dict[str, Any]]:
        exigir_perfil(user, "profissional")
        agora = tempo.agora()
        stmt = (
            select(
                Usuario.id,
                Usuario.nome,
                Usuario.email,
                func.count(Sessao.id),
                func.sum(case((Sessao.status == "concluida", 1), else_=0)),
                func.min(case(((Sessao.status == "agendada") & (Sessao.data_hora >= agora), Sessao.data_hora))),
            )
            .join(Sessao, Sessao.paciente_id == Usuario.id)
            .where(Sessao.profissional_id == user.id, Sessao.status != "cancelada")
            .group_by(Usuario.id)
            .order_by(func.lower(Usuario.nome))
        )
        return [
            {
                "id": i,
                "nome": n,
                "email": e,
                "total": int(t),
                "concluidas": int(c or 0),
                "proxima": p.isoformat() if p else None,
            }
            for i, n, e, t, c, p in db.execute(stmt).all()
        ]

    return router
