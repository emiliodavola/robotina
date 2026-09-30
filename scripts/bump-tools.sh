#!/bin/sh
# Resuelve la ultima version de las dependencias que el Dockerfile fija en ARG,
# y opcionalmente reescribe el pin.
#
#   scripts/bump-tools.sh                  # igual que --check
#   scripts/bump-tools.sh --check          # que pin quedo atrasado
#   scripts/bump-tools.sh --write engram   # reescribe el ARG de una herramienta
#   scripts/bump-tools.sh --write all      # reescribe todos los que esten atras
#
# Por que existe: Dependabot no puede con estas dependencias. Su parser `docker`
# resuelve tags de `FROM` y de `image:`, no valores de `ARG`, y no hay ecosistema
# para un tarball de release de GitHub. Sin este script, "actualizar" es
# acordarse de siete repos, siete tags, siete nombres de asset y una API mas
# (ver #52).
#
# Corre en el HOST, no adentro del contenedor: edita robotina/Dockerfile y
# consulta las APIs publicas, que son la red del build (fuera de Squid). La
# allowlist de egreso no participa.
#
# El pin SIGUE siendo explicito a proposito. Un build que resolviera "latest"
# por su cuenta dejaria de ser reproducible y haria que la pregunta "que version
# corre" no se pueda contestar ni desde la imagen ni desde el repo. La politica
# es: la ultima manda, y la ultima se escribe aca, en un commit que se lee.
#
# Salida: 0 si todos los pins estan al dia; 1 si alguno quedo atrasado o no se
# pudo verificar (sirve para gatear, no solo para mirar); 2 si el uso es invalido.
set -eu

DOCKERFILE="${DOCKERFILE:-robotina/Dockerfile}"
MODE="check"
TARGET=""

usage() {
  cat >&2 <<'EOF'
uso: scripts/bump-tools.sh [--check | --write <herramienta|all>] [-f DOCKERFILE]

  --check            (default) reporta que pins quedaron atrasados
  --write X          reescribe el ARG de X; `all` reescribe todos los atrasados
  -f DOCKERFILE      Dockerfile a inspeccionar (default robotina/Dockerfile)

Variables: DOCKERFILE  equivale a -f
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
  --check) MODE="check"; shift ;;
  --write)
    [ $# -ge 2 ] || { echo "bump-tools: --write necesita una herramienta" >&2; exit 2; }
    MODE="write"; TARGET="$2"; shift 2 ;;
  -f)
    [ $# -ge 2 ] || { echo "bump-tools: -f necesita una ruta" >&2; exit 2; }
    DOCKERFILE="$2"; shift 2 ;;
  -h | --help) usage; exit 0 ;;
  *) echo "bump-tools: opcion desconocida: $1" >&2; usage; exit 2 ;;
  esac
done

[ -f "$DOCKERFILE" ] || { echo "bump-tools: no existe $DOCKERFILE" >&2; exit 2; }

# nombre | tipo | fuente | ARG del Dockerfile
# El orden es el del bloque "versiones fijadas" del Dockerfile.
catalog() {
  cat <<'EOF'
engram github Gentleman-Programming/engram ENGRAM_VERSION
gentle-ai github Gentleman-Programming/gentle-ai GENTLE_AI_VERSION
marksman github artempyanykh/marksman MARKSMAN_RELEASE
gh github cli/cli GH_VERSION
taplo github tamasfe/taplo TAPLO_VERSION
opencode-ai npm opencode-ai OPENCODE_VERSION
huggingface-hub pypi huggingface_hub HUGGINGFACE_HUB_VERSION
EOF
}

if [ "$MODE" = "write" ] && [ "$TARGET" != "all" ]; then
  if ! catalog | awk '{print $1}' | grep -qx -- "$TARGET"; then
    echo "bump-tools: herramienta desconocida: $TARGET" >&2
    echo "bump-tools: conocidas: $(catalog | awk '{print $1}' | tr '\n' ' ')" >&2
    exit 2
  fi
fi

pinned_of() {
  sed -n "s/^ARG ${1}=//p" "$DOCKERFILE" | head -1
}

# Ultima version publicada, sin la `v` inicial de los tags de GitHub.
# Cadena vacia = no se pudo verificar; el caller lo trata como tal, nunca como
# "esta al dia".
latest_of() {
  kind="$1"
  src="$2"
  case "$kind" in
  github)
    curl -fsSL -m 20 "https://api.github.com/repos/$src/releases/latest" 2>/dev/null |
      tr -d '\n' |
      sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p'
    ;;
  npm)
    # `dist-tags` es un documento chico y plano: no tiene versiones de
    # dependencias anidadas que puedan confundir al parser.
    curl -fsSL -m 20 "https://registry.npmjs.org/-/package/$src/dist-tags" 2>/dev/null |
      tr -d '\n' |
      sed -n 's/.*"latest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
    ;;
  pypi)
    # `info.version` del JSON de PyPI ya es la ultima version ESTABLE: una
    # pre-release no la reemplaza mientras exista una estable. El `sed` greedy
    # toma la ULTIMA aparicion de la clave en el documento (medido: es la
    # unica), igual que la rama de GitHub de arriba.
    curl -fsSL -m 20 "https://pypi.org/pypi/$src/json" 2>/dev/null |
      tr -d '\n' |
      sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
    ;;
  esac
}

write_pin() {
  name="$1"
  arg="$2"
  new="$3"
  old="$(pinned_of "$arg")"
  if [ -z "$old" ]; then
    echo "  $name: no se encontro ARG $arg en $DOCKERFILE" >&2
    return 1
  fi
  if [ "$old" = "$new" ]; then
    echo "  $name: ya esta en $new"
    return 0
  fi
  tmp="$(mktemp)"
  sed "s|^ARG ${arg}=.*|ARG ${arg}=${new}|" "$DOCKERFILE" >"$tmp"
  # `cat >` y no `mv`: conserva el archivo y su modo en lugar de reemplazarlo.
  cat "$tmp" >"$DOCKERFILE"
  rm -f "$tmp"
  echo "  $name: $old -> $new"
  case "$arg" in
  TAPLO_VERSION)
    echo "    AVISO: taplo no publica checksums.txt en su release; hay que refrescar"
    echo "           TAPLO_SHA256 a mano (el build falla si no coincide)."
    ;;
  GENTLE_AI_VERSION)
    echo "    AVISO: gentle-ai regenera el arbol de agentes y skills en el build."
    echo "           Ese bump pide su propia verificacion; no alcanza con mover el pin."
    ;;
  HUGGINGFACE_HUB_VERSION)
    echo "    AVISO: el pin es de huggingface_hub, no del paquete hf: las ruedas"
    echo "           de hf >= 1.32.0 declaran 'Dynamic: requires-dist' y uv no las"
    echo "           resuelve. No cambies el pin al paquete hf."
    ;;
  esac
}

[ "$MODE" = "write" ] && echo "bump-tools: escribiendo en $DOCKERFILE"

list="$(mktemp)"
catalog >"$list"
behind=0
unknown=0

# Se lee desde un archivo y no desde una tuberia: con `catalog | while` el bucle
# corre en un subshell y los contadores se perderian al salir.
while read -r name kind src arg; do
  [ -n "$name" ] || continue
  pinned="$(pinned_of "$arg")"
  latest="$(latest_of "$kind" "$src")"

  if [ -z "$pinned" ]; then
    printf '%-12s %-10s %s\n' "$name" "-" "sin ARG $arg en $DOCKERFILE"
    unknown=$((unknown + 1))
    continue
  fi
  if [ -z "$latest" ]; then
    printf '%-12s %-10s %s\n' "$name" "$pinned" "no se pudo consultar la ultima ($src)"
    unknown=$((unknown + 1))
    continue
  fi
  if [ "$pinned" = "$latest" ]; then
    printf '%-12s %-10s %s\n' "$name" "$pinned" "al dia"
    continue
  fi

  printf '%-12s %-10s -> %-10s %s\n' "$name" "$pinned" "$latest" "ATRASADO ($src)"
  behind=$((behind + 1))
  if [ "$MODE" = "write" ] && { [ "$TARGET" = "all" ] || [ "$TARGET" = "$name" ]; }; then
    write_pin "$name" "$arg" "$latest" || true
  fi
done <"$list"
rm -f "$list"

echo "---"
if [ "$behind" -gt 0 ] || [ "$unknown" -gt 0 ]; then
  echo "bump-tools: $behind atrasado(s), $unknown sin verificar"
  exit 1
fi
echo "bump-tools: todos los pins al dia"
exit 0
