#!/bin/sh
# Oneshot de arranque de opencode. Corre como uid 10000 (Hermes) via
# `s6-setuidgid hermes`, asi que todo lo que escribe ya queda con el dueno
# correcto y no hace falta ningun chown posterior.
#
# Es el reemplazo de los pasos 1, 2 y 4 del entrypoint del contenedor opencode
# viejo. El orden es deliberado:
#
#   1. Artefactos de gentle-ai generados en el build por SU instalador
#      (/opt/gentle-ai-stage). Son autoritativos: se re-aplican en cada
#      arranque, asi que la forma de cambiarlos es el repo + rebuild.
#      node_modules y package-lock.json son estado del runtime (opencode los
#      administra) y no se pisan.
#   2. overlay.json propio, mergeado por clave y NO destructivo: las claves del
#      repo ganan, todo lo demas del opencode.json del usuario sobrevive. `mcp`
#      y `lsp` mergean por clave; `permission` se reemplaza ENTERO a proposito,
#      porque el bloque del overlay es una politica completa y un merge parcial
#      dejaria una regla vieja re-permitiendo algo que el repo niega.
#   3. Un opencode.json invalido se cuarentena con timestamp y el arranque
#      sigue: un archivo de estado roto no puede brickear el contenedor. Los
#      bytes del usuario se preservan para repararlos a mano.
#   4. Escritura ATOMICA: se mergea a un temporal DENTRO del directorio de
#      config (mismo filesystem, el mv es rename y no una copia) y recien ahi se
#      mueve a su lugar, para que ningun lector vea un JSON a medio escribir.
#   5. Aviso accionable si /workspace no es escribible. Con el cont-init propio
#      ya no deberia pasar; se mantiene como AVISO, nunca como fallo.
set -eu

CONFIG_DIR="${HOME:-/opt/data}/.config/opencode"
STAGED="/opt/gentle-ai-stage/.config/opencode"
OVERLAY="/opt/robotina/overlay.json"

mkdir -p "$CONFIG_DIR" "${ENGRAM_DATA_DIR:-$HOME/.engram}"

# 1. Artefactos de gentle-ai. El glob cubre tambien los dotfiles; el case evita
#    que un glob vacio convierta el borrado en algo que no queremos.
if [ -d "$STAGED" ]; then
  for item in "$STAGED"/* "$STAGED"/.[!.]*; do
    [ -e "$item" ] || continue
    base="$(basename "$item")"
    case "$base" in
      node_modules|package-lock.json) continue ;;
      ''|.|..) continue ;;
    esac
    rm -rf "${CONFIG_DIR:?}/$base"
    cp -a "$item" "${CONFIG_DIR:?}/$base"
  done
fi

# 2. Overlay propio: merge por clave, no destructivo.
if [ -f "$OVERLAY" ]; then
  target="$CONFIG_DIR/opencode.json"
  if [ ! -f "$target" ]; then
    # Sin base: el overlay se instala como archivo inicial.
    cp "$OVERLAY" "$target"
  elif ! jq -e . "$target" >/dev/null 2>&1; then
    # 3. JSON invalido: cuarentena, nunca fatal.
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    mv "$target" "$target.invalid-$stamp"
    echo "robotina: $target no era JSON valido; cuarentenado en $target.invalid-$stamp" >&2
    cp "$OVERLAY" "$target"
  else
    # 4. Escritura atomica dentro del directorio de config.
    tmp="$(mktemp "$CONFIG_DIR/.opencode.json.XXXXXX")"
    jq -s '.[0] as $b | .[1] as $o
           | ($b * $o)
           | .mcp = (($b.mcp // {}) * ($o.mcp // {}))
           | .lsp = (($b.lsp // {}) * ($o.lsp // {}))
           | if ($o.permission // null) != null then .permission = $o.permission else . end' \
      "$target" "$OVERLAY" > "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$target"
  fi
fi

# 5. Aviso de /workspace (nunca fallo: el oneshot no puede arreglarlo, solo
#    avisar fuerte para que no se descubra recien cuando falle una escritura).
if [ ! -w /workspace ]; then
  echo "AVISO: /workspace no es escribible por uid $(id -u)." >&2
  echo "       En el host:  chmod 777 <HOST_DATA_DIR>/workspace  &&  docker compose up -d" >&2
fi
