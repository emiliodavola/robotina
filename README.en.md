# Robotina

[Español](README.md) · [English](README.en.md)

Two autonomous agents, each in its own container, sharing one workspace
and with **no direct route to the Internet**: all their egress goes through a
Squid proxy that only lets a whitelist of domains out.

| Piece | What it is |
| --- | --- |
| **hermes** | Telegram gateway (`nousresearch/hermes-agent`). Takes requests from chat and either runs them or delegates them. |
| **opencode** | Headless HTTP coding server (`ghcr.io/anomalyco/opencode`, extended by `opencode/Dockerfile`). No TUI, no published port. |
| **egress-proxy** | Squid with a domain allowlist. It is the only container with a way out. |
| **Security model** | [`SECURITY.md`](SECURITY.md) — guarantees, measurements and residual risks. |

## What it solves

Handing an autonomous agent a shell and a GitHub token is handing an attacker a
shell and a token. This stack does not try to make "nothing happen": it
**bounds the damage**. The two agents live on an internal network with no
gateway, egress is an explicit list of domains, nothing is published, and state
lives in host folders you can inspect. The useful question stops being "did
something happen?" and becomes "how far can it get?".

## Architecture

```text
                    host: ${HOST_DATA_DIR}/
                    ├── hermes/     (Hermes config and sessions)
                    ├── workspace/  (the code both agents see)
                    ├── opencode/   (config, plugins, gentle-ai artifacts)
                    ├── backups/    (JSON exports of volume-resident state)
                    ├── git/        (global git config)
                    └── go/         (GOPATH)

                    native Docker volumes
                    ├── robotina_opencode_db   (opencode sessions — WAL)
                    └── robotina_engram_db     (agent memory    — WAL)

  network "agents" (internal: true, NO gateway: no route, no external DNS)
  ┌────────────────┐   ┌────────────────┐   ┌────────────────┐
  │     hermes     │   │    opencode    │   │  egress-proxy  │
  │  Telegram      │──▶│  :4096 (HTTP)  │   │  squid :3128   │
  │  gateway       │   │  no TUI        │   │  uid 13, rootfs│
  │  uid 10000     │   │  uid 10000     │   │  read-only     │
  └────────────────┘   └────────────────┘   └───────┬────────┘
        │                     │                     │
        └── shared /workspace (host bind) ──────────┘
                                                    │  network "egress" (has a gateway)
                                                    ▼
                                    CONNECT/GET only to squid/allowlist.txt
                                    (.telegram.org, .opencode.ai, .github.com,
                                     .pypi.org, proxy.golang.org, …)
```

Three consequences of the design worth knowing up front:

- **`hermes` and `opencode` are not reachable from the host over the network.**
  The opencode server answers at `http://opencode:4096` on the internal network
  and nowhere else. The way to talk to it is by delegating from Hermes.
- **Both agents write the same folder** (`/workspace`). Both run as uid 10000
  precisely so neither ends up unable to edit the other's files.
- **`hermes` has no GitHub credentials, on purpose.** The PAT lives only in
  `opencode`. For private repos and for pushes, Hermes delegates.

## Requirements

- Docker (the design assumes Windows bind mounts, and the
  startup path was measured there).
- Docker Compose v2.
- PowerShell 7 (`pwsh`) for `scripts/fix-permissions.ps1`.
- A Telegram bot token (`@BotFather`).
- A model provider key.
- Optional: a fine-grained GitHub PAT with **only the repositories you need** and
  Contents read/write, so OpenCode can clone private repos and push.
- Internet access on the host to build the opencode image and pull the base
  images: **the build does not go through Squid**.

## Getting started

1. Clone the repo. `main` is the default branch; if the stack is not merged there
   yet, clone the working branch:

   ```bash
   git clone -b security/egress-hardening https://github.com/emiliodavola/robotina.git
   ```

   (If you can see this README, you are on the right branch.)

2. Create `.env` from the template and fill in the **four mandatory** values:
   compose aborts with an explicit message if any of them is missing.

   ```bash
   cp .env.example .env
   ```

   ```ini
   HOST_DATA_DIR=C:/robotina-data      # host folder that holds all the state
   TELEGRAM_BOT_TOKEN=                 # from @BotFather
   HERMES_OPENCODE_GO_API_KEY=         # model used by Hermes
   OPENCODE_GO_API_KEY=                # model used by OpenCode
   TELEGRAM_ALLOWED_USERS=             # optional: who may use the bot
   OPENCODE_SERVER_PASSWORD=           # optional: HTTP Basic for the server
   GITHUB_TOKEN=                       # optional: fine-grained PAT
   ```

   `.env` is gitignored. Its values are readable with `docker inspect`: an
   accepted risk, documented in `SECURITY.md`.

3. Build the opencode image (the service references it as
   `robotina-opencode:local`):

   ```bash
   docker compose build opencode
   ```

4. Bring the stack up:

   ```bash
   docker compose up -d
   ```

5. Align ownership of the host folders. **This step is mandatory**: `opencode`
   runs as uid 10000 and freshly created folders end up owned by root, so
   neither agent can write.

   ```bash
   pwsh -File scripts/fix-permissions.ps1
   ```

   Re-run it whenever one of those folders is recreated from scratch.

6. Check that it came up:

   ```bash
   docker compose ps
   docker compose exec hermes hermes status
   ```

7. Message the bot on Telegram. With `TELEGRAM_ALLOWED_USERS` empty, Hermes
   answers unknown users with a pairing code instead of obeying them: that list
   is the access control, not the network.

## Using it

**Hermes, over Telegram.** The front door. It can do work itself or delegate it
to OpenCode.

**OpenCode, over HTTP.** It exposes `GET /doc` (OpenAPI), `GET /global/health`,
`POST /session`, `POST /session/{id}/message` and friends, but **only from the
internal network**: you cannot reach it from the host. Drive it by delegating
from Hermes, whose `opencode-server` skill carries the recipe. With
`OPENCODE_SERVER_PASSWORD` set it requires HTTP Basic (username `opencode`).

**Both together.** Hermes creates a session in OpenCode, sends it the request,
and reads the same `/workspace`, so whatever OpenCode writes shows up
immediately on Hermes' side and in your host folder.

## Adding an egress domain

Nothing gets out unless it is in `squid/allowlist.txt`. To enable a destination:

1. Edit `squid/allowlist.txt`: one domain per line, and a leading dot includes
   subdomains (`.github.com` covers `api.github.com`).
2. Apply the change:

   ```bash
   docker compose up -d --force-recreate egress-proxy
   ```

3. Check that the policy is well formed (it fails on an invalid ACL):

   ```bash
   docker compose run --rm --no-deps --entrypoint /usr/sbin/squid \
     egress-proxy -f /etc/squid/squid.conf -k parse
   ```

4. If something is being refused, read the proxy log. It records the domain, not
   the URL:

   ```bash
   docker logs egress-proxy | grep -v '127.0.0.1' | grep 'client='
   ```

Before adding a host, ask yourself whether that service needs to see your
agents' traffic. The allowlist bounds **where** they talk, not **what** they
send: see "Puntos de atención" in `SECURITY.md`.

## State and backups

Both SQLite databases use WAL and live in native Docker volumes, because WAL on
a Windows folder (virtiofs/9p) can be silently corrupted. The rest of the state
is host folders.

To get that state out in a portable, readable format:

```bash
docker compose exec opencode sh /opt/export-state.sh
# -> ${HOST_DATA_DIR}/backups/engram-<date>.json
# -> ${HOST_DATA_DIR}/backups/opencode-<session>-<date>.json
```

An explicit trade-off: those two databases cannot be opened by hand from
Explorer, and a factory reset of Docker Desktop deletes them. The JSON files do
survive.

## Versions

Measured inside the running containers, not copied from documentation.

| Component | Version | How it gets there |
| --- | --- | --- |
| opencode | 1.18.31 | base image `ghcr.io/anomalyco/opencode:latest` |
| Squid | 6.13 | `ubuntu/squid:latest` |
| Hermes | — | `nousresearch/hermes-agent:latest` |
| git / gh | 2.54.0 / 2.97.0 | `apk` |
| Go / uv / jq / ripgrep | 1.26.8 / 0.11.19 / 1.8.2 / 15.1.0 | `apk` (uv via its installer) |
| CPython | 3.13.13 | `uv python install 3.13` |
| Node | 24.18.1 | `apk` |
| engram | 1.20.0 | release, checksum-verified |
| gentle-ai | 3.1.0 | release, checksum-verified |
| LSPs | marksman 2026-02-08, basedpyright 1.39.9, vscode-langservers 4.10.0, dockerfile-language-server 0.15.0, taplo and R `languageserver` | npm / `apk` / R |

`opencode/Dockerfile` pins engram, gentle-ai, marksman and the npm packages, and
**checksum-verifies the engram and gentle-ai downloads**. marksman is pinned by
release tag — a tag upstream can move — with no integrity check, and the npm
packages are pinned by version with no Dockerfile-level checksum. Everything else
resolves at build time (`latest` tags and unpinned `apk`), so **these versions
describe the image that was measured, not a forward guarantee**: to audit a
specific version, measure it again inside the container.

## Security model in five lines

The agents have no route of their own to the Internet (an `internal: true`
network with no gateway); their only egress is the proxy, which allows a list of
domains and denies everything else, including private and cloud-metadata ranges.
No ports are published, the Docker socket is never mounted, the proxy runs
read-only as uid 13, and all three containers drop capabilities with
`no-new-privileges`. The sharpest residual risk is that secrets are environment
variables, readable with `docker inspect`, and that `gh auth token` prints them
inside the container.

**Threats, measurements and the full residual-risk list: [`SECURITY.md`](SECURITY.md).**

## Deliberate decisions

- **Hermes has no GitHub credentials.** No `GITHUB_TOKEN`, no credential helper,
  no `~/.config/gh`. Private repos and pushes are delegated to OpenCode.
- **SSH is impossible, by design.** The proxy only allows `CONNECT` on port 443,
  so there is no route for SSH. The `git@github.com:` → HTTPS rewrite exists
  **only in the opencode container** (`/etc/gitconfig`); inside `hermes` you must
  use `https://` URLs directly.
- **No published ports**, neither the Hermes dashboard nor the opencode server.
- **Out of scope for now**: Docker rootless or `userns-remap`, secrets in
  `/run/secrets`, and `read_only: true` on the agents.

## Repository layout

```text
compose.yml                      the three services, networks, limits and mounts
SECURITY.md                      threat model, measurements and residual risks
.env.example                     the seven variable names, no values
opencode/Dockerfile              the coding agent's image (toolchain, LSPs, gentle-ai)
opencode/entrypoint.sh           applies gentle-ai artifacts and the overlay, then starts
opencode/overlay.json            the agent's own MCP, LSP and permission settings
squid/squid.conf                 Squid policy: default deny, no TLS interception
squid/allowlist.txt              the enabled domains, one per line
hermes/context/.hermes.md        environment facts Hermes reads on startup
hermes/skills/                   its own skills, mounted read-only
scripts/fix-permissions.ps1      aligns host folder ownership (uid 10000)
scripts/export-state.sh          exports volume-resident state to JSON
odd/tasks/                       decisions and evidence for each stage of the stack
```

## License

MIT — see [`LICENSE`](LICENSE). Copyright (c) 2026 Emilio Dávola.
