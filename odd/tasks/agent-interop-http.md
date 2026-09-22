# Feature: agent-interop-http

> **Superseded (2026-09-22)** — this feature's design is superseded by the
> `single-robotina-container` change (R6). `opencode serve` no longer lives in its own container
> reached over the `agents` network; it runs on loopback inside the single `robotina` container,
> and the network hop described below is retired. The history below is preserved unchanged as the
> record of how the HTTP interop was built and what it proved; it is not the current topology.
> See `odd/tasks/single-robotina-container.md` for the merged reality.

## Goal

Make Hermes able to dispatch coding work to OpenCode, keeping the two agents in
separate containers (the user's decision: automation without losing isolation).

The original `compose.yml` claimed "Comunicación Hermes <-> OpenCode" and shared
a `workspace` volume, but a shared volume shares **files, not control**: nothing
listens on either side, and Hermes has no ACP client (`agent_client_protocol` is
imported only by `/opt/hermes/acp_adapter/`, which exposes Hermes to an editor —
the opposite direction). Verified by running both services: opencode was an idle
TUI (`PID 57404`, `pts/0`, no listener) and the agent correctly answered "no lo
tengo instalado" about its own container.

## Shape

- `opencode` stops being an idle TUI and becomes a headless server:
  `opencode serve --hostname 0.0.0.0 --port 4096`.
- It stays on the `agents` network only; no ports are published, so the HTTP
  surface is reachable by `hermes` and by nothing else.
- `NO_PROXY` already lists `opencode`, so the internal call bypasses squid.
- Hermes learns the API through a **skill** in its volume, not through code
  changes to the image.

## Non-goals

- Bypassing the proxy or giving either container a direct Internet route.
- Modifying the vendor images.
- Making opencode the orchestrator.

## Open risks to verify

- Does opencode (Bun) honor `HTTP(S)_PROXY`? If it ignores the env, its model
  calls have no route and the whole interop is useless. Testable for free with
  the `opencode/*-free` tier and observable in squid's access log.
- Where does `opencode serve` persist session state? If it writes outside the
  mounted `opencode_data` volume, sessions vanish on recreate.

## Tasks

- [x] T1 — Feature document (this file).
- [x] T2 — Switch the opencode service to `serve`, drop TTY.
- [x] T3 — Discover the real HTTP API surface from the running server.
- [x] T4 — Prove opencode's model traffic goes through the proxy (free model).
- [x] T5 — Write the Hermes skill describing the API.
- [x] T6 — End-to-end test: Hermes dispatches a task to opencode.
- [x] T7 — Document in SECURITY.md and commit.

## Evidence

Isolation preserved — the two agents are separate containers, and they talk over
TCP on the internal `agents` network. Nothing was copied into Hermes:

```text
/hermes   ip=172.19.0.3 pid_host=69678 path=/opt/hermes/docker/entrypoint-dispatch.sh
/opencode ip=172.19.0.2 pid_host=69619 path=opencode
hermes: command -v opencode -> opencode: NO EXISTE en el contenedor de hermes
mounts shared: volume:/workspace (only)
```

Service change: `opencode serve --hostname 0.0.0.0 --port 4096` replaced the idle
TUI (`PID 57404`, `pts/0`, no listener). The port is not published, so the HTTP
surface is reachable only from the `agents` network.

API contract taken from the server's own spec (`GET /doc`, OpenAPI 3.1, 479 KB),
not from memory:

- `POST /session` → `{"id":"ses_...", ...}` (directory reported as `/workspace`)
- `POST /session/{id}/message` with
  `{"parts":[{"type":"text","text":"..."}],"model":{"providerID":"opencode","modelID":"mimo-v2.5-free"}}`
  → blocking `{"info":{..."finish":"stop","tokens":{...}},"parts":[...]}`

End-to-end, run from inside the hermes container with the recipe the skill
documents (free tier, zero cost):

```text
SID extraido por sed: [ses_f4e124c95ffebw3TklMSv66N81]
{"info":{..."cost":0,"tokens":{"total":8395...},"modelID":"mimo-v2.5-free",
 "providerID":"opencode","finish":"stop",...}}
```

Opencode's own egress is verified by construction and by log: the container has no
route except the proxy, and its model call to `models.opencode.ai` appears as
`TCP_TUNNEL` in squid. Bun honors `HTTPS_PROXY`.

Session auth control verified with a temporary password (inline env, the user's
`.env` untouched): server with `OPENCODE_SERVER_PASSWORD` → `401` without
credentials and `200` with HTTP Basic (username `opencode`); the skill recipe picks
the password from the environment. Reverted to unset, matching the current `.env`.

Skill landed in the repo and mounted read-only, so the agent cannot rewrite its own
instructions: `hermes skills list` → `opencode-server | autonomous-ai-agents |
local | local | enabled`. The bundled `opencode` skill (CLI-based) remains enabled
too, which is why the new skill states explicitly that `which -a opencode` failing
is expected and not a reason to give up.

## Gotchas found

- **Internal names must be in `NO_PROXY`.** A probe against a container named
  `octest` returned `403` with Squid's HTML error page: the host was not in
  `NO_PROXY`, so the call went out through the proxy and the allowlist denied it.
  `opencode`/`hermes`/`egress-proxy` are listed, so the real path bypasses squid.
- **Squid co-tenancy.** `egress-proxy` is the only other member of the `agents`
  network, so a compromised proxy could drive opencode. That is what the server
  password closes; it is documented as a one-line opt-in and left unset by default.
- **The free tier is served from `models.opencode.ai`**, a subdomain already
  covered by the `.opencode.ai` allowlist entry.
- Reading the proxy log by IP requires re-checking the mapping: recreating a
  container reshuffles `agents` addresses (hermes and opencode swapped).
