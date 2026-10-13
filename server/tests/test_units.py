from __future__ import annotations

import pytest

from app.config import load_settings
from app.security import criar_token, hash_senha, ler_token, verificar_senha


def test_hash_scrypt_e_verificacao():
    h = hash_senha("segredo-123")
    assert h.startswith("scrypt$") and "segredo" not in h
    assert verificar_senha("segredo-123", h) and not verificar_senha("outra", h)
    assert hash_senha("segredo-123") != h  # salt aleatório
    assert not verificar_senha("x", "lixo") and not verificar_senha("x", "md5$1$2$3$4$5")


def test_token_valido_expirado_e_adulterado():
    t = criar_token(7, "s" * 40, 1)
    assert ler_token(t, "s" * 40) == 7
    assert ler_token(t, "outra-chave-" * 4) is None
    assert ler_token(criar_token(7, "s" * 40, -1), "s" * 40) is None
    assert ler_token(t[:-3] + "abc", "s" * 40) is None


def test_config_recusa_segredo_fraco(monkeypatch):
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.delenv("JWT_SECRET", raising=False)
    with pytest.raises(RuntimeError):
        load_settings()
    monkeypatch.setenv("JWT_SECRET", "curto")
    with pytest.raises(RuntimeError):
        load_settings()
    monkeypatch.setenv("JWT_SECRET", "a" * 40)
    monkeypatch.setenv("CORS_ORIGINS", "*")
    with pytest.raises(RuntimeError):
        load_settings()
    monkeypatch.setenv("CORS_ORIGINS", "https://a.com, https://b.com")
    monkeypatch.setenv("DATABASE_URL", "postgres://u:p@h/db")
    cfg = load_settings()
    assert cfg.cors_origins == ("https://a.com", "https://b.com")
    assert cfg.database_url.startswith("postgresql+psycopg://")
