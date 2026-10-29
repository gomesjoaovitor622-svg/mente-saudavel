from __future__ import annotations

from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app import tempo
from app.db import Base


def _now() -> datetime:
    return tempo.agora().replace(microsecond=0)


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
    valor_sessao_centavos: Mapped[int | None] = mapped_column(Integer, nullable=True)  # preço do profissional (R$ em centavos)
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=_now)
    # LGPD: qual versão dos Termos/Política a pessoa aceitou e quando; e quando os dados foram anonimizados.
    aceite_termos_versao: Mapped[str | None] = mapped_column(String(20), nullable=True)
    aceite_termos_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    anonimizado_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # Sobe quando a senha muda: os tokens emitidos antes deixam de valer (roubo de token, aparelho perdido).
    token_versao: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    # Profissional só aparece na busca e recebe agendamentos depois de APROVADO por um administrador
    # (conferência do CRP): `python -m app.admin aprovar EMAIL`. Pacientes não usam este campo.
    verificado_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    # Quando a pessoa provou ser dona do e-mail (código enviado por e-mail).
    email_verificado_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


# Índice único PARCIAL: só vale para sessões não canceladas (cancelar libera o horário).
_ATIVA = text("status <> 'cancelada'")
_COM_CHAVE = text("chave_idempotencia IS NOT NULL")


class Sessao(Base):
    __tablename__ = "sessoes"
    __table_args__ = (
        CheckConstraint("status IN ('agendada','concluida','cancelada')", name="ck_status"),
        Index("idx_sessoes_prof", "profissional_id", "data_hora"),
        Index("idx_sessoes_pac", "paciente_id", "data_hora"),
        # Anti-corrida: o banco recusa 2 sessões ativas no mesmo horário (o "SELECT antes de gravar" sozinho não basta).
        Index("uq_sessao_prof_horario", "profissional_id", "data_hora", unique=True, postgresql_where=_ATIVA, sqlite_where=_ATIVA),
        Index("uq_sessao_pac_horario", "paciente_id", "data_hora", unique=True, postgresql_where=_ATIVA, sqlite_where=_ATIVA),
        # Idempotência: reenviar o MESMO agendamento (app offline que tenta de novo) não cria uma 2ª sessão.
        Index("uq_sessao_idempotencia", "paciente_id", "chave_idempotencia", unique=True, postgresql_where=_COM_CHAVE, sqlite_where=_COM_CHAVE),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    paciente_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"))
    profissional_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"))
    data_hora: Mapped[datetime] = mapped_column(DateTime)
    modalidade: Mapped[str] = mapped_column(String(20))
    status: Mapped[str] = mapped_column(String(20), default="agendada")
    anotacoes: Mapped[str | None] = mapped_column(Text, nullable=True)
    chave_idempotencia: Mapped[str | None] = mapped_column(String(64), nullable=True)
    valor_centavos: Mapped[int] = mapped_column(Integer, default=0, server_default="0")  # preço combinado na hora do agendamento
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


_TIPOS_PRONTUARIO = "tipo IN ('evolucao','anamnese','plano','observacao')"


class ProntuarioEntrada(Base):
    """Registro clínico do psicólogo sobre um paciente. O texto fica CIFRADO; nunca é apagado (guarda legal)."""

    __tablename__ = "prontuario_entradas"
    __table_args__ = (
        CheckConstraint(_TIPOS_PRONTUARIO, name="ck_prontuario_tipo"),
        Index("idx_prontuario_prof_pac", "profissional_id", "paciente_id", "criado_em"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    # RESTRICT: não dá para apagar a conta (e levar o prontuário junto) enquanto houver registros sob guarda.
    profissional_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="RESTRICT"), nullable=False)
    paciente_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="RESTRICT"), nullable=False)
    sessao_id: Mapped[int | None] = mapped_column(ForeignKey("sessoes.id", ondelete="SET NULL"), nullable=True)
    tipo: Mapped[str] = mapped_column(String(20), nullable=False)
    conteudo_cifrado: Mapped[str] = mapped_column(Text, nullable=False)
    versao: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    criado_em: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    atualizado_em: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class ProntuarioRevisao(Base):
    """Versão ANTERIOR de uma entrada, guardada a cada edição (trilha de alterações)."""

    __tablename__ = "prontuario_revisoes"
    __table_args__ = (UniqueConstraint("entrada_id", "versao", name="uq_prontuario_revisao"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    entrada_id: Mapped[int] = mapped_column(ForeignKey("prontuario_entradas.id", ondelete="CASCADE"), nullable=False)
    versao: Mapped[int] = mapped_column(Integer, nullable=False)
    conteudo_cifrado: Mapped[str] = mapped_column(Text, nullable=False)
    substituida_em: Mapped[datetime] = mapped_column(DateTime, nullable=False)


class ProntuarioAcesso(Base):
    """Quem leu ou alterou prontuário, e quando (LGPD: rastreabilidade de acesso a dado sensível). Só insere."""

    __tablename__ = "prontuario_acessos"
    __table_args__ = (Index("idx_prontuario_acessos", "paciente_id", "em"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    profissional_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="RESTRICT"), nullable=False)
    paciente_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="RESTRICT"), nullable=False)
    entrada_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    acao: Mapped[str] = mapped_column(String(20), nullable=False)
    em: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    request_id: Mapped[str | None] = mapped_column(String(32), nullable=True)


class CodigoEmail(Base):
    """Código de 6 dígitos enviado por e-mail (confirmar e-mail ou redefinir senha). Só o HMAC do código é guardado."""

    __tablename__ = "codigos_email"
    __table_args__ = (
        CheckConstraint("finalidade IN ('verificar_email','redefinir_senha')", name="ck_codigo_finalidade"),
        Index("idx_codigos_usuario", "usuario_id", "finalidade"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    usuario_id: Mapped[int] = mapped_column(ForeignKey("usuarios.id", ondelete="CASCADE"))
    finalidade: Mapped[str] = mapped_column(String(20))
    codigo_hash: Mapped[str] = mapped_column(String(64))
    expira_em: Mapped[datetime] = mapped_column(DateTime)
    tentativas: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0", default=0)
    usado_em: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    criado_em: Mapped[datetime] = mapped_column(DateTime, default=_now)
