"""Prontidão da API (readiness): o banco responde e está na versão certa do esquema?

Diferente de `/health` (a API está de pé), `/health/ready` diz se ela CONSEGUE trabalhar. Os detalhes de erro vão
só para o log; a resposta pública traz apenas ok/falha por verificação, sem mensagens do banco.
"""

from __future__ import annotations

import logging
import time
from typing import Any

from sqlalchemy import Engine, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.config import Settings
from app.migracoes import versao_atual, versao_esperada
from app.observabilidade import Metricas

ROTAS_SAUDE = frozenset({"/health", "/health/ready"})


def verificar_prontidao(db: Session, cfg: Settings, metricas: Metricas, log: logging.Logger) -> tuple[bool, dict[str, Any]]:
    """Devolve (tudo_ok, corpo da resposta). Também atualiza os medidores `ms_db_up` e `ms_db_latency_seconds`."""
    checks: dict[str, dict[str, Any]] = {}

    inicio = time.perf_counter()
    try:
        db.execute(select(1))
        banco_ok = True
    except SQLAlchemyError:
        log.error("prontidao_banco_falhou", exc_info=True)
        banco_ok = False
    segundos = time.perf_counter() - inicio
    checks["banco"] = {"ok": banco_ok, "ms": round(segundos * 1000, 1)}
    metricas.definir("ms_db_up", 1.0 if banco_ok else 0.0)
    metricas.definir("ms_db_latency_seconds", segundos)

    if cfg.schema_mode == "alembic" and banco_ok:
        try:
            bind = db.get_bind()
            engine = bind if isinstance(bind, Engine) else bind.engine
            migrado = versao_atual(engine) == versao_esperada()
        except SQLAlchemyError:
            log.error("prontidao_migracoes_falhou", exc_info=True)
            migrado = False
        checks["migracoes"] = {"ok": migrado}

    tudo_ok = all(c["ok"] for c in checks.values())
    return tudo_ok, {"status": "ok" if tudo_ok else "degradado", "checks": checks}
