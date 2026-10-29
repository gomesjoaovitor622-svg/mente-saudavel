"""Peças compartilhadas pelas rotas: sessão do banco, usuário logado, limites e regras de agenda."""

import re
import time
from collections import defaultdict, deque
from collections.abc import Iterator
from datetime import datetime
from typing import Annotated, Any

from fastapi import Depends, HTTPException, Request, Response
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import Settings
from app.db import session_iter
from app.models import Sessao, Usuario
from app.security import criar_token, ler_token_com_versao

COOKIE_SESSAO = "ms_sessao"
CHAVE_IDEMPOTENCIA = re.compile(r"[A-Za-z0-9_-]{8,64}")


class LimiteLogin:
    """Limita tentativas de login (janela de 60 s) por chave. Em memória: 1 processo."""

    def __init__(self, maximo: int) -> None:
        self.maximo = maximo
        self._tentativas: dict[str, deque[float]] = defaultdict(deque)

    def checar(self, chave: str) -> None:
        agora = time.monotonic()
        if len(self._tentativas) > 10_000:  # evita crescer sem fim com chaves (e-mails/IPs) que nunca voltam
            for k in [k for k, f in self._tentativas.items() if not f or agora - f[-1] > 60]:
                del self._tentativas[k]
        fila = self._tentativas[chave]
        while fila and agora - fila[0] > 60:
            fila.popleft()
        if len(fila) >= self.maximo:
            raise HTTPException(429, "Muitas tentativas. Aguarde um minuto e tente novamente.")
        fila.append(agora)

    def limpar(self, chave: str) -> None:
        self._tentativas.pop(chave, None)


def get_db(request: Request) -> Iterator[Session]:
    yield from session_iter(request.app.state.session_factory)


Db = Annotated[Session, Depends(get_db)]


def usuario_atual(request: Request, db: Db) -> Usuario:
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):  # celular: token no cabeçalho (guardado no Keystore/Keychain)
        token = auth[7:]
    else:  # web: cookie HttpOnly, que o JavaScript da página não consegue ler (protege contra XSS)
        token = request.cookies.get(COOKIE_SESSAO, "")
        if not token:
            raise HTTPException(401, "Não autenticado.")
        # Defesa extra contra CSRF (além de SameSite=Strict): ações que alteram dados exigem este
        # cabeçalho, que um formulário de outro site não consegue enviar.
        if request.method not in {"GET", "HEAD", "OPTIONS"} and request.headers.get("X-Requested-With") != "mente-saudavel":
            raise HTTPException(403, "Requisição não permitida.")
    if not token:
        raise HTTPException(401, "Não autenticado.")
    lido = ler_token_com_versao(token, request.app.state.settings.jwt_secret)
    user = db.get(Usuario, lido[0]) if lido is not None else None
    if user is None or user.anonimizado_em is not None or lido is None or lido[1] != user.token_versao:
        raise HTTPException(401, "Sessão expirada. Entre novamente.")
    return user


Eu = Annotated[Usuario, Depends(usuario_atual)]


def emitir_token(cfg: Settings, user: Usuario, response: Response) -> str:
    """Cria o token da sessão e grava o cookie HttpOnly (web). Devolve o token (celular)."""
    token = criar_token(user.id, cfg.jwt_secret, cfg.jwt_ttl_hours, user.token_versao)
    response.set_cookie(COOKIE_SESSAO, token, max_age=cfg.jwt_ttl_hours * 3600, httponly=True, secure=cfg.cookie_secure, samesite="strict", path="/")
    return token


def exigir_perfil(user: Usuario, perfil: str) -> None:
    if user.perfil != perfil:
        raise HTTPException(403, "Ação não permitida para o seu perfil.")


def carregar_sessao(db: Session, sessao_id: int, user: Usuario) -> Sessao:
    s = db.get(Sessao, sessao_id)
    # 404 (e não 403) para não revelar a existência de sessões de outras pessoas.
    if s is None or user.id not in (s.paciente_id, s.profissional_id):
        raise HTTPException(404, "Sessão não encontrada.")
    return s


def mensagem_conflito(db: Session, prof_id: int, pac_id: int, quando: datetime, ignorar: int) -> str | None:
    def existe(coluna: Any, valor: int) -> bool:
        q = select(func.count()).select_from(Sessao).where(coluna == valor, Sessao.data_hora == quando, Sessao.status != "cancelada", Sessao.id != ignorar)
        return (db.scalar(q) or 0) > 0

    if existe(Sessao.profissional_id, prof_id):
        return "O profissional já tem uma sessão neste horário."
    if existe(Sessao.paciente_id, pac_id):
        return "Você já tem uma sessão neste horário."
    return None


def gravar_sessao(db: Session, prof_id: int, pac_id: int, quando: datetime, ignorar: int, chave: str | None = None) -> Sessao | None:
    """Confirma a gravação. Se o banco recusar por horário duplicado (corrida entre 2 requisições), responde 409.

    Se a recusa foi da CHAVE DE IDEMPOTÊNCIA (o mesmo agendamento chegou duas vezes ao mesmo tempo),
    devolve a sessão que já existe em vez de erro."""
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        texto = str(e.orig).lower()
        if "unique" not in texto and "duplicate" not in texto:
            raise
        if chave:
            existente = db.scalar(select(Sessao).where(Sessao.paciente_id == pac_id, Sessao.chave_idempotencia == chave))
            if existente is not None:
                return existente
        raise HTTPException(409, mensagem_conflito(db, prof_id, pac_id, quando, ignorar) or "Este horário acabou de ser ocupado. Escolha outro.") from None
    return None
