"""Painel financeiro e carteira de pacientes do profissional (consultas agregadas no banco, sem N+1)."""

from datetime import datetime
from typing import Any

from sqlalchemy import case, extract, func, select
from sqlalchemy.orm import Session

from app.models import Sessao, Usuario


def _linha_mes(ano: int, mes: int, recebido: int, concluidas: int, a_receber: int, agendadas: int) -> dict[str, Any]:
    return {
        "mes": f"{ano:04d}-{mes:02d}",
        "recebido_centavos": recebido,
        "sessoes_concluidas": concluidas,
        "a_receber_centavos": a_receber,
        "sessoes_agendadas": agendadas,
    }


def _inicio_do_mes_seguinte(ano: int, mes: int) -> datetime:
    return datetime(ano + (mes == 12), 1 if mes == 12 else mes + 1, 1)


def faturamento_do_mes(db: Session, profissional_id: int, ano: int, mes: int) -> dict[str, Any]:
    """Recebido (sessões concluídas) e a receber (agendadas) no mês, numa única consulta agrupada por status."""
    linhas = db.execute(
        select(Sessao.status, func.coalesce(func.sum(Sessao.valor_centavos), 0), func.count(Sessao.id))
        .where(
            Sessao.profissional_id == profissional_id,
            Sessao.status.in_(("concluida", "agendada")),
            Sessao.data_hora >= datetime(ano, mes, 1),
            Sessao.data_hora < _inicio_do_mes_seguinte(ano, mes),
        )
        .group_by(Sessao.status)
    ).all()
    por_status = {st: (int(total), int(qtd)) for st, total, qtd in linhas}
    recebido, concluidas = por_status.get("concluida", (0, 0))
    a_receber, agendadas = por_status.get("agendada", (0, 0))
    return _linha_mes(ano, mes, recebido, concluidas, a_receber, agendadas)


def historico(db: Session, profissional_id: int, meses: int, hoje: datetime) -> list[dict[str, Any]]:
    """Últimos `meses` meses (o mais recente primeiro) em UMA consulta agrupada por mês e status."""
    pedidos: list[tuple[int, int]] = []
    ano, num = hoje.year, hoje.month
    for _ in range(meses):
        pedidos.append((ano, num))
        ano, num = (ano - 1, 12) if num == 1 else (ano, num - 1)
    inicio = datetime(*pedidos[-1], 1)
    fim = _inicio_do_mes_seguinte(*pedidos[0])
    ano_col, mes_col = extract("year", Sessao.data_hora), extract("month", Sessao.data_hora)
    linhas = db.execute(
        select(ano_col, mes_col, Sessao.status, func.coalesce(func.sum(Sessao.valor_centavos), 0), func.count(Sessao.id))
        .where(Sessao.profissional_id == profissional_id, Sessao.status.in_(("concluida", "agendada")), Sessao.data_hora >= inicio, Sessao.data_hora < fim)
        .group_by(ano_col, mes_col, Sessao.status)
    ).all()
    totais = {(int(a), int(m), st): (int(v), int(q)) for a, m, st, v, q in linhas}
    saida = []
    for a, m in pedidos:
        recebido, concluidas = totais.get((a, m, "concluida"), (0, 0))
        a_receber, agendadas = totais.get((a, m, "agendada"), (0, 0))
        saida.append(_linha_mes(a, m, recebido, concluidas, a_receber, agendadas))
    return saida


def pacientes_do_profissional(db: Session, profissional_id: int, agora: datetime) -> list[dict[str, Any]]:
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
        .where(Sessao.profissional_id == profissional_id, Sessao.status != "cancelada")
        .group_by(Usuario.id)
        .order_by(func.lower(Usuario.nome))
    )
    return [
        {"id": i, "nome": n, "email": e, "total": int(t), "concluidas": int(c or 0), "proxima": p.isoformat() if p else None}
        for i, n, e, t, c, p in db.execute(stmt).all()
    ]
