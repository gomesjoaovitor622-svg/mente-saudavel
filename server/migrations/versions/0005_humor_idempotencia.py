"""Idempotência do diário de humor (reenvio da fila offline do app não duplica registros).

Revision ID: 0005
Revises: 0004
Create Date: 2026-11-05
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None

_COM_CHAVE = sa.text("chave_idempotencia IS NOT NULL")


def upgrade() -> None:
    op.add_column("humor_registros", sa.Column("chave_idempotencia", sa.String(64), nullable=True))
    op.create_index(
        "uq_humor_idempotencia",
        "humor_registros",
        ["usuario_id", "chave_idempotencia"],
        unique=True,
        postgresql_where=_COM_CHAVE,
        sqlite_where=_COM_CHAVE,
    )


def downgrade() -> None:
    op.drop_index("uq_humor_idempotencia", table_name="humor_registros")
    op.drop_column("humor_registros", "chave_idempotencia")
