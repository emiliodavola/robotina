# Robotina

[Español](README.md) · [English](README.en.md)

Dos agentes autónomos, cada uno en su contenedor, sobre un workspace
compartido y **sin ruta directa a Internet**: todo su egreso pasa por un proxy
Squid que solo deja salir una lista blanca de dominios.

| Pieza | Qué es |
| --- | --- |
| **hermes** | Gateway de Telegram (`nousresearch/hermes-agent`). Recibe pedidos por chat y los ejecuta o los delega. |
| **opencode** | Servidor HTTP de código, headless (`ghcr.io/anomalyco/opencode`, extendido por `opencode/Dockerfile`). No tiene TUI ni puerto publicado. |
| **egress-proxy** | Squid con allowlist de dominios. Es el único contenedor con salida. |
| **Modelo de seguridad** | [`SECURITY.md`](SECURITY.md) — garantías, mediciones y riesgos residuales. |

## Arquitectura

```text
                    host: ${HOST_DATA_DIR}/
                    ├── hermes/     (config y sesiones de Hermes)
                    ├── workspace/  (el código que ven los dos agentes)
                    ├── opencode/   (config, plugins, skills de gentle-ai)
                    ├── backups/    (exports JSON del estado en volumen)
                    ├── git/        (config global de git)
                    └── go/         (GOPATH)

                    volúmenes nativos de Docker
                    ├── robotina_opencode_db   (sesiones de opencode — WAL)
                    └── robotina_engram_db     (memoria del agente  — WAL)

  red "agents" (internal: true, SIN gateway: no hay salida ni DNS externo)
  ┌────────────────┐   ┌────────────────┐   ┌────────────────┐
  │     hermes     │   │    opencode    │   │  egress-proxy  │
  │  gateway de    │──▶│  :4096 (HTTP)  │   │  squid :3128   │
  │  Telegram      │   │  sin TUI       │   │  uid 13, rootfs│
  │  uid 10000     │   │  uid 10000     │   │  read-only     │
  └────────────────┘   └────────────────┘   └───────┬────────┘
        │                     │                     │
        └── /workspace compartido (bind del host) ──┘
                                                    │  red "egress" (con gateway)
                                                    ▼
                                    CONNECT/GET solo a squid/allowlist.txt
                                    (.telegram.org, .opencode.ai, .github.com,
                                     .pypi.org, proxy.golang.org, …)
```

Tres consecuencias del diseño que conviene tener claras desde el principio:

- **`hermes` y `opencode` no se ven por red con el host.** El server de opencode
  se alcanza como `http://opencode:4096` desde la red interna, y desde ningún
  otro lado. La forma de hablarle es delegando desde Hermes.
- **Los dos agentes escriben la misma carpeta** (`/workspace`). Los dos corren
  como uid 10000 justamente para que ninguno quede sin poder editar los archivos
  del otro.
- **`hermes` no tiene credenciales de GitHub, a propósito.** El PAT vive solo en
  `opencode`. Para repos privados y para pushear, Hermes delega.

## Requisitos

- Docker (el diseño asume bind mounts de Windows; la
  operación de arranque está medida ahí).
- Docker Compose v2.
- PowerShell 7 (`pwsh`) para `scripts/fix-permissions.ps1`.
- Un token de bot de Telegram (`@BotFather`).
- Una clave del proveedor de modelos.
- Opcional: un PAT fine-grained de GitHub, con **los repos justos y Contents
  read/write**, para que OpenCode pueda clonar repos privados y pushear.
- Salida a Internet en el host para construir la imagen de opencode y bajar las
  imágenes base: **el build no pasa por Squid**.

## Puesta en marcha

1. Cloná el repo. `main` es la rama por defecto; si el stack todavía no está
   mergeado ahí, cloná la rama de trabajo:

   ```bash
   git clone -b security/egress-hardening https://github.com/emiliodavola/robotina.git
   ```

   (Si ves este README, estás en la rama correcta.)

2. Creá el `.env` a partir de la plantilla y completá las **cuatro
   obligatorias**: compose aborta con un mensaje explícito si falta alguna.

   ```bash
   cp .env.example .env
   ```

   ```ini
   HOST_DATA_DIR=C:/robotina-data      # carpeta del host donde vive el estado
   TELEGRAM_BOT_TOKEN=                 # @BotFather
   HERMES_OPENCODE_GO_API_KEY=         # modelo que usa Hermes
   OPENCODE_GO_API_KEY=                # modelo que usa OpenCode
   TELEGRAM_ALLOWED_USERS=             # opcional: quién puede usar el bot
   OPENCODE_SERVER_PASSWORD=           # opcional: HTTP Basic del server
   GITHUB_TOKEN=                       # opcional: PAT fine-grained
   ```

   El `.env` está gitignoreado. Sus valores son legibles con `docker inspect`:
   es un riesgo asumido y está documentado en `SECURITY.md`.

3. Construí la imagen de opencode (el servicio la referencia como
   `robotina-opencode:local`):

   ```bash
   docker compose build opencode
   ```

4. Levantá el stack:

   ```bash
   docker compose up -d
   ```

5. Alineá el dueño de las carpetas del host. **Este paso es obligatorio**:
   `opencode` corre como uid 10000 y las carpetas recién creadas quedan de root,
   con lo cual ninguno de los dos agentes puede escribir.

   ```bash
   pwsh -File scripts/fix-permissions.ps1
   ```

   Hay que volver a correrlo cada vez que alguna de esas carpetas se recrea
   desde cero.

6. Verificá que arrancó:

   ```bash
   docker compose ps
   docker compose exec hermes hermes status
   ```

7. Hablale al bot por Telegram. Con `TELEGRAM_ALLOWED_USERS` vacío, Hermes
   responde con un código de vinculación a cualquier desconocido en vez de
   obedecerlo: el control de acceso es esa lista, no la red.

## Uso

**Hermes, por Telegram.** Es la puerta de entrada. Puede ejecutar trabajo él
mismo o delegarlo a OpenCode.

**OpenCode, por HTTP.** Expone `GET /doc` (OpenAPI), `GET /global/health`,
`POST /session`, `POST /session/{id}/message` y compañía, pero **solo desde la
red interna**: no lo alcanzás desde el host. Se maneja delegando desde Hermes,
que tiene la receta en su skill `opencode-server`. Con
`OPENCODE_SERVER_PASSWORD` seteado exige HTTP Basic (usuario `opencode`).

**Los dos juntos.** Hermes crea una sesión en OpenCode, le manda el pedido y lee
el mismo `/workspace`, así que lo que OpenCode escribe aparece al instante del
lado de Hermes y en tu carpeta del host.

## Agregar un dominio de egreso

Nada sale si no está en `squid/allowlist.txt`. Para habilitar un destino:

1. Editá `squid/allowlist.txt`: un dominio por línea, y el punto inicial incluye
   subdominios (`.github.com` cubre `api.github.com`).
2. Aplicá el cambio:

   ```bash
   docker compose up -d --force-recreate egress-proxy
   ```

3. Verificá que la política quedó bien formada (falla si hay un ACL inválido):

   ```bash
   docker compose run --rm --no-deps --entrypoint /usr/sbin/squid \
     egress-proxy -f /etc/squid/squid.conf -k parse
   ```

4. Si algo rebota, mirá el log del proxy. Registra el dominio, no la URL:

   ```bash
   docker logs egress-proxy | grep -v '127.0.0.1' | grep 'client='
   ```

Antes de agregar un host, preguntate si ese servicio necesita ver el tráfico de
tus agentes. La allowlist acota **a dónde** hablan, no **qué** mandan: ver
«Puntos de atención» en `SECURITY.md`.

## Estado y backups

Las dos bases SQLite usan WAL y viven en volúmenes nativos de Docker, porque WAL
sobre una carpeta de Windows (virtiofs/9p) puede corromperse en silencio. El
resto del estado son carpetas del host.

Para sacar ese estado a un formato portable y legible:

```bash
docker compose exec opencode sh /opt/export-state.sh
# -> ${HOST_DATA_DIR}/backups/engram-<fecha>.json
# -> ${HOST_DATA_DIR}/backups/opencode-<sesion>-<fecha>.json
```

Compromiso explícito: esas dos bases no se abren a mano desde el Explorador, y
un reset de fábrica de Docker Desktop las borra. Los JSON sí sobreviven.

## Versiones

Medido dentro de los contenedores que corren, no copiado de la documentación.

| Componente | Versión | Cómo llega |
| --- | --- | --- |
| opencode | 1.18.31 | imagen base `ghcr.io/anomalyco/opencode:latest` |
| Squid | 6.13 | `ubuntu/squid:latest` |
| Hermes | — | `nousresearch/hermes-agent:latest` |
| git / gh | 2.54.0 / 2.97.0 | `apk` |
| Go / uv / jq / ripgrep | 1.26.8 / 0.11.19 / 1.8.2 / 15.1.0 | `apk` (uv por su instalador) |
| CPython | 3.13.13 | `uv python install 3.13` |
| Node | 24.18.1 | `apk` |
| engram | 1.20.0 | release, con checksum |
| gentle-ai | 3.1.0 | release, con checksum |
| LSPs | marksman 2026-02-08, basedpyright 1.39.9, vscode-langservers 4.10.0, dockerfile-language-server 0.15.0, taplo y R `languageserver` | npm / `apk` / R |

`opencode/Dockerfile` pinea engram, gentle-ai, marksman y los paquetes npm, y
verifica los binarios por checksum. Todo lo demás se resuelve al construir (tags
`latest` y `apk` sin versión), así que **estas versiones describen la imagen
medida, no una garantía a futuro**: para auditar una versión concreta hay que
volver a medirla en el contenedor.

## Modelo de seguridad, en cinco líneas

Los agentes no tienen ruta propia a Internet (red `internal: true` sin gateway);
su único egreso es el proxy, que permite una lista de dominios y deniega todo lo
demás, incluidos rangos privados y de metadata de cloud. No se publica ningún
puerto, no se monta el socket de Docker, el proxy corre read-only como uid 13 y
los tres contenedores bajan capabilities con `no-new-privileges`. El riesgo
residual más filoso es que los secretos son variables de entorno, legibles con
`docker inspect`, y que `gh auth token` los imprime dentro del contenedor.

**Amenazas, mediciones y lista completa de riesgos residuales: [`SECURITY.md`](SECURITY.md).**

## Decisiones deliberadas

- **Hermes no tiene credenciales de GitHub.** Ni `GITHUB_TOKEN`, ni credential
  helper, ni `~/.config/gh`. Los repos privados y los push se delegan a OpenCode.
- **SSH es imposible, por diseño.** El proxy solo permite `CONNECT` al puerto
  443, así que no hay ruta para SSH. La reescritura de `git@github.com:` a HTTPS
  existe **solo en el contenedor de opencode** (`/etc/gitconfig`); en `hermes`
  hay que usar URLs `https://` directamente.
- **Ningún puerto publicado**, ni el dashboard de Hermes ni el server de opencode.
- **Fuera de alcance, por ahora**: Docker rootless o `userns-remap`, secretos en
  `/run/secrets`, y `read_only: true` en los agentes.

## Estructura del repo

```text
compose.yml                      los tres servicios, redes, límites y montajes
SECURITY.md                      modelo de amenazas, mediciones y riesgos residuales
.env.example                     los siete nombres de variable, sin valores
opencode/Dockerfile              imagen del agente de código (toolchain, LSPs, gentle-ai)
opencode/entrypoint.sh           aplica los artefactos de gentle-ai, el overlay y arranca
opencode/overlay.json            MCP, LSP y permisos propios del agente
squid/squid.conf                 política de Squid: default deny, sin intercepción TLS
squid/allowlist.txt              los dominios habilitados, uno por línea
hermes/context/.hermes.md        hechos del entorno que Hermes lee al arrancar
hermes/skills/                   skills propias, montadas read-only
scripts/fix-permissions.ps1      alinea el dueño de las carpetas del host (uid 10000)
scripts/export-state.sh          saca el estado en volumen a JSON
odd/tasks/                       decisiones y evidencia de cada etapa del stack
```

## Licencia

MIT — ver [`LICENSE`](LICENSE). Copyright (c) 2026 Emilio Dávola.
