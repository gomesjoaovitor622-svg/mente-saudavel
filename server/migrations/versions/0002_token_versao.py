"""Revogação de tokens: usuarios.token_versao.

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-26

Sem perda de dados: coluna nova com DEFAULT 0 (os tokens já emitidos têm versão 0 implícita e
continuam valendo até a pessoa trocar a senha).
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("usuarios", sa.Column("token_versao", sa.Integer(), nullable=False, server_default="0"))


def downgrade() -> None:
    with op.batch_alter_table("usuarios") as lote:  # SQLite precisa do modo "lote" para remover coluna
        lote.drop_column("token_versao")
