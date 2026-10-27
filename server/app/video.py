"""Videochamada das sessões online (Jitsi Meet com autenticação por JWT).

O servidor NÃO transmite vídeo: ele decide QUEM pode entrar e QUANDO, e entrega um link com token de curta duração
para um servidor Jitsi (próprio, recomendado). Veja docs/VIDEO.md.
- Sala única e imprevisível por sessão (HMAC), só para os dois participantes.
- Só abre numa janela ao redor do horário (padrão: 15 min antes até 120 min depois).
- O profissional entra como moderador. O paciente entra identificado só pelo primeiro nome.
"""

import hashlib
import hmac
import logging
import time
from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Annotated, Any
from urllib.parse import quote

import jwt
from fastapi import Depends, FastAPI, HTTPException
from sqlalchemy.orm import Session

from app.config import Settings
from app.models import Sessao, Usuario


def nome_da_sala(segredo: str, sessao: Sessao) -> str:
    """Nome imprevisível e estável: quem não participa da sessão não consegue adivinhá-lo."""
    base = f"video|{sessao.id}|{sessao.profissional_id}|{sessao.paciente_id}|{sessao.criado_em.isoformat()}"
    return "ms-" + hmac.new(segredo.encode(), base.encode(), hashlib.sha256).hexdigest()[:32]


def token_jitsi(cfg: Settings, sala: str, nome: str, moderador: bool, expira_em: float) -> str:
    agora = int(time.time())
    carga = {
        "iss": cfg.video_app_id,
        "aud": "jitsi",
        "sub": cfg.video_domain,
        "room": sala,
        "nbf": agora - 10,
        "exp": int(expira_em),
        "moderator": moderador,
        "context": {"user": {"name": nome, "moderator": moderador}},
    }
    return jwt.encode(carga, cfg.video_app_secret, algorithm="HS256")


def registrar_rotas(app: FastAPI, cfg: Settings, get_db: Callable[..., Any], usuario_atual: Callable[..., Usuario], log: logging.Logger) -> None:
    Db = Annotated[Session, Depends(get_db)]  # noqa: N806
    Eu = Annotated[Usuario, Depends(usuario_atual)]  # noqa: N806

    @app.get("/sessoes/{sessao_id}/video")
    def entrar_na_video(sessao_id: int, user: Eu, db: Db) -> dict[str, Any]:
        if not cfg.video_domain:
            raise HTTPException(503, "A videochamada não está configurada neste servidor.")
        s = db.get(Sessao, sessao_id)
        if s is None or user.id not in (s.paciente_id, s.profissional_id):
            raise HTTPException(404, "Sessão não encontrada.")  # não revela sessões de outras pessoas
        if s.modalidade != "Online":
            raise HTTPException(409, "Esta sessão é presencial.")
        if s.status != "agendada":
            raise HTTPException(409, "Esta sessão foi cancelada ou já foi encerrada.")
        agora = datetime.now()
        abre, fecha = s.data_hora - timedelta(minutes=cfg.video_antes_min), s.data_hora + timedelta(minutes=cfg.video_depois_min)
        if agora < abre:
            raise HTTPException(409, f"A sala abre às {abre:%H:%M} de {abre:%d/%m}.")
        if agora > fecha:
            raise HTTPException(409, "O horário desta sessão já passou.")
        moderador = user.id == s.profissional_id
        sala = nome_da_sala(cfg.jwt_secret, s)
        expira_em = time.time() + (fecha - agora).total_seconds()
        url = f"https://{cfg.video_domain}/{sala}"
        if cfg.video_app_secret:
            nome = user.nome if moderador else user.nome.split()[0]  # minimização: o paciente aparece só pelo primeiro nome
            url += f"?jwt={quote(token_jitsi(cfg, sala, nome, moderador, expira_em))}"
        log.info("video_acesso", extra={"campos": {"sessao_id": s.id, "usuario_id": user.id}})  # sem URL/token no log
        return {"url": url, "sala": sala, "moderador": moderador, "expira_em": datetime.fromtimestamp(expira_em).replace(microsecond=0).isoformat()}
