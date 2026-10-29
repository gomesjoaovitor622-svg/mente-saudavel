"""Comandos de administração (sem rota HTTP de propósito: aprovar profissional exige acesso ao servidor).

Uso:
    python -m app.admin pendentes
    python -m app.admin aprovar EMAIL
    python -m app.admin revogar EMAIL
"""

from __future__ import annotations

import sys

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import tempo
from app.config import load_settings
from app.db import make_engine, make_session_factory
from app.models import Usuario


def pendentes(db: Session) -> list[Usuario]:
    q = select(Usuario).where(Usuario.perfil == "profissional", Usuario.verificado_em.is_(None)).order_by(Usuario.criado_em)
    return list(db.scalars(q))


def _achar(db: Session, email: str) -> Usuario:
    u = db.scalar(select(Usuario).where(Usuario.email == email.strip().lower(), Usuario.perfil == "profissional"))
    if u is None:
        raise SystemExit(f"Profissional não encontrado: {email}")
    return u


def aprovar(db: Session, email: str) -> Usuario:
    u = _achar(db, email)
    u.verificado_em = tempo.agora().replace(microsecond=0)
    db.commit()
    return u


def revogar(db: Session, email: str) -> Usuario:
    u = _achar(db, email)
    u.verificado_em = None
    db.commit()
    return u


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in {"pendentes", "aprovar", "revogar"} or (argv[0] != "pendentes" and len(argv) != 2):
        print(__doc__)
        return 2
    cfg = load_settings()
    tempo.definir_fuso(cfg.app_tz)
    with make_session_factory(make_engine(cfg.database_url))() as db:
        if argv[0] == "pendentes":
            for u in pendentes(db):
                print(f"{u.email}\t{u.nome}\tCRP {u.registro}\tcadastro em {u.criado_em:%d/%m/%Y %H:%M}")
        elif argv[0] == "aprovar":
            u = aprovar(db, argv[1])
            print(f"Aprovado: {u.nome} ({u.email}) — CRP {u.registro}")
        else:
            u = revogar(db, argv[1])
            print(f"Aprovação removida: {u.nome} ({u.email})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
