#!/bin/sh
# Restaura um backup .dump. ATENÇÃO: substitui os dados atuais do banco. Pare a API antes.
#   docker compose -f docker-compose.prod.yml stop api caddy
#   docker compose -f docker-compose.prod.yml exec -T backup sh /usr/local/bin/restore-postgres.sh /backups/diario/ARQUIVO.dump
#   docker compose -f docker-compose.prod.yml up -d
set -eu
arq="${1:?uso: restore-postgres.sh ARQUIVO.dump}"
[ -f "$arq" ] || { echo "arquivo não encontrado: $arq" >&2; exit 1; }
if [ -f "$arq.sha256" ]; then ( cd "$(dirname "$arq")" && sha256sum -c "$(basename "$arq").sha256" ); fi
pg_restore --list "$arq" > /dev/null
pg_restore --clean --if-exists --no-owner --single-transaction --dbname="${PGDATABASE:?}" "$arq"
echo "restauração concluída: $arq"
