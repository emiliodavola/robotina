# Robotina

[Español](README.md) · [English](README.en.md)

Un agente autónomo, en **un solo contenedor**, sobre un workspace compartido y
**sin ruta directa a Internet**: todo su egreso pasa por un proxy Squid que solo
deja salir una lista blanca de dominios. Dentro del contenedor conviven Hermes
(gateway de Telegram), `opencode serve` (el server de código) y `engram` (la
memoria), supervisados por s6.

| Pieza | Qué es |
| --- | --- |
| **robotina** | El contenedor único. Corre Hermes (gateway de Telegram), `opencode serve` (solo loopback) y `engram`, supervisados por s6. `HOME=/opt/data`, uid 10000. |
| **egress-proxy** | Squid con allowlist de dominios. Es el único contenedor con salida. |
| **Modelo de seguridad** | [`SECURITY.md`](SECURITY.md) — garantías, mediciones y riesgos residuales. |

## Arquitectura

```text
                    host: ${HOST_DATA_DIR}/
                    ├── hermes/      (HOME del agente: config, sesiones, SOUL.md)
                    │   ├── .engram/                 ← punto de montaje del volumen (vacío)
                    │   └── .local/share/opencode/   ← punto de montaje del volumen (vacío)
                    ├── workspace/   (el código que ve el agente)
                    └── backups/     (exports JSON del estado en volumen)

                    volúmenes nativos de Docker (anidados dentro del bind)
                    ├── robotina_opencode_db   (sesiones de opencode — WAL)
                    └── robotina_engram_db     (memoria del agente  — WAL)

  red "agents" (internal: true, SIN gateway: no hay salida ni DNS externo)
  ┌────────────────────────────────────┐   ┌────────────────┐
  │              robotina              │   │  egress-proxy  │
  │  s6 supervisa:                     │──▶│  squid :3128   │
  │   • hermes gateway  (Telegram)     │   │  uid 13, rootfs│
  │   • opencode serve  :4096 loopback │   │  read-only     │
  │   • engram                         │   └───────┬────────┘
  │  uid 10000 · HOME=/opt/data        │           │  red "egress" (con gateway)
  └────────────────────────────────────┘           ▼
        │                                CONNECT/GET solo a squid/allowlist.txt
        └── /workspace (bind del host)   (.telegram.org, .opencode.ai, .github.com,
                                          .pypi.org, proxy.golang.org, …)
```

Tres consecuencias del diseño que conviene tener claras desde el principio:

- **El server de OpenCode escucha en `127.0.0.1:4096`, solo loopback.** No lo
  alcanzás desde el host ni desde otro contenedor: para manejarlo se entra al
  contenedor con `docker compose exec robotina …` (recetas más abajo). El agente
  además tiene el CLI `opencode` instalado localmente, que es la vía normal. Lo
  documentan la skill `opencode` que trae el vendor (el CLI) y la skill propia del
  repo `hermes/skills/opencode-delegation/SKILL.md` (delegación a OpenCode: el agente
  ejecutor, la regla de proveedor/modelo, el endpoint no bloqueante y el servidor
  único supervisado).
- **Todo el contenedor comparte un solo `HOME`** (`/opt/data`) y un solo uid
  (10000). El estado de Hermes, la config de OpenCode y la de git caen todos
  dentro del bind de `${HOST_DATA_DIR}/hermes`.
- **El contenedor único tiene `gh` y `GITHUB_TOKEN`.** El token vive en el
  contenedor entero: Hermes y OpenCode lo ven por igual. Los repos privados y
  los push ya no se delegan por falta de credencial.

### Qué reemplazó al layout anterior

Si venís de la versión con Hermes y OpenCode en **servicios separados**, esto es
lo que cambió y por qué:

- `robotina/Dockerfile` reemplaza a `opencode/Dockerfile`: una sola imagen sobre
  la base vendor Debian, con la toolchain, los LSPs y gentle-ai ya adentro.
- s6 (`robotina/s6/`) supervisa los tres programas dentro del mismo contenedor,
  en vez de un entrypoint por servicio.
- El server de OpenCode pasó a escuchar en loopback (`127.0.0.1:4096`): no hay
  red entre agentes, porque los tres programas son procesos del mismo
  contenedor.
- El dueño del estado lo corrige el propio contenedor al arrancar
  (`robotina/s6/cont-init.d/10-robotina-state`), no un script privilegiado en el
  host.
- El estado que vivía en `${HOST_DATA_DIR}/opencode` y `${HOST_DATA_DIR}/git`
  se copia hacia `${HOST_DATA_DIR}/hermes/.config/` con un paso de migración
  (sección «Migración»).

## Requisitos

- Docker (el diseño asume bind mounts de Windows; la operación de arranque está
  medida ahí).
- Docker Compose v2.
- Un token de bot de Telegram (`@BotFather`).
- Una clave del proveedor de modelos (compose usa **dos nombres**: una para
  Hermes y otra para OpenCode).
- Opcional: un PAT fine-grained de GitHub, con **los repos justos y Contents
  read/write**, para que el agente pueda clonar repos privados y pushear.
- Salida a Internet en el host para construir la imagen: **el build no pasa por
  Squid**.
- Opcional, solo si migrás estado en Windows: PowerShell 7 (`pwsh`) para
  `scripts/migrate-state.ps1`. En Linux/macOS hay equivalente POSIX documentado.

## Puesta en marcha

1. Cloná el repo. `main` es la rama por defecto; si el contenedor único todavía
   no está mergeado ahí, cloná la rama de trabajo:

   ```bash
   git clone -b feat/single-robotina-container https://github.com/emiliodavola/robotina.git
   ```

   (Si ves este README, estás en la rama correcta.)

2. Creá el `.env` a partir de la plantilla y completá las **cuatro
   obligatorias**: compose aborta con un mensaje explícito si falta alguna.

   ```bash
   cp .env.example .env
   ```

   ```ini
   HOST_DATA_DIR=C:/robotina-data          # carpeta del host donde vive el estado
   ROBOTINA_TELEGRAM_BOT_TOKEN=            # @BotFather
   ROBOTINA_HERMES_MODEL_KEY=              # clave que usa Hermes
   ROBOTINA_OPENCODE_MODEL_KEY=            # clave que usa OpenCode
   ROBOTINA_TELEGRAM_ALLOWED_USERS=        # opcional: quién puede usar el bot
   ROBOTINA_OPENCODE_SERVER_PASSWORD=      # opcional: HTTP Basic del server
   ROBOTINA_GITHUB_TOKEN=                  # opcional: PAT fine-grained
   ```

   Las dos claves de modelo se publican con nombres distintos a propósito:
   `ROBOTINA_HERMES_MODEL_KEY` llega al proceso Hermes con el nombre que espera
   la imagen vendor, y `ROBOTINA_OPENCODE_MODEL_KEY` la reexporta el run script de
   `opencode` **solo en su propio proceso**. El `.env` está gitignoreado; sus
   valores son legibles con `docker inspect`, riesgo asumido y documentado en
   `SECURITY.md`.

   **Por qué los nombres llevan el prefijo `ROBOTINA_`.** Docker Compose le da
   precedencia al entorno del proceso por sobre el `.env`. Si dejaste exportada
   en tu shell una variable con el mismo nombre que una de estas claves —el caso
   real fue `OPENCODE_GO_API_KEY`, el nombre propio del vendor— ese valor pisaba
   en silencio al del `.env` y el contenedor arrancaba con una credencial vieja.
   El prefijo `ROBOTINA_` no existe en el entorno del host, así que la colisión
   es imposible. En la práctica: **no exportes estas variables en tu shell**;
   editá el `.env` y recreá el contenedor.

3. Configurá el modelo de Hermes (opcional). El cont-init `30-robotina-model`
   aplica esta configuración **automáticamente en cada arranque**, así que no
   tenés que editar `config.yaml` a mano. Los defaults ya son los de OpenCode Go:

   ```ini
   ROBOTINA_HERMES_MODEL_PROVIDER=     # default: opencode-go
   ROBOTINA_HERMES_MODEL_BASE_URL=     # default: https://opencode.ai/zen/go/v1
   ROBOTINA_HERMES_MODEL=              # default: deepseek-v4.1-flash
   ```

   Dejalos vacíos para usar los defaults, o definí un id del catálogo del plan
   para cambiarlo (sin prefijo `opencode-go/`). Con esto Hermes queda apuntado a
   `opencode-go` en vez del `provider: auto` que siembra el vendor, que acá no
   puede funcionar: `openrouter.ai` está fuera de la allowlist de Squid por
   diseño y, con `auto`, Hermes resuelve al único proveedor con credencial.
   **Si apuntás Hermes a otro proveedor, ese host también tiene que estar en
   `squid/allowlist.txt`**, o el pedido muere en el proxy. Para cambiarlo en
   caliente está la receta de «Modelo y plan del proveedor» más abajo.

4. Construí la imagen del agente (el servicio la referencia como
   `robotina:local`):

   ```bash
   docker compose build robotina
   ```

5. Levantá el stack:

   ```bash
   docker compose up -d
   ```

   **No hay paso de permisos en el host.** El contenedor arregla el dueño de
   `/opt/data`, `/workspace` y `/backups` al arrancar, corriendo como root antes
   de cualquier servicio. Una carpeta de estado recién creada queda escribible
   por uid 10000 sin que corras nada privilegiado afuera.

6. Verificá que arrancó:

   ```bash
   docker compose ps
   docker compose exec robotina hermes status
   ```

7. Si venías del layout anterior, migrá el estado (sección «Migración»).

8. En BotFather, renombrá el **nombre visible** (display name) del bot a
   `robotina`. Es el único paso manual del lado de Telegram: no hace falta
   cambiar el handle público, y el token del `.env` sigue siendo el mismo.
   Hablale al bot. Con `ROBOTINA_TELEGRAM_ALLOWED_USERS` vacío, Hermes responde
   con un código de vinculación a cualquier desconocido en vez de obedecerlo: el
   control de acceso es esa lista, no la red.

## Uso

**Por Telegram.** Es la puerta de entrada. Hermes puede ejecutar trabajo él
mismo o delegarlo al server local de OpenCode.

**Dentro del contenedor.** Como el server de OpenCode es loopback-only, la
única forma de inspeccionar las cosas es `docker compose exec robotina …`:

```bash
# Estado de los servicios y de la supervisión s6
docker compose ps
docker compose exec robotina hermes status
docker compose exec robotina /command/s6-rc -a list

# Salud del endpoint local (credential-aware: solo manda -u si hay password)
docker compose exec robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/global/health'

# Logs acotados (el stream del contenedor incluye a los tres procesos)
docker compose logs --tail 200 robotina

# Export del estado en volumen a JSON
docker compose exec robotina sh /opt/export-state.sh
```

Dos notas de operación:

- Las herramientas de s6 viven en `/command`, que **no** está en el `PATH` por
  defecto dentro del contenedor; invocalas con la ruta completa.
- En Git Bash, para rutas absolutas del contenedor usá
  `MSYS_NO_PATHCONV=1` y evitá que el shell del host te traduzca la ruta.

La API HTTP de OpenCode (`GET /doc` como OpenAPI, `GET /global/health`,
`POST /session`, `POST /session/{id}/message` y compañía) existe, pero **solo
se alcanza desde adentro del contenedor**, por loopback. Con
`OPENCODE_SERVER_PASSWORD` seteado exige HTTP Basic (usuario `opencode`).

## Migración desde el layout anterior

Si tu `${HOST_DATA_DIR}` tiene las carpetas del layout previo, copiá el estado
hacia la ruta nueva. El helper **copia hacia adelante y nunca pisa**: solo copia
una ruta cuando el destino no existe, así que un archivo destino más nuevo queda
intacto. No borra ni mueve nada: las carpetas legacy son la red de rollback.

**Antes de migrar, sacá un export como red de seguridad** (barato y portable):

```bash
docker compose exec robotina sh /opt/export-state.sh
# -> ${HOST_DATA_DIR}/backups/engram-<fecha>.json
# -> ${HOST_DATA_DIR}/backups/opencode-<sesion>-<fecha>.json
```

En Windows, con el helper del repo (lee `HOST_DATA_DIR` del `.env`):

```bash
pwsh -File scripts/migrate-state.ps1
```

En Linux/macOS, el equivalente POSIX documentado. `cp -an` nunca pisa el
destino (el `-n` es «no clobber»); con `rsync` el flag es
`--ignore-existing`. Para replicar la omisión de `node_modules/` del helper,
agregá el `--exclude`:

```bash
cp -an "$HOST_DATA_DIR/opencode/." "$HOST_DATA_DIR/hermes/.config/opencode/"
cp -an "$HOST_DATA_DIR/git/."      "$HOST_DATA_DIR/hermes/.config/git/"

# o, con rsync:
rsync -a --ignore-existing --exclude 'node_modules' \
  "$HOST_DATA_DIR/opencode/" "$HOST_DATA_DIR/hermes/.config/opencode/"
rsync -a --ignore-existing \
  "$HOST_DATA_DIR/git/" "$HOST_DATA_DIR/hermes/.config/git/"
```

El `GOPATH` (`${HOST_DATA_DIR}/go`) **no se copia**: es cache reconstruible.
Correr la migración antes o después del primer arranque da igual: nada en
compose ni en la imagen la llama, y el contenedor arranca bien con la migración
sin correr.

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
tu agente. La allowlist acota **a dónde** habla, no **qué** manda: ver «Puntos
de atención» en `SECURITY.md`.

## Estado, volúmenes y persistencia

Las dos bases SQLite usan WAL y viven en **volúmenes nativos de Docker,
anidados dentro del bind** de `${HOST_DATA_DIR}/hermes`. No es capricho: WAL
sobre una carpeta de Windows (virtiofs/9p) puede corromperse en silencio.

| Qué | Dónde vive | Notas |
| --- | --- | --- |
| Estado de Hermes (config, sesiones, SOUL.md) | bind `${HOST_DATA_DIR}/hermes` → `/opt/data` | rw; es el `HOME` del árbol de procesos |
| Memoria de engram (SQLite WAL) | volumen `robotina_engram_db` → `/opt/data/.engram` | nativo, anidado dentro del bind |
| Sesiones de OpenCode (SQLite WAL) | volumen `robotina_opencode_db` → `/opt/data/.local/share/opencode` | nativo, anidado dentro del bind |
| Workspace compartido | bind `${HOST_DATA_DIR}/workspace` → `/workspace` | rw |
| Salida de exports | bind `${HOST_DATA_DIR}/backups` → `/backups` | rw |

Docker crea `${HOST_DATA_DIR}/hermes/.engram` y
`${HOST_DATA_DIR}/hermes/.local/share/opencode` como carpetas **normales y
vacías** del host: son puntos de montaje que los volúmenes tapan. Verlas vacías
es lo esperado; si apareciera un `.db` ahí adentro, el anidamiento falló y las
bases estarían sobre el bind.

Para sacar el estado en volumen a un formato portable y legible:

```bash
docker compose exec robotina sh /opt/export-state.sh
# -> ${HOST_DATA_DIR}/backups/engram-<fecha>.json
# -> ${HOST_DATA_DIR}/backups/opencode-<sesion>-<fecha>.json
```

Compromiso explícito: esas dos bases no se abren a mano desde el Explorador, y
un reset de fábrica de Docker Desktop las borra. Los JSON sí sobreviven.

**Las pruebas numéricas de esta documentación asumen el uid por defecto.** El
usuario `hermes` de la imagen es uid 10000, y las recetas que imprimen
`10000:10000`, `CapBnd=0x00000000000000eb` o `pids.max=1024` valen para esa
configuración. Un `HERMES_UID` distinto las invalida sin invalidar el diseño.

## Versiones

Medido dentro de los contenedores que corren, no copiado de la documentación.

| Componente | Versión | Cómo llega |
| --- | --- | --- |
| opencode | 1.18.32 | asset glibc x64, versión exacta pineada en `robotina/Dockerfile` |
| Squid | 6.13 | `ubuntu/squid:latest` |
| Hermes | — | `nousresearch/hermes-agent:latest` |
| git / gh | 2.47.3 / 2.97.0 | base vendor / release pineada |
| Go / uv / jq / ripgrep | 1.24.4 / 0.11.6 / 1.7 / 14.1.1 | base vendor / instalador de uv / `apk` |
| Python | 3.13.5 | intérprete del venv de Hermes |
| Node | v26.5.1 | base vendor |
| R | 4.5.0 | base vendor |
| engram | 1.20.0 | release, con checksum |
| gentle-ai | 3.1.0 | release, con checksum |
| taplo / marksman / codegraph | 0.10.0 / 2026-02-08 / 1.5.0 | releases pineadas por tag |

`robotina/Dockerfile` pinea la versión de opencode, gh, taplo, marksman,
codegraph, engram, gentle-ai y los paquetes npm, y **verifica por checksum las
descargas que lo exponen**. marksman va por tag de release, sin verificación de
integridad. Lo demás se resuelve al construir (tags `latest` y `apk` sin
versión), así que **estas versiones describen la imagen medida, no una garantía
a futuro**: para auditar una versión concreta hay que volver a medirla en el
contenedor.

## Modelo de seguridad, en cinco líneas

El agente no tiene ruta propia a Internet (red `internal: true` sin gateway); su
único egreso es el proxy, que permite una lista de dominios y deniega todo lo
demás, incluidos rangos privados y de metadata de cloud. No se publica ningún
puerto, no se monta el socket de Docker, el proxy corre read-only como uid 13 y
los contenedores bajan capabilities con `no-new-privileges`. El riesgo residual
más filoso es que los secretos son variables de entorno, legibles con
`docker inspect`, y que `gh auth token` los imprime dentro del contenedor.

**Amenazas, mediciones y lista completa de riesgos residuales: [`SECURITY.md`](SECURITY.md).**

## Decisiones deliberadas

- **Un solo ciclo de vida, y es el del contenedor.** El gateway de Hermes es un
  servicio de s6 (`gateway-default`): si cae, s6 lo reinicia **en el lugar** y el
  contenedor sigue arriba, con `RestartCount` y `StartedAt` sin cambios. Lo
  compartido es el ciclo de vida del contenedor: sale cuando baja el **árbol de
  supervisión de s6**, no cuando sale Hermes, y `opencode` y `engram` se van con
  él. Es la regresión aceptada del merge (R4 en `SECURITY.md`).
- **Un solo uid para todo el árbol (10000).** El aislamiento de claves por
  proceso no es exigible a igual uid; lo que sí se exige es que cada proceso se
  configure **solo con su propia clave**, y el arranque lo verifica (R2).
- **SSH es imposible, por diseño.** El proxy solo permite `CONNECT` al puerto
  443, así que no hay ruta para SSH. La reescritura de `git@github.com:` a HTTPS
  vive en `/etc/gitconfig` de la imagen, así que aplica a todo el contenedor.
- **Ningún puerto publicado**, ni el dashboard de Hermes ni el server de
  OpenCode.
- **Fuera de alcance, por ahora**: Docker rootless o `userns-remap`, secretos en
  `/run/secrets`, y `read_only: true` en el agente.

## Estructura del repo

```text
compose.yml                      los dos servicios, redes, límites y montajes
SECURITY.md                      modelo de amenazas, mediciones y riesgos residuales
.env.example                     los nombres de variable, sin valores
robotina/Dockerfile              la imagen del agente (toolchain, LSPs, gentle-ai)
robotina/opencode-init.sh        aplica los artefactos de gentle-ai, el overlay y arranca
robotina/overlay.json            MCP, LSP y permisos propios del agente
robotina/s6/                     la supervisión: cont-init y los servicios de s6
squid/squid.conf                 política de Squid: default deny, sin intercepción TLS
squid/allowlist.txt              los dominios habilitados, uno por línea
hermes/skins/robotina.yaml       la identidad visible del agente, montada read-only
hermes/context/.hermes.md        hechos del entorno que Hermes lee al arrancar
hermes/skills/                   skills propias (github-private-repos, opencode-delegation), montadas read-only
scripts/migrate-state.ps1        copia hacia adelante el estado del layout anterior
scripts/export-state.sh          saca el estado en volumen a JSON
odd/tasks/                       decisiones y evidencia de cada etapa del stack
```

## Licencia

MIT — ver [`LICENSE`](LICENSE). Copyright (c) 2026 Emilio Dávola.
