"""Token Jitsi: assinatura, validade, papéis, estabilidade da sala e ausência de vazamento em log."""

from __future__ import annotations

import logging
import time
from urllib.parse import parse_qs, urlparse

import jwt
import pytest

from tests.test_video import DOMINIO, SEGREDO_VIDEO, _sessao, client  # noqa: F401  (fixture reutilizada)


def _token(url: str) -> str:
    return parse_qs(urlparse(url).query)["jwt"][0]


def test_assinatura_so_confere_com_o_segredo_do_servidor_jitsi(client):  # noqa: F811
    pro, _, sid = _sessao(client)
    t = _token(client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()["url"])
    jwt.decode(t, SEGREDO_VIDEO, algorithms=["HS256"], audience="jitsi")  # ok
    with pytest.raises(jwt.InvalidSignatureError):
        jwt.decode(t, "outro-segredo-qualquer-com-mais-de-32-caracteres", algorithms=["HS256"], audience="jitsi")
    with pytest.raises(jwt.InvalidAudienceError):
        jwt.decode(t, SEGREDO_VIDEO, algorithms=["HS256"], audience="outra")


def test_token_adulterado_para_moderador_e_rejeitado(client):  # noqa: F811
    _, pac, sid = _sessao(client)
    t = _token(client.get(f"/sessoes/{sid}/video", headers=pac["h"]).json()["url"])
    cabecalho, carga, assinatura = t.split(".")
    import base64
    import json

    dados = json.loads(base64.urlsafe_b64decode(carga + "=" * (-len(carga) % 4)))
    dados["moderator"] = True
    dados["context"]["user"]["moderator"] = True
    nova = base64.urlsafe_b64encode(json.dumps(dados).encode()).rstrip(b"=").decode()
    with pytest.raises(jwt.InvalidSignatureError):
        jwt.decode(f"{cabecalho}.{nova}.{assinatura}", SEGREDO_VIDEO, algorithms=["HS256"], audience="jitsi")


def test_alg_none_nao_e_aceito(client):  # noqa: F811
    pro, _, sid = _sessao(client)
    t = _token(client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()["url"])
    sem_assinatura = jwt.encode(jwt.decode(t, options={"verify_signature": False}, audience="jitsi"), key=None, algorithm="none")
    with pytest.raises(jwt.InvalidAlgorithmError):
        jwt.decode(sem_assinatura, SEGREDO_VIDEO, algorithms=["HS256"], audience="jitsi")


def test_campos_exigidos_pelo_jitsi_e_janela_de_validade(client):  # noqa: F811
    pro, _, sid = _sessao(client, minutos=10)
    r = client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()
    c = jwt.decode(_token(r["url"]), SEGREDO_VIDEO, algorithms=["HS256"], audience="jitsi")
    assert c["iss"] == "ms-teste" and c["sub"] == DOMINIO and c["room"] == r["sala"]
    assert c["nbf"] <= time.time() < c["exp"]
    assert c["exp"] - time.time() <= (10 + 120) * 60 + 5  # nunca passa do fim da janela da sessão
    assert set(c["context"]["user"]) == {"name", "moderator"}  # sem e-mail, sem id: minimização


def test_papeis_profissional_modera_paciente_nao(client):  # noqa: F811
    pro, pac, sid = _sessao(client)
    cp = jwt.decode(_token(client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()["url"]), SEGREDO_VIDEO, algorithms=["HS256"], audience="jitsi")
    ca = jwt.decode(_token(client.get(f"/sessoes/{sid}/video", headers=pac["h"]).json()["url"]), SEGREDO_VIDEO, algorithms=["HS256"], audience="jitsi")
    assert cp["moderator"] is True and ca["moderator"] is False
    assert cp["room"] == ca["room"]


def test_sala_e_estavel_entre_chamadas_mas_o_token_e_novo(client):  # noqa: F811
    pro, _, sid = _sessao(client)
    a = client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()
    time.sleep(1.1)
    b = client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()
    assert a["sala"] == b["sala"]  # reentrar cai na mesma sala
    assert _token(a["url"]) != _token(b["url"])  # mas o token é emitido de novo (iat/nbf mudam)


def test_trocar_o_segredo_do_servidor_muda_todas_as_salas(client):  # noqa: F811
    from app.config import Settings
    from app.video import nome_da_sala

    pro, _, sid = _sessao(client)
    sala = client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()["sala"]
    with client.app.state.session_factory() as db:
        from app.models import Sessao

        s = db.get(Sessao, sid)
        assert nome_da_sala("x" * 40, s) == sala
        assert nome_da_sala("y" * 40, s) != sala
    assert isinstance(client.app.state.settings, Settings)


def test_url_e_token_nao_vao_para_o_log(client, caplog):  # noqa: F811
    pro, _, sid = _sessao(client)
    with caplog.at_level(logging.DEBUG):
        r = client.get(f"/sessoes/{sid}/video", headers=pro["h"]).json()
    assert _token(r["url"]) not in caplog.text and r["sala"] not in caplog.text


def test_sem_login_nao_ha_sala(client):  # noqa: F811
    _, _, sid = _sessao(client)
    assert client.get(f"/sessoes/{sid}/video").status_code == 401
