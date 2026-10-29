"""Conta: confirmação de e-mail e recuperação de senha por código enviado por e-mail.

- Código de 6 dígitos, válido por `codigo_validade_min` (padrão 15 min), de uso único; só o HMAC fica no banco.
- No máximo 5 tentativas por código (6 dígitos = 1 milhão de possibilidades: sem limite seria quebrável).
- "Esqueci a senha" responde SEMPRE igual (204), exista a conta ou não: não revela quem tem cadastro.
- O envio acontece em segundo plano, para o tempo de resposta não revelar se o e-mail existe.
- Trocar a senha por este caminho derruba todos os aparelhos (token_versao) e confirma o e-mail.
"""

import hashlib
import hmac
import logging
import secrets
from collections.abc import Callable
from datetime import timedelta
from typing import Annotated, Any

from fastapi import BackgroundTasks, Depends, FastAPI, HTTPException, Request, Response
from pydantic import EmailStr, Field
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app import tempo
from app.config import Settings
from app.emailer import Mailer, enviar_sem_vazar
from app.models import CodigoEmail, Usuario
from app.schemas import _Base
from app.security import hash_senha

MAX_TENTATIVAS = 5
VERIFICAR = "verificar_email"
REDEFINIR = "redefinir_senha"


class EsqueciIn(_Base):
    email: EmailStr


class RedefinirIn(_Base):
    email: EmailStr
    codigo: str = Field(pattern=r"^\d{6}$")
    nova_senha: str = Field(min_length=1, max_length=128)


class CodigoIn(_Base):
    codigo: str = Field(pattern=r"^\d{6}$")


class Conta:
    def __init__(self, cfg: Settings, mailer: Mailer, log: logging.Logger) -> None:
        self.cfg, self.mailer, self.log = cfg, mailer, log

    def _hash(self, usuario_id: int, finalidade: str, codigo: str) -> str:
        return hmac.new(self.cfg.jwt_secret.encode(), f"{usuario_id}|{finalidade}|{codigo}".encode(), hashlib.sha256).hexdigest()

    def criar_codigo(self, db: Session, user: Usuario, finalidade: str) -> str:
        """Gera um código novo e invalida os anteriores da mesma finalidade. Quem chama faz o commit."""
        db.execute(delete(CodigoEmail).where(CodigoEmail.usuario_id == user.id, CodigoEmail.finalidade == finalidade))
        codigo = f"{secrets.randbelow(10**6):06d}"
        db.add(
            CodigoEmail(
                usuario_id=user.id,
                finalidade=finalidade,
                codigo_hash=self._hash(user.id, finalidade, codigo),
                expira_em=tempo.agora() + timedelta(minutes=self.cfg.codigo_validade_min),
            )
        )
        return codigo

    def conferir(self, db: Session, user: Usuario, finalidade: str, codigo: str) -> bool:
        """True se o código vale (e o consome). Errar gasta tentativas; passou do limite, o código morre."""
        c = db.scalar(select(CodigoEmail).where(CodigoEmail.usuario_id == user.id, CodigoEmail.finalidade == finalidade, CodigoEmail.usado_em.is_(None)))
        agora = tempo.agora()
        if c is None or c.expira_em < agora or c.tentativas >= MAX_TENTATIVAS:
            return False
        if hmac.compare_digest(c.codigo_hash, self._hash(user.id, finalidade, codigo)):
            c.usado_em = agora
            return True
        c.tentativas += 1
        db.commit()  # a tentativa errada precisa ficar registrada mesmo que a requisição termine em erro
        return False

    def texto_verificacao(self, codigo: str) -> tuple[str, str]:
        return (
            "Mente Saudável: confirme seu e-mail",
            f"Seu código para confirmar o e-mail é {codigo}.\nEle vale por {self.cfg.codigo_validade_min} minutos. Se não foi você, ignore esta mensagem.",
        )

    def texto_redefinicao(self, codigo: str) -> tuple[str, str]:
        return (
            "Mente Saudável: código para redefinir a senha",
            f"Seu código para redefinir a senha é {codigo}.\nEle vale por {self.cfg.codigo_validade_min} minutos. "
            "Se você não pediu, ignore esta mensagem: sua senha continua a mesma.",
        )

    def agendar_envio(self, background: BackgroundTasks, para: str, assunto_texto: tuple[str, str]) -> None:
        background.add_task(enviar_sem_vazar, self.mailer, self.log, para, assunto_texto[0], assunto_texto[1])

    def enviar_verificacao(self, db: Session, user: Usuario, background: BackgroundTasks) -> None:
        """Cadastro novo / reenvio: gera o código, grava e agenda o e-mail. Sem SMTP, não faz nada."""
        if not self.cfg.email_ativo:
            return
        codigo = self.criar_codigo(db, user, VERIFICAR)
        db.commit()
        self.agendar_envio(background, user.email, self.texto_verificacao(codigo))


def registrar_rotas(
    app: FastAPI,
    cfg: Settings,
    conta: Conta,
    get_db: Callable[..., Any],
    usuario_atual: Callable[..., Usuario],
    limite_ip: Any,
    limite_email: Any,
    limite_usuario: Any,
) -> None:
    Db = Annotated[Session, Depends(get_db)]  # noqa: N806
    Eu = Annotated[Usuario, Depends(usuario_atual)]  # noqa: N806

    def exigir_email() -> None:
        if not cfg.email_ativo:
            raise HTTPException(503, "O envio de e-mail não está configurado neste servidor.")

    @app.post("/auth/senha/esqueci", status_code=204)
    def esqueci_senha(body: EsqueciIn, request: Request, db: Db, background: BackgroundTasks) -> Response:
        exigir_email()
        email = body.email.lower()
        limite_ip.checar(request.client.host if request.client else "?")
        limite_email.checar(email)
        user = db.scalar(select(Usuario).where(Usuario.email == email))
        if user is not None and user.anonimizado_em is None:
            codigo = conta.criar_codigo(db, user, REDEFINIR)
            db.commit()
            conta.agendar_envio(background, user.email, conta.texto_redefinicao(codigo))
        return Response(status_code=204)  # igual com ou sem conta

    @app.post("/auth/senha/redefinir", status_code=204)
    def redefinir_senha(body: RedefinirIn, request: Request, db: Db) -> Response:
        exigir_email()
        limite_ip.checar(request.client.host if request.client else "?")
        if len(body.nova_senha) < cfg.password_min:
            raise HTTPException(422, f"A senha deve ter pelo menos {cfg.password_min} caracteres.")
        user = db.scalar(select(Usuario).where(Usuario.email == body.email.lower()))
        if user is None or user.anonimizado_em is not None or not conta.conferir(db, user, REDEFINIR, body.codigo):
            raise HTTPException(400, "Código inválido ou expirado. Peça um novo código.")
        user.senha_hash = hash_senha(body.nova_senha)
        user.token_versao += 1  # derruba todos os aparelhos
        if user.email_verificado_em is None:
            user.email_verificado_em = tempo.agora()  # quem recebeu o código é dono do e-mail
        db.commit()
        conta.log.info("senha_redefinida", extra={"campos": {"usuario_id": user.id}})
        return Response(status_code=204)

    @app.post("/auth/email/codigo", status_code=204)
    def reenviar_codigo(user: Eu, db: Db, background: BackgroundTasks) -> Response:
        exigir_email()
        limite_usuario.checar(f"email|{user.id}")
        if user.email_verificado_em is not None:
            raise HTTPException(409, "Seu e-mail já está confirmado.")
        conta.enviar_verificacao(db, user, background)
        return Response(status_code=204)

    @app.post("/auth/email/verificar", status_code=204)
    def verificar_email(body: CodigoIn, user: Eu, db: Db) -> Response:
        exigir_email()
        limite_usuario.checar(f"verificar|{user.id}")
        if user.email_verificado_em is not None:
            return Response(status_code=204)
        if not conta.conferir(db, user, VERIFICAR, body.codigo):
            raise HTTPException(400, "Código inválido ou expirado. Peça um novo código.")
        user.email_verificado_em = tempo.agora()
        db.commit()
        return Response(status_code=204)
