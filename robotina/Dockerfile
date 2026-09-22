# syntax=docker/dockerfile:1
# =============================================================================
# Imagen de robotina: un unico contenedor de agentes.
#
# Por que existe: la imagen vendor de Hermes (Debian trixie, glibc, s6-overlay)
# ya trae node, npm, uv, git, curl, python3, bash, tar, xz, procps y las
# librerias base — no hay que reinstalar nada de eso. La imagen pelada de
# opencode (Alpine/musl) queda superada. Este Dockerfile NO rearma la base:
# DERIVA de la vendor de Hermes y le agrega la toolchain que tenia la imagen de
# opencode (opencode serve, los LSP, gh, codegraph, engram, gentle-ai, R, go).
#
# Direccion de la fusion: opencode SOBRE Hermes, nunca al reves. La razon es
# dura y no negociable: el arbol de Hermes es glibc y s6-overlay esta compilado
# para Debian; el binario de opencode se elige glibc a proposito (ver la
# asercion de abajo). Invertirla significaria arrastrar musl por todos lados.
#
# Que NO hace este build, a proposito:
#   - No pisa ENTRYPOINT ni setea CMD: el entrypoint vendor tiene que seguir
#     siendo PID 1 y el Cmd vacio deja que compose mande `gateway run`.
#   - No escribe nada dentro de /opt/hermes/** (la clave de opencode viaja por
#     entorno, jamas parcheando un archivo del vendor).
#   - No crea /usr/local/bin/python3: el venv de Hermes no se ensombrece (ver UV
#     mas abajo).
#
# Nota: el build corre en el host, FUERA del proxy de egreso. Es lo mismo que
# cualquier build de imagen; el trafico medido por Squid no incluye esto.
# =============================================================================
FROM nousresearch/hermes-agent:latest

# --- versiones fijadas --------------------------------------------------------
# Las tres primeras vienen de la imagen de opencode anterior (paridad). Las tres
# siguientes son nuevas y se fijan para que el merge sea reproducible: el
# binario de opencode cambia de assets entre releases (riesgo glibc/musl).
ARG ENGRAM_VERSION=1.20.0
ARG GENTLE_AI_VERSION=3.1.0
ARG MARKSMAN_RELEASE=2026-02-08
ARG OPENCODE_VERSION=1.18.32
ARG GH_VERSION=2.97.0
ARG TAPLO_VERSION=0.10.0
# taplo no publica checksums.txt en su release: el pin es este sha256, medido
# sobre taplo-linux-x86_64.gz de la version de arriba.
ARG TAPLO_SHA256=8fe196b894ccf9072f98d4e1013a180306e17d244830b03986ee5e8eabeb6156

# pipefail: las verificaciones de checksum usan `grep ... | sha256sum -c -`.
# Sin esto, un grep que no matchea no corta el build y la verificacion podria
# pasar con entrada vacia. dash (el /bin/sh de Debian) no tiene pipefail.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- 1. toolchain que la vendor NO trae ---------------------------------------
# Lo que YA esta y no se reinstala: bash, tar, xz, tzdata, ca-certificates,
# node, npm, uv, git, curl, python3, procps (ps/pgrep/pkill), ripgrep.
# Lo que falta de verdad: jq (merge del overlay), go (paridad de toolchain),
# iproute2 (ss, la sonda de bind de EP1), R + toolchain de compilacion (el LSP
# de R) y las libs de desarrollo que languageserver compila en su cadena
# (fs/stringi/xml2): sin libuv-dev la cadena entera cae con "uv.h not found".
# ripgrep y procps quedan en la lista a proposito: reinstalarlos es un no-op de
# apt y garantiza el inventario aunque la base cambie.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      jq ripgrep procps iproute2 golang-go \
      r-base r-base-dev \
      gcc g++ gfortran make pkg-config \
      libxml2-dev libssl-dev zlib1g-dev libuv1-dev libicu-dev libcurl4-openssl-dev \
 && rm -rf /var/lib/apt/lists/* \
 && command -v jq rg go ss R gcc g++ gfortran make

# --- 2. opencode (asset glibc) + asercion de asset ---------------------------
# Este es el item que decide la fusion. opencode-ai publica assets por
# plataforma y libc (opencode-linux-x64 y opencode-linux-x64-musl): sobre esta
# base glibc tiene que quedar el asset x64 y NINGUNO musl. Un loader equivocado
# muere en la primera ejecucion, asi que la asercion corre en el build, no en un
# probe posterior.
#
# Desvio medido respecto del design §2.6 paso 3: aquel chequeo
# (`! grep -qs 'ld-musl' "$bin"`) no sirve por dos motivos independientes.
# (a) El binario es un ELF de Bun que EMBEBE los nombres de los loaders musl
#     (ld-musl-x86_64.so.1 / ld-musl-aarch64.so.1) como strings: el grep siempre
#     matchea aunque el binario sea glibc. (b) Bajo `set -e`, un `! cmd` que
#     falla NO corta el build (errexit se suprime en comandos negados), asi que
#     la asercion era un no-op que nunca podia fallar.
# Se assertea en positivo, que es lo que el design queria probar: el binario
# resuelto de `opencode` es EL MISMO archivo (mismo inode) que el asset x64, y su
# interprete real es el loader de glibc.
RUN npm install -g --no-fund --no-audit --loglevel=error \
      "opencode-ai@${OPENCODE_VERSION}" \
 && npm cache clean --force
RUN set -eux; \
    opencode --version | grep -F "${OPENCODE_VERSION}"; \
    g="$(npm root -g)"; \
    test -z "$(find "$g" -maxdepth 3 -path '*opencode-linux-musl*' -print)"; \
    x64="$(find "$g" -maxdepth 5 -path '*opencode-linux-x64/bin/opencode' -print -quit)"; \
    test -n "$x64"; \
    bin="$(readlink -f "$(command -v opencode)")"; \
    test "$bin" -ef "$x64"; \
    ldd "$bin" | grep -q 'ld-linux-x86-64'; \
    echo "robotina: opencode ${OPENCODE_VERSION} es el asset glibc x64 (mismo inode que $x64)"

# --- 3. LSP + taplo + marksman + R languageserver ----------------------------
# Los tres npm con los mismos pins del contenedor anterior (paridad).
RUN npm install -g --no-fund --no-audit --loglevel=error \
      vscode-langservers-extracted@4.10.0 \
      dockerfile-language-server-nodejs@0.15.0 \
      basedpyright@1.39.9 \
 && npm cache clean --force \
 && command -v vscode-json-language-server docker-langserver basedpyright-langserver

# taplo: release de upstream verificado por el sha256 fijado arriba.
RUN set -eux; \
    curl -fsSL -o /tmp/taplo.gz \
      "https://github.com/tamasfe/taplo/releases/download/${TAPLO_VERSION}/taplo-linux-x86_64.gz"; \
    echo "${TAPLO_SHA256}  /tmp/taplo.gz" | sha256sum -c -; \
    gunzip -c /tmp/taplo.gz > /usr/local/bin/taplo; \
    chmod 0755 /usr/local/bin/taplo; \
    taplo --version

# marksman: se mantiene el pin que ya tenia la imagen de opencode, pero se usa
# el asset GLIBC, no el musl. Medido en este build: marksman-linux-musl-x64 es
# dinamico contra el loader musl y sobre la base glibc muere con "cannot
# execute: required file not found"; el design lo daba por estatico y no lo es.
# El asset glibc es un binario .NET self-contained y necesita libicu, que ya
# instala el paso 1 (libicu-dev) — sin esa lib falla con "Couldn't find a valid
# ICU package".
RUN curl -fsSL -o /usr/local/bin/marksman \
      "https://github.com/artempyanykh/marksman/releases/download/${MARKSMAN_RELEASE}/marksman-linux-x64" \
 && chmod 0755 /usr/local/bin/marksman \
 && test -x /usr/local/bin/marksman \
 && marksman --version

# R languageserver se compila en el build (no hay paquete). El arbol de
# dependencias (fs, stringi, xml2, lintr, styler, roxygen2...) compila C/C++
# contra libuv, ICU, curl y libxml2 — de ahi las libs-*-dev del paso 1.
RUN mkdir -p /usr/share/doc/R/html \
 && R -q -e 'install.packages("languageserver", repos="https://cloud.r-project.org", Ncpus=4)' \
 && R -q -e 'stopifnot(requireNamespace("languageserver", quietly=TRUE))'

# --- 4. gh (CLI + credential helper de git), release + checksum --------------
RUN set -eux; \
    f="gh_${GH_VERSION}_linux_amd64.tar.gz"; \
    base="https://github.com/cli/cli/releases/download/v${GH_VERSION}"; \
    curl -fsSL -o "/tmp/${f}" "${base}/${f}"; \
    curl -fsSL -o /tmp/gh-checksums.txt "${base}/gh_${GH_VERSION}_checksums.txt"; \
    cd /tmp; grep " ${f}\$" gh-checksums.txt | sha256sum -c -; \
    tar -xzf "${f}"; \
    install -m 0755 "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh; \
    gh --version

# --- 5. codegraph (MCP) ------------------------------------------------------
# codegraph-linux-x64 empaqueta su PROPIO runtime `node` compilado contra glibc.
# Sobre la base Debian ese runtime es el correcto, asi que NO se borra ni se
# reemplaza por un shim (eso era el arreglo para musl, y hacerlo aca rompe el
# MCP: el wrapper resuelve `node` al lado suyo). Consecuencia aceptada: ~123 MB
# de runtime duplicado que se quedan en la imagen.
RUN npm install -g --no-fund --no-audit --loglevel=error \
      @colbymchenry/codegraph@1.5.0 \
 && npm cache clean --force \
 && codegraph --version

# --- 6. uv + CPython 3.13 fuera de toda montura ------------------------------
# UV_* apuntan a /opt/uv, una ruta de IMAGEN que ninguna montura tapa (la
# alternativa, /opt/data/.local/share/uv, queda ensombrecida por el bind de
# Hermes en runtime y perderia el interprete horneado, forzando una descarga
# que la allowlist de egreso no admite). `python3`/`python` se exponen en
# /opt/uv/bin. El PATH se APPENDEA (nunca se prependea) para que el venv de
# Hermes conserve prioridad.
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_TOOL_DIR=/opt/uv/tools \
    UV_TOOL_BIN_DIR=/opt/uv/bin \
    UV_LINK_MODE=copy \
    UV_PYTHON_PREFERENCE=only-managed
RUN uv python install 3.13 \
 && p="$(uv python find 3.13)" \
 && install -d /opt/uv/bin \
 && ln -sf "$p" /opt/uv/bin/python3 \
 && ln -sf "$p" /opt/uv/bin/python \
 && /opt/uv/bin/python3 --version \
 && uv python list --only-installed

# PATH se appendea: /opt/uv/bin va DESPUES de /opt/hermes/.venv/bin.
ENV PATH=$PATH:/opt/uv/bin

# --- 7. engram (memoria del agente): release + checksum ----------------------
RUN set -eux; \
    f="engram_${ENGRAM_VERSION}_linux_amd64.tar.gz"; \
    base="https://github.com/Gentleman-Programming/engram/releases/download/v${ENGRAM_VERSION}"; \
    curl -fsSL -o "/tmp/${f}" "${base}/${f}"; \
    curl -fsSL -o /tmp/engram-checksums.txt "${base}/checksums.txt"; \
    cd /tmp; grep " ${f}\$" engram-checksums.txt | sha256sum -c -; \
    tar -xzf "${f}"; \
    install -m 0755 /tmp/engram /usr/local/bin/engram; \
    engram --version

# --- 8. gentle-ai (el instalador, no una copia de sus archivos) --------------
# Los artefactos de gentle-ai NO se copian a mano: los genera su propio
# instalador en un staging durante el build, y el oneshot opencode-init los
# aplica al arrancar. Actualizar gentle-ai = subir la version y reconstruir.
RUN set -eux; \
    f="gentle-ai_${GENTLE_AI_VERSION}_linux_amd64.tar.gz"; \
    base="https://github.com/Gentleman-Programming/gentle-ai/releases/download/v${GENTLE_AI_VERSION}"; \
    curl -fsSL -o "/tmp/${f}" "${base}/${f}"; \
    curl -fsSL -o /tmp/ga-checksums.txt "${base}/checksums.txt"; \
    cd /tmp; grep " ${f}\$" ga-checksums.txt | sha256sum -c -; \
    mkdir -p /tmp/ga; tar -xzf "${f}" -C /tmp/ga; \
    bin="$(find /tmp/ga -maxdepth 3 -type f -name gentle-ai -print -quit)"; \
    test -n "$bin"; install -m 0755 "$bin" /usr/local/bin/gentle-ai; \
    gentle-ai --version
RUN mkdir -p /opt/gentle-ai-stage \
 && timeout 900 env HOME=/opt/gentle-ai-stage CI=1 \
      gentle-ai install --scope global --channel stable --agents opencode \
 && echo "--- artefactos generados ---" \
 && find /opt/gentle-ai-stage -maxdepth 4 -mindepth 1 -print \
 && echo "--- fin de artefactos ---"

# --- 9. /etc/gitconfig: preservar y despues mergear ---------------------------
# El config de SISTEMA de git es programa, no estado: el helper de credenciales
# lee el token del entorno via gh, y las URLs SSH se reescriben a HTTPS porque
# el proxy de egreso solo permite CONNECT al 443. El config GLOBAL (identidad,
# preferencias) vive en el host via GIT_CONFIG_GLOBAL.
#
# Nunca se pisa el archivo: si la base vendor trae /etc/gitconfig, se copia a
# /etc/gitconfig.vendor (una sola vez) y despues se escriben SOLO nuestras
# claves con `git config --system`, asi ninguna clave del vendor se pierde. Al
# final se verifica que toda clave del vendor siga presente y se registra su
# sha256 en el log del build.
RUN set -eux; \
    if [ -f /etc/gitconfig ]; then cp -a /etc/gitconfig /etc/gitconfig.vendor; fi; \
    git config --system credential.https://github.com.helper '!gh auth git-credential'; \
    git config --system url.https://github.com/.insteadOf 'git@github.com:'; \
    git config --system init.defaultBranch main; \
    git config --system --list; \
    if [ -f /etc/gitconfig.vendor ]; then \
      git config --system --name-only --list | sort -u > /tmp/gitconfig.after.keys; \
      git config --file /etc/gitconfig.vendor --name-only --list | sort -u > /tmp/gitconfig.vendor.keys; \
      test -z "$(comm -23 /tmp/gitconfig.vendor.keys /tmp/gitconfig.after.keys)"; \
      echo "robotina: claves vendor preservadas ($(wc -l < /tmp/gitconfig.vendor.keys))"; \
      sha256sum /etc/gitconfig.vendor; \
    else \
      echo "robotina: la base vendor no trae /etc/gitconfig; no hay nada que preservar"; \
    fi

# --- 10 y 11. archivos propios: overlay, oneshot, healthcheck y arbol s6 ----
# Todo el contexto de build entra en un unico COPY y un RUN lo instala en sus
# rutas definitivas. Se hace asi (y no con un `COPY s6/` literal) porque el
# arbol s6 lo entrega el slice de supervision: con COPY por directorio el build
# de este slice no resolveria. El bloque del arbol s6 es condicional: cuando el
# arbol exista, se instala y se valida; mientras no exista, no hay nada que
# instalar y el paso lo dice explicitamente.
COPY . /opt/robotina-src/
RUN set -eux; \
    install -d /opt/robotina; \
    install -m 0644 /opt/robotina-src/overlay.json /opt/robotina/overlay.json; \
    install -m 0755 /opt/robotina-src/opencode-init.sh /opt/robotina/opencode-init.sh; \
    install -m 0755 /opt/robotina-src/healthcheck.sh /opt/robotina/healthcheck.sh; \
    sh -n /opt/robotina/opencode-init.sh; \
    sh -n /opt/robotina/healthcheck.sh; \
    if [ -d /opt/robotina-src/s6/cont-init.d ]; then \
      for f in /opt/robotina-src/s6/cont-init.d/*; do \
        [ -f "$f" ] || continue; \
        sh -n "$f"; \
        install -m 0755 "$f" "/etc/cont-init.d/$(basename "$f")"; \
      done; \
      echo "robotina: cont-init.d propio instalado"; \
    fi; \
    if [ -d /opt/robotina-src/s6/s6-rc.d ]; then \
      cp -a /opt/robotina-src/s6/s6-rc.d/. /etc/s6-overlay/s6-rc.d/; \
      for d in /opt/robotina-src/s6/s6-rc.d/*/; do \
        n="$(basename "$d")"; \
        if [ "$n" = "user2" ]; then continue; fi; \
        t="$(cat "$d/type")"; \
        case "$t" in \
          longrun) s="$d/run" ;; \
          oneshot) s="$d/up" ;; \
          *) echo "robotina: type invalido en $n: $t" >&2; exit 1 ;; \
        esac; \
        test -f "$s"; chmod 0755 "$s"; sh -n "$s"; \
      done; \
      echo "robotina: arbol s6 propio instalado y validado"; \
    fi

# --- 12. aserciones finales ---------------------------------------------------
# La suite de verificacion del cambio (39 requisitos) asume TODO este
# inventario. Una herramienta faltante tiene que fallar el BUILD, no un probe.
RUN set -eux; \
    command -v gh jq rg go opencode taplo marksman codegraph engram gentle-ai \
                uv node npm python3 R pgrep pkill ss curl git; \
    gh --version; \
    jq --version; \
    rg --version | head -1; \
    go version; \
    opencode --version; \
    taplo --version; \
    marksman --version; \
    codegraph --version; \
    engram --version; \
    gentle-ai --version; \
    uv --version; \
    node --version; \
    npm --version; \
    python3 --version; \
    R --version | head -1; \
    ss -V; \
    git --version; \
    echo "robotina: inventario de herramientas OK"

# Sin ENTRYPOINT y sin CMD a proposito: el entrypoint vendor tiene que seguir
# siendo PID 1 y el Cmd vacio deja que compose mande ["gateway", "run"].
