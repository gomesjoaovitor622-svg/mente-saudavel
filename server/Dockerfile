# API do Mente Saudável. Imagem enxuta, usuário sem privilégios, dependências com hash.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    TZ=America/Sao_Paulo

RUN apt-get update \
 && apt-get install -y --no-install-recommends tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --create-home app

WORKDIR /srv
COPY requirements.txt .
RUN pip install --require-hashes -r requirements.txt

COPY app ./app
COPY alembic.ini ./alembic.ini
COPY migrations ./migrations
USER 10001

EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=5 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status==200 else 1)"

# --factory: cria o app lendo a configuração do ambiente. A API não é exposta à internet
# (só o Caddy fala com ela), por isso confia nos cabeçalhos X-Forwarded-*.
CMD ["uvicorn", "app.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*", "--no-server-header"]
