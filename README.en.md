# Robotina

[Español](README.md) · [English](README.en.md)

One autonomous agent, in a **single container**, over a shared workspace and
with **no direct route to the Internet**: all its egress goes through a Squid
proxy that only lets a whitelist of domains out. Inside the container live
Hermes (the Telegram gateway), `opencode serve` (the coding server) and `engram`
(the memory), all supervised by s6.

| Piece | What it is |
| --- | --- |
| **robotina** | The single container. Runs Hermes (Telegram gateway), `opencode serve` (loopback only) and `engram`, supervised by s6. `HOME=/opt/data`, uid 10000. |
| **egress-proxy** | Squid with a domain allowlist. It is the only container with a way out. |
| **Security model** | [`SECURITY.md`](SECURITY.md) — guarantees, measurements and residual risks. |

## What it solves

Handing an autonomous agent a shell and a GitHub token is handing an attacker a
shell and a token. This stack does not try to make "nothing happen": it
**bounds the damage**. The agent lives on an internal network with no gateway,
egress is an explicit list of domains, nothing is published, and state lives in
host folders you can inspect. The useful question stops being "did something
happen?" and becomes "how far can it get?".

## Architecture

```text
                    host: ${HOST_DATA_DIR}/
                    ├── hermes/      (agent HOME: config, sessions, SOUL.md)
                    │   ├── .engram/                 ← volume mount point (empty on the host)
                    │   └── .local/share/opencode/   ← volume mount point (empty on the host)
                    ├── workspace/   (the code the agent sees)
                    └── backups/     (JSON exports of volume-resident state)

                    native Docker volumes (nested inside the bind)
                    ├── robotina_opencode_db   (opencode sessions — WAL)
                    └── robotina_engram_db     (agent memory    — WAL)

  network "agents" (internal: true, NO gateway: no route, no external DNS)
  ┌────────────────────────────────────┐   ┌────────────────┐
  │              robotina              │   │  egress-proxy  │
  │  s6 supervises:                    │──▶│  squid :3128   │
  │   • hermes gateway  (Telegram)     │   │  uid 13, rootfs│
  │   • opencode serve  :4096 loopback │   │  read-only     │
  │   • engram                         │   └───────┬────────┘
  │  uid 10000 · HOME=/opt/data        │           │  network "egress" (has a gateway)
  └────────────────────────────────────┘           ▼
        │                                CONNECT/GET only to squid/allowlist.txt
        └── /workspace (host bind)       (.telegram.org, .opencode.ai, .github.com,
                                          .pypi.org, proxy.golang.org, …)
```

Three consequences of the design worth knowing up front:

- **The OpenCode server listens on `127.0.0.1:4096`, loopback only.** You cannot
  reach it from the host or from another container: to drive it you go into the
  container with `docker compose exec robotina …` (recipes below). The agent also
  has the `opencode` CLI installed locally, which is the normal path. It is
  documented by the vendor's builtin `opencode` skill (the CLI) and by the repo's own
  `hermes/skills/opencode-delegation/SKILL.md` (delegation to OpenCode: the executor
  agent, the provider/model rule, the non-blocking endpoint and the single supervised
  server).
- **The whole container shares one `HOME`** (`/opt/data`) and one uid (10000).
  Hermes state, the OpenCode config and the git config all land inside the
  `${HOST_DATA_DIR}/hermes` bind.
- **The single container has `gh` and `GITHUB_TOKEN`.** The token lives in the
  whole container: Hermes and OpenCode both see it. Private repos and pushes are
  no longer delegated for lack of a credential.

### What replaced the previous layout

If you are coming from the version with Hermes and OpenCode in **separate
services**, this is what changed and why:

- `robotina/Dockerfile` replaces `opencode/Dockerfile`: one image over the
  vendor Debian base, with the toolchain, the LSPs and gentle-ai already
  inside.
- s6 (`robotina/s6/`) supervises the three programs inside the same container,
  instead of one entrypoint per service.
- The OpenCode server now listens on loopback (`127.0.0.1:4096`): there is no
  network between agents, because the three programs are processes of the same
  container.
- State ownership is fixed by the container itself at startup
  (`robotina/s6/cont-init.d/10-robotina-state`), not by a privileged script on
  the host.
- State that lived in `${HOST_DATA_DIR}/opencode` and `${HOST_DATA_DIR}/git` is
  copied into `${HOST_DATA_DIR}/hermes/.config/` by a migration step (see
  "Migration").

## Requirements

- Docker (the design assumes Windows bind mounts, and the startup path was
  measured there).
- Docker Compose v2.
- A Telegram bot token (`@BotFather`).
- A model provider key (compose uses **two names**: one for Hermes and one for
  OpenCode).
- Optional: a fine-grained GitHub PAT with **only the repositories you need** and
  Contents read/write, so the agent can clone private repos and push.
- Internet access on the host to build the image: **the build does not go
  through Squid**.
- Optional, only if you migrate state on Windows: PowerShell 7 (`pwsh`) for
  `scripts/migrate-state.ps1`. Linux/macOS has a documented POSIX equivalent.

## Getting started

1. Clone the repo. `main` is the default branch; if the single container is not
   merged there yet, clone the working branch:

   ```bash
   git clone -b feat/single-robotina-container https://github.com/emiliodavola/robotina.git
   ```

   (If you can see this README, you are on the right branch.)

2. Create `.env` from the template and fill in the **four mandatory** values:
   compose aborts with an explicit message if any of them is missing.

   ```bash
   cp .env.example .env
   ```

   ```ini
   HOST_DATA_DIR=C:/robotina-data          # host folder that holds all the state
   ROBOTINA_TELEGRAM_BOT_TOKEN=            # from @BotFather
   ROBOTINA_HERMES_MODEL_KEY=              # key used by Hermes
   ROBOTINA_OPENCODE_MODEL_KEY=            # key used by OpenCode
   ROBOTINA_TELEGRAM_ALLOWED_USERS=        # optional: who may use the bot
   ROBOTINA_OPENCODE_SERVER_PASSWORD=      # optional: HTTP Basic for the server
   ROBOTINA_GITHUB_TOKEN=                  # optional: fine-grained PAT
   ```

   The two model keys are published under distinct names on purpose:
   `ROBOTINA_HERMES_MODEL_KEY` reaches the Hermes process under the name the
   vendor image expects, and `ROBOTINA_OPENCODE_MODEL_KEY` is re-exported by the
   `opencode` run script **only inside its own process**. `.env` is gitignored;
   its values are readable with `docker inspect`, an accepted risk documented in
   `SECURITY.md`.

   **Why the names start with `ROBOTINA_`.** Docker Compose gives the process
   environment precedence over `.env`. If you left a shell variable exported
   under the same name as one of these keys — the real case was
   `OPENCODE_GO_API_KEY`, the vendor's own name — that exported value silently
   overrode `.env` and the container started with a stale credential. The
   `ROBOTINA_` prefix does not exist in the host environment, so the collision is
   impossible. In practice: **do not export these variables in your shell**; edit
   `.env` and recreate the container.

3. Configure Hermes' model (optional). The `30-robotina-model` cont-init applies
   this configuration **automatically on every startup**, so you do not have to
   edit `config.yaml` by hand. The defaults are already the OpenCode Go ones:

   ```ini
   ROBOTINA_HERMES_MODEL_PROVIDER=     # default: opencode-go
   ROBOTINA_HERMES_MODEL_BASE_URL=     # default: https://opencode.ai/zen/go/v1
   ROBOTINA_HERMES_MODEL=              # default: deepseek-v4.1-flash
   ```

   Leave them empty to use the defaults, or set an id from the plan's catalog to
   change it (without the `opencode-go/` prefix). With this, Hermes points at
   `opencode-go` instead of the `provider: auto` the vendor seeds, which cannot
   work here: `openrouter.ai` is deliberately outside Squid's allowlist, and with
   `auto` Hermes resolves to the only provider with a credential.
   **If you point Hermes at another provider, that host also has to be in
   `squid/allowlist.txt`**, or the request dies at the proxy. To change it on a
   running stack, use the recipe under "Model and provider plan" below.

4. Build the agent image (the service references it as `robotina:local`):

   ```bash
   docker compose build robotina
   ```

5. Bring the stack up:

   ```bash
   docker compose up -d
   ```

   **There is no host permission step.** The container fixes ownership of
   `/opt/data`, `/workspace` and `/backups` at startup, running as root before
   any service. A freshly created state folder ends up writable by uid 10000
   without your running anything privileged outside.

6. Check that it came up:

   ```bash
   docker compose ps
   docker compose exec robotina hermes status
   ```

7. If you came from the previous layout, migrate the state (see "Migration").

8. In BotFather, rename the bot's public **display name** to `robotina`. It is
   the only manual Telegram-side step: you do not need to change the public
   handle, and the token in `.env` stays the same. Message the bot. With
   `ROBOTINA_TELEGRAM_ALLOWED_USERS` empty, Hermes answers unknown users with a
   pairing code instead of obeying them: that list is the access control, not the
   network.

## Using it

**Over Telegram.** The front door. Hermes can do work itself or delegate it to
the local OpenCode server.

**Inside the container.** Because the OpenCode server is loopback-only, the only
way to inspect things is `docker compose exec robotina …`:

```bash
# Service status and the s6 supervision tree
docker compose ps
docker compose exec robotina hermes status
docker compose exec robotina /command/s6-rc -a list

# Local endpoint health (credential-aware: passes -u only when a password is set)
docker compose exec robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/global/health'

# Bounded logs (the container stream carries all three processes)
docker compose logs --tail 200 robotina

# OpenCode's own log (the server detail, not the s6 stream)
docker compose exec robotina tail -n 200 /opt/data/.local/share/opencode/log/opencode.log

# Export volume-resident state to JSON
docker compose exec robotina sh /opt/export-state.sh
```

Two operating notes:

- The s6 tools live in `/command`, which is **not** on the container's default
  `PATH`; invoke them with the full path.
- In Git Bash, use `MSYS_NO_PATHCONV=1` for absolute container paths, so the
  host shell does not rewrite them.

The OpenCode HTTP API (`GET /doc` as OpenAPI, `GET /global/health`,
`POST /session`, `POST /session/{id}/message` and friends) exists, but it is
**only reachable from inside the container**, over loopback. With
`OPENCODE_SERVER_PASSWORD` set it requires HTTP Basic (user `opencode`).

For server-level detail there is a dedicated log at
`/opt/data/.local/share/opencode/log/opencode.log`, and `GET /event` streams a session's live
progress (SSE). The full runbook is in `SECURITY.md`.

## Migration from the previous layout

If your `${HOST_DATA_DIR}` holds the previous layout's folders, copy the state
into the new path. The helper **copies forward and never overwrites**: it only
copies a path when the destination does not exist, so a newer destination file
is left alone. It deletes and moves nothing: the legacy folders are the rollback
safety net.

**Before migrating, take an export as a safety net** (cheap and portable):

```bash
docker compose exec robotina sh /opt/export-state.sh
# -> ${HOST_DATA_DIR}/backups/engram-<date>.json
# -> ${HOST_DATA_DIR}/backups/opencode-<session>-<date>.json
```

On Windows, with the repo helper (it reads `HOST_DATA_DIR` from `.env`):

```bash
pwsh -File scripts/migrate-state.ps1
```

On Linux/macOS, the documented POSIX equivalent. `cp -an` never overwrites the
destination (the `-n` is "no clobber"); with `rsync` the flag is
`--ignore-existing`. To mirror the helper's `node_modules/` skip, add the
`--exclude`:

```bash
cp -an "$HOST_DATA_DIR/opencode/." "$HOST_DATA_DIR/hermes/.config/opencode/"
cp -an "$HOST_DATA_DIR/git/."      "$HOST_DATA_DIR/hermes/.config/git/"

# or, with rsync:
rsync -a --ignore-existing --exclude 'node_modules' \
  "$HOST_DATA_DIR/opencode/" "$HOST_DATA_DIR/hermes/.config/opencode/"
rsync -a --ignore-existing \
  "$HOST_DATA_DIR/git/" "$HOST_DATA_DIR/hermes/.config/git/"
```

`GOPATH` (`${HOST_DATA_DIR}/go`) is **not** copied: it is a rebuildable cache.
Running the migration before or after the first start makes no difference:
nothing in compose or in the image calls it, and the container comes up fine
with the migration never run.

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
agent's traffic. The allowlist bounds **where** it talks, not **what** it
sends: see "Puntos de atención" in `SECURITY.md`.

## State, volumes and persistence

Both SQLite databases use WAL and live on **native Docker volumes, nested inside
the `${HOST_DATA_DIR}/hermes` bind**. That is not a whim: WAL on a Windows folder
(virtiofs/9p) can be silently corrupted.

| What | Where it lives | Notes |
| --- | --- | --- |
| Hermes state (config, sessions, SOUL.md) | bind `${HOST_DATA_DIR}/hermes` → `/opt/data` | rw; it is the `HOME` of the process tree |
| engram memory (SQLite WAL) | volume `robotina_engram_db` → `/opt/data/.engram` | native, nested inside the bind |
| OpenCode sessions (SQLite WAL) | volume `robotina_opencode_db` → `/opt/data/.local/share/opencode` | native, nested inside the bind |
| Shared workspace | bind `${HOST_DATA_DIR}/workspace` → `/workspace` | rw |
| Export output | bind `${HOST_DATA_DIR}/backups` → `/backups` | rw |

Docker creates `${HOST_DATA_DIR}/hermes/.engram` and
`${HOST_DATA_DIR}/hermes/.local/share/opencode` as **ordinary, empty** host
directories: they are mount points that the volumes shadow. Seeing them empty is
expected; a `.db` showing up there would mean the nesting failed and the
databases landed on the bind.

To get that volume-resident state out in a portable, readable format:

```bash
docker compose exec robotina sh /opt/export-state.sh
# -> ${HOST_DATA_DIR}/backups/engram-<date>.json
# -> ${HOST_DATA_DIR}/backups/opencode-<session>-<date>.json
```

An explicit trade-off: those two databases cannot be opened by hand from
Explorer, and a factory reset of Docker Desktop deletes them. The JSON files do
survive.

**The numeric proofs in this documentation assume the default uid.** The image's
`hermes` user is uid 10000, and the recipes that print `10000:10000`,
`CapBnd=0x00000000000000eb` or `pids.max=1024` hold for that configuration. A
different `HERMES_UID` invalidates them without invalidating the design.

## Versions

Measured inside the running containers, not copied from documentation.

| Component | Version | How it gets there |
| --- | --- | --- |
| opencode | 1.18.32 | glibc x64 asset, exact version pinned in `robotina/Dockerfile` |
| Squid | 6.13 | `ubuntu/squid:latest` |
| Hermes | — | `nousresearch/hermes-agent:latest` |
| git / gh | 2.47.3 / 2.97.0 | vendor base / pinned release |
| Go / uv / jq / ripgrep | 1.24.4 / 0.11.6 / 1.7 / 14.1.1 | vendor base / uv installer / `apk` |
| Python | 3.13.5 | Hermes venv interpreter |
| Node | v26.5.1 | vendor base |
| R | 4.5.0 | vendor base |
| engram | 1.20.0 | release, checksum-verified |
| gentle-ai | 3.1.0 | release, checksum-verified |
| taplo / marksman / codegraph | 0.10.0 / 2026-02-08 / 1.5.0 | releases pinned by tag |

`robotina/Dockerfile` pins the version of opencode, gh, taplo, marksman,
codegraph, engram, gentle-ai and the npm packages, and **checksum-verifies the
downloads that expose one**. marksman is pinned by release tag, with no
integrity check. Everything else resolves at build time (`latest` tags and
unpinned `apk`), so **these versions describe the image that was measured, not a
forward guarantee**: to audit a specific version, measure it again inside the
container.

## Security model in five lines

The agent has no route of its own to the Internet (an `internal: true` network
with no gateway); its only egress is the proxy, which allows a list of domains
and denies everything else, including private and cloud-metadata ranges. No
ports are published, the Docker socket is never mounted, the proxy runs
read-only as uid 13, and the containers drop capabilities with
`no-new-privileges`. The sharpest residual risk is that secrets are environment
variables, readable with `docker inspect`, and that `gh auth token` prints them
inside the container.

**Threats, measurements and the full residual-risk list: [`SECURITY.md`](SECURITY.md).**

## Deliberate decisions

- **A single lifecycle, and it is the container's.** The Hermes gateway is an s6
  service (`gateway-default`): if it falls, s6 restarts it **in place** and the
  container stays up, with `RestartCount` and `StartedAt` unchanged. What is
  shared is the container's lifecycle: it exits when the **s6 supervision tree**
  goes down, not when Hermes exits, and `opencode` and `engram` go with it. This
  is the merge's accepted regression (R4 in `SECURITY.md`).
- **One uid for the whole tree (10000).** Per-process key isolation is not
  enforceable at equal uid; what is required is that each process is configured
  **with only its own key**, and startup verifies it (R2).
- **SSH is impossible, by design.** The proxy only allows `CONNECT` on port 443,
  so there is no route for SSH. The `git@github.com:` → HTTPS rewrite lives in
  the image's `/etc/gitconfig`, so it applies to the whole container.
- **No published ports**, neither the Hermes dashboard nor the OpenCode server.
- **Out of scope for now**: Docker rootless or `userns-remap`, secrets in
  `/run/secrets`, and `read_only: true` on the agent.

## Repository layout

```text
compose.yml                      the two services, networks, limits and mounts
SECURITY.md                      threat model, measurements and residual risks
.env.example                     the variable names, no values
robotina/Dockerfile              the agent's image (toolchain, LSPs, gentle-ai)
robotina/opencode-init.sh        applies gentle-ai artifacts and the overlay, then starts
robotina/overlay.json            the agent's own MCP, LSP and permission settings
robotina/s6/                     supervision: cont-init and the s6 services
squid/squid.conf                 Squid policy: default deny, no TLS interception
squid/allowlist.txt              the enabled domains, one per line
hermes/skins/robotina.yaml       the agent's displayed identity, mounted read-only
hermes/context/.hermes.md        environment facts Hermes reads on startup
hermes/skills/                   its own skills (github-private-repos, opencode-delegation), mounted read-only
scripts/migrate-state.ps1        copies the previous layout's state forward
scripts/export-state.sh          exports volume-resident state to JSON
odd/tasks/                       decisions and evidence for each stage of the stack
```

## License

MIT — see [`LICENSE`](LICENSE). Copyright (c) 2026 Emilio Dávola.
