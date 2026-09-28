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
# Se ejecuta DENTRO del contenedor unico `robotina` (ahi viven los dos CLIs):
#   docker compose exec robotina sh /opt/export-state.sh
# En Git Bash hay que anteponer MSYS_NO_PATHCONV=1: sin eso la ruta /opt/... se
# reescribe a C:/Program Files/Git/opt/... y el comando muere.
#
# Escribe en /backups, que compose monta sobre ${HOST_DATA_DIR}/backups.
set -eu

DEST="${1:-/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"

# Se levanta al final: un respaldo vacio no es un respaldo, pero un problema de
# engram no tiene que esconder la exportacion de las sesiones.
engram_empty=0

echo "== engram (memoria) =="
# `--all` NO es opcional. En 2.x `engram export` (y `stats`) estan scopeados al
# proyecto que se detecta del cwd, y el cwd de Hermes (/opt/data) no tiene
# memorias propias: sin el flag, el respaldo son 135 bytes de arreglos vacios,
# escritos con exito y en silencio. Medido el 2026-09-28 (issue #58).
if command -v engram >/dev/null 2>&1; then
  out="$DEST/engram-$STAMP.json"
  engram export "$out" --all | tail -3
  n="$(jq -r '(.observations // []) | length' "$out" 2>/dev/null || echo '?')"
  case "$n" in
  0)
    engram_empty=1
    echo "AVISO: el export de engram quedo VACIO ($out)." >&2
    echo "       Un export vacio suele ser scope por proyecto: revisa el flag --all." >&2
    ;;
  \?)
    echo "AVISO: no se pudieron contar las observaciones de $out (falta jq)." >&2
    ;;
  *)
    echo "engram: $n observaciones exportadas"
    ;;
  esac
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

if [ "$engram_empty" = 1 ]; then
  echo "export-state: el cerebro de engram salio vacio; el respaldo NO esta completo" >&2
  exit 1
fi
