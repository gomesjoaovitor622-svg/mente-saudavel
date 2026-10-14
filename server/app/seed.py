"""Dados de demonstração (só com DEMO_SEED=true). Nunca use em produção real."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Avaliacao, Humor, Sessao, Usuario
from app.security import hash_senha


def popular_demo(db: Session) -> None:
    if (db.scalar(select(func.count()).select_from(Usuario)) or 0) > 0:
        return  # só semeia banco vazio

    def user(nome: str, email: str, senha: str, perfil: str, **extra: Any) -> Usuario:
        u = Usuario(nome=nome, email=email, senha_hash=hash_senha(senha), perfil=perfil, **extra)
        db.add(u)
        db.flush()
        return u

    helena = user(
        "Dra. Helena Marques",
        "helena@mentesaudavel.app",
        "mente123",
        "profissional",
        registro="06/12345",
        especialidade="Psicologia clínica",
        valor_sessao_centavos=15000,
        endereco="Av. Paulista, 1000, Bela Vista, São Paulo - SP",
    )
    user("Dr. Rafael Andrade", "rafael@mentesaudavel.app", "mente123", "profissional", registro="06/54321", especialidade="Terapia cognitivo-comportamental")
    user("Dra. Beatriz Souza", "beatriz@mentesaudavel.app", "mente123", "profissional", registro="06/11223", especialidade="Psicologia infantil")
    carlos = user("Carlos Silva", "carlos@email.com", "123456", "paciente")

    agora = datetime.now().replace(minute=0, second=0, microsecond=0)
    dia = agora.replace(hour=10) - timedelta(days=9)

    def sessao(quando: datetime, modalidade: str, status: str, notas: str | None = None) -> Sessao:
        s = Sessao(paciente_id=carlos.id, profissional_id=helena.id, data_hora=quando, modalidade=modalidade, status=status, anotacoes=notas, valor_centavos=15000)
        db.add(s)
        db.flush()
        return s

    primeira = sessao(dia, "Online", "concluida", "Primeira sessão: queixa principal de ansiedade no trabalho.")
    sessao(agora.replace(hour=10) - timedelta(days=2), "Online", "concluida", "Trabalhadas técnicas de respiração e rotina de sono.")
    sessao(agora.replace(hour=14) + timedelta(days=1), "Online", "agendada")
    sessao(agora.replace(hour=15) + timedelta(days=3), "Presencial", "agendada")
    db.add(Avaliacao(sessao_id=primeira.id, paciente_id=carlos.id, profissional_id=helena.id, nota=5, comentario="Atendimento acolhedor e muito claro."))
    for i, nivel in enumerate([2, 3, 3, 4, 3, 4, 5]):
        db.add(Humor(usuario_id=carlos.id, nivel=nivel, nota="", data_hora=agora - timedelta(days=6 - i)))
    db.commit()
