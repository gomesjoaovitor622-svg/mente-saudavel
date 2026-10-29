"""O que as rotas precisam saber do servidor em execução (configuração, log, métricas, limites, e-mail)."""

import logging
from dataclasses import dataclass

from app.config import Settings
from app.conta import Conta
from app.deps import LimiteLogin
from app.observabilidade import Metricas


@dataclass(frozen=True)
class Contexto:
    cfg: Settings
    log: logging.Logger
    metricas: Metricas
    conta: Conta
    limite: LimiteLogin  # login (por e-mail)
    limite_cadastro: LimiteLogin  # cadastro (por IP)
    limite_telemetria: LimiteLogin  # telemetria (por IP)
