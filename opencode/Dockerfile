# syntax=docker/dockerfile:1
# =============================================================================
# Imagen de opencode para el stack robotina.
#
# Por que existe: la imagen oficial es Alpine pelado — sin node, npm, python,
# git ni curl. Todo lo que el agente necesita (servidores LSP, los MCP locales,
# engram y el instalador de gentle-ai) hay que instalarlo de forma
# reproducible. Lo que se instala aca es PROGRAMA; el estado (config, memoria,
# workspace) vive en carpetas del host que monta compose.
#
# Los artefactos de gentle-ai NO se copian a mano: los genera su propio
# instalador en un directorio de staging durante el build, y el entrypoint los
# aplica al arrancar. Actualizar gentle-ai = subir la version y reconstruir.
#
# Nota: el build corre en el host, FUERA del proxy de egreso. Es lo mismo que
# cualquier build de imagen; el trafico medido por Squid no incluye esto.
# =============================================================================
FROM ghcr.io/anomalyco/opencode:latest

ARG ENGRAM_VERSION=1.20.0
ARG GENTLE_AI_VERSION=3.1.0
ARG MARKSMAN_RELEASE=2026-02-08

# pipefail: la verificacion de checksums usa `grep ... | sha256sum -c -`. Sin
# esto, un grep que no matchea no corta el build y la verificacion podria pasar
# con entrada vacia.
SHELL ["/bin/sh", "-o", "pipefail", "-c"]

# --- runtimes y herramientas del agente --------------------------------------
# R viene con las toolchain porque languageserver se compila al instalarse.
RUN apk add --no-cache \
      bash curl git jq nodejs npm python3 py3-pip ripgrep tar xz \
      tzdata ca-certificates \
      R R-dev gcc g++ make gfortran libxml2-dev openssl-dev zlib-dev \
      linux-headers \
 && rm -rf /var/cache/apk/*

# --- LSP: json, dockerfile y python (versiones iguales a las del host) -------
RUN npm install -g --no-fund --no-audit --loglevel=error \
      vscode-langservers-extracted@4.10.0 \
      dockerfile-language-server-nodejs@0.15.0 \
      basedpyright@1.39.9 \
 && npm cache clean --force \
 && command -v vscode-json-language-server docker-langserver basedpyright-langserver

# --- LSP: toml ---------------------------------------------------------------
RUN apk add --no-cache taplo && command -v taplo

# --- LSP: marksman (el release musl trae el binario suelto) ------------------
RUN curl -fsSL -o /usr/local/bin/marksman \
      "https://github.com/artempyanykh/marksman/releases/download/${MARKSMAN_RELEASE}/marksman-linux-musl-x64" \
 && chmod 0755 /usr/local/bin/marksman \
 && test -x /usr/local/bin/marksman

# --- LSP: R (languageserver se compila; verifica que quede usable) -----------
# El arbol de dependencias de languageserver (fs, stringi, xml2, lintr, styler,
# roxygen2...) compila C/C++ contra libuv, ICU, curl y libxml2: sin estas
# librerias falla 'fs' con "fatal error: uv.h: No such file or directory" y la
# cadena entera cae con el. Alpine ademas trae R sin el indice HTML de paquetes.
RUN apk add --no-cache libuv-dev icu-dev curl-dev pkgconf \
 && mkdir -p /usr/share/doc/R/html
RUN R -q -e 'install.packages("languageserver", repos="https://cloud.r-project.org", Ncpus=4)' \
 && R -q -e 'stopifnot(requireNamespace("languageserver", quietly=TRUE))'

# --- herramientas de desarrollo ------------------------------------------------
# gh: ademas de CLI, es el credential helper de git para HTTPS. Con
# GITHUB_TOKEN en el entorno, gh lo toma sin necesidad de `gh auth login`.
RUN apk add --no-cache github-cli && gh --version

# Config de SISTEMA de git (programa, no estado): el helper de credenciales lee
# el token del entorno via gh, y las URLs SSH se reescriben a HTTPS porque el
# proxy de egreso solo permite CONNECT al puerto 443 — SSH por 22 es imposible
# aca. El archivo de config GLOBAL (identidad, preferencias) vive en el host,
# apuntado por GIT_CONFIG_GLOBAL desde compose.
RUN printf '[credential "https://github.com"]\n\thelper = !gh auth git-credential\n[url "https://github.com/"]\n\tinsteadOf = git@github.com:\n[init]\n\tdefaultBranch = main\n' > /etc/gitconfig \
 && git config --system --get-regexp 'credential|url|init'
# codegraph-linux-x64 empaqueta su propio runtime `node`, compilado contra
# glibc: en Alpine (musl) su loader no existe, el MCP muere con "MCP error
# -32000: Connection closed" y el wrapper reporta "node: not found" (el sintoma
# clasico de glibc sobre musl). Se lo apunta al node de Alpine, que es musl, y
# se borra el empaquetado para no arrastrar 123 MB inutiles.
RUN npm install -g --no-fund --no-audit --loglevel=error @colbymchenry/codegraph@1.5.0 \
 && d=/usr/local/lib/node_modules/@colbymchenry/codegraph/node_modules/@colbymchenry/codegraph-linux-x64 \
 && rm -f "$d/node" \
 && printf '#!/bin/sh\nexec /usr/bin/node "$@"\n' > "$d/node" \
 && chmod 0755 "$d/node" \
 && codegraph --version

# --- engram (memoria del agente): release verificado por checksum ------------
RUN set -eux; \
    f="engram_${ENGRAM_VERSION}_linux_amd64.tar.gz"; \
    base="https://github.com/Gentleman-Programming/engram/releases/download/v${ENGRAM_VERSION}"; \
    curl -fsSL -o "/tmp/${f}" "${base}/${f}"; \
    curl -fsSL -o /tmp/engram-checksums.txt "${base}/checksums.txt"; \
    cd /tmp; grep " ${f}\$" engram-checksums.txt | sha256sum -c -; \
    tar -xzf "${f}"; \
    install -m 0755 /tmp/engram /usr/local/bin/engram; \
    engram --version

# --- gentle-ai: el instalador (no una copia de sus archivos) -----------------
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

# --- artefactos de gentle-ai, generados por SU instalador en el build --------
# HOME apunta a un staging: el contenedor arranca con la config del host
# montada, y el entrypoint copia esto ahi. Asi el runtime no necesita red ni
# una instalacion manual, y lo que se aplica no se desincroniza del instalador.
RUN mkdir -p /opt/gentle-ai-stage \
 && timeout 900 env HOME=/opt/gentle-ai-stage CI=1 \
      gentle-ai install --scope global --channel stable --agents opencode \
 && echo "--- artefactos generados ---" \
 && find /opt/gentle-ai-stage -maxdepth 4 -mindepth 1 -print \
 && echo "--- fin de artefactos ---"

# --- configuracion propia (lo que NO gestiona gentle-ai) --------------------
COPY overlay.json /opt/opencode-overlay.json
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
