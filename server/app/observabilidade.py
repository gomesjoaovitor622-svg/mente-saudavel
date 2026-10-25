"""Logs estruturados (JSON), identificador de requisição e métricas simples no formato Prometheus.

Regras de privacidade: nunca entram nos logs corpo da requisição, query string, cabeçalhos de
autenticação nem e-mails. O caminho registrado é o MODELO da rota (`/sessoes/{sessao_id}`), não o
valor real, para não vazar identificadores.
"""

from __future__ import annotations

import json
import logging
import re
import threading
from datetime import UTC, datetime
from typing import Any

LOGGER = "mente_saudavel"
REQUEST_ID_RE = re.compile(r"[A-Za-z0-9._-]{8,64}")
# Quantificadores LIMITADOS: sem repetição ilimitada, o tempo de busca não explode com texto malicioso (ReDoS).
_EMAIL_RE = re.compile(r"[\w.+-]{1,64}@[\w-]{1,63}(?:\.[\w-]{1,63}){1,8}")
_CONTROLE_RE = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")


class JsonFormatter(logging.Formatter):
    """Uma linha JSON por evento: fácil de filtrar com jq e de enviar para Loki/ELK/CloudWatch."""

    def format(self, record: logging.LogRecord) -> str:
        linha: dict[str, Any] = {
            "ts": datetime.fromtimestamp(record.created, tz=UTC).isoformat(timespec="milliseconds"),
            "nivel": record.levelname,
            "msg": record.getMessage(),
        }
        campos = getattr(record, "campos", None)
        if isinstance(campos, dict):
            linha.update(campos)
        if record.exc_info:
            linha["erro"] = self.formatException(record.exc_info)
        return json.dumps(linha, ensure_ascii=False, default=str)


def configurar_logs(nivel: str = "INFO") -> logging.Logger:
    log = logging.getLogger(LOGGER)
    log.setLevel(nivel.upper())
    if not any(isinstance(h.formatter, JsonFormatter) for h in log.handlers):
        h = logging.StreamHandler()
        h.setFormatter(JsonFormatter())
        log.addHandler(h)
    return log


def limpar_texto_cliente(texto: str | None, limite: int) -> str | None:
    """Texto vindo do aplicativo: tira e-mails (dado pessoal) e caracteres de controle."""
    if texto is None:
        return None
    # Corta ANTES do regex (um e-mail cabe em 320 caracteres), tira quebras de linha (anti log-injection)
    # e caracteres de controle, mascara e-mails e só então aplica o limite final.
    curto = texto[: limite + 320].replace("\r", " ").replace("\n", " ")
    return _EMAIL_RE.sub("[email]", _CONTROLE_RE.sub(" ", curto))[:limite]


_FAIXAS = (0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0)


class Metricas:
    """Contadores e histograma de latência por (método, rota, classe de status). Um processo só."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._dados: dict[tuple[str, str, str], list[float]] = {}

    def observar(self, metodo: str, rota: str, status: int, segundos: float) -> None:
        chave = (metodo, rota, f"{status // 100}xx")
        with self._lock:
            d = self._dados.setdefault(chave, [0.0] * (len(_FAIXAS) + 2))
            d[0] += 1  # contagem
            d[1] += segundos  # soma
            for i, limite in enumerate(_FAIXAS):
                if segundos <= limite:
                    d[2 + i] += 1

    def texto(self) -> str:
        linhas = [
            "# HELP ms_http_requests_total Requisições HTTP.",
            "# TYPE ms_http_requests_total counter",
            "# HELP ms_http_request_duration_seconds Latência das requisições.",
            "# TYPE ms_http_request_duration_seconds histogram",
        ]
        with self._lock:
            itens = sorted(self._dados.items())
        for (metodo, rota, classe), d in itens:
            rot = f'metodo="{metodo}",rota="{rota}",status="{classe}"'
            linhas.append(f"ms_http_requests_total{{{rot}}} {int(d[0])}")
            for i, limite in enumerate(_FAIXAS):
                linhas.append(f'ms_http_request_duration_seconds_bucket{{{rot},le="{limite}"}} {int(d[2 + i])}')
            linhas.append(f'ms_http_request_duration_seconds_bucket{{{rot},le="+Inf"}} {int(d[0])}')
            linhas.append(f"ms_http_request_duration_seconds_sum{{{rot}}} {d[1]:.6f}")
            linhas.append(f"ms_http_request_duration_seconds_count{{{rot}}} {int(d[0])}")
        return "\n".join(linhas) + "\n"
