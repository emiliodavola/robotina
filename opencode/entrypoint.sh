#!/bin/sh
# Arranque del contenedor de opencode.
#
# Orden deliberado:
#   1. Artefactos de gentle-ai, generados en el build por SU instalador
#      (no copiados a mano al repo). Son autoritativos: se re-aplican en cada
#      arranque, asi que la forma de cambiarlos es el repo + rebuild.
#   2. Overlay propio (LSP, MCP del usuario, permisos) mergeado sobre eso.
#   3. engram serve, al lado del agente: el MCP y el CLI leen la base local y
#      el plugin habla con este HTTP en 127.0.0.1 — el mismo arreglo que en el
#      host de desarrollo.
#   4. exec opencode (con los args de compose: serve --hostname 0.0.0.0 ...).
set -eu

CONFIG_DIR="${HOME:-/root}/.config/opencode"
STAGED="/opt/gentle-ai-stage/.config/opencode"
OVERLAY="/opt/opencode-overlay.json"

mkdir -p "$CONFIG_DIR" "${ENGRAM_DATA_DIR:-/root/.engram}" /var/log

# 1. Artefactos de gentle-ai. node_modules y package-lock son estado del
#    runtime (opencode los administra): no se pisan.
if [ -d "$STAGED" ]; then
  for item in "$STAGED"/* "$STAGED"/.[!.]*; do
    [ -e "$item" ] || continue
    base="$(basename "$item")"
    case "$base" in
      # node_modules y package-lock son estado del runtime (opencode los
      # administra): no se pisan. El resto de los casos evita que un glob
      # vacio convierta el borrado en algo que no queremos.
      node_modules|package-lock.json) continue ;;
      ''|.|..) continue ;;
    esac
    rm -rf "${CONFIG_DIR:?}/$base"
    cp -a "$item" "${CONFIG_DIR:?}/$base"
  done
fi

# 2. Overlay propio: merge no destructivo. Las claves mias ganan; las de
#    gentle-ai (agents, default_agent, context7, engram) se preservan.
if [ -f "$OVERLAY" ]; then
  if [ -f "$CONFIG_DIR/opencode.json" ]; then
    jq -s '.[0] as $b | .[1] as $o
           | ($b * $o)
           | .mcp = (($b.mcp // {}) * ($o.mcp // {}))
           | .lsp = (($b.lsp // {}) * ($o.lsp // {}))' \
      "$CONFIG_DIR/opencode.json" "$OVERLAY" > /tmp/opencode.json.merged
    mv /tmp/opencode.json.merged "$CONFIG_DIR/opencode.json"
  else
    cp "$OVERLAY" "$CONFIG_DIR/opencode.json"
  fi
fi

# 3. engram: memoria persistente del agente del contenedor.
if command -v engram >/dev/null 2>&1; then
  engram serve > /var/log/engram.log 2>&1 &
fi

# 4. Aviso accionable si el workspace compartido no es escribible.
# Este contenedor corre con el uid de Hermes (10000) y el workspace es una
# carpeta del host: si se recreó, queda root:root 755 y ninguno de los dos
# agentes puede escribir. No se puede arreglar desde aca (haría falta root),
# asi que se avisa fuerte en vez de fallar en silencio mas tarde.
if [ ! -w /workspace ]; then
  echo "AVISO: /workspace no es escribible por uid $(id -u)." >&2
  echo "       En el host:  chmod 777 <HOST_DATA_DIR>/workspace  &&  docker compose up -d" >&2
fi

# 5. El agente.
exec opencode "$@"
