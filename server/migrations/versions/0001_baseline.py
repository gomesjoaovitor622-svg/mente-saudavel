"""Esquema inicial completo (baseline): usuários, sessões, humor e avaliações.

Revision ID: 0001
Revises:
Create Date: 2026-10-25

DDL escrito à mão (não gerado), de propósito: é o contrato do banco de produção. O teste
`test_migracoes.py` garante que ele continua IDÊNTICO aos models.

Banco que já existia, criado pelo modo "auto" da API (create_all)? Não rode esta migração:
confirme que o esquema bate e marque a versão com `alembic stamp 0001`.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None

# Índices únicos PARCIAIS (mesma sintaxe no PostgreSQL e no SQLite): valem só para registros "ativos".
_ATIVA = sa.text("status <> 'cancelada'")
_COM_CHAVE = sa.text("chave_idempotencia IS NOT NULL")


def upgrade() -> None:
    op.create_table(
        "usuarios",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("nome", sa.String(120), nullable=False),
        sa.Column("email", sa.String(254), nullable=False),
        sa.Column("senha_hash", sa.String(255), nullable=False),
        sa.Column("perfil", sa.String(20), nullable=False),
        sa.Column("registro", sa.String(40)),
        sa.Column("especialidade", sa.String(120)),
        sa.Column("endereco", sa.String(255)),
        sa.Column("valor_sessao_centavos", sa.Integer()),
        sa.Column("criado_em", sa.DateTime(), nullable=False),
        sa.Column("aceite_termos_versao", sa.String(20)),
        sa.Column("aceite_termos_em", sa.DateTime()),
        sa.Column("anonimizado_em", sa.DateTime()),
        sa.CheckConstraint("perfil IN ('paciente','profissional')", name="ck_perfil"),
    )
    op.create_index("ix_usuarios_email", "usuarios", ["email"], unique=True)

    op.create_table(
        "sessoes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("paciente_id", sa.Integer(), sa.ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False),
        sa.Column("profissional_id", sa.Integer(), sa.ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False),
        sa.Column("data_hora", sa.DateTime(), nullable=False),
        sa.Column("modalidade", sa.String(20), nullable=False),
        sa.Column("status", sa.String(20), nullable=False),
        sa.Column("anotacoes", sa.Text()),
        sa.Column("chave_idempotencia", sa.String(64)),
        sa.Column("valor_centavos", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("criado_em", sa.DateTime(), nullable=False),
        sa.CheckConstraint("status IN ('agendada','concluida','cancelada')", name="ck_status"),
    )
    op.create_index("idx_sessoes_prof", "sessoes", ["profissional_id", "data_hora"])
    op.create_index("idx_sessoes_pac", "sessoes", ["paciente_id", "data_hora"])
    # Anti-corrida: duas sessões ATIVAS no mesmo horário são impossíveis, mesmo com requisições simultâneas.
    op.create_index("uq_sessao_prof_horario", "sessoes", ["profissional_id", "data_hora"], unique=True, postgresql_where=_ATIVA, sqlite_where=_ATIVA)
    op.create_index("uq_sessao_pac_horario", "sessoes", ["paciente_id", "data_hora"], unique=True, postgresql_where=_ATIVA, sqlite_where=_ATIVA)
    # Idempotência: reenviar o MESMO agendamento (fila offline do app) não cria uma 2ª sessão.
    op.create_index("uq_sessao_idempotencia", "sessoes", ["paciente_id", "chave_idempotencia"], unique=True, postgresql_where=_COM_CHAVE, sqlite_where=_COM_CHAVE)

    op.create_table(
        "humor_registros",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("usuario_id", sa.Integer(), sa.ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False),
        sa.Column("nivel", sa.Integer(), nullable=False),
        sa.Column("nota", sa.Text(), nullable=False),
        sa.Column("data_hora", sa.DateTime(), nullable=False),
        sa.CheckConstraint("nivel BETWEEN 1 AND 5", name="ck_nivel"),
    )
    op.create_index("idx_humor_usuario", "humor_registros", ["usuario_id", "data_hora"])

    op.create_table(
        "avaliacoes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("sessao_id", sa.Integer(), sa.ForeignKey("sessoes.id", ondelete="CASCADE"), nullable=False),
        sa.Column("paciente_id", sa.Integer(), sa.ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False),
        sa.Column("profissional_id", sa.Integer(), sa.ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False),
        sa.Column("nota", sa.Integer(), nullable=False),
        sa.Column("comentario", sa.Text(), nullable=False),
        sa.Column("criado_em", sa.DateTime(), nullable=False),
        sa.CheckConstraint("nota BETWEEN 1 AND 5", name="ck_nota"),
        sa.UniqueConstraint("sessao_id", name="uq_avaliacao_sessao"),
    )
    op.create_index("idx_avaliacoes_prof", "avaliacoes", ["profissional_id"])


def downgrade() -> None:
    op.drop_table("avaliacoes")
    op.drop_table("humor_registros")
    op.drop_table("sessoes")  # leva os índices junto
    op.drop_table("usuarios")
