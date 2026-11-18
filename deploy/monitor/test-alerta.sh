#!/bin/bash
# Testa o monitor com uma API falsa e um "webhook" falso (sem Docker, sem banco).
set -euo pipefail
aqui="$(cd "$(dirname "$0")" && pwd)"
t="$(mktemp -d)"; trap 'kill "${pid:-0}" 2>/dev/null || true; rm -rf "$t"' EXIT
porta=$((20000 + RANDOM % 20000))

cat > "$t/falso.py" <<'PY'
import http.server, os, sys
estado, hook, total_f, erro_f = sys.argv[2:6]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/health/ready":
            ok = open(estado).read().strip() == "ok"
            self.send_response(200 if ok else 503); self.end_headers(); self.wfile.write(b"{}"); return
        if self.path == "/metricas":
            if self.headers.get("Authorization") != "Bearer tok":
                self.send_response(401); self.end_headers(); return
            t, e = int(open(total_f).read()), int(open(erro_f).read())
            passo_t, passo_e = int(os.environ.get("PASSO_T", "0")), int(os.environ.get("PASSO_E", "0"))
            open(total_f, "w").write(str(t + passo_t)); open(erro_f, "w").write(str(e + passo_e))
            corpo = f'ms_http_requests_total{{metodo="GET",rota="/x",status="2xx"}} {t - e}\nms_http_requests_total{{metodo="GET",rota="/x",status="5xx"}} {e}\n'
            self.send_response(200); self.end_headers(); self.wfile.write(corpo.encode()); return
        self.send_response(404); self.end_headers()
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        open(hook, "ab").write(self.rfile.read(n) + b"\n")
        self.send_response(204); self.end_headers()
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY

servir() { [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null || true
  PASSO_T="${2:-0}" PASSO_E="${3:-0}" python3 "$t/falso.py" "$porta" "$t/estado" "$t/hook" "$t/total" "$t/erro" & pid=$!
  echo "$1" > "$t/estado"; : > "$t/hook"; echo 0 > "$t/total"; echo 0 > "$t/erro"
  for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$porta/x" && break; sleep 0.1; done; }
roda() { env ALERTA_URL="http://127.0.0.1:$porta/health/ready" ALERTA_METRICAS_URL="http://127.0.0.1:$porta/metricas" \
  ALERTA_WEBHOOK_URL="http://127.0.0.1:$porta/hook" ALERTA_INTERVALO=0 "$@" sh "$aqui/alerta.sh" 2>"$t/log" >/dev/null; }
conta() { grep -c "$1" "$t/hook" || true; }

# 1) API fora do ar: UM alerta após 3 falhas seguidas (não um por ciclo); depois, UM aviso de recuperação
servir fora
roda ALERTA_CICLOS=6 ALERTA_FALHAS=3
[ "$(conta CRITICO)" = 1 ] || { echo "FALHA: esperava 1 alerta CRITICO, veio $(conta CRITICO)"; cat "$t/hook"; exit 1; }
echo ok > "$t/estado"
roda ALERTA_CICLOS=1 ALERTA_FALHAS=3   # novo processo = estado novo: nada a recuperar, sem alerta novo
[ "$(conta CRITICO)" = 1 ] || { echo "FALHA: alerta indevido com a API saudável"; exit 1; }

# 2) menos falhas que o limite não alertam
servir fora; roda ALERTA_CICLOS=2 ALERTA_FALHAS=3
[ "$(conta CRITICO)" = 0 ] || { echo "FALHA: alertou antes do limite"; exit 1; }

# 3) taxa de 5xx alta (100 req/ciclo, 20 erros = 20%) alerta uma vez; sem METRICS_TOKEN não olha a taxa
servir ok 100 20
roda ALERTA_CICLOS=4 METRICS_TOKEN=tok ALERTA_TAXA_5XX=0.05 ALERTA_MIN_REQ=20
[ "$(conta ATENCAO)" = 1 ] || { echo "FALHA: esperava 1 alerta de taxa 5xx, veio $(conta ATENCAO)"; cat "$t/hook"; exit 1; }
servir ok 100 20
roda ALERTA_CICLOS=4
[ "$(conta ATENCAO)" = 0 ] || { echo "FALHA: olhou a taxa sem METRICS_TOKEN"; exit 1; }

# 4) taxa baixa (1%) não alerta; poucas requisições (abaixo do mínimo) também não
servir ok 100 1
roda ALERTA_CICLOS=4 METRICS_TOKEN=tok
[ "$(conta ATENCAO)" = 0 ] || { echo "FALHA: alertou com taxa baixa"; exit 1; }
servir ok 10 10
roda ALERTA_CICLOS=4 METRICS_TOKEN=tok ALERTA_MIN_REQ=20
[ "$(conta ATENCAO)" = 0 ] || { echo "FALHA: alertou com poucas requisições"; exit 1; }

# 5) o alerta também vai para o log, e a mensagem é sanitizada (sem aspas que quebrem o JSON do webhook)
servir fora; roda ALERTA_CICLOS=3 ALERTA_FALHAS=3 ALERTA_URL="http://127.0.0.1:$porta/health/ready"
grep -q "^ALERTA .* CRITICO" "$t/log" || { echo "FALHA: alerta não foi para o log"; exit 1; }
python3 - "$t/hook" <<'PY'
import json, sys
for linha in open(sys.argv[1]):
    if linha.strip(): json.loads(linha)  # todo corpo enviado é JSON válido
PY
echo "monitor de alertas: OK"
