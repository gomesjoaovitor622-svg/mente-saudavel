#!/bin/sh
# Monitor leve de produção (sem serviço externo pago): confere a API a cada ALERTA_INTERVALO segundos e AVISA
# só quando algo muda, para não gerar ruído:
#   1) /health/ready falha ALERTA_FALHAS vezes seguidas  -> "API fora do ar / banco indisponível";
#   2) taxa de respostas 5xx acima de ALERTA_TAXA_5XX na janela (precisa de METRICS_TOKEN) -> "taxa de erros alta";
#   3) volta ao normal -> "recuperado".
# O aviso sempre vai para o log do contêiner (docker compose logs monitor); se ALERTA_WEBHOOK_URL existir, também
# é enviado lá (Slack, Discord, Teams ou qualquer endpoint que aceite JSON com "text"/"content").
# POSIX sh: roda no Alpine (busybox wget) e em qualquer Linux com curl.
set -u

URL_READY="${ALERTA_URL:-http://api:8000/health/ready}"
URL_METRICAS="${ALERTA_METRICAS_URL:-http://api:8000/metricas}"
TOKEN="${METRICS_TOKEN:-}"
INTERVALO="${ALERTA_INTERVALO:-30}"
LIMITE_FALHAS="${ALERTA_FALHAS:-3}"
TAXA_MAX="${ALERTA_TAXA_5XX:-0.05}"
MIN_REQ="${ALERTA_MIN_REQ:-20}"
WEBHOOK="${ALERTA_WEBHOOK_URL:-}"
CICLOS="${ALERTA_CICLOS:-0}" # 0 = para sempre (só os testes usam outro valor)

http_get() { # $1 = URL, $2 = token opcional; imprime o corpo; sai com erro se não for 2xx
  if command -v curl >/dev/null 2>&1; then
    if [ -n "${2:-}" ]; then curl -fsS --max-time 5 -H "Authorization: Bearer $2" "$1"; else curl -fsS --max-time 5 "$1"; fi
  else
    if [ -n "${2:-}" ]; then wget -q -T 5 -O - --header="Authorization: Bearer $2" "$1"; else wget -q -T 5 -O - "$1"; fi
  fi
}

http_post_json() { # $1 = URL, $2 = JSON
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 10 -H 'Content-Type: application/json' -d "$2" "$1" >/dev/null
  else
    wget -q -T 10 -O /dev/null --header='Content-Type: application/json' --post-data="$2" "$1"
  fi
}

avisar() { # $1 = mensagem (sem aspas nem quebras de linha)
  msg="$(printf '%s' "$1" | tr -d '"\\\n\r' | cut -c1-300)"
  echo "ALERTA $(date -Iseconds 2>/dev/null || date) $msg" >&2
  [ -n "$WEBHOOK" ] || return 0
  http_post_json "$WEBHOOK" "{\"text\":\"Mente Saudavel: $msg\",\"content\":\"Mente Saudavel: $msg\"}" ||
    echo "ALERTA (webhook falhou) $(date -Iseconds 2>/dev/null || date)" >&2
}

falhas=0
fora_do_ar=0
taxa_alta=0
tot_ant=""
err_ant=""
ciclo=0
echo "monitor: $URL_READY a cada ${INTERVALO}s; alerta após $LIMITE_FALHAS falhas seguidas; taxa 5xx > $TAXA_MAX"

while true; do
  # ---- 1) prontidão (API + banco)
  if http_get "$URL_READY" >/dev/null 2>&1; then
    falhas=0
    if [ "$fora_do_ar" = 1 ]; then fora_do_ar=0; avisar "RECUPERADO: a API voltou a responder (banco ok)."; fi
  else
    falhas=$((falhas + 1))
    if [ "$falhas" -ge "$LIMITE_FALHAS" ] && [ "$fora_do_ar" = 0 ]; then
      fora_do_ar=1
      avisar "CRITICO: a API nao esta pronta ($falhas falhas seguidas em $URL_READY). Verifique a API e o banco de dados."
    fi
  fi

  # ---- 2) taxa de 5xx na janela entre duas leituras (só com METRICS_TOKEN)
  if [ -n "$TOKEN" ] && corpo="$(http_get "$URL_METRICAS" "$TOKEN" 2>/dev/null)"; then
    par="$(printf '%s\n' "$corpo" | awk '/^ms_http_requests_total\{/ { n=$NF; t+=n; if ($0 ~ /status="5xx"/) e+=n } END { printf "%d %d", t, e }')"
    tot="${par% *}"
    err="${par#* }"
    if [ -n "$tot_ant" ] && [ "$tot" -ge "$tot_ant" ]; then
      dt=$((tot - tot_ant))
      de=$((err - err_ant))
      if [ "$dt" -ge "$MIN_REQ" ]; then
        alta="$(awk -v e="$de" -v t="$dt" -v m="$TAXA_MAX" 'BEGIN { print (e / t > m) ? 1 : 0 }')"
        if [ "$alta" = 1 ] && [ "$taxa_alta" = 0 ]; then
          taxa_alta=1
          avisar "ATENCAO: $de de $dt respostas da API foram 5xx na ultima janela (limite $TAXA_MAX)."
        elif [ "$alta" = 0 ] && [ "$taxa_alta" = 1 ]; then
          taxa_alta=0
          avisar "RECUPERADO: a taxa de respostas 5xx voltou ao normal."
        fi
      fi
    fi
    tot_ant="$tot"
    err_ant="$err"
  fi

  ciclo=$((ciclo + 1))
  if [ "$CICLOS" -gt 0 ] && [ "$ciclo" -ge "$CICLOS" ]; then break; fi
  sleep "$INTERVALO"
done
