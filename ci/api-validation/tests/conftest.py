"""Opções e fixtures dos testes de sistema.

Variáveis de ambiente (todas opcionais):
  API_BASE_URL    URL do serviço sob teste (padrão http://127.0.0.1:8765)
  TARGET_ORIGIN   origem "autorizada" usada nos testes de CORS
  DENIED_ORIGIN   origem "não autorizada"
  API_AUTH_TOKEN  token do serviço sob teste (NUNCA é enviado a APIs de terceiros)
"""

from __future__ import annotations

import os
from collections.abc import Iterator
from typing import Any

import pytest
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

DEFAULT_ORIGIN = "https://gomesjoaovitor622-svg.github.io"


def pytest_addoption(parser: pytest.Parser) -> None:
    grupo = parser.getgroup("api-validation")
    grupo.addoption("--base-url", default=os.getenv("API_BASE_URL", "http://127.0.0.1:8765"))
    grupo.addoption("--origin-allowed", default=os.getenv("TARGET_ORIGIN") or DEFAULT_ORIGIN)
    grupo.addoption("--origin-denied", default=os.getenv("DENIED_ORIGIN", "https://evil.example"))


class TimeoutSession(requests.Session):
    """Session com timeout padrão (conexão, leitura): nenhum request fica pendurado."""

    def __init__(self, base_url: str = "", timeout: tuple[float, float] = (3.05, 10)) -> None:
        super().__init__()
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout

    def request(self, method: str, url: str, **kwargs: Any) -> requests.Response:  # type: ignore[override]
        if self._base_url and url.startswith("/"):
            url = self._base_url + url
        kwargs.setdefault("timeout", self._timeout)
        return super().request(method, url, **kwargs)


def _with_retries(session: requests.Session) -> requests.Session:
    # Só reexecuta métodos idempotentes, e só em erros transitórios de rede/gateway.
    retry = Retry(
        total=2,
        connect=2,
        read=2,
        backoff_factor=0.3,
        status_forcelist=(502, 503, 504),
        allowed_methods=frozenset({"GET", "HEAD", "OPTIONS"}),
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session


@pytest.fixture(scope="session")
def base_url(pytestconfig: pytest.Config) -> str:
    return str(pytestconfig.getoption("--base-url")).rstrip("/")


@pytest.fixture(scope="session")
def allowed_origin(pytestconfig: pytest.Config) -> str:
    return str(pytestconfig.getoption("--origin-allowed"))


@pytest.fixture(scope="session")
def denied_origin(pytestconfig: pytest.Config) -> str:
    return str(pytestconfig.getoption("--origin-denied"))


@pytest.fixture(scope="session")
def auth_enabled() -> bool:
    """True quando o serviço foi iniciado exigindo token (o pipeline gera um por execução)."""
    return bool(os.getenv("API_AUTH_TOKEN"))


@pytest.fixture(scope="session")
def api(base_url: str) -> Iterator[requests.Session]:
    """Cliente do serviço sob teste. Único que envia API_AUTH_TOKEN."""
    sessao = _with_retries(TimeoutSession(base_url))
    token = os.getenv("API_AUTH_TOKEN")
    if token:
        sessao.headers["Authorization"] = f"Bearer {token}"
    yield sessao
    sessao.close()


@pytest.fixture(scope="session")
def anonymous(base_url: str) -> Iterator[requests.Session]:
    """Cliente do serviço sob teste SEM credenciais."""
    sessao = _with_retries(TimeoutSession(base_url))
    yield sessao
    sessao.close()


@pytest.fixture(scope="session")
def public() -> Iterator[requests.Session]:
    """Cliente para APIs públicas de terceiros. Nunca recebe credenciais."""
    sessao = _with_retries(TimeoutSession(timeout=(5, 15)))
    sessao.headers["User-Agent"] = "mente-saudavel-api-validation/1.0"
    yield sessao
    sessao.close()
