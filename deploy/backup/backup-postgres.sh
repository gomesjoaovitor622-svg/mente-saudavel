#!/bin/sh
# Backup do PostgreSQL: pg_dump formato custom (já comprimido, nível 9) + checksum + verificação + rotação.
# Usa as variáveis padrão do PostgreSQL (PGHOST, PGUSER, PGDATABASE, PGPASSWORD).
#   BACKUP_DIR      pasta de destino (padrão ./backups)
#   KEEP_DAILY=7    quantos diários guardar      KEEP_WEEKLY=4  semanais (domingo)     KEEP_MONTHLY=12  mensais (dia 1)
#   BACKUP_NOW      data/hora fixa AAAAMMDD_HHMMSS (só para testes)
set -eu
dir="${BACKUP_DIR:-./backups}"
keep_d="${KEEP_DAILY:-7}"; keep_w="${KEEP_WEEKLY:-4}"; keep_m="${KEEP_MONTHLY:-12}"
agora="${BACKUP_NOW:-$(date +%Y%m%d_%H%M%S)}"
dia="${agora%%_*}"
umask 077
mkdir -p "$dir/diario" "$dir/semanal" "$dir/mensal"

arq="$dir/diario/mente_saudavel_$agora.dump"
tmp="$arq.parcial"
trap 'rm -f "$tmp"' EXIT
pg_dump --format=custom --compress=9 --no-owner --file="$tmp"
# Um dump que não consegue ser listado está corrompido: não entra na rotação.
pg_restore --list "$tmp" > /dev/null
mv "$tmp" "$arq"
( cd "$dir/diario" && sha256sum "$(basename "$arq")" > "$(basename "$arq").sha256" )

# Cópias de longo prazo: domingo -> semanal, dia 1 -> mensal.
dow=$(date -d "$(echo "$dia" | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/')" +%u 2>/dev/null || date +%u)
[ "$dow" = "7" ] && cp "$arq" "$dir/semanal/"
[ "${dia#??????}" = "01" ] && cp "$arq" "$dir/mensal/"

# Rotação: mantém os N mais novos de cada pasta (o nome carrega a data, então ordem alfabética = cronológica).
rotacionar() { # pasta quantidade
  ls -1 "$1"/mente_saudavel_*.dump 2>/dev/null | sort -r | tail -n +"$(($2 + 1))" | while read -r velho; do
    rm -f "$velho" "$velho.sha256"
  done
}
rotacionar "$dir/diario" "$keep_d"; rotacionar "$dir/semanal" "$keep_w"; rotacionar "$dir/mensal" "$keep_m"
echo "backup ok: $arq ($(du -h "$arq" | cut -f1))"
