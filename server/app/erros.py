"""Erros de negócio levantados pelos serviços (sem HTTP). Um handler os traduz para o mesmo JSON de sempre."""


class ErroDeNegocio(Exception):
    """Regra violada. `status` é o código HTTP equivalente; `mensagem` já vem pronta para o usuário."""

    def __init__(self, status: int, mensagem: str) -> None:
        super().__init__(mensagem)
        self.status = status
        self.mensagem = mensagem


def exigir_perfil(user: object, perfil: str) -> None:
    """Só o perfil indicado ("paciente" ou "profissional") pode seguir."""
    if getattr(user, "perfil", None) != perfil:
        raise ErroDeNegocio(403, "Ação não permitida para o seu perfil.")
