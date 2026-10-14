from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

Perfil = Literal["paciente", "profissional"]
Modalidade = Literal["Online", "Presencial"]
StatusSessao = Literal["agendada", "concluida", "cancelada"]


class _Base(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class CadastroIn(_Base):
    nome: str = Field(min_length=2, max_length=120)
    email: EmailStr
    senha: str = Field(min_length=1, max_length=128)
    perfil: Perfil
    registro: str | None = Field(default=None, max_length=40)
    especialidade: str | None = Field(default=None, max_length=120)


class EntrarIn(_Base):
    email: EmailStr
    senha: str = Field(min_length=1, max_length=128)


class PerfilIn(_Base):
    nome: str = Field(min_length=2, max_length=120)
    registro: str | None = Field(default=None, max_length=40)
    especialidade: str | None = Field(default=None, max_length=120)
    endereco: str | None = Field(default=None, max_length=255)
    valor_sessao_centavos: int | None = Field(default=None, ge=0, le=1_000_000)  # até R$ 10.000,00


class SenhaIn(_Base):
    senha_atual: str = Field(min_length=1, max_length=128)
    nova_senha: str = Field(min_length=1, max_length=128)


class UsuarioOut(BaseModel):
    id: int
    nome: str
    email: str
    perfil: str
    registro: str | None = None
    especialidade: str | None = None
    endereco: str | None = None
    valor_sessao_centavos: int | None = None
    criado_em: str


class AuthOut(BaseModel):
    token: str
    usuario: UsuarioOut


def _naive(v: datetime | None) -> datetime | None:
    """O app trabalha com horário local sem fuso; descarta o fuso se vier um."""
    return v.replace(tzinfo=None) if v is not None and v.tzinfo else v


class SessaoIn(_Base):
    profissional_id: int
    data_hora: datetime
    modalidade: Modalidade

    _n = field_validator("data_hora")(_naive)


class SessaoPatch(_Base):
    status: StatusSessao | None = None
    anotacoes: str | None = Field(default=None, max_length=5000)
    data_hora: datetime | None = None

    _n = field_validator("data_hora")(_naive)


class HumorIn(_Base):
    nivel: int = Field(ge=1, le=5)
    nota: str = Field(default="", max_length=500)
    data_hora: datetime | None = None

    _n = field_validator("data_hora")(_naive)


class AvaliacaoIn(_Base):
    nota: int = Field(ge=1, le=5)
    comentario: str = Field(default="", max_length=300)

    @field_validator("comentario")
    @classmethod
    def _limpa(cls, v: str) -> str:
        return v.strip()
