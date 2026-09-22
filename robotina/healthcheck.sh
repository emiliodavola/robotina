#!/bin/sh
# Healthcheck del unico contenedor de agentes. Es OBSERVABILIDAD, no
# recuperacion: `restart: unless-stopped` actua sobre la salida de PID 1, no
# sobre el health status, asi que este script no reinicia nada. Su valor es que
# `docker compose ps` deje de ser ciego a un opencode o un engram caidos en
# crash loop mientras Hermes sigue vivo.
#
# Dos comprobaciones:
#   1. El endpoint local de opencode responde. La sonda es CREDENCIAL-AWARE: si
#      OPENCODE_SERVER_PASSWORD esta definido, manda la credencial; si esta
#      vacio, va sin ella. No imprime el secreto en ningun caso.
#   2. Existe un proceso `engram serve`. El patron usa una clase de caracteres
#      ([e]ngram) para que el regex no matchee la linea de comandos de este
#      propio script: un match vacio es un FAIL, nunca un pass.
set -eu

url=http://127.0.0.1:4096/global/health
if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  curl -fsS -m 4 -u "opencode:$OPENCODE_SERVER_PASSWORD" "$url" >/dev/null
else
  curl -fsS -m 4 "$url" >/dev/null
fi

pgrep -f "[e]ngram serve" >/dev/null
