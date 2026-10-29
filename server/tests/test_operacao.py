"""Partes operacionais: CLI de administração, envio SMTP, seed de demonstração e validação da configuração."""

from __future__ import annotations

import logging

import pytest
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from app import admin
from app.config import Settings, load_settings
from app.db import Base
from app.emailer import SmtpMailer, enviar_sem_vazar
from app.models import Usuario
from app.seed import popular_demo


# ---------------------------------------------------------------- CLI admin
@pytest.fixture()
def banco_arquivo(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'x.db'}"
    monkeypatch.setenv("DATABASE_URL", url)
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.delenv("JWT_SECRET", raising=False)
    eng = create_engine(url)
    Base.metadata.create_all(eng)
    with Session(eng) as s:
        s.add(Usuario(nome="Dra. Ana", email="ana@x.com", senha_hash="h", perfil="profissional", registro="06/1"))
        s.commit()
    return eng


def test_cli_lista_aprova_e_revoga(banco_arquivo, capsys):
    assert admin.main(["pendentes"]) == 0
    assert "ana@x.com" in capsys.readouterr().out
    assert admin.main(["aprovar", "ANA@x.com"]) == 0
    assert "Aprovado" in capsys.readouterr().out
    admin.main(["pendentes"])
    assert "ana@x.com" not in capsys.readouterr().out
    assert admin.main(["revogar", "ana@x.com"]) == 0
    assert "removida" in capsys.readouterr().out
    with Session(banco_arquivo) as s:
        assert s.scalar(select(Usuario.verificado_em).where(Usuario.email == "ana@x.com")) is None


def test_cli_uso_errado_mostra_ajuda(capsys):
    assert admin.main([]) == 2
    assert admin.main(["aprovar"]) == 2
    assert admin.main(["apagar", "x@x.com"]) == 2
    assert "python -m app.admin" in capsys.readouterr().out


# ---------------------------------------------------------------- SMTP
class SmtpFalso:
    ultimo: SmtpFalso | None = None

    def __init__(self, host, port, timeout=None, context=None):
        self.host, self.port, self.context = host, port, context
        self.passos: list[str] = []
        self.mensagem = None
        SmtpFalso.ultimo = self

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def starttls(self, context=None):
        self.passos.append("starttls")

    def login(self, u, p):
        self.passos.append(f"login:{u}")

    def send_message(self, msg):
        self.mensagem = msg
        self.passos.append("enviado")


def _cfg(**kw) -> Settings:
    base = {"env": "development", "database_url": "sqlite://", "jwt_secret": "x" * 40, "smtp_host": "smtp.x", "smtp_from": "no-reply@x.com"}
    return Settings(**{**base, **kw})


def test_smtp_starttls_com_login(monkeypatch):
    monkeypatch.setattr("app.emailer.smtplib.SMTP", SmtpFalso)
    SmtpMailer(_cfg(smtp_user="u", smtp_password="p")).enviar("a@b.com", "Assunto", "Corpo")
    f = SmtpFalso.ultimo
    assert f.passos == ["starttls", "login:u", "enviado"] and f.port == 587
    assert f.mensagem["To"] == "a@b.com" and f.mensagem["From"] == "no-reply@x.com" and f.mensagem["Subject"] == "Assunto"


def test_smtp_ssl_e_sem_seguranca(monkeypatch):
    monkeypatch.setattr("app.emailer.smtplib.SMTP_SSL", SmtpFalso)
    SmtpMailer(_cfg(smtp_seguranca="ssl", smtp_port=465)).enviar("a@b.com", "A", "C")
    assert SmtpFalso.ultimo.passos == ["enviado"]  # sem usuário: não faz login
    monkeypatch.setattr("app.emailer.smtplib.SMTP", SmtpFalso)
    SmtpMailer(_cfg(smtp_seguranca="none")).enviar("a@b.com", "A", "C")
    assert "starttls" not in SmtpFalso.ultimo.passos


def test_falha_de_envio_nao_vaza_endereco_nem_codigo(caplog):
    class Quebrado:
        def enviar(self, para, assunto, texto):
            raise OSError("conexão recusada")

    log = logging.getLogger("teste_email")
    with caplog.at_level(logging.INFO, logger="teste_email"):
        enviar_sem_vazar(Quebrado(), log, "segredo@x.com", "A", "código 123456")  # não pode levantar
    texto = caplog.text
    assert "email_falhou" in texto and "segredo@x.com" not in texto and "123456" not in texto.replace("conexão", "")


# ---------------------------------------------------------------- seed
def test_seed_cria_contas_demo_aprovadas_e_nao_repete():
    eng = create_engine("sqlite://")
    Base.metadata.create_all(eng)
    with Session(eng) as s:
        popular_demo(s)
        s.commit()
        profs = list(s.scalars(select(Usuario).where(Usuario.perfil == "profissional")))
        assert len(profs) == 3 and all(p.verificado_em and p.email_verificado_em for p in profs)
        n = len(list(s.scalars(select(Usuario))))
        popular_demo(s)  # banco já populado: nada muda
        assert len(list(s.scalars(select(Usuario)))) == n


# ---------------------------------------------------------------- configuração
def _env_prod(monkeypatch, **extra):
    for k in ("SMTP_HOST", "SMTP_FROM", "APP_TZ", "SMTP_SECURITY", "CORS_ORIGINS"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("JWT_SECRET", "k" * 40)
    monkeypatch.setenv("PRONTUARIO_KEYS", "chave")
    for k, v in extra.items():
        monkeypatch.setenv(k, v)


def test_smtp_pela_metade_recusa_subir(monkeypatch):
    _env_prod(monkeypatch, SMTP_HOST="smtp.x")
    with pytest.raises(RuntimeError, match="SMTP_HOST e SMTP_FROM"):
        load_settings()
    _env_prod(monkeypatch, SMTP_HOST="smtp.x", SMTP_FROM="a@x.com")
    assert load_settings().email_ativo is True
    _env_prod(monkeypatch)
    assert load_settings().email_ativo is False


def test_fuso_e_seguranca_smtp_invalidos_recusam_subir(monkeypatch):
    _env_prod(monkeypatch, APP_TZ="Marte/Olympus")
    with pytest.raises(RuntimeError, match="APP_TZ"):
        load_settings()
    _env_prod(monkeypatch, SMTP_SECURITY="tls13")
    with pytest.raises(RuntimeError, match="SMTP_SECURITY"):
        load_settings()
