# Feature: opencode-config-port

## Goal

Port the host's OpenCode configuration into the opencode container, without
merging containers and without breaking the fail-closed egress model:

- MCP servers, **except `sofer`** (explicitly excluded by the user).
- LSP servers.
- gentle-ai (agents, skills, SDD commands, plugins, AGENTS.md, themes).
- The installation bits those need.

## Inventory (host `~/.config/opencode`, verified)

| Piece | Detail | Needs |
| --- | --- | --- |
| `mcp.codegraph` | local `codegraph serve --mcp`; host install is npm `@colbymchenry/codegraph@1.5.0` | node/npm in container |
| `mcp.context7` | remote `https://mcp.context7.com/mcp`, no auth headers | allowlist entry |
| `mcp.gh_grep` | remote `https://mcp.grep.app`, no auth headers | allowlist entry |
| `mcp.engram` | local `engram mcp --tools=agent`; host install `%LOCALAPPDATA%\engram\bin\engram` | engram binary |
| `mcp.sofer` | local `sofer-mcp` | **excluded by request** |
| `lsp` (8) | dockerfile, json, julia, marksman, powershell, python, r, toml | binaries/runtimes |
| `agent` (23) | gentle-orchestrator, sdd-*, jd-*, review-* | files only |
| `skills` (27) | gentle-ai skills | files only |
| `commands` (13) | sdd-*.md | files only |
| `plugins` (6) | engram.ts, model-variants.ts, opencode-review-transport.ts, sdd-task-result-artifacts.ts, skill-registry.ts, telemetry-runtime.ts | files + npm deps |
| npm deps | `@opencode-ai/plugin`, `opencode-sdd-engram-manage`, `opencode-subagent-statusline` | registry.npmjs.org (already allowlisted) |
| `AGENTS.md`, `.gentle-ai-*.json`, `themes/` (2), `tui-plugins/` (1), `prompts/sdd` | instructions, state markers, themes | files only |

Facts that shape the design:

- **The container is bare Alpine**: `apk` exists; there is **no** node, npm, npx,
  bun, python3, pip, curl, git, go, cargo, uv. Every local MCP/LSP needs an
  install. Installs in the container filesystem do not survive recreation.
- `unpkg.com` appears **only in a comment** in `telemetry-runtime.ts`; no runtime
  egress to it. Real egress from the plugins: `127.0.0.1:<port>` (engram plugin).
- `permission.read` already denies `**/.env`, `**/.ssh/**`, `**/.aws/credentials`,
  `**/*.pem`, `**/*.key`, `**/.credentials/**`, `**/secrets/**`; copy as-is.
- Opencode's embedded Bun installs npm deps itself and already did so through the
  proxy (`registry.npmjs.org` tunnels observed).

## Shape (decided)

A **derived image** in the repo, `opencode/Dockerfile`, based on the vendor image:
install the runtimes and servers the chosen scope needs, and COPY the config tree
into `/root/.config/opencode`. Rationale: a bare `apk add` inside a running
container is lost on the next recreate, and the whole stack is meant to be
declarative and reviewable.

`opencode_data` keeps persisting runtime state; Docker seeds a new volume from the
image, so the baked config is the initial content.

Note: image builds run on the host **outside** the allowlist proxy (as any build
does). That is expected but must be stated: the build is not mediated by Squid.

## Open decisions (asked to the user)

1. Which LSP subset (portable/light vs including Julia and R vs all including PowerShell).
   **Answered:** the 5 portable ones plus R and Julia (PowerShell excluded).
2. engram: install inside the container (isolated memory) vs leave out vs a
   separate engram container with the plugin pointed at it.
   **Answered:** separate container — but this turned out to be infeasible, see below.
3. Remote MCPs (context7, gh_grep): **Answered:** include and allowlist them.
4. Agent configuration: **Answered:** identical to the host, `default_agent:
   gentle-orchestrator` with all 23 agents.

## Finding: engram cannot be split across containers

`engram` (v1.20.0) is local-first by design. Verified against the real binary:

| Probe | Result |
| --- | --- |
| `ENGRAM_URL=http://127.0.0.1:9 engram search test` | works identically → the CLI does not use HTTP |
| `ENGRAM_URL=http://127.0.0.1:9 engram mcp` + `tools/call mem_search` | works identically → the MCP does not use HTTP either |
| `ENGRAM_DATA_DIR=<empty dir> engram mcp` | answers "no memories" → it opened the local DB there |
| `engram serve 0.0.0.0:7438` | ignores host:port and binds 127.0.0.1:7437 |

So: the CLI and the MCP are direct readers/writers of the SQLite brain in
`ENGRAM_DATA_DIR`; only the opencode plugin speaks HTTP, to a loopback URL built
from `ENGRAM_PORT` in its source. On the host all three live on the same machine.

Consequences for the requested "separate engram container":

- The agent's `mem_*` tools would write to a database **inside its own container**,
  not to the server's, so the separate container would serve no purpose.
- Sharing one brain would mean mounting the same SQLite file in two containers with
  two writers → corruption risk, and on Docker Desktop for Windows it would be
  SQLite over a virtiofs/9p mount, which breaks locking outright. Rejected.
- The only *supported* multi-instance sharing path is the cloud route
  (`engram cloud serve` + `ENGRAM_DATABASE_URL` Postgres + autosync + tokens/JWT),
  which is two extra services and a separate project.

Faithful port of the host arrangement = `engram serve` **inside the opencode
container** (local DB + plugin over loopback), with `ENGRAM_DATA_DIR` on a volume
so memory survives recreation. That memory is its own brain, not the host's.

## Tasks

- [x] T1 — Feature document (this file).
- [x] T2 — Resolve the four open decisions.
- [x] T3 — Copy the config tree into the repo — **corregido por el usuario**: los
      artefactos de gentle-ai NO se copian, los genera su instalador. Del copiado
      original solo quedo lo propio (LSP, MCP del usuario, permisos), y hoy vive
      en `opencode/overlay.json`.
- [x] T4 — `opencode/Dockerfile`: runtimes, 6 LSP, codegraph, engram, gentle-ai.
- [x] T5 — Persistencia en carpetas del host (`HOST_DATA_DIR`) + volumenes para
      las dos bases WAL + allowlist de los MCP remotos.
- [x] T6 — Verificado: 4 MCP conectados, interop OK, export a JSON en el host.
- [x] T7 — Documentado en SECURITY.md y commiteado.

## Evidence

Imagen `robotina-opencode:local` construida desde el vendor Alpine. Verificado
dentro del contenedor: `vscode-json-language-server`, `docker-langserver`,
`basedpyright-langserver`, `taplo`, `marksman`, `codegraph`, `engram`,
`gentle-ai` y `R` (con `library(languageserver)` cargando: `R-OK`).

Estado de los MCP segun el propio opencode (`GET /mcp`):

```json
{"context7":{"status":"connected"},"engram":{"status":"connected"},
 "codegraph":{"status":"connected"},"gh_grep":{"status":"connected"}}
```

Gentle-ai: su instalador se corre en el build con `HOME=/opt/gentle-ai-stage` y
`--scope global --agents opencode`, y el entrypoint aplica el resultado al
arrancar. Genero exactamente el inventario del host (6 plugins, `.gentle-ai-*`,
`AGENTS.md`, 2 temas, `tui.json`, `tui-plugins/`, el set de skills) y ademas
clono `gentleman-guardian-angel` v2.10.1 desde GitHub, que es la razon por la que
correr el instalador es correcto y copiar los archivos no.

Config resultante en el host (`${HOST_DATA_DIR}/opencode/opencode.json`), merge de
lo de gentle-ai con el overlay propio: `mcp: codegraph, context7, engram,
gh_grep` · `lsp: dockerfile, json, marksman, python, r, toml` ·
`default_agent: gentle-orchestrator` · `agent: 23`.

## Gotchas found (todos medidos, ninguno supuesto)

1. **Julia no entra.** No existe en ningun repo de Alpine (ni edge/testing) y los
   binarios oficiales son glibc. El escape -rebasar a Debian- tambien esta
   cerrado: el binario de opencode es musl-linked (`/lib/ld-musl-x86_64.so.1`) y
   con el loader musl en Debian muere por simbolos de C++. Seis LSP, no siete.
2. **codegraph no arrancaba** (`MCP error -32000: Connection closed`). El paquete
   `codegraph-linux-x64` trae su propio runtime `node` **compilado contra glibc**;
   en musl su loader no existe y el wrapper reporta `node: not found`.
   `codegraph --version` fallaba. Solucion: apuntarlo al node de Alpine y borrar
   los 123 MB inutiles.
3. **R `languageserver` no compilaba**: `fs` necesita `uv.h` (`libuv-dev`), y el
   arbol entero (stringi → ICU, xml2, lintr, styler) necesita mas librerias.
   Tambien el paquete `curl-dev` de Alpine se llama asi, no `libcurl-dev`.
4. **`--noexec` en tmpfs**: Docker agrega `noexec` a todo tmpfs salvo que pidas
   `exec`. OpenTUI extrae una `.so` a `/tmp` y la carga con `dlopen`; sobre
   `noexec` eso devuelve EPERM (no EACCES) y el contenedor entra en crash loop.
5. **WAL sobre carpeta de Windows.** Hermes lo denuncia en su log y lo medimos en
   el header de cada base: las suyas se pudieron pasar a rollback
   (`journal_mode: delete` + conversion offline), pero `opencode.db` y
   `engram.db` **vuelven a WAL al escribir**, asi que esas dos van a volumen
   nativo y el estado se exporta a JSON en el host con `scripts/export-state.sh`.
6. **Expansion sin comillas del password** en la receta de la skill: `AUTH="-u
   opencode:$PASS"` y luego `curl $AUTH` parte el password en varios argumentos
   y la API responde `401` como si la credencial estuviera mal. La receta usa
   ahora parametros posicionales con `"$@"`.
7. **Artefactos ajenos no se editan a mano.** Un chequeo automatico marco dos
   `catch {}` vacios y luego dos `Reflect.get` en plugins de gentle-ai. Son codigo
   de upstream, el diff probo que solo habia tocado una linea (la ruta del binario
   de engram), y la respuesta correcta fue dejar de copiar esos archivos y
   generarlos con el instalador.
