#!/bin/bash
# Testa a rotação e a verificação do backup com pg_dump/pg_restore falsos (sem banco real).
set -euo pipefail
aqui="$(cd "$(dirname "$0")" && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
cat > "$t/bin/pg_dump" <<'S'
#!/bin/sh
for a in "$@"; do case "$a" in --file=*) echo "dump" > "${a#--file=}";; esac; done
S
cat > "$t/bin/pg_restore" <<'S'
#!/bin/sh
[ -n "${FALHA_RESTORE:-}" ] && exit 1
exit 0
S
chmod +x "$t/bin"/*
export PATH="$t/bin:$PATH" BACKUP_DIR="$t/b" KEEP_DAILY=3 KEEP_WEEKLY=2 KEEP_MONTHLY=2

for d in 20260101 20260102 20260103 20260104 20260105 20260106 20260107 20260108; do
  BACKUP_NOW="${d}_030000" sh "$aqui/backup-postgres.sh" > /dev/null
done
n=$(ls "$t/b/diario"/*.dump | wc -l)
[ "$n" = 3 ] || { echo "esperava 3 diários, tem $n"; exit 1; }
ls "$t/b/diario" | grep -q 20260108 || { echo "o mais novo sumiu"; exit 1; }
! ls "$t/b/diario" | grep -q 20260101 || { echo "o mais velho não foi apagado"; exit 1; }
[ -f "$t/b/mensal/mente_saudavel_20260101_030000.dump" ] || { echo "falta cópia mensal (dia 1)"; exit 1; }
[ -n "$(ls "$t/b/semanal")" ] || { echo "falta cópia semanal (domingo)"; exit 1; }
(cd "$t/b/diario" && sha256sum -c ./*.sha256 > /dev/null)

# dump que não passa na verificação não pode entrar na rotação
if FALHA_RESTORE=1 BACKUP_NOW=20260109_030000 sh "$aqui/backup-postgres.sh" 2>/dev/null; then echo "devia falhar"; exit 1; fi
! ls "$t/b/diario" | grep -q 20260109 || { echo "dump inválido foi guardado"; exit 1; }
echo "backup: testes ok"
