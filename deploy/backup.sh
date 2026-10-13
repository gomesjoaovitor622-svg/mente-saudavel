#!/usr/bin/env bash
# Backup do PostgreSQL. Rode na pasta deploy/ (ex.: via cron, todo dia às 3h).
#   0 3 * * * cd /opt/mente-saudavel/deploy && ./backup.sh >> backup.log 2>&1
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p backups
arquivo="backups/mente_saudavel_$(date +%Y%m%d_%H%M%S).sql.gz"
docker compose exec -T db pg_dump -U mente -d mente_saudavel --no-owner | gzip > "$arquivo"
test -s "$arquivo"
# Mantém os 14 backups mais recentes.
find backups -name 'mente_saudavel_*.sql.gz' -type f -printf '%T@ %p\n' | sort -rn | tail -n +15 | cut -d' ' -f2- | xargs -r rm -f
echo "backup ok: $arquivo"
