"""API REST do Mente Saudável. Toda regra de acesso fica aqui, no servidor."""

import hmac
import logging
import re
import time
import uuid
from collections import defaultdict, deque
from collections.abc import Callable, Iterator
from datetime import datetime, timedelta
from typing import Annotated, Any

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from sqlalchemy import Engine, case, delete, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from app import schemas
from app.config import Settings, load_settings
from app.db import Base, garantir_colunas, garantir_indices, make_engine, make_session_factory, session_iter
from app.models import Avaliacao, Humor, Sessao, Usuario
from app.observabilidade import REQUEST_ID_RE, Metricas, configurar_logs, limpar_texto_cliente
from app.security import HASH_FALSO, criar_token, hash_senha, ler_token, verificar_senha


def _usuario_out(u: Usuario) -> dict[str, Any]:
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
    }


def _sessao_out(s: Sessao, *, ver_anotacoes: bool) -> dict[str, Any]:
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


def _avaliacao_out(a: Avaliacao) -> dict[str, Any]:
    return {
        "id": a.id,
        "sessao_id": a.sessao_id,
        "paciente_id": a.paciente_id,
        "profissional_id": a.profissional_id,
        "nota": a.nota,
        "comentario": a.comentario,
        "criado_em": a.criado_em.isoformat(),
        "paciente_nome": a.paciente.nome,
    }


def _humor_out(h: Humor) -> dict[str, Any]:
    return {
        "id": h.id,
        "usuario_id": h.usuario_id,
        "nivel": h.nivel,
        "nota": h.nota,
        "data_hora": h.data_hora.isoformat(),
    }


class _LimiteLogin:
    """Limita tentativas de login (janela de 60 s) por chave. Em memória: 1 processo."""

    def __init__(self, maximo: int) -> None:
        self.maximo = maximo
        self._tentativas: dict[str, deque[float]] = defaultdict(deque)

    def checar(self, chave: str) -> None:
        agora = time.monotonic()
        fila = self._tentativas[chave]
        while fila and agora - fila[0] > 60:
            fila.popleft()
        if len(fila) >= self.maximo:
            raise HTTPException(429, "Muitas tentativas. Aguarde um minuto e tente novamente.")
        fila.append(agora)

    def limpar(self, chave: str) -> None:
        self._tentativas.pop(chave, None)


COOKIE_SESSAO = "ms_sessao"
_CHAVE_IDEMPOTENCIA = re.compile(r"[A-Za-z0-9_-]{8,64}")


def create_app(settings: Settings | None = None, engine: Engine | None = None) -> FastAPI:
    cfg = settings or load_settings()
    eng = engine or make_engine(cfg.database_url)
    Base.metadata.create_all(eng)
    garantir_colunas(eng)
    indices_faltando = garantir_indices(eng)
    if indices_faltando:
        logging.getLogger("mente_saudavel").warning(
            "Há sessões ativas duplicadas: não foi possível criar os índices %s. Cancele as duplicadas e reinicie.", indices_faltando
        )
    factory: sessionmaker[Session] = make_session_factory(eng)
    limite = _LimiteLogin(cfg.login_max_attempts)
    limite_cadastro = _LimiteLogin(cfg.signup_max_attempts)  # por IP: evita criação em massa de contas

    app = FastAPI(
        title="Mente Saudável API", version="1.0.0", docs_url="/docs" if cfg.is_dev else None, redoc_url=None, openapi_url="/openapi.json" if cfg.is_dev else None
    )
    app.state.settings = cfg
    app.state.session_factory = factory

    if cfg.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=list(cfg.cors_origins),
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=["Authorization", "Content-Type", "X-Requested-With", "Idempotency-Key", "X-Request-ID"],
            max_age=600,
        )

    log = configurar_logs(cfg.log_level)
    metricas = Metricas()

    @app.middleware("http")
    async def _observar(request: Request, call_next: Callable[..., Any]) -> Response:
        """Cabeçalhos de segurança + id da requisição + 1 linha de log JSON + métricas (sem dados pessoais)."""
        rid = request.headers.get("X-Request-ID", "")
        if not REQUEST_ID_RE.fullmatch(rid):
            rid = uuid.uuid4().hex
        request.state.request_id = rid
        inicio = time.perf_counter()
        try:
            resp: Response = await call_next(request)
        except Exception:  # erro não tratado: registra com a pilha e devolve 500 sem detalhes internos
            log.error("erro_nao_tratado", extra={"campos": {"request_id": rid, "metodo": request.method}}, exc_info=True)
            resp = JSONResponse({"detail": f"Erro interno. Informe o código {rid} ao suporte."}, status_code=500)
        segundos = time.perf_counter() - inicio
        rota = getattr(request.scope.get("route"), "path", None) or "(sem rota)"
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["Cache-Control"] = "no-store"
        resp.headers["Referrer-Policy"] = "no-referrer"
        resp.headers["X-Request-ID"] = rid
        resp.headers["Server-Timing"] = f"app;dur={segundos * 1000:.1f}"
        metricas.observar(request.method, rota, resp.status_code, segundos)
        if rota != "/health":  # o healthcheck do Docker enche o log à toa
            nivel = logging.ERROR if resp.status_code >= 500 else logging.INFO
            log.log(
                nivel,
                "requisicao",
                extra={"campos": {"request_id": rid, "metodo": request.method, "rota": rota, "status": resp.status_code, "duracao_ms": round(segundos * 1000, 1)}},
            )
        return resp

    def get_db() -> Iterator[Session]:
        yield from session_iter(factory)

    Db = Annotated[Session, Depends(get_db)]

    def usuario_atual(request: Request, db: Db) -> Usuario:
        auth = request.headers.get("Authorization", "")
        if auth.startswith("Bearer "):  # celular: token no cabeçalho (guardado no Keystore/Keychain)
            token = auth[7:]
        else:  # web: cookie HttpOnly, que o JavaScript da página não consegue ler (protege contra XSS)
            token = request.cookies.get(COOKIE_SESSAO, "")
            if not token:
                raise HTTPException(401, "Não autenticado.")
            # Defesa extra contra CSRF (além de SameSite=Strict): ações que alteram dados exigem este
            # cabeçalho, que um formulário de outro site não consegue enviar.
            if request.method not in {"GET", "HEAD", "OPTIONS"} and request.headers.get("X-Requested-With") != "mente-saudavel":
                raise HTTPException(403, "Requisição não permitida.")
        if not token:
            raise HTTPException(401, "Não autenticado.")
        uid = ler_token(token, cfg.jwt_secret)
        user = db.get(Usuario, uid) if uid is not None else None
        if user is None or user.anonimizado_em is not None:
            raise HTTPException(401, "Sessão expirada. Entre novamente.")
        return user

    Eu = Annotated[Usuario, Depends(usuario_atual)]

    def exigir_perfil(user: Usuario, perfil: str) -> None:
        if user.perfil != perfil:
            raise HTTPException(403, "Ação não permitida para o seu perfil.")

    def carregar_sessao(db: Session, sessao_id: int, user: Usuario) -> Sessao:
        s = db.get(Sessao, sessao_id)
        # 404 (e não 403) para não revelar a existência de sessões de outras pessoas.
        if s is None or user.id not in (s.paciente_id, s.profissional_id):
            raise HTTPException(404, "Sessão não encontrada.")
        return s

    def mensagem_conflito(db: Session, prof_id: int, pac_id: int, quando: datetime, ignorar: int) -> str | None:
        def existe(coluna: Any, valor: int) -> bool:
            q = select(func.count()).select_from(Sessao).where(coluna == valor, Sessao.data_hora == quando, Sessao.status != "cancelada", Sessao.id != ignorar)
            return (db.scalar(q) or 0) > 0

        if existe(Sessao.profissional_id, prof_id):
            return "O profissional já tem uma sessão neste horário."
        if existe(Sessao.paciente_id, pac_id):
            return "Você já tem uma sessão neste horário."
        return None

    def gravar_sessao(db: Session, prof_id: int, pac_id: int, quando: datetime, ignorar: int, chave: str | None = None) -> Sessao | None:
        """Confirma a gravação. Se o banco recusar por horário duplicado (corrida entre 2 requisições), responde 409.

        Se a recusa foi da CHAVE DE IDEMPOTÊNCIA (o mesmo agendamento chegou duas vezes ao mesmo tempo),
        devolve a sessão que já existe em vez de erro."""
        try:
            db.commit()
        except IntegrityError as e:
            db.rollback()
            texto = str(e.orig).lower()
            if "unique" not in texto and "duplicate" not in texto:
                raise
            if chave:
                existente = db.scalar(select(Sessao).where(Sessao.paciente_id == pac_id, Sessao.chave_idempotencia == chave))
                if existente is not None:
                    return existente
            raise HTTPException(409, mensagem_conflito(db, prof_id, pac_id, quando, ignorar) or "Este horário acabou de ser ocupado. Escolha outro.") from None
        return None

    # ------------------------------------------------------------------ saúde
    @app.get("/health")
    def health(db: Db) -> dict[str, str]:
        db.execute(select(1))
        return {"status": "ok"}

    # ------------------------------------------------------------------- auth
    def emitir(user: Usuario, response: Response) -> dict[str, Any]:
        token = criar_token(user.id, cfg.jwt_secret, cfg.jwt_ttl_hours)
        response.set_cookie(COOKIE_SESSAO, token, max_age=cfg.jwt_ttl_hours * 3600, httponly=True, secure=cfg.cookie_secure, samesite="strict", path="/")
        return {"token": token, "usuario": _usuario_out(user)}

    @app.post("/auth/cadastro", status_code=201)
    def cadastro(body: schemas.CadastroIn, request: Request, response: Response, db: Db) -> dict[str, Any]:
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
            aceite_termos_em=datetime.now().replace(microsecond=0) if body.aceite_termos_versao else None,
        )
        db.add(user)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "Este e-mail já está cadastrado.") from None
        return emitir(user, response)

    @app.post("/auth/entrar")
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

    @app.post("/auth/sair", status_code=204)
    def sair() -> Response:
        """Encerra a sessão web: apaga o cookie (só o servidor consegue, porque ele é HttpOnly)."""
        resp = Response(status_code=204)
        resp.delete_cookie(COOKIE_SESSAO, path="/", httponly=True, secure=cfg.cookie_secure, samesite="strict")
        return resp

    @app.get("/auth/eu")
    def eu(user: Eu) -> dict[str, Any]:
        return _usuario_out(user)

    @app.get("/auth/eu/exportar")
    def exportar_meus_dados(user: Eu, db: Db) -> dict[str, Any]:
        """Portabilidade (LGPD, art. 18): todos os dados da própria pessoa em um JSON."""
        souprof = user.perfil == "profissional"
        coluna = Sessao.profissional_id if souprof else Sessao.paciente_id
        sessoes = db.scalars(select(Sessao).where(coluna == user.id).order_by(Sessao.data_hora.asc()))
        dados: dict[str, Any] = {
            "exportado_em": datetime.now().replace(microsecond=0).isoformat(),
            "usuario": _usuario_out(user),
            # O profissional recebe as próprias anotações; o paciente nunca recebe as do profissional.
            "sessoes": [_sessao_out(s, ver_anotacoes=souprof) for s in sessoes],
        }
        if souprof:
            recebidas = db.scalars(select(Avaliacao).where(Avaliacao.profissional_id == user.id).order_by(Avaliacao.criado_em.asc()))
            dados["avaliacoes_recebidas"] = [_avaliacao_out(a) for a in recebidas]
        else:
            feitas = db.scalars(select(Avaliacao).where(Avaliacao.paciente_id == user.id).order_by(Avaliacao.criado_em.asc()))
            dados["avaliacoes_feitas"] = [_avaliacao_out(a) for a in feitas]
            humor = db.scalars(select(Humor).where(Humor.usuario_id == user.id).order_by(Humor.data_hora.asc()))
            dados["humor"] = [_humor_out(h) for h in humor]
        return dados

    @app.patch("/auth/eu")
    def atualizar_eu(body: schemas.PerfilIn, user: Eu, db: Db) -> dict[str, Any]:
        user.nome = body.nome
        if user.perfil == "profissional":
            user.registro = body.registro or None
            user.especialidade = body.especialidade or None
            user.endereco = body.endereco or None
            user.valor_sessao_centavos = body.valor_sessao_centavos
        db.commit()
        return _usuario_out(user)

    @app.post("/auth/senha", status_code=204)
    def alterar_senha(body: schemas.SenhaIn, user: Eu, db: Db) -> Response:
        if not verificar_senha(body.senha_atual, user.senha_hash):
            raise HTTPException(400, "A senha atual está incorreta.")
        if len(body.nova_senha) < cfg.password_min:
            raise HTTPException(422, f"A senha deve ter pelo menos {cfg.password_min} caracteres.")
        user.senha_hash = hash_senha(body.nova_senha)
        db.commit()
        return Response(status_code=204)

    @app.delete("/auth/eu", status_code=204)
    def excluir_conta(user: Eu, db: Db) -> Response:
        db.delete(user)  # cascata no banco (FK ON DELETE CASCADE) via ORM abaixo
        db.commit()
        return Response(status_code=204)

    @app.post("/auth/eu/aceite", status_code=200)
    def registrar_aceite(body: schemas.AceiteIn, user: Eu, db: Db) -> dict[str, Any]:
        """LGPD: registra qual versão dos Termos/Política a pessoa aceitou e quando (prova do consentimento)."""
        user.aceite_termos_versao = body.versao
        user.aceite_termos_em = datetime.now().replace(microsecond=0)
        db.commit()
        return _usuario_out(user)

    @app.post("/auth/eu/anonimizar", status_code=204)
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
        db.execute(update(Sessao).where(Sessao.paciente_id == user.id, Sessao.status == "agendada", Sessao.data_hora > datetime.now()).values(status="cancelada"))
        user.nome = "Paciente anonimizado"
        user.email = f"anonimizado-{user.id}@anonimizado.invalid"
        user.senha_hash = HASH_FALSO  # ninguém conhece a senha deste hash
        user.aceite_termos_em = None
        user.anonimizado_em = datetime.now().replace(microsecond=0)
        db.commit()
        log.info("conta_anonimizada", extra={"campos": {"usuario_id": user.id}})
        resp = Response(status_code=204)
        resp.delete_cookie(COOKIE_SESSAO, path="/", httponly=True, secure=cfg.cookie_secure, samesite="strict")
        return resp

    # ----------------------------------------------------------- telemetria e métricas
    limite_telemetria = _LimiteLogin(cfg.telemetry_max_per_minute)

    @app.post("/telemetria", status_code=204)
    def receber_telemetria(body: schemas.TelemetriaIn, request: Request) -> Response:
        """Erros e tempos medidos pelo app, gravados como logs JSON. Aberto (o erro pode ocorrer antes do
        login), por isso tem limite por IP, tamanho máximo e remove e-mails dos textos."""
        limite_telemetria.checar(request.client.host if request.client else "?")
        for e in body.eventos:
            log.info(
                "evento_cliente",
                extra={
                    "campos": {
                        "request_id": request.state.request_id,
                        "origem": "app",
                        "tipo": limpar_texto_cliente(e.tipo, 20),
                        "nome": limpar_texto_cliente(e.nome, 80),
                        "duracao_ms": e.duracao_ms,
                        "status": e.status,
                        "mensagem": limpar_texto_cliente(e.mensagem, 300),
                        "pilha": limpar_texto_cliente(e.pilha, 4000),
                        "versao_app": limpar_texto_cliente(body.versao_app, 20),
                        "plataforma": limpar_texto_cliente(body.plataforma, 20),
                    }
                },
            )
        return Response(status_code=204)

    @app.get("/metricas", response_class=PlainTextResponse)
    def exportar_metricas(request: Request) -> Response:
        """Formato Prometheus. Desligado (404) sem METRICS_TOKEN; com ele exige `Authorization: Bearer`."""
        if not cfg.metrics_token:
            raise HTTPException(404, "Não encontrado.")
        enviado = request.headers.get("Authorization", "").removeprefix("Bearer ")
        if not hmac.compare_digest(enviado.encode(), cfg.metrics_token.encode()):
            raise HTTPException(401, "Não autenticado.")
        return PlainTextResponse(metricas.texto())

    # ----------------------------------------------------------- profissionais
    @app.get("/profissionais")
    def profissionais(user: Eu, db: Db, q: str = Query(default="", max_length=80)) -> list[dict[str, Any]]:
        termo = f"%{q.strip()}%"
        media = func.avg(Avaliacao.nota)
        stmt = (
            select(Usuario, media.label("media"), func.count(Avaliacao.id).label("total"))
            .outerjoin(Avaliacao, Avaliacao.profissional_id == Usuario.id)
            .where(Usuario.perfil == "profissional")
            .where(Usuario.nome.ilike(termo) | func.coalesce(Usuario.especialidade, "").ilike(termo))
            .group_by(Usuario.id)
            .order_by(media.is_(None), media.desc(), func.lower(Usuario.nome))
        )
        return [
            {
                "id": u.id,
                "nome": u.nome,
                "registro": u.registro,
                "especialidade": u.especialidade,
                "endereco": u.endereco,
                "valor_sessao_centavos": u.valor_sessao_centavos,
                "media": float(m) if m is not None else None,
                "total": int(t),
            }
            for u, m, t in db.execute(stmt).all()
        ]

    @app.get("/profissionais/{prof_id}/avaliacoes")
    def avaliacoes_do_profissional(prof_id: int, user: Eu, db: Db, limite: int = Query(default=30, ge=1, le=1000)) -> list[dict[str, Any]]:
        stmt = select(Avaliacao).where(Avaliacao.profissional_id == prof_id).order_by(Avaliacao.criado_em.desc()).limit(limite)
        return [_avaliacao_out(a) for a in db.scalars(stmt)]

    @app.get("/profissionais/{prof_id}/horas-ocupadas")
    def horas_ocupadas(prof_id: int, user: Eu, db: Db, dia: datetime) -> list[int]:
        inicio = dia.replace(hour=0, minute=0, second=0, microsecond=0)
        stmt = select(Sessao.data_hora).where(
            Sessao.profissional_id == prof_id,
            Sessao.status != "cancelada",
            Sessao.data_hora >= inicio,
            Sessao.data_hora < inicio + timedelta(days=1),
        )
        return sorted({d.hour for d in db.scalars(stmt)})

    # ----------------------------------------------------------------- sessões
    @app.get("/sessoes")
    def listar_sessoes(
        user: Eu,
        db: Db,
        status: schemas.StatusSessao | None = None,
        de: datetime | None = None,
        ate: datetime | None = None,
        nao_canceladas: bool = False,
        paciente_id: int | None = None,
    ) -> list[dict[str, Any]]:
        souprof = user.perfil == "profissional"
        stmt = select(Sessao).where((Sessao.profissional_id if souprof else Sessao.paciente_id) == user.id)
        if status:
            stmt = stmt.where(Sessao.status == status)
        if nao_canceladas:
            stmt = stmt.where(Sessao.status != "cancelada")
        if de:
            stmt = stmt.where(Sessao.data_hora >= de)
        if ate:
            stmt = stmt.where(Sessao.data_hora < ate)
        if paciente_id is not None and souprof:
            stmt = stmt.where(Sessao.paciente_id == paciente_id)
        stmt = stmt.order_by(Sessao.data_hora.asc() if (de or ate) else Sessao.data_hora.desc())
        return [_sessao_out(s, ver_anotacoes=souprof) for s in db.scalars(stmt)]

    @app.get("/sessoes/conflito")
    def conflito(user: Eu, db: Db, profissional_id: int, data_hora: datetime, ignorar_id: int = -1) -> dict[str, str | None]:
        pac_id = user.id if user.perfil == "paciente" else -1
        return {"mensagem": mensagem_conflito(db, profissional_id, pac_id, data_hora, ignorar_id)}

    @app.post("/sessoes", status_code=201)
    def criar_sessao(
        body: schemas.SessaoIn,
        user: Eu,
        db: Db,
        response: Response,
        chave: Annotated[str | None, Header(alias="Idempotency-Key")] = None,
    ) -> dict[str, Any]:
        exigir_perfil(user, "paciente")
        if chave is not None and not _CHAVE_IDEMPOTENCIA.fullmatch(chave):
            raise HTTPException(422, "Idempotency-Key inválida (8 a 64 letras, números, '-' ou '_').")
        if chave:
            # Reenvio do mesmo agendamento (ex.: o app estava offline e tentou de novo): devolve o que já existe.
            existente = db.scalar(select(Sessao).where(Sessao.paciente_id == user.id, Sessao.chave_idempotencia == chave))
            if existente is not None:
                response.status_code = 200
                return _sessao_out(existente, ver_anotacoes=False)
        prof = db.get(Usuario, body.profissional_id)
        if prof is None or prof.perfil != "profissional":
            raise HTTPException(404, "Profissional não encontrado.")
        if body.data_hora <= datetime.now():
            raise HTTPException(422, "Escolha um horário no futuro.")
        msg = mensagem_conflito(db, prof.id, user.id, body.data_hora, -1)
        if msg:
            raise HTTPException(409, msg)
        s = Sessao(
            paciente_id=user.id,
            profissional_id=prof.id,
            data_hora=body.data_hora,
            modalidade=body.modalidade,
            valor_centavos=prof.valor_sessao_centavos or 0,  # congela o preço da hora do agendamento
            chave_idempotencia=chave,
        )
        db.add(s)
        ja_existia = gravar_sessao(db, prof.id, user.id, body.data_hora, -1, chave)
        if ja_existia is not None:
            response.status_code = 200
            return _sessao_out(ja_existia, ver_anotacoes=False)
        return _sessao_out(s, ver_anotacoes=False)

    @app.patch("/sessoes/{sessao_id}")
    def alterar_sessao(sessao_id: int, body: schemas.SessaoPatch, user: Eu, db: Db) -> dict[str, Any]:
        s = carregar_sessao(db, sessao_id, user)
        souprof = user.perfil == "profissional"
        if body.anotacoes is not None:
            if not souprof:
                raise HTTPException(403, "Somente o profissional edita as anotações.")
            s.anotacoes = body.anotacoes
        if body.status is not None:
            permitido = {"concluida", "cancelada"} if souprof else {"cancelada"}
            if body.status not in permitido or s.status != "agendada":
                raise HTTPException(409, "Mudança de status não permitida.")
            s.status = body.status
        if body.data_hora is not None:
            if souprof:
                raise HTTPException(403, "Somente o paciente remarca a sessão.")
            if s.status == "cancelada" or body.data_hora <= datetime.now():
                raise HTTPException(422, "Escolha um horário no futuro para uma sessão ativa.")
            msg = mensagem_conflito(db, s.profissional_id, s.paciente_id, body.data_hora, s.id)
            if msg:
                raise HTTPException(409, msg)
            s.data_hora = body.data_hora
            s.status = "agendada"
        gravar_sessao(db, s.profissional_id, s.paciente_id, s.data_hora, s.id)
        return _sessao_out(s, ver_anotacoes=souprof)

    @app.delete("/sessoes/{sessao_id}", status_code=204)
    def excluir_sessao(sessao_id: int, user: Eu, db: Db) -> Response:
        s = carregar_sessao(db, sessao_id, user)
        if s.status == "agendada":
            raise HTTPException(409, "Cancele a sessão antes de excluí-la do histórico.")
        db.delete(s)
        db.commit()
        return Response(status_code=204)

    def faturamento_do_mes(db: Session, user: Usuario, ano: int, num: int) -> dict[str, Any]:
        inicio = datetime(ano, num, 1)
        fim = datetime(ano + (num == 12), 1 if num == 12 else num + 1, 1)

        def somar(status: str) -> tuple[int, int]:
            total, qtd = db.execute(
                select(func.coalesce(func.sum(Sessao.valor_centavos), 0), func.count(Sessao.id)).where(
                    Sessao.profissional_id == user.id,
                    Sessao.status == status,
                    Sessao.data_hora >= inicio,
                    Sessao.data_hora < fim,
                )
            ).one()
            return int(total), int(qtd)

        recebido, concluidas = somar("concluida")
        a_receber, agendadas = somar("agendada")
        return {
            "mes": f"{ano:04d}-{num:02d}",
            "recebido_centavos": recebido,
            "sessoes_concluidas": concluidas,
            "a_receber_centavos": a_receber,
            "sessoes_agendadas": agendadas,
        }

    @app.get("/profissional/financeiro")
    def financeiro(user: Eu, db: Db, mes: str | None = Query(default=None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$")) -> dict[str, Any]:
        """Faturamento do mês (YYYY-MM; padrão: mês atual): recebido (concluídas) e a receber (agendadas)."""
        exigir_perfil(user, "profissional")
        hoje = datetime.now()
        ano, num = (int(mes[:4]), int(mes[5:])) if mes else (hoje.year, hoje.month)
        return {**faturamento_do_mes(db, user, ano, num), "valor_sessao_centavos": user.valor_sessao_centavos}

    @app.get("/profissional/financeiro/historico")
    def historico_financeiro(user: Eu, db: Db, meses: int = Query(default=6, ge=1, le=24)) -> list[dict[str, Any]]:
        """Faturamento dos últimos `meses` meses (o mais recente primeiro), para a tela de histórico."""
        exigir_perfil(user, "profissional")
        hoje = datetime.now()
        ano, num = hoje.year, hoje.month
        saida: list[dict[str, Any]] = []
        for _ in range(meses):
            saida.append(faturamento_do_mes(db, user, ano, num))
            ano, num = (ano - 1, 12) if num == 1 else (ano, num - 1)
        return saida

    @app.get("/profissional/pacientes")
    def pacientes(user: Eu, db: Db) -> list[dict[str, Any]]:
        exigir_perfil(user, "profissional")
        agora = datetime.now()
        stmt = (
            select(
                Usuario.id,
                Usuario.nome,
                Usuario.email,
                func.count(Sessao.id),
                func.sum(case((Sessao.status == "concluida", 1), else_=0)),
                func.min(case(((Sessao.status == "agendada") & (Sessao.data_hora >= agora), Sessao.data_hora))),
            )
            .join(Sessao, Sessao.paciente_id == Usuario.id)
            .where(Sessao.profissional_id == user.id, Sessao.status != "cancelada")
            .group_by(Usuario.id)
            .order_by(func.lower(Usuario.nome))
        )
        return [
            {
                "id": i,
                "nome": n,
                "email": e,
                "total": int(t),
                "concluidas": int(c or 0),
                "proxima": p.isoformat() if p else None,
            }
            for i, n, e, t, c, p in db.execute(stmt).all()
        ]

    # --------------------------------------------------------------- avaliação
    @app.get("/sessoes/{sessao_id}/avaliacao")
    def ver_avaliacao(sessao_id: int, user: Eu, db: Db) -> dict[str, Any] | None:
        s = carregar_sessao(db, sessao_id, user)
        a = db.scalar(select(Avaliacao).where(Avaliacao.sessao_id == s.id))
        return _avaliacao_out(a) if a else None

    @app.put("/sessoes/{sessao_id}/avaliacao")
    def avaliar(sessao_id: int, body: schemas.AvaliacaoIn, user: Eu, db: Db) -> dict[str, Any]:
        exigir_perfil(user, "paciente")
        s = carregar_sessao(db, sessao_id, user)
        if s.status != "concluida":
            raise HTTPException(409, "Só é possível avaliar sessões concluídas.")
        a = db.scalar(select(Avaliacao).where(Avaliacao.sessao_id == s.id))
        if a is None:
            a = Avaliacao(sessao_id=s.id, paciente_id=user.id, profissional_id=s.profissional_id, nota=body.nota)
            db.add(a)
        a.nota = body.nota
        a.comentario = body.comentario
        a.criado_em = datetime.now().replace(microsecond=0)
        db.commit()
        return _avaliacao_out(a)

    # ------------------------------------------------------------------- humor
    @app.get("/humor")
    def listar_humor(user: Eu, db: Db, limite: int = Query(default=50, ge=1, le=1000), dias: int | None = Query(default=None, ge=1, le=3650)) -> list[dict[str, Any]]:
        exigir_perfil(user, "paciente")
        stmt = select(Humor).where(Humor.usuario_id == user.id)
        if dias:
            stmt = stmt.where(Humor.data_hora >= datetime.now() - timedelta(days=dias))
        stmt = stmt.order_by(Humor.data_hora.desc()).limit(limite)
        return [_humor_out(h) for h in db.scalars(stmt)]

    @app.post("/humor", status_code=201)
    def registrar_humor(body: schemas.HumorIn, user: Eu, db: Db) -> dict[str, Any]:
        exigir_perfil(user, "paciente")
        h = Humor(usuario_id=user.id, nivel=body.nivel, nota=body.nota, data_hora=body.data_hora or datetime.now().replace(microsecond=0))
        db.add(h)
        db.commit()
        return _humor_out(h)

    @app.delete("/humor/{humor_id}", status_code=204)
    def excluir_humor(humor_id: int, user: Eu, db: Db) -> Response:
        h = db.get(Humor, humor_id)
        if h is None or h.usuario_id != user.id:
            raise HTTPException(404, "Registro não encontrado.")
        db.delete(h)
        db.commit()
        return Response(status_code=204)

    if cfg.demo_seed:
        from app.seed import popular_demo

        with factory() as db:
            popular_demo(db)

    return app
