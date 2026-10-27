"""Prontuário do psicólogo: entradas cifradas, revisões e registro de acessos.

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-27

Só cria tabelas novas (nenhum dado existente é alterado). As FKs para usuários são RESTRICT de propósito:
prontuário tem guarda obrigatória e não pode sumir junto com uma conta.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "prontuario_entradas",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("profissional_id", sa.Integer(), sa.ForeignKey("usuarios.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("paciente_id", sa.Integer(), sa.ForeignKey("usuarios.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("sessao_id", sa.Integer(), sa.ForeignKey("sessoes.id", ondelete="SET NULL")),
        sa.Column("tipo", sa.String(20), nullable=False),
        sa.Column("conteudo_cifrado", sa.Text(), nullable=False),
        sa.Column("versao", sa.Integer(), nullable=False),
        sa.Column("criado_em", sa.DateTime(), nullable=False),
        sa.Column("atualizado_em", sa.DateTime(), nullable=False),
        sa.CheckConstraint("tipo IN ('evolucao','anamnese','plano','observacao')", name="ck_prontuario_tipo"),
    )
    op.create_index("idx_prontuario_prof_pac", "prontuario_entradas", ["profissional_id", "paciente_id", "criado_em"])
    op.create_table(
        "prontuario_revisoes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("entrada_id", sa.Integer(), sa.ForeignKey("prontuario_entradas.id", ondelete="CASCADE"), nullable=False),
        sa.Column("versao", sa.Integer(), nullable=False),
        sa.Column("conteudo_cifrado", sa.Text(), nullable=False),
        sa.Column("substituida_em", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("entrada_id", "versao", name="uq_prontuario_revisao"),
    )
    op.create_table(
        "prontuario_acessos",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("profissional_id", sa.Integer(), sa.ForeignKey("usuarios.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("paciente_id", sa.Integer(), sa.ForeignKey("usuarios.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("entrada_id", sa.Integer()),
        sa.Column("acao", sa.String(20), nullable=False),
        sa.Column("em", sa.DateTime(), nullable=False),
        sa.Column("request_id", sa.String(32)),
    )
    op.create_index("idx_prontuario_acessos", "prontuario_acessos", ["paciente_id", "em"])


def downgrade() -> None:
    op.drop_table("prontuario_acessos")
    op.drop_table("prontuario_revisoes")
    op.drop_table("prontuario_entradas")
