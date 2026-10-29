"""Cadastro, login e conta do usuário (LGPD: exportar, aceitar termos, anonimizar)."""

from typing import Any

from fastapi import APIRouter, BackgroundTasks, HTTPException, Request, Response
from sqlalchemy import delete, exists, select, update
from sqlalchemy.exc import IntegrityError

from app import schemas, tempo
from app.contexto import Contexto
from app.deps import COOKIE_SESSAO, Db, Eu, emitir_token
from app.models import Avaliacao, Humor, ProntuarioEntrada, Sessao, Usuario
from app.saidas import avaliacao_out, humor_out, sessao_out, usuario_out
from app.security import HASH_FALSO, hash_senha, verificar_senha


def criar_rotas(ctx: Contexto) -> APIRouter:
    router = APIRouter()
    cfg = ctx.cfg
    log = ctx.log
    conta = ctx.conta
    limite = ctx.limite
    limite_cadastro = ctx.limite_cadastro

    # ------------------------------------------------------------------- auth
    def emitir(user: Usuario, response: Response) -> dict[str, Any]:
        token = emitir_token(cfg, user, response)
        return {"token": token, "usuario": usuario_out(user, cfg.email_ativo)}

    @router.post("/auth/cadastro", status_code=201)
    def cadastro(body: schemas.CadastroIn, request: Request, response: Response, db: Db, background: BackgroundTasks) -> dict[str, Any]:
        limite_cadastro.checar(request.client.host if request.client else "?")
        if len(body.senha) < cfg.password_min:
            raise HTTPException(422, f"A senha deve ter pelo menos {cfg.password_min} caracteres.")
        if body.perfil == "profissional" and not (body.registro or "").strip():
            raise HTTPException(422, "Informe o registro profissional (CRP).")
        email = body.email.lower()
        if db.scalar(select(Usuario).where(Usuario.email == email)) is not None:
            raise HTTPException(409, "Este e-mail já está cadastrado.")
        user = Usuario(
            nome=body.nome,
            email=email,
            senha_hash=hash_senha(body.senha),
            perfil=body.perfil,
            registro=(body.registro or None) if body.perfil == "profissional" else None,
            especialidade=(body.especialidade or None) if body.perfil == "profissional" else None,
            aceite_termos_versao=body.aceite_termos_versao,
            aceite_termos_em=tempo.agora().replace(microsecond=0) if body.aceite_termos_versao else None,
        )
        db.add(user)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "Este e-mail já está cadastrado.") from None
        conta.enviar_verificacao(db, user, background)  # código de 6 dígitos por e-mail (se o SMTP estiver configurado)
        return emitir(user, response)

    @router.post("/auth/entrar")
    def entrar(body: schemas.EntrarIn, request: Request, response: Response, db: Db) -> dict[str, Any]:
        email = body.email.lower()
        chave = f"{request.client.host if request.client else '?'}|{email}"
        limite.checar(chave)
        user = db.scalar(select(Usuario).where(Usuario.email == email))
        # Sempre faz um scrypt, exista o e-mail ou não (evita revelar contas pelo tempo).
        ok = verificar_senha(body.senha, user.senha_hash if user else HASH_FALSO)
        if user is None or not ok:
            raise HTTPException(401, "E-mail ou senha incorretos.")
        limite.limpar(chave)
        return emitir(user, response)

    @router.post("/auth/sair", status_code=204)
    def sair() -> Response:
        """Encerra a sessão web: apaga o cookie (só o servidor consegue, porque ele é HttpOnly)."""
        resp = Response(status_code=204)
        resp.delete_cookie(COOKIE_SESSAO, path="/", httponly=True, secure=cfg.cookie_secure, samesite="strict")
        return resp

    @router.get("/auth/eu")
    def eu(user: Eu) -> dict[str, Any]:
        return usuario_out(user, cfg.email_ativo)

    @router.get("/auth/eu/exportar")
    def exportar_meus_dados(user: Eu, db: Db) -> dict[str, Any]:
        """Portabilidade (LGPD, art. 18): todos os dados da própria pessoa em um JSON."""
        souprof = user.perfil == "profissional"
        coluna = Sessao.profissional_id if souprof else Sessao.paciente_id
        sessoes = db.scalars(select(Sessao).where(coluna == user.id).order_by(Sessao.data_hora.asc()))
        dados: dict[str, Any] = {
            "exportado_em": tempo.agora().replace(microsecond=0).isoformat(),
            "usuario": usuario_out(user, cfg.email_ativo),
            # O profissional recebe as próprias anotações; o paciente nunca recebe as do profissional.
            "sessoes": [sessao_out(s, ver_anotacoes=souprof) for s in sessoes],
        }
        if souprof:
            recebidas = db.scalars(select(Avaliacao).where(Avaliacao.profissional_id == user.id).order_by(Avaliacao.criado_em.asc()))
            dados["avaliacoes_recebidas"] = [avaliacao_out(a, True) for a in recebidas]
        else:
            feitas = db.scalars(select(Avaliacao).where(Avaliacao.paciente_id == user.id).order_by(Avaliacao.criado_em.asc()))
            dados["avaliacoes_feitas"] = [avaliacao_out(a, True) for a in feitas]
            humor = db.scalars(select(Humor).where(Humor.usuario_id == user.id).order_by(Humor.data_hora.asc()))
            dados["humor"] = [humor_out(h) for h in humor]
        return dados

    @router.patch("/auth/eu")
    def atualizar_eu(body: schemas.PerfilIn, user: Eu, db: Db) -> dict[str, Any]:
        if user.perfil == "profissional" and body.registro is not None and not body.registro.strip():
            raise HTTPException(422, "O registro profissional (CRP) não pode ficar vazio.")
        user.nome = body.nome
        if user.perfil == "profissional":
            if body.registro is not None:  # omitido = mantém o atual
                user.registro = body.registro
            user.especialidade = body.especialidade or None
            user.endereco = body.endereco or None
            user.valor_sessao_centavos = body.valor_sessao_centavos
        db.commit()
        return usuario_out(user, cfg.email_ativo)

    @router.post("/auth/senha")
    def alterar_senha(body: schemas.SenhaIn, user: Eu, db: Db, response: Response) -> dict[str, Any]:
        """Troca a senha e REVOGA os outros aparelhos: devolve um token novo só para quem acabou de trocar."""
        chave = f"senha|{user.id}"
        limite.checar(chave)  # quem roubou um token não pode adivinhar a senha atual à vontade
        if not verificar_senha(body.senha_atual, user.senha_hash):
            raise HTTPException(400, "A senha atual está incorreta.")
        limite.limpar(chave)
        if len(body.nova_senha) < cfg.password_min:
            raise HTTPException(422, f"A senha deve ter pelo menos {cfg.password_min} caracteres.")
        user.senha_hash = hash_senha(body.nova_senha)
        user.token_versao += 1
        db.commit()
        return emitir(user, response)

    @router.delete("/auth/eu", status_code=204)
    def excluir_conta(user: Eu, db: Db) -> Response:
        if db.scalar(select(exists().where((ProntuarioEntrada.profissional_id == user.id) | (ProntuarioEntrada.paciente_id == user.id)))):
            raise HTTPException(
                409,
                "Esta conta tem prontuário sob guarda legal e não pode ser apagada. Pacientes devem usar a anonimização; "
                "profissionais devem exportar os dados e falar com o suporte.",
            )
        db.delete(user)  # cascata no banco (FK ON DELETE CASCADE) via ORM abaixo
        db.commit()
        return Response(status_code=204)

    @router.post("/auth/eu/aceite", status_code=200)
    def registrar_aceite(body: schemas.AceiteIn, user: Eu, db: Db) -> dict[str, Any]:
        """LGPD: registra qual versão dos Termos/Política a pessoa aceitou e quando (prova do consentimento)."""
        user.aceite_termos_versao = body.versao
        user.aceite_termos_em = tempo.agora().replace(microsecond=0)
        db.commit()
        return usuario_out(user, cfg.email_ativo)

    @router.post("/auth/eu/anonimizar", status_code=204)
    def anonimizar_conta(body: schemas.AnonimizarIn, user: Eu, db: Db) -> Response:
        """LGPD, art. 18 (eliminação): exclusão lógica + anonimização da conta de PACIENTE.

        Apaga os registros de humor e os comentários de avaliação, troca nome/e-mail por valores anônimos
        e bloqueia o acesso. As sessões ficam, sem identificar a pessoa, porque o profissional precisa
        guardar o prontuário e os registros financeiros por obrigação legal (art. 16, I)."""
        if user.perfil != "paciente":
            raise HTTPException(403, "Profissionais devem usar a exclusão de conta (os pacientes dependem do histórico).")
        if not verificar_senha(body.senha, user.senha_hash):
            raise HTTPException(401, "Senha incorreta.")
        db.execute(delete(Humor).where(Humor.usuario_id == user.id))
        db.execute(update(Avaliacao).where(Avaliacao.paciente_id == user.id).values(comentario=""))
        # Sessões futuras são canceladas: o profissional não deve esperar alguém que já não existe.
        db.execute(update(Sessao).where(Sessao.paciente_id == user.id, Sessao.status == "agendada", Sessao.data_hora > tempo.agora()).values(status="cancelada"))
        user.nome = "Paciente anonimizado"
        user.email = f"anonimizado-{user.id}@anonimizado.invalid"
        user.senha_hash = HASH_FALSO  # ninguém conhece a senha deste hash
        user.aceite_termos_em = None
        user.anonimizado_em = tempo.agora().replace(microsecond=0)
        db.commit()
        log.info("conta_anonimizada", extra={"campos": {"usuario_id": user.id}})
        resp = Response(status_code=204)
        resp.delete_cookie(COOKIE_SESSAO, path="/", httponly=True, secure=cfg.cookie_secure, samesite="strict")
        return resp

    return router
