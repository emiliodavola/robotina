#!/bin/sh
# Exporta a JSON, en una carpeta del host, el estado que vive en volumenes
# nativos de Docker.
#
# Por que existe: las bases de opencode (sesiones) y de engram (memoria) usan
# SQLite en modo WAL, y WAL sobre una carpeta de Windows (virtiofs/9p) puede
# corromperse en silencio, como avisa el propio Hermes. Por eso esas dos bases
# viven en volumenes nativos, donde WAL es seguro. Este script devuelve ese
# estado al host en un formato que si es portable y legible: JSON.
#
# Se ejecuta DENTRO del contenedor de opencode (ahi viven los dos CLIs):
#   docker compose exec opencode sh /opt/export-state.sh
#
# Escribe en /backups, que compose monta sobre ${HOST_DATA_DIR}/backups.
set -eu

DEST="${1:-/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"

echo "== engram (memoria) =="
if command -v engram >/dev/null 2>&1; then
  engram export "$DEST/engram-$STAMP.json" | tail -3
else
  echo "engram no está disponible"
fi

echo "== opencode (sesiones) =="
# El server local exige Basic si OPENCODE_SERVER_PASSWORD esta seteado. Con
# parametros posicionales el password sobrevive cualquier caracter.
set --
[ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"

ids="$(curl -s "$@" --max-time 30 http://127.0.0.1:4096/session \
        | grep -o '"id":"ses_[^"]*"' | cut -d'"' -f4 || true)"

if [ -z "$ids" ]; then
  echo "sin sesiones para exportar"
else
  for sid in $ids; do
    if opencode export "$sid" > "$DEST/opencode-$sid-$STAMP.json" 2>/dev/null; then
      echo "  exportada $sid"
    else
      echo "  fallo la exportacion de $sid"
    fi
  done
fi

echo "== resultado en $DEST =="
for f in "$DEST"/*.json; do
  [ -e "$f" ] || continue
  echo "  $(basename "$f")"
done
