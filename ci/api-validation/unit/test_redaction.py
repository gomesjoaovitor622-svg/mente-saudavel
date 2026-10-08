"""Mascaramento de segredos e PII: nada sensível pode sair do sistema."""

import pytest

from apival.redaction import redact


@pytest.mark.parametrize(
    ("entrada", "proibido"),
    [
        ("Authorization: Bearer abc123SEGREDO", "abc123SEGREDO"),
        ("authorization=Basic dXNlcjpwYXNz", "dXNlcjpwYXNz"),
        ("token=xyz789abc", "xyz789abc"),
        ("API_AUTH_TOKEN: s3cr3t-valor", "s3cr3t-valor"),
        ("password = hunter2", "hunter2"),
        ("github_pat_" + "A" * 30, "A" * 30),
        ("ghp_" + "b" * 30, "b" * 30),
        ("AKIA" + "IOSFODNN7EXAMPLE", "IOSFODNN7EXAMPLE"),
        ("AIza" + "c" * 35, "c" * 35),
        ("xox" + "b-1234567890-abcdef", "1234567890-abcdef"),
        (
            "eyJhbGciOiJIUzI1NiJ9" + "." + "eyJzdWIiOiIxMjM0NTY3ODkwIn0" + "." + "dBjftJeZ4CVPmB92" + "K27uhbUJU1p1r",
            "eyJhbGciOiJIUzI1NiJ9",
        ),
        ("-----BEGIN RSA " + "PRIVATE KEY-----\nMIIBOgIBAAJBAK\n-----END RSA " + "PRIVATE KEY-----", "MIIBOgIBAAJBAK"),
    ],
)
def test_segredos_sao_mascarados(entrada: str, proibido: str) -> None:
    assert proibido not in redact(entrada)


@pytest.mark.parametrize(
    ("entrada", "proibido"),
    [
        ("contato joao.silva@empresa.com.br urgente", "joao.silva@empresa.com.br"),
        ("CPF 123.456.789-09 do paciente", "123.456.789-09"),
        ("cpf 12345678909", "12345678909"),
        ("CNPJ 12.345.678/0001-95", "12.345.678/0001-95"),
        ("fone (11) 98765-4321", "98765-4321"),
        ("whatsapp +55 11 987654321", "987654321"),
        ("cliente em 203.0.113.42 acessou", "203.0.113.42"),
    ],
)
def test_pii_e_mascarada(entrada: str, proibido: str) -> None:
    assert proibido not in redact(entrada)


def test_loopback_e_preservado_para_diagnostico() -> None:
    assert "127.0.0.1" in redact("health em http://127.0.0.1:8765/health")
    assert "0.0.0.0" in redact("bind 0.0.0.0")


def test_ip_invalido_nao_e_tratado_como_ip() -> None:
    assert redact("versão 999.999.999.999 estranha") == "versão 999.999.999.999 estranha"


def test_segredos_conhecidos_em_tempo_de_execucao_incluem_forma_codificada() -> None:
    segredo = "valor com espaço&simbolos"
    saida = redact(f"x={segredo} y=valor%20com%20espa%C3%A7o%26simbolos", extra_secrets=[segredo])
    assert "espaço" not in saida
    assert "espa%C3%A7o" not in saida


def test_segredo_curto_demais_nao_e_usado_para_nao_destruir_o_texto() -> None:
    assert redact("abc def", extra_secrets=["ab"]) == "abc def"


def test_texto_comum_nao_e_alterado() -> None:
    texto = "[CONTRACT] GET /health: esperado HTTP 200, recebido 500 em 0.12s"
    assert redact(texto) == texto
