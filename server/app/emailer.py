"""Envio de e-mail por SMTP (só biblioteca padrão). Usado para códigos de confirmação e de redefinição de senha."""

from __future__ import annotations

import logging
import smtplib
import ssl
from email.message import EmailMessage
from typing import Protocol

from app.config import Settings


class Mailer(Protocol):
    def enviar(self, para: str, assunto: str, texto: str) -> None: ...


class SmtpMailer:
    """Conexão curta por mensagem (volume baixo). Qualquer falha vira exceção; quem chama decide o que fazer."""

    def __init__(self, cfg: Settings) -> None:
        self._cfg = cfg

    def enviar(self, para: str, assunto: str, texto: str) -> None:
        c = self._cfg
        msg = EmailMessage()
        msg["From"] = c.smtp_from
        msg["To"] = para
        msg["Subject"] = assunto
        msg.set_content(texto)
        contexto = ssl.create_default_context()
        if c.smtp_seguranca == "ssl":
            with smtplib.SMTP_SSL(c.smtp_host, c.smtp_port, timeout=15, context=contexto) as s:
                self._entregar(s, msg)
        else:
            with smtplib.SMTP(c.smtp_host, c.smtp_port, timeout=15) as s:
                if c.smtp_seguranca == "starttls":
                    s.starttls(context=contexto)
                self._entregar(s, msg)

    def _entregar(self, s: smtplib.SMTP, msg: EmailMessage) -> None:
        if self._cfg.smtp_user:
            s.login(self._cfg.smtp_user, self._cfg.smtp_password)
        s.send_message(msg)


class NenhumMailer:
    """E-mail desligado: nunca é chamado (as rotas respondem 503 antes), mas existe para o tipo ficar completo."""

    def enviar(self, para: str, assunto: str, texto: str) -> None:  # pragma: no cover
        raise RuntimeError("O envio de e-mail não está configurado (SMTP_HOST e SMTP_FROM).")


def enviar_sem_vazar(mailer: Mailer, log: logging.Logger, para: str, assunto: str, texto: str) -> None:
    """Para tarefa em segundo plano: registra só o resultado, nunca o endereço nem o código."""
    try:
        mailer.enviar(para, assunto, texto)
        log.info("email_enviado")
    except Exception:  # noqa: BLE001  (SMTP pode falhar de muitas formas; a requisição já respondeu)
        log.error("email_falhou", exc_info=True)
