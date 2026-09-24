# Project: robotina

One autonomous agent with a shell on a shared workspace: Hermes (Telegram gateway) and an
OpenCode HTTP server run as supervised processes inside a **single** container named
`robotina`, with **no direct route to the Internet** — every outbound connection goes through
a separate Squid egress proxy that only admits an explicit domain allowlist. The design goal is
not "nothing happens" but **bounded blast radius**.

> Active SDD change: `single-robotina-container` — the two agent containers (`hermes` +
> `opencode`) were merged into one container named `robotina`, keeping `egress-proxy` separate.
> See `odd/tasks/single-robotina-container.md`.

## Stack

| Domain | Tool |
| --- | --- |
| Orchestration | Docker Compose v2 (`compose.yml`) |
| Images | Vendor base `nousresearch/hermes-agent:latest` + one custom Dockerfile (`robotina/Dockerfile`) |
| Host verified with | Docker 29.8.0, Docker Compose v5.5.1 (Windows + Docker Desktop) |
| Test runner | **none** — no unit-test framework exists in this repository |
| Linter / formatter / type checker | none configured |
| CI | none (GitHub Actions is disabled on this repository) |
| Secrets | gitignored `.env`, interpolated by compose; `.env.example` documents the keys |

## Services (current, one-agent layout)

| Service | Image | Notes |
| --- | --- | --- |
| `robotina` | `robotina:local` (built from `robotina/Dockerfile` over the vendor base) | The merged agent. Runs **s6-overlay as PID 1** (so no `init: true`), app uid 10000, `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, KILL]` (six capabilities, bounding mask `0xeb`). Hosts `opencode serve` on loopback, `engram`, and the Hermes Telegram gateway as s6 services. Carries the OpenCode toolchain (node/npm, uv + Python 3.13, R + `languageserver`, `gh`, engram, gentle-ai, codegraph, six LSP servers) plus `git`/`curl`/`python3`. Has `gh` **and** `GITHUB_TOKEN` (the retired "Hermes has no GitHub credential" invariant stays retired). |
| `egress-proxy` | `ubuntu/squid:latest` | Sole container with Internet egress. uid 13, read-only rootfs, tmpfs for logs/cache. **Stays separate** — not part of the merge. |

## Networks and persistence

- `agents` (`internal: true`) — agent + proxy, **no gateway**: no egress, no external DNS.
- `egress` (bridge) — used only by `egress-proxy`.
- **No service publishes a port.** The OpenCode server is reachable only at
  `http://127.0.0.1:4096` from inside `robotina`.
- State lives in host folders under `${HOST_DATA_DIR}` (`hermes/`, `workspace/`, `backups/`).
  The legacy `opencode/`, `git/` and `go/` folders are no longer mounted (they never existed on
  the authoring host); OpenCode state was consolidated under `/opt/data`.
- WAL SQLite DBs (`opencode.db`, `engram.db`) live on **native Docker volumes**
  (`robotina_opencode_db`, `robotina_engram_db`) mounted **nested inside** the `/opt/data`
  bind, at `/opt/data/.local/share/opencode` and `/opt/data/.engram`, because WAL over a
  Windows bind mount can corrupt silently. State is exported to JSON with
  `scripts/export-state.sh`.

## Repository layout

```
compose.yml                  # two services: robotina + egress-proxy; shared anchors x-hardening / x-egress-env
robotina/
  Dockerfile                 # merged image: vendor base + OpenCode toolchain + s6 tree
  overlay.json               # only what gentle-ai does not manage (lsp, mcp, permissions)
  opencode-init.sh           # oneshot: staged gentle-ai tree, per-key overlay merge, atomic write
  opencode-ready.sh          # oneshot: bounded credential-aware readiness poll on /global/health
  healthcheck.sh             # loopback health probe + `engram serve` existence check
  bin/opencode               # PATH wrapper: gives the local CLI OpenCode's own key
  s6/cont-init.d/            # 10-robotina-state (ownership), 20-robotina-identity (display.skin)
  s6/s6-rc.d/                # opencode, engram (longruns) + opencode-init, opencode-ready (oneshots)
hermes/
  skins/robotina.yaml        # identity skin (name + branding.agent_name), mounted read-only
  context/.hermes.md         # highest-priority environment facts, mounted at /workspace/.hermes.md
  skills/                    # repo-local skills, mounted read-only at /opt/data/skills/stack
    github-private-repos/SKILL.md  # PAT usage; the credential split is retired
    opencode-delegation/SKILL.md   # delegation to the local OpenCode CLI/server: executor agent, provider/model rule, non-blocking endpoint, single supervised server
squid/
  squid.conf                 # deny private ranges before the allowlist
  allowlist.txt              # the only permitted egress destinations
scripts/
  export-state.sh            # WAL DBs -> portable JSON in ${HOST_DATA_DIR}/backups
  migrate-state.ps1          # copy-forward migration of the legacy host folders (never deletes)
odd/tasks/*.md               # ODD feature trackers (English)
README.md / README.en.md     # Spanish / English, must be kept in sync
SECURITY.md                  # Spanish; guarantees, measurements, residual risks
.env.example                 # documents required variables (no values)
openspec/                    # SDD artifacts (this directory)
```

## Coupling map — what the merge must preserve

1. **The entrypoint owns PID 1.** The container runs s6-overlay and its entrypoint only
   `exec /init` when `$$ -eq 1`. Adding `init: true` or another PID 1 degrades it
   (`skipping s6-overlay /init ... Supervised services are unavailable`).
2. **s6 needs six capabilities** under `cap_drop: [ALL]` (bounding mask `0xeb`); without them
   startup dies at `s6-applyuidgid: fatal: unable to set supplementary group list`. `KILL` was
   added at apply (design §13.3) so the root supervisors can signal their uid-10000 children; the
   uid-10000 OpenCode process keeps none of them (`CapEff = 0x0`).
3. **The vendor image rejects uid 0 (and arbitrary `user:`).** It validates `HERMES_UID`
   1–65534 and silently discards 0, so uid alignment is done on the OpenCode side (uid 10000)
   — both processes share `/workspace` and, with `cap_drop: ALL`, a process without
   `CAP_DAC_OVERRIDE` cannot write another uid's files.
4. **The OpenCode toolchain is large** and is built, not copied: LSPs, engram
   (checksum-verified release), and gentle-ai artifacts generated by `gentle-ai install` at
   build time.
5. **Two distinct API keys are wired per process.** Hermes' key travels as the vendor-expected
   `OPENCODE_GO_API_KEY`; OpenCode's key travels as `ROBOTINA_OPENCODE_GO_API_KEY` and the
   `opencode` run script exports it as `OPENCODE_GO_API_KEY` **only for its own process**.
   At equal uid the isolation is not enforceable — the acceptance is "each process is
   configured with only its own key" (spec CR6).
6. **The egress boundary is a separate container.** Merging the agents must not merge the proxy.
7. **`/tmp` must be `exec`** for OpenCode.

## Conventions

- Compose comments and `SECURITY.md` / `README.md` are **Spanish**; `README.en.md` and
  `odd/tasks/*.md` are **English**; `openspec/` artifacts are **English**.
- Bilingual docs desynchronize: any measured claim changed in `README.md` MUST be changed in
  `README.en.md` in the same commit, or one document must own the claim and the other link to it.
- Compose uses YAML anchors (`x-hardening`, `x-egress-env`) — extend them, do not duplicate.
- Security invariants are non-negotiable: no published ports, no direct Internet for the agent,
  no Docker socket, `no-new-privileges:true`, `cap_drop: [ALL]` + minimal `cap_add`, core dumps
  off, bounded logs, resource limits.
- Secrets only through `.env` (gitignored). Never commit a token, never print one.

## Verification (real — there is no test runner)

| Layer | Command |
| --- | --- |
| Static validation | `docker compose config -q` — **`-q` is mandatory**; the bare form prints resolved `.env` secrets |
| Service inventory | `docker compose config --services` |
| Build | `docker compose build` |
| Runtime | `docker compose up -d` + `docker compose ps` (expect exactly `robotina` and `egress-proxy`) |
| Probes | in-container `curl -fsS http://127.0.0.1:4096/global/health`; the same URL MUST fail from the host and from `egress-proxy`; per-process key configuration check |
| Docs | grep for stale two-container claims in `README.md`, `README.en.md`, `SECURITY.md`, `hermes/` |
| Secrets | grep tracked files for real secret values (must find none) |

## SDD session configuration (from preflight, 2026-09-22)

- Artifact store: `openspec` (this directory).
- Execution: interactive (auto mode enabled).
- Delivery strategy: `ask-on-risk`; review budget **400 authored changed lines**. The user
  accepted a per-slice `size:exception` of roughly **650** authored lines for this change's
  chained slices.
- Chain strategy: **`feature-branch-chain`** — tracker `feat/single-robotina-container`; each
  slice branches from the previous one and merges bottom-up.
- `exception-ok`: accepted per slice by explicit user decision (recorded in
  `odd/tasks/single-robotina-container.md`); never inferred.
- Strict TDD: **false** — the project declares no test runner; do not invent one.
- Branch: `feat/single-robotina-container` (tracker); never commit to `main`, merge via PR.

## Known traps

- `docker compose config` without `-q` leaks every interpolated secret.
- `docker inspect` must always use a narrow `--format` that excludes `.Config.Env`.
- MSYS/Git Bash rewrites absolute paths: prefix `MSYS_NO_PATHCONV=1` for
  `docker compose run --entrypoint /usr/sbin/squid egress-proxy ...`.
- A GitHub `403` for git-over-HTTPS (`remote: Write access to repository not granted.`) is a
  token/permission problem, not a Squid denial (Squid returns an HTML error page).
  `git ls-remote` is refs-only and never proves a clone.
- An s6 oneshot `up` file is executed **as execline**, not as a shell script; it must be a
  single command line starting with an absolute executable path.
- `chown` in the image has no `--one-file-system`; a recursive ownership pass over `/opt/data`
  must prune the read-only mounts (`/opt/data/skins`, `/opt/data/skills/stack`). Add every new
  mount under `/opt/data` to that prune list.
- Changing the Dockerfile does not recreate the container: `docker compose up -d` compares the
  declared config, not the image contents — use `--force-recreate` after a build.
- `HOST_DATA_DIR` is mandatory: if missing, the stack refuses to start (state must never end
  up hidden inside the repo).
