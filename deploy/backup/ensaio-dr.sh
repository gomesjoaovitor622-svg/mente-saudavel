#!/usr/bin/env bash
# Ensaio de recuperação de desastre (rode em deploy/, com a pilha de produção no ar):
# insere um registro, faz backup, apaga o banco, restaura e confere registro + versão do Alembic.
# ATENÇÃO: apaga o banco. Use só em ambiente de teste/local, ou antes do lançamento (banco ainda sem dados reais).
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "${CONFIRMO:-}" == "sim" ]] || { echo "Isto APAGA o banco. Rode com CONFIRMO=sim para continuar." >&2; exit 1; }
dc() { docker compose -f docker-compose.prod.yml "$@"; }
psql_db() { dc exec -T db psql -U mente -d "${2:-mente_saudavel}" -v ON_ERROR_STOP=1 -tAc "$1"; }
email="dr-teste-$(date +%s)@exemplo.com"

echo "1/6 inserindo registro de teste: $email"
psql_db "INSERT INTO usuarios (nome,email,senha_hash,perfil,criado_em) VALUES ('Teste DR','$email','x','paciente',now());"
versao_antes=$(psql_db "SELECT version_num FROM alembic_version")

echo "2/6 backup"
dc exec -T backup sh /usr/local/bin/backup-postgres.sh
ultimo=$(ls -1 backups/diario/*.dump | sort | tail -1)
echo "    arquivo: $ultimo"; (cd backups/diario && sha256sum -c "$(basename "$ultimo").sha256")

echo "3/6 desastre: parando API e apagando o banco"
dc stop api caddy backup >/dev/null
dc up -d db >/dev/null
psql_db "DROP DATABASE mente_saudavel WITH (FORCE)" postgres
psql_db "CREATE DATABASE mente_saudavel" postgres

echo "4/6 restaurando (confere o SHA256 antes)"
dc run --rm --no-deps --entrypoint sh backup /usr/local/bin/restore-postgres.sh "/backups/diario/$(basename "$ultimo")"

echo "5/6 conferindo"
achou=$(psql_db "SELECT count(*) FROM usuarios WHERE email='$email'")
versao_depois=$(psql_db "SELECT version_num FROM alembic_version")
[[ "$achou" == 1 ]] || { echo "FALHOU: registro não voltou" >&2; exit 1; }
[[ "$versao_antes" == "$versao_depois" ]] || { echo "FALHOU: Alembic $versao_antes -> $versao_depois" >&2; exit 1; }
echo "    registro recuperado; Alembic em $versao_depois"

echo "6/6 subindo tudo de novo (migrate deve não ter nada a fazer)"
dc up -d
psql_db "DELETE FROM usuarios WHERE email='$email'"
echo "ENSAIO OK"
