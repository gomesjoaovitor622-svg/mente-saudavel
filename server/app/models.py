from __future__ import annotations

from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def _now() -> datetime:
    return datetime.now().replace(microsecond=0)


class Usuario(Base):
    __tablename__ = "usuarios"
    __table_args__ = (CheckConstraint("perfil IN ('paciente','profissional')", name="ck_perfil"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    nome: Mapped[str] = mapped_column(String(120))
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    senha_hash: Mapped[str] = mapped_column(String(255))
    perfil: Mapped[str] = mapped_column(String(20))
    registro: Mapped[str | None] = mapped_column(String(40), nullable=True)
    especialidade: Mapped[str | None] = mapped_column(String(120), nullable=True)
    endereco: Mapped[str | None] = mapped_column(String(255), nullable=True)
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=_now)


class Sessao(Base):
    __tablename__ = "sessoes"
    __table_args__ = (
        CheckConstraint("status IN ('agendada','concluida','cancelada')", name="ck_status"),
        Index("idx_sessoes_prof", "profissional_id", "data_hora"),
        Index("idx_sessoes_pac", "paciente_id", "data_hora"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    paciente_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"))
    profissional_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"))
    data_hora: Mapped[datetime] = mapped_column(DateTime)
    modalidade: Mapped[str] = mapped_column(String(20))
    status: Mapped[str] = mapped_column(String(20), default="agendada")
    anotacoes: Mapped[str | None] = mapped_column(Text, nullable=True)
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=_now)

    paciente: Mapped[Usuario] = relationship(foreign_keys=[paciente_id])
    profissional: Mapped[Usuario] = relationship(foreign_keys=[profissional_id])


class Humor(Base):
    __tablename__ = "humor_registros"
    __table_args__ = (
        CheckConstraint("nivel BETWEEN 1 AND 5", name="ck_nivel"),
        Index("idx_humor_usuario", "usuario_id", "data_hora"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"))
    nivel: Mapped[int] = mapped_column(Integer)
    nota: Mapped[str] = mapped_column(Text, default="")
    data_hora: Mapped[datetime] = mapped_column(DateTime)


class Avaliacao(Base):
    __tablename__ = "avaliacoes"
    __table_args__ = (
        CheckConstraint("nota BETWEEN 1 AND 5", name="ck_nota"),
        UniqueConstraint("sessao_id", name="uq_avaliacao_sessao"),
        Index("idx_avaliacoes_prof", "profissional_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    sessao_id: Mapped[int] = mapped_column(ForeignKey("sessoes.id", ondelete="CASCADE"))
    paciente_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"))
    profissional_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"))
    nota: Mapped[int] = mapped_column(Integer)
    comentario: Mapped[str] = mapped_column(Text, default="")
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=_now)

    paciente: Mapped[Usuario] = relationship(foreign_keys=[paciente_id])
