"""Classificação de falhas em categorias acionáveis.

A ordem de precedência evita falso diagnóstico: um teste de CORS que falha por timeout
é um problema de INFRAESTRUTURA, não de política CORS; um módulo que não importa é
COMPILAÇÃO, e nenhum teste chegou a rodar.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import StrEnum


class Category(StrEnum):
    COMPILATION = "compilation"
    INFRA = "infra"
    SECURITY = "security"
    CORS = "cors"
    CONTRACT = "contract"
    OTHER = "other"


@dataclass(frozen=True)
class CategoryInfo:
    title: str
    icon: str
    action: str


CATEGORY_INFO: dict[Category, CategoryInfo] = {
    Category.COMPILATION: CategoryInfo(
        "Erros de Compilação",
        "🧱",
        "Corrija a sintaxe/imports apontados. Reproduza com `python -m compileall -q .` e "
        "`pytest --collect-only`. Nenhum teste rodou de fato enquanto isto não for resolvido.",
    ),
    Category.INFRA: CategoryInfo(
        "Timeouts de Infraestrutura",
        "⏱️",
        "Nada indica falha de regra de negócio. Veja se o serviço subiu (`server.log`), aumente "
        "`health_timeout` se o boot é lento e confira DNS/conectividade. Reexecute para descartar instabilidade.",
    ),
    Category.SECURITY: CategoryInfo(
        "Violações de Segurança",
        "🛡️",
        "Um controle de segurança falhou (headers, limites, autenticação ou validação de entrada). "
        "Trate como bloqueante: corrija antes de qualquer deploy.",
    ),
    Category.CORS: CategoryInfo(
        "Violações de Política CORS",
        "🌐",
        "A política CORS diverge do esperado. Confira `Allow-Origin` exato, `Vary: Origin`, "
        "`Allow-Methods/Headers`, `Max-Age`, e nunca `*` com credenciais.",
    ),
    Category.CONTRACT: CategoryInfo(
        "Falhas de Contrato de API",
        "📜",
        "Status HTTP, tipo de dado ou schema divergem de `contracts/openapi.yaml`. Se a mudança foi "
        "intencional, atualize a especificação (e o consumidor); se não, é regressão da API.",
    ),
    Category.OTHER: CategoryInfo(
        "Outras falhas",
        "❓",
        "Falha não classificada. Leia o trecho do erro e o log completo do artefato `failure-dumps-*`.",
    ),
}

_COMPILE = re.compile(
    r"(SyntaxError|IndentationError|TabError|ModuleNotFoundError|ImportError|ERROR collecting|"
    r"Compilation failed|FAILURE: Build failed|error TS\d+|\.dart:\d+:\d+: Error:)"
)
_INFRA = re.compile(
    r"(HEALTHCHECK_TIMEOUT|SERVER_EXITED|ConnectTimeout|ReadTimeout|TimeoutError|Timeout >|timed out|"
    r"Max retries exceeded|ConnectionError|ConnectionRefusedError|RemoteDisconnected|NameResolutionError|"
    r"Temporary failure in name resolution|Failed to establish a new connection|Connection aborted)",
    re.IGNORECASE,
)
# Configuração CORS proibida recusada pelo serviço no boot: é política, não infraestrutura.
_CORS_FATAL = re.compile(r"FATAL:.*(ALLOWED_ORIGINS|ALLOW_CREDENTIALS|CORS)")
_SECURITY = re.compile(r"(\[SECURITY\]|SecurityViolation)")
_CORS = re.compile(r"(\[CORS\]|CorsPolicyViolation)")
_CONTRACT = re.compile(r"(\[CONTRACT\]|ContractViolation|jsonschema)")

_HINTS: tuple[tuple[re.Pattern[str], str], ...] = (
    (
        re.compile(r"Access-Control-Allow-Origin"),
        "Ecoe a origem exata autorizada (nunca por sufixo) e não emita o header para origens desconhecidas.",
    ),
    (re.compile(r"Vary"), "Adicione `Vary: Origin` (e, no preflight, `Access-Control-Request-Method/Headers`)."),
    (
        re.compile(r"Allow-Credentials"),
        "Com credenciais, `Allow-Origin` deve ser a origem exata, apenas para origens autorizadas.",
    ),
    (re.compile(r"Max-Age"), "Defina `Access-Control-Max-Age` como inteiro entre 1 e 86400."),
    (re.compile(r"Allow-Methods"), "Anuncie no preflight só os métodos que a rota aceita."),
    (re.compile(r"Allow-Headers"), "Anuncie só os headers realmente aceitos (content-type, authorization...)."),
    (
        re.compile(r"esperado HTTP"),
        "O status difere do contrato: verifique roteamento, validação de entrada e tratamento de erros.",
    ),
    (
        re.compile(r"schema inválido"),
        "Campo obrigatório ausente ou de tipo errado: compare com `contracts/openapi.yaml`.",
    ),
    (re.compile(r"HEALTHCHECK_TIMEOUT"), "O serviço não respondeu em /health no prazo: veja `server.log` e a porta."),
    (re.compile(r"SERVER_EXITED"), "O serviço morreu no boot: veja o traceback/FATAL em `server.log`."),
    (re.compile(r"ModuleNotFoundError|ImportError"), "Dependência ausente: confira `requirements.txt` e os imports."),
    (re.compile(r"SyntaxError|IndentationError"), "Erro de sintaxe: rode `python -m py_compile <arquivo>`."),
    (re.compile(r"\[SECURITY\]"), "Revise o controle indicado em `docs/SECURITY-CONTROLS.md`."),
)


# Ordem = precedência. A primeira regra que casar define a categoria.
_RULES: tuple[tuple[re.Pattern[str], Category], ...] = (
    (_COMPILE, Category.COMPILATION),
    (_CORS_FATAL, Category.CORS),
    (_INFRA, Category.INFRA),
    (_SECURITY, Category.SECURITY),
    (_CORS, Category.CORS),
    (_CONTRACT, Category.CONTRACT),
)


def classify(text: str) -> Category:
    """Categoria de um texto de falha, respeitando a precedência documentada."""
    return next((category for pattern, category in _RULES if pattern.search(text)), Category.OTHER)


def has_cors_fatal(text: str) -> bool:
    return bool(_CORS_FATAL.search(text))


def hints_for(text: str, limit: int = 2) -> tuple[str, ...]:
    return tuple(hint for pattern, hint in _HINTS if pattern.search(text))[:limit]
