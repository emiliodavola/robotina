#!/bin/sh
# Healthcheck del unico contenedor de agentes. Es OBSERVABILIDAD, no
# recuperacion: `restart: unless-stopped` actua sobre la salida de PID 1, no
# sobre el health status, asi que este script no reinicia nada. Su valor es que
# `docker compose ps` deje de ser ciego a un opencode o un engram caidos en
# crash loop mientras Hermes sigue vivo.
#
# Tres comprobaciones:
#   1. El endpoint local de opencode responde. La sonda es CREDENCIAL-AWARE: si
#      OPENCODE_SERVER_PASSWORD esta definido, manda la credencial; si esta
#      vacio, va sin ella. No imprime el secreto en ningun caso.
#   2. Existe un proceso `engram serve`. El patron usa una clase de caracteres
#      ([e]ngram) para que el regex no matchee la linea de comandos de este
#      propio script: un match vacio es un FAIL, nunca un pass.
#   3. El engram que CORRE es el que la imagen fijo: el del servicio (ruta
#      absoluta) y el que resuelve el PATH, que es el que usan el servidor MCP y
#      el export de estado. No es teorico: habia 2.1.0 corriendo desde el HOME
#      del agente sobre un pin de 1.20.0 y nada lo delataba (#42).
set -eu

url=http://127.0.0.1:4096/global/health
if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  curl -fsS -m 4 -u "opencode:$OPENCODE_SERVER_PASSWORD" "$url" >/dev/null
else
  curl -fsS -m 4 "$url" >/dev/null
fi

pgrep -f "[e]ngram serve" >/dev/null

# --- 3. engram: lo que corre contra lo que la imagen dice que fijo -----------
# `ROBOTINA_ENGRAM_VERSION` la publica el Dockerfile desde el ARG. Un contenedor
# viejo tambien falla aca, y eso es correcto: la imagen en ejecucion no coincide
# con el pin que el repo cree que fijo.
if [ -n "${ROBOTINA_ENGRAM_VERSION:-}" ]; then
  pinned="$ROBOTINA_ENGRAM_VERSION"
  # Anclado al formato completo (`engram X.Y.Z`): las versiones viejas imprimen
  # ademas un banner de actualizacion en stdout, y el ancla evita leer el
  # numero del banner. `tail -1` porque la linea de version va al final.
  running="$(/usr/local/bin/engram --version 2>/dev/null | tr -d '\r' |
    sed -n 's/^engram[[:space:]]\{1,\}\([^[:space:]]*\)$/\1/p' | tail -1)"
  if [ "$running" != "$pinned" ]; then
    echo "healthcheck: /usr/local/bin/engram reporta '${running:-desconocido}' y la imagen fijo $pinned" >&2
    exit 1
  fi
  resolved="$(command -v engram 2>/dev/null || true)"
  if [ "$resolved" != "/usr/local/bin/engram" ]; then
    echo "healthcheck: el PATH resuelve '${resolved:-nada}' en lugar de /usr/local/bin/engram: una copia en el HOME del agente esta ensombreciendo el binario de la imagen. Cuarentenala (mv, no rm) y volve a correr el healthcheck." >&2
    exit 1
  fi
fi
