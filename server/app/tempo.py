"""Relógio da clínica.

Todas as datas do sistema são "horário de parede" SEM fuso (como o app envia e exibe), sempre no fuso da clínica
(`APP_TZ`, padrão America/Sao_Paulo = horário de Brasília). Assim o servidor não depende do fuso do contêiner e todos
veem o mesmo horário, com o rótulo "horário de Brasília" na tela. O Brasil não tem horário de verão desde 2019.
"""

from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

FUSO_PADRAO = "America/Sao_Paulo"
_fuso = ZoneInfo(FUSO_PADRAO)


def definir_fuso(nome: str) -> None:
    global _fuso  # noqa: PLW0603
    _fuso = ZoneInfo(nome)


def nome_do_fuso() -> str:
    return _fuso.key


def agora() -> datetime:
    """Agora, no fuso da clínica, sem informação de fuso (naive), como o resto do sistema."""
    return datetime.now(_fuso).replace(tzinfo=None)


def rotulo_do_fuso() -> str:
    """Texto curto para a tela, ex.: "horário de Brasília (UTC-03:00)"."""
    desloc = datetime.now(_fuso).utcoffset()
    total = int(desloc.total_seconds()) if desloc else 0
    sinal = "+" if total >= 0 else "-"
    total = abs(total)
    hhmm = f"UTC{sinal}{total // 3600:02d}:{total % 3600 // 60:02d}"
    nome = "horário de Brasília" if _fuso.key == FUSO_PADRAO else _fuso.key
    return f"{nome} ({hhmm})"
