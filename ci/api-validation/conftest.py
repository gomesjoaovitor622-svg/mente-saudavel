"""Configuração do pytest: opções de linha de comando e fixtures.

Variáveis de ambiente aceitas (todas opcionais):
  API_BASE_URL     URL do serviço sob teste (padrão http://127.0.0.1:8765)
  TARGET_ORIGIN    origem "autorizada" usada nos testes de CORS
  DENIED_ORIGIN    origem "não autorizada"
  API_AUTH_TOKEN   token do serviço sob teste (NUNCA é enviado a APIs de terceiros)
"""
from __future__ import annotations

import os

import pytest
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

DEFAULT_ORIGIN = "https://gomesjoaovitor622-svg.github.io"


def pytest_addoption(parser):
    grupo = parser.getgroup("api-validation")
    grupo.addoption("--base-url", default=os.getenv("API_BASE_URL", "http://127.0.0.1:8765"))
    grupo.addoption("--origin-allowed", default=os.getenv("TARGET_ORIGIN") or DEFAULT_ORIGIN)
    grupo.addoption("--origin-denied", default=os.getenv("DENIED_ORIGIN", "https://evil.example"))


class _TimeoutSession(requests.Session):
    """Session com timeout padrão (conexão, leitura): nenhum request fica pendurado."""

    def __init__(self, base_url: str = "", timeout=(3.05, 10)):
        super().__init__()
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout

    def request(self, method, url, **kwargs):  # type: ignore[override]
        if self._base_url and url.startswith("/"):
            url = self._base_url + url
        kwargs.setdefault("timeout", self._timeout)
        return super().request(method, url, **kwargs)


def _with_retries(session: requests.Session) -> requests.Session:
    # Só reexecuta métodos idempotentes e só em erros transitórios de rede/gateway.
    retry = Retry(
        total=2, connect=2, read=2, backoff_factor=0.3,
        status_forcelist=(502, 503, 504),
        allowed_methods=frozenset({"GET", "HEAD", "OPTIONS"}),
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session


@pytest.fixture(scope="session")
def base_url(pytestconfig) -> str:
    return pytestconfig.getoption("--base-url").rstrip("/")


@pytest.fixture(scope="session")
def allowed_origin(pytestconfig) -> str:
    return pytestconfig.getoption("--origin-allowed")


@pytest.fixture(scope="session")
def denied_origin(pytestconfig) -> str:
    return pytestconfig.getoption("--origin-denied")


@pytest.fixture(scope="session")
def api(base_url):
    """Cliente do serviço sob teste. Único que pode enviar API_AUTH_TOKEN."""
    sessao = _with_retries(_TimeoutSession(base_url))
    token = os.getenv("API_AUTH_TOKEN")
    if token:
        sessao.headers["Authorization"] = f"Bearer {token}"
    yield sessao
    sessao.close()


@pytest.fixture(scope="session")
def public():
    """Cliente para APIs públicas de terceiros. Nunca recebe credenciais."""
    sessao = _with_retries(_TimeoutSession(timeout=(5, 15)))
    sessao.headers["User-Agent"] = "mente-saudavel-api-validation/1.0"
    yield sessao
    sessao.close()
