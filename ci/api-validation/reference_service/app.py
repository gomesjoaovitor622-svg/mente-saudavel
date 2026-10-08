"""Lógica da API de referência (pura: sem sockets, totalmente testável).

Controles de segurança implementados aqui (mapa em docs/SECURITY-CONTROLS.md):
  CORS estrito (origem exata, Vary, preflight validado), autenticação Bearer em tempo
  constante, rate limit, validação rígida de entrada, cabeçalhos de segurança em toda
  resposta, mensagens de erro sem detalhes internos.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import math
import re
import time
import uuid
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from reference_service.config import ServiceConfig

ALLOWED_HEADERS = frozenset({"content-type", "authorization", "x-requested-with"})
EXPOSED_HEADERS = "X-Request-Id"
MODALIDADES = frozenset({"Online", "Presencial"})
_PATH = re.compile(r"^/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*$")
_MAX_PATH = 2048
_MIN_YEAR, _MAX_YEAR = 1900, 2100

FERIADOS_FIXOS = (
    ("01-01", "Confraternização Universal"),
    ("04-21", "Tiradentes"),
    ("05-01", "Dia do Trabalho"),
    ("09-07", "Independência do Brasil"),
    ("10-12", "Nossa Senhora Aparecida"),
    ("11-02", "Finados"),
    ("11-15", "Proclamação da República"),
    ("11-20", "Dia da Consciência Negra"),
    ("12-25", "Natal"),
)
CEPS = {
    "01001000": {"cep": "01001000", "logradouro": "Praça da Sé", "bairro": "Sé", "localidade": "São Paulo", "uf": "SP"},
}

SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "no-store",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Referrer-Policy": "no-referrer",
    "X-Frame-Options": "DENY",
}


@dataclass(frozen=True)
class Request:
    method: str
    path: str
    headers: Mapping[str, str]  # chaves em minúsculas
    body: bytes = b""
    client: str = "-"  # chave do rate limit; nunca é registrada em log


@dataclass
class Response:
    status: int
    payload: Any = None
    headers: dict[str, str] = field(default_factory=dict)


def error(
    status: int,
    code: str,
    message: str,
    details: list[dict[str, str]] | None = None,
    headers: dict[str, str] | None = None,
) -> Response:
    corpo: dict[str, Any] = {"code": code, "message": message}
    if details is not None:
        corpo["details"] = details
    return Response(status, {"error": corpo}, headers or {})


class RateLimiter:
    """Token bucket por cliente. ``rate`` <= 0 desliga o limite."""

    def __init__(self, rate_per_sec: float, burst: int, clock: Callable[[], float] = time.monotonic) -> None:
        self._rate, self._burst, self._clock = rate_per_sec, float(burst), clock
        self._buckets: dict[str, tuple[float, float]] = {}

    def check(self, key: str) -> tuple[bool, float]:
        """(permitido, segundos até poder tentar de novo)."""
        if self._rate <= 0:
            return True, 0.0
        agora = self._clock()
        tokens, ultimo = self._buckets.get(key, (self._burst, agora))
        tokens = min(self._burst, tokens + (agora - ultimo) * self._rate)
        if tokens >= 1:
            self._buckets[key] = (tokens - 1, agora)
            return True, 0.0
        self._buckets[key] = (tokens, agora)
        return False, (1 - tokens) / self._rate


def _reject_constant(nome: str) -> Any:  # noqa: ANN401
    raise ValueError(f"constante JSON proibida: {nome}")


class ReferenceApp:
    def __init__(self, config: ServiceConfig, clock: Callable[[], float] = time.monotonic) -> None:
        self.config = config
        self._started = clock()
        self._clock = clock
        self._limiter = RateLimiter(config.rate_limit_per_sec, config.rate_burst, clock)
        self._routes: list[tuple[re.Pattern[str], dict[str, Callable[..., Response]]]] = [
            (re.compile(r"^/health$"), {"GET": self._health}),
            (re.compile(r"^/api/v1/feriados/(?P<ano>[^/]+)$"), {"GET": self._feriados}),
            (re.compile(r"^/api/v1/cep/(?P<cep>[^/]+)$"), {"GET": self._cep}),
            (re.compile(r"^/api/v1/sessoes/validar$"), {"POST": self._validar}),
        ]

    # ------------------------------------------------------------------ CORS
    def origin_allowed(self, origin: str | None) -> bool:
        return origin is not None and origin in self.config.allowed_origins  # comparação EXATA

    def _cors(self, origin: str | None) -> dict[str, str]:
        headers = {"Vary": "Origin"}
        if self.origin_allowed(origin) and origin is not None:
            headers["Access-Control-Allow-Origin"] = origin  # ecoa a origem; nunca "*" com credenciais
            headers["Access-Control-Expose-Headers"] = EXPOSED_HEADERS
            if self.config.allow_credentials:
                headers["Access-Control-Allow-Credentials"] = "true"
        return headers

    def _preflight(self, req: Request, methods: set[str] | None) -> Response:
        origin = req.headers.get("origin")
        method = req.headers.get("access-control-request-method")
        if origin is None or method is None:
            return error(400, "not_a_preflight", "Faltam Origin e/ou Access-Control-Request-Method.")
        if not self.origin_allowed(origin):
            return error(403, "origin_not_allowed", "Origem não autorizada.", headers={"Vary": "Origin"})
        if methods is None:
            return error(404, "not_found", "Rota inexistente.", headers=self._cors(origin))
        permitidos = methods | {"OPTIONS"}
        if method.upper() not in permitidos:
            return error(
                405,
                "method_not_allowed",
                "Método não permitido.",
                headers={"Allow": ", ".join(sorted(permitidos)), "Vary": "Origin"},
            )
        pedidos = [
            h.strip().lower() for h in req.headers.get("access-control-request-headers", "").split(",") if h.strip()
        ]
        invalidos = [h for h in pedidos if h not in ALLOWED_HEADERS]
        if invalidos:
            return error(403, "header_not_allowed", "Header não permitido.", headers={"Vary": "Origin"})
        headers = self._cors(origin)
        headers.update(
            {
                "Access-Control-Allow-Methods": ", ".join(sorted(permitidos)),
                "Access-Control-Allow-Headers": ", ".join(pedidos) if pedidos else "content-type",
                "Access-Control-Max-Age": str(self.config.cors_max_age),
                "Vary": "Origin, Access-Control-Request-Method, Access-Control-Request-Headers",
            }
        )
        return Response(204, None, headers)

    # ------------------------------------------------------------------ autenticação
    def _authorized(self, req: Request) -> bool:
        esperado = self.config.auth_token
        if esperado is None:
            return True
        enviado = req.headers.get("authorization", "")
        prefixo = "Bearer "
        if not enviado.startswith(prefixo):
            return False
        return hmac.compare_digest(enviado[len(prefixo) :].encode(), esperado.encode())

    # ------------------------------------------------------------------ despacho
    def handle(self, req: Request) -> Response:
        resposta = self._dispatch(req)
        resposta.headers = {**SECURITY_HEADERS, "X-Request-Id": uuid.uuid4().hex[:12], **resposta.headers}
        return resposta

    def _guard(self, req: Request) -> Response | None:
        """Pré-condições comuns a toda rota: rate limit e validação do caminho."""
        permitido, espera = self._limiter.check(req.client)
        if not permitido:
            return error(
                429, "rate_limited", "Muitas requisições.", headers={"Retry-After": str(max(1, math.ceil(espera)))}
            )
        if len(req.path) > _MAX_PATH:
            return error(414, "uri_too_long", "Caminho longo demais.")
        if not _PATH.match(req.path):
            return error(400, "invalid_path", "Caminho com caracteres inválidos.")
        return None

    def _dispatch(self, req: Request) -> Response:
        bloqueio = self._guard(req)
        if bloqueio is not None:
            return bloqueio

        params, methods = self._find(req.path)
        if req.method == "OPTIONS":
            return self._preflight(req, set(methods) if methods else None)
        cors = self._cors(req.headers.get("origin"))
        if methods is None:
            return error(404, "not_found", "Rota inexistente.", headers=cors)
        if req.method not in methods:
            allow = ", ".join(sorted({*methods, "OPTIONS"}))
            return error(405, "method_not_allowed", "Método não permitido.", headers={**cors, "Allow": allow})
        if req.path.startswith("/api/") and not self._authorized(req):
            return error(
                401,
                "unauthorized",
                "Credenciais ausentes ou inválidas.",
                headers={**cors, "WWW-Authenticate": "Bearer"},
            )
        resposta = methods[req.method](req, **params)
        resposta.headers = {**cors, **resposta.headers}
        return resposta

    def _find(self, path: str) -> tuple[dict[str, str], dict[str, Callable[..., Response]] | None]:
        for padrao, metodos in self._routes:
            m = padrao.match(path)
            if m:
                return m.groupdict(), metodos
        return {}, None

    # ------------------------------------------------------------------ rotas
    def _health(self, _req: Request) -> Response:
        return Response(200, {"status": "ok", "version": "1.0.0", "uptime_s": round(self._clock() - self._started, 3)})

    @staticmethod
    def _feriados(_req: Request, ano: str) -> Response:
        if not re.fullmatch(r"\d{4}", ano) or not _MIN_YEAR <= int(ano) <= _MAX_YEAR:
            return error(400, "invalid_year", "O ano deve ter 4 dígitos e estar entre 1900 e 2100.")
        return Response(200, [{"date": f"{ano}-{d}", "name": n, "type": "national"} for d, n in FERIADOS_FIXOS])

    @staticmethod
    def _cep(_req: Request, cep: str) -> Response:
        if not re.fullmatch(r"\d{8}", cep):
            return error(400, "invalid_cep", "O CEP deve ter exatamente 8 dígitos.")
        if cep not in CEPS:
            return error(404, "cep_not_found", "CEP não encontrado.")
        return Response(200, CEPS[cep])

    @staticmethod
    def _validar(req: Request) -> Response:
        tipo = req.headers.get("content-type", "").split(";")[0].strip().lower()
        if tipo != "application/json":
            return error(415, "unsupported_media_type", "Use Content-Type: application/json.")
        try:
            dados = json.loads(req.body.decode("utf-8"), parse_constant=_reject_constant)
        except (ValueError, RecursionError):  # UnicodeDecodeError e JSONDecodeError herdam de ValueError
            return error(400, "invalid_json", "O corpo não é um JSON válido.")
        if not isinstance(dados, dict):
            return error(422, "validation_error", "O corpo deve ser um objeto JSON.", [])

        erros: list[dict[str, str]] = []
        for campo in ("paciente_id", "profissional_id"):
            valor = dados.get(campo)
            if not isinstance(valor, int) or isinstance(valor, bool) or valor <= 0:
                erros.append({"field": campo, "message": "deve ser um inteiro positivo"})
        try:
            datetime.fromisoformat(str(dados.get("data_hora", "")))
        except ValueError:
            erros.append({"field": "data_hora", "message": "deve ser uma data/hora ISO 8601"})
        if dados.get("modalidade") not in MODALIDADES:
            erros.append({"field": "modalidade", "message": "deve ser Online ou Presencial"})
        if erros:
            return error(422, "validation_error", "Payload inválido.", erros)

        base = f"{dados['paciente_id']}-{dados['profissional_id']}-{dados['data_hora']}"
        sala = "MenteSaudavel-" + hashlib.sha256(base.encode()).hexdigest()[:12]
        return Response(200, {"valid": True, "sala": sala})
