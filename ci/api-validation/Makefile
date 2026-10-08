# Atalhos de desenvolvimento. Execute dentro de ci/api-validation/.
PY ?= python3
.PHONY: install lint typecheck sast unit system audit lock all

install:            ## instala dependências com verificação de hash
	$(PY) -m pip install --require-hashes -r requirements.txt -r requirements-quality.txt

lint:               ## ruff (lint + formato)
	ruff check . && ruff format --check .

typecheck:          ## mypy --strict
	mypy

sast:               ## bandit
	bandit -q -c pyproject.toml -r apival reference_service

unit:               ## testes unitários + cobertura mínima de 90%
	pytest unit --cov

system:             ## sobe o serviço com autenticação e roda contrato + conformidade + CORS + segurança
	@TOKEN=$$($(PY) -c "import secrets; print(secrets.token_hex(24))"); \
	API_AUTH_TOKEN_EXPECTED=$$TOKEN SOCKET_TIMEOUT_S=2 $(PY) -m reference_service.server > /tmp/ref-service.log 2>&1 & echo $$! > /tmp/ref-service.pid; \
	$(PY) -m apival.healthcheck http://127.0.0.1:8765/health --timeout 20 --pid-file /tmp/ref-service.pid && \
	API_AUTH_TOKEN=$$TOKEN SOCKET_TIMEOUT_S=2 pytest tests -m reference; \
	status=$$?; kill $$(cat /tmp/ref-service.pid) 2>/dev/null; exit $$status

audit:              ## vulnerabilidades conhecidas nas dependências
	pip-audit --require-hashes --disable-pip --strict -r requirements.txt -r requirements-quality.txt

lock:               ## regenera os arquivos travados com hashes (requer uv)
	uv pip compile requirements.in --universal --generate-hashes --python-version 3.11 -o requirements.txt
	uv pip compile requirements-quality.in --universal --generate-hashes --python-version 3.11 -o requirements-quality.txt
	uv pip compile requirements-security.in --universal --generate-hashes --python-version 3.11 -o requirements-security.txt

all: lint typecheck sast unit system
