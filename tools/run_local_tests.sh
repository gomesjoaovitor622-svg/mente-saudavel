#!/usr/bin/env bash
# Diagnóstico e execução integrada, no SEU computador (Linux, macOS, WSL ou Git Bash no Windows).
# Cada etapa grava um log em logs-locais/ — se algo falhar, cole aqui o final do log indicado.
#   tools/run_local_tests.sh deps      # confere Docker, Compose, Flutter, ADB, curl
#   tools/run_local_tests.sh dr        # ensaio de restauração (APAGA o banco de teste)
#   tools/run_local_tests.sh lan       # sobe a pilha com a API em HTTP:8000 e testa /health
#   tools/run_local_tests.sh android   # prepara android/, confere celular, gera e instala o APK de debug
#   tools/run_local_tests.sh all       # deps -> dr -> lan -> android
set -uo pipefail
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"; cd "$RAIZ"
LOGS="$RAIZ/logs-locais"; mkdir -p "$LOGS"; TS="$(date +%Y%m%d_%H%M%S)"
DC=(docker compose -f docker-compose.prod.yml)
ok()   { printf '  [OK]   %s\n' "$*"; }
falha(){ printf '  [FALHA] %s\n' "$*" >&2; }
info() { printf '\n== %s\n' "$*"; }
log_de() { echo "$LOGS/$1-$TS.log"; }

# ---------------------------------------------------------------- deps
etapa_deps() {
  info "Dependências"; local faltou=0
  for c in docker curl; do command -v "$c" >/dev/null && ok "$c" || { falha "$c não encontrado"; faltou=1; }; done
  docker compose version >/dev/null 2>&1 && ok "docker compose ($(docker compose version --short))" || { falha "docker compose (plugin v2) ausente"; faltou=1; }
  docker info >/dev/null 2>&1 && ok "daemon do Docker respondendo" || { falha "Docker não está rodando (abra o Docker Desktop / 'sudo systemctl start docker')"; faltou=1; }
  command -v flutter >/dev/null && ok "flutter ($(flutter --version 2>/dev/null | head -1))" || { falha "flutter não está no PATH (só necessário na etapa android)"; }
  command -v adb >/dev/null && ok "adb ($(adb version 2>/dev/null | head -1))" || { falha "adb não está no PATH (Android SDK platform-tools; só na etapa android)"; }
  [[ -f deploy/.env ]] && ok "deploy/.env existe" || falha "deploy/.env ausente: rode 'cp deploy/.env.example deploy/.env' e preencha (veja o aviso da etapa dr)"
  return $faltou
}

# ---------------------------------------------------------------- .env de teste
garantir_env() {
  [[ -f deploy/.env ]] && return 0
  info "Criando deploy/.env de TESTE (segredos aleatórios, DEMO_SEED=true)"
  {
    echo "DOMAIN=localhost"
    echo "POSTGRES_PASSWORD=$(openssl rand -hex 16 2>/dev/null || date +%s%N | sha256sum | cut -c1-32)"
    echo "JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || date +%s%N | sha256sum | cut -c1-64)"
    echo "DEMO_SEED=true"
  } > deploy/.env
  ok "criado (não vai para o Git)"
}

# ---------------------------------------------------------------- dr
etapa_dr() {
  info "Ensaio de Disaster Recovery"; local log; log="$(log_de dr)"
  garantir_env
  # O contêiner do PostgreSQL grava como outro usuário: libera a pasta de backups antes.
  mkdir -p deploy/backups && chmod -R a+rwX deploy/backups && ok "permissão de deploy/backups ajustada"
  ( cd deploy && "${DC[@]}" up -d --build ) >"$log" 2>&1 || { falha "subir a pilha falhou — veja $log"; tail -25 "$log"; return 1; }
  # espera a API ficar saudável
  for _ in $(seq 1 60); do [[ "$(cd deploy && "${DC[@]}" ps api --format '{{.Health}}' 2>/dev/null)" == healthy ]] && break; sleep 5; done
  ( cd deploy && CONFIRMO=sim ./backup/ensaio-dr.sh ) >>"$log" 2>&1
  local rc=$?
  if [[ $rc -ne 0 ]] && grep -qi "permission denied" "$log"; then
    echo "  permissão negada: reaplicando chmod e tentando de novo"; chmod -R a+rwX deploy/backups
    ( cd deploy && CONFIRMO=sim ./backup/ensaio-dr.sh ) >>"$log" 2>&1; rc=$?
  fi
  tail -12 "$log"
  if [[ $rc -eq 0 ]] && grep -q "ENSAIO OK" "$log"; then ok "ENSAIO OK  (log: $log)"; else falha "ensaio falhou — cole o final de $log"; return 1; fi
}

# ---------------------------------------------------------------- lan
ip_local() {
  local ip=""
  if command -v hostname >/dev/null && hostname -I >/dev/null 2>&1; then ip=$(hostname -I | tr ' ' '\n' | grep -E '^(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))\.' | head -1)
  elif command -v ipconfig >/dev/null && ipconfig getifaddr en0 >/dev/null 2>&1; then ip=$(ipconfig getifaddr en0)
  elif command -v ipconfig >/dev/null; then ip=$(ipconfig 2>/dev/null | tr -d '\r' | grep -E 'IPv4' | grep -oE '(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+' | head -1)
  fi
  echo "$ip"
}

etapa_lan() {
  info "Pilha em modo LAN (API em http://IP:8000)"; local log; log="$(log_de lan)"
  garantir_env
  ( cd deploy && docker compose -f docker-compose.prod.yml -f docker-compose.lan.yml up -d --build ) >"$log" 2>&1 \
    || { falha "subida falhou — veja $log"; tail -25 "$log"; return 1; }
  local ip; ip="$(ip_local)"; echo "  IP local detectado: ${ip:-NÃO DETECTADO}"
  for _ in $(seq 1 40); do curl -fsS http://localhost:8000/health >/dev/null 2>&1 && break; sleep 3; done
  curl -fsS http://localhost:8000/health >>"$log" 2>&1 && ok "http://localhost:8000/health respondeu" \
    || { falha "localhost:8000/health não respondeu — veja 'docker compose logs api'"; ( cd deploy && "${DC[@]}" logs --tail=40 api ) | tee -a "$log"; return 1; }
  if [[ -n "$ip" ]]; then
    curl -fsS --max-time 5 "http://$ip:8000/health" >/dev/null 2>&1 && ok "http://$ip:8000/health respondeu pelo IP da rede" \
      || falha "pelo IP $ip não respondeu: firewall do computador bloqueando a porta 8000 (veja docs/TROUBLESHOOTING-LOCAL.md)"
    mkdir -p env
    if [[ ! -f env/local.json ]]; then printf '{\n  "API_URL": "http://%s:8000",\n  "DEMO_MODE": "true"\n}\n' "$ip" > env/local.json; ok "env/local.json criado com $ip"
    else echo "  env/local.json já existe (não alterei): $(tr -d '\n ' < env/local.json)"; fi
    echo "  >> No navegador do CELULAR abra: http://$ip:8000/health  (deve mostrar {\"status\":\"ok\"})"
  fi
}

# ---------------------------------------------------------------- android
etapa_android() {
  info "Android: preparar, conectar, compilar e instalar"; local log; log="$(log_de android)"
  command -v flutter >/dev/null && command -v adb >/dev/null || { falha "flutter e adb são necessários (rode a etapa deps)"; return 1; }
  [[ -f env/local.json ]] || { falha "env/local.json ausente: rode a etapa lan primeiro (ou copie env/local.json.example e ponha seu IP)"; return 1; }
  tools/preparar_android.sh >"$log" 2>&1 || { falha "preparar_android.sh falhou"; tail -20 "$log"; return 1; }; ok "android/ preparado"
  adb start-server >>"$log" 2>&1
  local dispositivos; dispositivos="$(adb devices | tail -n +2 | grep -w device || true)"
  if [[ -z "$dispositivos" ]]; then
    falha "nenhum celular autorizado no 'adb devices'. Ative Depuração USB, conecte o cabo e aceite o aviso no celular."; adb devices; return 1
  fi
  ok "celular conectado: $(echo "$dispositivos" | head -1 | cut -f1)"
  flutter pub get >>"$log" 2>&1 || { falha "flutter pub get falhou — veja $log"; tail -20 "$log"; return 1; }
  flutter build apk --debug --dart-define-from-file=env/local.json 2>&1 | tee -a "$log"
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then falha "build falhou — cole o final de $log"; tail -40 "$log" | tail -25; return 1; fi
  ok "APK gerado"
  adb install -r build/app/outputs/flutter-apk/app-debug.apk 2>&1 | tee -a "$log"
  [[ ${PIPESTATUS[0]} -eq 0 ]] || { falha "instalação falhou — veja $log"; return 1; }
  ok "instalado. Abra o app 'Mente Saudável' e siga o checklist em docs/GUIA-DR-E-APK.md (seção 4)"
  local api; api=$(grep -oE 'http://[0-9.]+:[0-9]+' env/local.json | head -1)
  [[ -n "$api" ]] && { adb shell am start -a android.intent.action.VIEW -d "$api/health" >/dev/null 2>&1 && echo "  (abri $api/health no navegador do celular para testar a rede)"; }
}

case "${1:-all}" in
  deps) etapa_deps ;;
  dr) etapa_dr ;;
  lan) etapa_lan ;;
  android) etapa_android ;;
  all) etapa_deps; etapa_dr && etapa_lan && etapa_android ;;
  *) echo "uso: $0 {deps|dr|lan|android|all}" >&2; exit 2 ;;
esac
rc=$?
echo; echo "Logs em: $LOGS"
exit $rc
