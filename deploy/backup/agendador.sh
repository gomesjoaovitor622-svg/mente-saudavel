#!/bin/sh
# Roda o backup todo dia no horário BACKUP_HORA (HH:MM, fuso TZ). Sem cron: o contêiner dorme até a hora.
set -u
hora="${BACKUP_HORA:-03:00}"
echo "agendador de backup: diariamente às $hora"
while true; do
  agora=$(date +%s)
  alvo=$(date -d "$(date +%Y-%m-%d) $hora" +%s 2>/dev/null || date -d "today $hora" +%s)
  [ "$alvo" -le "$agora" ] && alvo=$((alvo + 86400))
  sleep $((alvo - agora))
  /bin/sh /usr/local/bin/backup-postgres.sh || echo "BACKUP FALHOU em $(date -Iseconds)" >&2
  sleep 60
done
