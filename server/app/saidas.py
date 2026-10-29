"""Formato das respostas da API (o que sai para o app)."""

from typing import Any

from app.models import Avaliacao, Humor, Sessao, Usuario


def usuario_out(u: Usuario, email_ativo: bool = False) -> dict[str, Any]:
    email_ok = u.email_verificado_em is not None
    return {
        "id": u.id,
        "nome": u.nome,
        "email": u.email,
        "perfil": u.perfil,
        "registro": u.registro,
        "especialidade": u.especialidade,
        "endereco": u.endereco,
        "valor_sessao_centavos": u.valor_sessao_centavos,
        "criado_em": u.criado_em.isoformat(),
        "aceite_termos_versao": u.aceite_termos_versao,
        "email_verificado": email_ok,
        # O app mostra o aviso "confirme seu e-mail" só quando o servidor consegue mesmo enviar o código.
        "precisa_verificar_email": email_ativo and not email_ok,
        # Profissional ainda não aprovado: não aparece na busca nem recebe agendamentos (paciente: sempre True).
        "verificado": u.perfil != "profissional" or u.verificado_em is not None,
    }


def sessao_out(s: Sessao, *, ver_anotacoes: bool) -> dict[str, Any]:
    return {
        "id": s.id,
        "paciente_id": s.paciente_id,
        "profissional_id": s.profissional_id,
        "data_hora": s.data_hora.isoformat(),
        "modalidade": s.modalidade,
        "status": s.status,
        # Anotações clínicas são PRIVADAS do profissional: nunca vão para o paciente.
        "anotacoes": s.anotacoes if ver_anotacoes else None,
        "paciente_nome": s.paciente.nome,
        "profissional_nome": s.profissional.nome,
        "profissional_registro": s.profissional.registro,
        "profissional_especialidade": s.profissional.especialidade,
        "profissional_endereco": s.profissional.endereco,
        "valor_centavos": s.valor_centavos,
    }


def nome_curto(nome: str) -> str:
    """ "Maria da Silva Souza" -> "Maria S.": quem não participou da sessão não precisa do nome completo."""
    partes = nome.split()
    return nome if len(partes) < 2 else f"{partes[0]} {partes[-1][0]}."


def avaliacao_out(a: Avaliacao, ver_nome_completo: bool = False) -> dict[str, Any]:
    return {
        "id": a.id,
        "sessao_id": a.sessao_id,
        "paciente_id": a.paciente_id,
        "profissional_id": a.profissional_id,
        "nota": a.nota,
        "comentario": a.comentario,
        "criado_em": a.criado_em.isoformat(),
        "paciente_nome": a.paciente.nome if ver_nome_completo else nome_curto(a.paciente.nome),
    }


def humor_out(h: Humor) -> dict[str, Any]:
    return {
        "id": h.id,
        "usuario_id": h.usuario_id,
        "nivel": h.nivel,
        "nota": h.nota,
        "data_hora": h.data_hora.isoformat(),
    }
