#!/bin/sh
# =============================================================================
# Compuerta de readiness de opencode (Q2 / EP4).
#
# Vive en la imagen y no en el `up` del oneshot porque s6-rc ejecuta los `up`
# como scripts de EXECLINE, no de shell: un shebang o un `set` inicial se
# interpretan como el programa a ejecutar y el servicio muere con exit 127. El
# `up` de opencode-ready es entonces UNA linea execline que invoca este archivo
# por ruta absoluta; toda la logica (con su comentario y su loop) vive aca.
#
# Es la unica compuerta del arranque: s6-rc levanta todo el arbol ANTES de que
# main-wrapper.sh ejecute el CMD, asi que una compuerta satisfecha significa que
# la primera delegacion de Hermes no puede competir con el bind del puerto. El
# estado "started" de s6 NO se trata como "listening".
#
# La sonda es credential-aware: si OPENCODE_SERVER_PASSWORD esta definida, manda
# la misma autenticacion que usa el healthcheck; si esta vacia, sonda sin `-u`
# (el servidor queda sin autenticar). Cota dura: 60 intentos x 2 s = 120 s.
# =============================================================================
set -u

url=http://127.0.0.1:4096/global/health
i=0
while [ "$i" -lt 60 ]; do
  if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
    curl -fsS -m 2 -u "opencode:$OPENCODE_SERVER_PASSWORD" "$url" >/dev/null 2>&1 \
      && { echo "robotina: opencode listo (intentos=$i)" >&2; exit 0; }
  else
    curl -fsS -m 2 "$url" >/dev/null 2>&1 \
      && { echo "robotina: opencode listo (intentos=$i)" >&2; exit 0; }
  fi
  i=$((i+1)); sleep 2
done
echo "robotina: ERROR: opencode serve no respondio en 120 s; el contenedor no arranca degradado" >&2
exit 1
