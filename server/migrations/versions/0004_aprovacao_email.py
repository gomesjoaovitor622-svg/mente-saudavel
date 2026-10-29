"""Aprovação de profissionais, confirmação de e-mail e códigos por e-mail.

Revision ID: 0004
Revises: 0003
Create Date: 2026-10-28

Contas que já existem são mantidas funcionando: profissionais atuais ficam aprovados e e-mails já cadastrados
contam como confirmados (o bloqueio vale só para quem se cadastrar daqui para frente).
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("usuarios", sa.Column("verificado_em", sa.DateTime(), nullable=True))
    op.add_column("usuarios", sa.Column("email_verificado_em", sa.DateTime(), nullable=True))
    op.execute("UPDATE usuarios SET verificado_em = CURRENT_TIMESTAMP WHERE perfil = 'profissional'")
    op.execute("UPDATE usuarios SET email_verificado_em = CURRENT_TIMESTAMP")
    op.create_table(
        "codigos_email",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("usuario_id", sa.Integer(), sa.ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False),
        sa.Column("finalidade", sa.String(20), nullable=False),
        sa.Column("codigo_hash", sa.String(64), nullable=False),
        sa.Column("expira_em", sa.DateTime(), nullable=False),
        sa.Column("tentativas", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("usado_em", sa.DateTime(), nullable=True),
        sa.Column("criado_em", sa.DateTime(), nullable=False),
        sa.CheckConstraint("finalidade IN ('verificar_email','redefinir_senha')", name="ck_codigo_finalidade"),
    )
    op.create_index("idx_codigos_usuario", "codigos_email", ["usuario_id", "finalidade"])


def downgrade() -> None:
    op.drop_index("idx_codigos_usuario", table_name="codigos_email")
    op.drop_table("codigos_email")
    op.drop_column("usuarios", "email_verificado_em")
    op.drop_column("usuarios", "verificado_em")
