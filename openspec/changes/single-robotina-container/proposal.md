# Proposal — single-robotina-container

Change: `single-robotina-container` · Branch: `feat/single-robotina-container`
Artifact store: `openspec/` (this file is the artifact of record for the propose phase)
Evidence base: `openspec/changes/single-robotina-container/explore.md` (complete)
Upstream: `odd/tasks/single-robotina-container.md`
Phase: propose (nothing implemented; no spec/design/tasks authored here)

---

## 1. Intent

Today the robotina stack runs **two agent containers** (`hermes`, `opencode`) joined only by
an HTTP hop over the internal `agents` network plus a shared `/workspace` bind. The user has
reported that the split does not work for them and wants a **single agent container**.

This proposal is the PRD for that merge: collapse both agents into **one** container whose
service and container name is `robotina`, which

1. **answers to the name `robotina`** — as a container (`docker compose exec robotina …`),
   as an egress peer, and as the agent's own identity;
2. **ships the OpenCode HTTP server bound to loopback `127.0.0.1:4096`** inside that
   container, and reachable from nowhere else;
3. **keeps two distinct API keys**, one per agent, each process configured with only its own.

`egress-proxy` (Squid) stays a **separate container** and the egress boundary is unchanged.

The merge retires a deliberately built property: the two-container split was chosen for
isolation and its Evidence block in `odd/tasks/agent-interop-http.md` calls that isolation
"preserved". Retiring it is a **product decision already taken by the user** (D1–D5), not a
defect fix. This proposal's job is to state the resulting model honestly — including the
parts that get **worse** — so it can be approved with eyes open.

## 2. What changes for the user (in one paragraph)

One container instead of two: fewer moving parts, one image to build, one lifecycle to
watch, and the OpenCode HTTP surface removed from the network entirely (it becomes
loopback-only, which closes a documented `egress-proxy` → opencode pivot path). In exchange,
the isolation the two-container split provided is gone: the Telegram-facing agent now shares a
uid, a filesystem, a capability set, a resource budget and a process lifetime with the coding
agent, **and** it now has GitHub credentials. That trade was made deliberately; this proposal
makes it explicit and testable.

## 3. Scope

### 3.1 In scope

- **Image composition**: build `FROM nousresearch/hermes-agent:latest` and port the OpenCode
  toolchain (opencode binary, `gh`, `jq`, `ripgrep`, R + `languageserver`, `taplo`,
  `marksman`, three npm LSPs, codegraph, uv-managed CPython, `engram`, `gentle-ai`, `go`,
  merged `/etc/gitconfig`) into it.
- **Supervision wiring**: `opencode serve` and `engram` become **s6 longruns** registered in
  the vendor's empty `user2` bundle, with an `opencode-init` oneshot for idempotent file
  work. The container CMD stays Hermes' main program.
- **Naming**: compose service + `container_name` = `robotina`; image tag, build directory and
  every doc/script reference follow.
- **Loopback server**: `opencode serve --hostname 127.0.0.1 --port 4096`, with a readiness
  guarantee so Hermes' first delegation does not race startup.
- **Credentials**: two distinct keys preserved under distinct env names, each process
  configured with only its own; `GITHUB_TOKEN` present in the merged container (D3).
- **Identity**: Hermes skin `robotina` (`branding.agent_name`) shipped from the repo, mounted
  read-only into `<HERMES_HOME>/skins/`, selected via `display.skin`; plus an explicit
  identity statement in the always-loaded context file; plus a documented BotFather step.
- **State layout (D5)**: OpenCode state consolidated under `/opt/data` (`HOME=/opt/data`),
  with the two WAL SQLite stores kept on native Docker volumes.
- **State migration**: a copy-forward, idempotent, **non-blocking** migration of the existing
  legacy host folders into the new `/opt/data/...` locations, documented in both READMEs and
  never deleting the pre-merge folders (§8.2).
- **In-container operator recipes**: because the OpenCode server is loopback-only, the
  inspection/export recipes that replace human access SHALL be documented in `README.md` and
  `README.en.md` (§17 answer 5).
- **Compensating simplification**: move host-state ownership fixing from the mandatory
  host-side `scripts/fix-permissions.ps1` (unpinned `alpine:latest` as root, host state bind
  mounted) into a container-side cont-init script.
- **Documentation truth-up**: every file enumerated in `explore.md` §7.1 — including the
  always-loaded `hermes/context/.hermes.md` and both Hermes skills — is rewritten to the
  single-container reality.
- **Security documentation**: `SECURITY.md` gains explicit entries for the retired credential
  invariant and for the unenforceable per-process isolation.

### 3.2 Out of scope (explicit non-goals)

- **Merging `egress-proxy`** into `robotina`, or touching `squid/squid.conf` /
  `squid/allowlist.txt`.
- **Publishing any port**, adding a Docker socket, or giving `robotina` direct Internet.
- **Exposing the OpenCode TUI/CLI** — only the HTTP server on loopback is required.
- **Re-opening D1–D5.** The direction, the accepted regressions, the credential decision, the
  identity mechanism and the state-root decision are frozen inputs.
- **Adding explicit capability dropping** to the OpenCode process (D2: accepted regression,
  no extra capability work). *Measurement of the actual `CapEff` set is still in scope, as
  evidence for `SECURITY.md` — only the mitigation is out of scope.*
- **Making per-process key isolation enforceable.** It cannot be done at equal uid, and
  redesigning uid separation / workspace sharing is a separate change.
- Introducing a test framework. This repository has no test runner; verification stays
  shell-level.
- Rewriting the history in `odd/tasks/agent-interop-http.md` — it gets a superseded note.

## 4. Approach (approvable level)

**4.1 Direction.** Compose the merged image from the vendor Debian 13 base
(`FROM nousresearch/hermes-agent:latest`). The reverse direction is proven infeasible: the
Hermes application tree (CPython venv, Debian-built s6-overlay) is glibc-bound and has no
Alpine/musl equivalent (D1).

**4.2 Build-time work.** Add the missing toolchain to the vendor base, skipping everything
the vendor base already covers (`bash`, `tar`, `xz`, `tzdata`, `ca-certificates`, `node`,
`npm`, `uv`, `git`, `curl`). The Hermes venv at `/opt/hermes/.venv` must stay unshadowed: the
uv-managed CPython added for agent work is never symlinked over `/usr/local/bin/python3`.
Install a **glibc** opencode build (`opencode-ai@1.18.32` publishes `opencode-linux-x64`
alongside `-musl`); do **not** ship the Alpine musl node shim for `codegraph`. Keep the
vendor `ENTRYPOINT` untouched and leave the vendor `CMD` free for compose's
`["gateway", "run"]`.

**4.3 Runtime shape.** Add `opencode-init` (oneshot), `engram` (longrun) and `opencode`
(longrun) under `/etc/s6-overlay/s6-rc.d/`, each depending on `base`, all registered in the
vendor's empty `user2` bundle — the vendor's own extension slot. The `opencode` run script
drops to the app uid with `s6-setuidgid hermes`, sets its own `HOME`, exporter variables and
API key, and execs `opencode serve --hostname 127.0.0.1 --port 4096`. Because `/init` brings
the whole tree up *before* exec'ing the CMD, opencode starts **before** Hermes and must never
be the CMD. Consequently the two processes share a lifetime: if Hermes exits, the container
exits and takes opencode and engram with it (accepted regression R4).

**4.4 Process-level configuration.** Compose sets both keys under **distinct names**; the
opencode run script exports the vendor-expected name **for its own process only**. Hermes'
main program inherits its own value. No vendor file is patched.

**4.5 Compose shape.** One service `robotina` (no `user:`, no `init: true`, merged resource
limits, `NO_PROXY` updated to `…,robotina,egress-proxy`, `cap_add` unchanged — Hermes still
needs the five), plus the unchanged `egress-proxy` service.

## 5. Requirement set

Requirement IDs are provisional; `sdd-spec` owns final numbering and Given/When/Then form.
Every requirement below names the **exact observation** that proves it (no test runner
exists — recipes are shell-level, per `openspec/config.yaml`).

### A. One container, named `robotina`

| ID | Requirement | Proof |
| --- | --- | --- |
| A1 | The compose file SHALL define exactly two services: `robotina` and `egress-proxy`. The `hermes` and `opencode` services SHALL cease to exist. | `docker compose config --services` → `robotina`, `egress-proxy` |
| A2 | The `robotina` container SHALL have `container_name: robotina`. | `docker compose ps --format '{{.Name}}'` |
| A3 | `robotina` SHALL NOT declare `user:`, SHALL NOT declare `init: true`, and SHALL RUN with the image entrypoint as PID 1 (s6-overlay). | `docker compose config -q`; `docker compose exec robotina sh -c 'tr "\0" " " < /proc/1/cmdline'` |
| A4 | `robotina` SHALL keep `cap_drop: [ALL]` plus exactly the five capabilities Hermes requires (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`), `no-new-privileges:true`, `ulimits.core: 0`, `pids_limit`, and bounded json-file logs. | `docker compose exec robotina sh -c 'grep -E "Cap(Bnd|Eff)" /proc/1/status'` |
| A5 | `opencode` and `engram` SHALL run as supervised s6 services (visible to s6), not as backgrounded children of an entrypoint. | `docker compose exec robotina s6-rc -a list` includes `opencode`, `engram` |
| A6 | The merged service SHALL carry a single consolidated budget: `mem_limit: 6g`, `cpus: 6.0` (decided, §17 answer 4), plus a `pids_limit` sized for Hermes + opencode + LSP children + engram + builds (`pids_limit` value pending measurement — §6.2 R5). | `docker compose config -q`; `docker compose exec robotina sh -c 'cat /sys/fs/cgroup/pids.max'` |
| A7 | `robotina` SHALL join only the `agents` network and SHALL publish no ports. | `docker compose config -q`; `docker compose ps --format '{{.Ports}}'` empty |

### B. OpenCode HTTP server on loopback inside `robotina`

| ID | Requirement | Proof |
| --- | --- | --- |
| B1 | `opencode serve` SHALL listen on `127.0.0.1:4096` inside `robotina`, and SHALL NOT listen on `0.0.0.0`. | `docker compose exec robotina sh -c 'curl -fsS http://127.0.0.1:4096/global/health'` |
| B2 | The server SHALL NOT be reachable from the host. | host-side `curl -m 5 http://127.0.0.1:4096/global/health` fails (no published port) |
| B3 | The server SHALL NOT be reachable from any other container, including `egress-proxy`. | `docker run --rm --network agents curlimages/curl -m 5 http://robotina:4096/global/health` fails; `docker compose exec egress-proxy bash -c 'exec 3<>/dev/tcp/robotina/4096'` fails |
| B4 | The server SHALL be ready before Hermes' first delegation can reach it; s6 "service started" SHALL NOT be treated as "port listening". | `docker compose up -d` then an immediate in-container health check (bounded retry) succeeds without a manual restart |
| B5 | The OpenCode server process SHALL run as the app uid (10000), not as root. | `docker compose exec robotina sh -c 'grep -E "^Uid" /proc/$(pgrep -f "opencode serve")/status'` |
| B6 | `OPENCODE_SERVER_PASSWORD` semantics SHALL be re-documented: after the merge it is defense-in-depth only, because no network peer can reach the port. Whether the variable is kept is an open question (§10). | `grep -n OPENCODE_SERVER_PASSWORD SECURITY.md README.md README.en.md` |

### C. Two distinct API keys, one per agent

| ID | Requirement | Proof |
| --- | --- | --- |
| C1 | `.env` SHALL keep two independent inputs: `HERMES_OPENCODE_GO_API_KEY` and `OPENCODE_GO_API_KEY`. Their values SHALL remain independently settable. | `git grep -n "HERMES_OPENCODE_GO_API_KEY\|OPENCODE_GO_API_KEY" -- .env.example compose.yml` |
| C2 | Hermes' process SHALL be configured with the Hermes key only, under the vendor-expected name `OPENCODE_GO_API_KEY`. | `/proc/<hermes-pid>/environ` hash of `OPENCODE_GO_API_KEY` = hash of the Hermes value |
| C3 | The OpenCode process SHALL be configured with the OpenCode key only, under the name `OPENCODE_GO_API_KEY`, scoped to its own process (set in the run script, not container-wide). | `/proc/<opencode-pid>/environ` hash of `OPENCODE_GO_API_KEY` = hash of the OpenCode value and **differs** from the Hermes hash |
| C4 | No secret value SHALL be echoed, logged or written to a tracked file by any test, script or doc. | `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'` finds nothing |
| C5 | `GITHUB_TOKEN` SHALL remain available in `robotina` (D3), and the "Hermes has no GitHub credential" invariant SHALL be formally retired in `SECURITY.md`. | `docker compose exec robotina sh -c 'test -n "$GITHUB_TOKEN" && echo present'`; `grep -n "sin credencial\|no GitHub credential" SECURITY.md hermes/` returns nothing |

**Key-distinctness probe (secret-safe — hashes only, never the value):**

```bash
docker compose exec robotina sh -c '
  for p in $(pgrep -f "opencode serve"); do echo "opencode: $(tr "\0" "\n" < /proc/$p/environ | grep "^OPENCODE_GO_API_KEY=" | sha256sum)"; done
  for p in $(pgrep -f "hermes");        do echo "hermes:   $(tr "\0" "\n" < /proc/$p/environ | grep "^OPENCODE_GO_API_KEY=" | sha256sum)"; done'
# two different hashes == two different values; nothing secret is echoed
```

### D. Frozen invariants (regression-guarded, not modified by this change)

IDs are `INV*` to avoid colliding with the frozen product decisions `D1`–`D5` used elsewhere in
this document.

| ID | Requirement | Proof |
| --- | --- | --- |
| INV1 | No service SHALL publish a port; no Docker socket SHALL be mounted; secrets SHALL come only from the gitignored `.env`. | `docker compose config -q`; `grep -rn "docker.sock" compose.yml` |
| INV2 | `robotina` SHALL have no direct Internet route; all egress SHALL go through `egress-proxy`. | `docker compose exec robotina sh -c 'curl -m 5 -sS https://example.com'` fails; `docker compose exec robotina sh -c 'curl -m 10 -sS https://<allowed-domain>'` succeeds |
| INV3 | `NO_PROXY` SHALL reference `robotina` (not `hermes`/`opencode`) and SHALL keep `127.0.0.1`, so the loopback hop never touches Squid. | `docker compose exec robotina sh -c 'printenv NO_PROXY'` |
| INV4 | `squid/squid.conf` and `squid/allowlist.txt` SHALL be byte-identical after this change. | `git diff --exit-code -- squid/` |
| INV5 | The stack SHALL refuse to start without `HOST_DATA_DIR` (state never hidden inside the repo). | `docker compose config -q` with `HOST_DATA_DIR` unset exits non-zero |

## 6. Security-model deltas

This is the section requiring explicit sign-off. The deltas are split honestly: what gets
*safer*, and what gets *worse* and is accepted.

### 6.1 Improvements

| # | Delta | Why it matters |
| --- | --- | --- |
| I1 | The OpenCode HTTP surface moves from `0.0.0.0:4096` to `127.0.0.1:4096`. | Removes the documented `egress-proxy` → opencode pivot, which `SECURITY.md` recorded as a real privilege jump from the proxy into an agent. After the merge, **no network peer** can reach the server. |
| I2 | Host-state ownership fixing moves into a container-side cont-init script. | Deletes a mandatory host step that ran **unpinned `alpine:latest` as root with host state bind-mounted** — a documented trap in `openspec/project.md` and `SECURITY.md`. Also deletes a host-side prerequisite from setup. |
| I3 | One fewer container. | One fewer network member, one fewer lifecycle, one fewer image to rebuild, one fewer `docker inspect` surface to audit. |

### 6.2 Accepted regressions (documented in `SECURITY.md`, no mitigation work per D2)

| # | Regression | Honest statement required in `SECURITY.md` |
| --- | --- | --- |
| R1 | **The GitHub credential invariant is retired.** `GITHUB_TOKEN`, `gh` and the git credential helper now live in the same container as the Telegram-facing agent. | Prompt injection into the bot now reaches GitHub directly (read private repos, push) instead of being stopped at the delegation boundary. The always-loaded context file and both Hermes skills must stop claiming otherwise. **Decided (§17 answer 1): the PAT is kept as-is — no narrowing work is part of this change.** |
| R2 | **Per-process key isolation is not enforceable.** Same uid, same container: `/proc/<pid>/environ`, `/proc/<pid>/fd` and any file the other process writes are reachable in principle. | The acceptance criterion "each process is configured with only its own key" is satisfiable; "neither can read the other's key" is **not**. Relying on `ptrace_scope`/Yama is not a security control. The only paths to a real boundary are separate containers (status quo) or separate uids with a redesigned workspace-sharing model — both out of scope. |
| R3 | **Capabilities are per-container, not per-process.** The OpenCode process now lives under `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID]`; today it runs with pure `cap_drop: ALL`. | No explicit capability dropping is added (D2). The actual `CapEff`/`CapBnd` of the uid-10000 opencode process MUST be **measured** and recorded as evidence, so the document states the fact rather than an assumption. |
| R4 | **Single lifecycle.** A Hermes crash exits the container and takes opencode and engram down with it. | Today they are independent failure domains. Inherent to the merge; the container CMD *is* Hermes' main program. |
| R5 | **Shared resource budget.** `mem_limit: 2g` + `4g` and `cpus: 2.0` + `4.0` collapse into one budget, and `pids_limit: 512` now covers Hermes + opencode + LSP children + engram + R/go builds. | **Decided (§17 answer 4): `mem_limit: 6g`, `cpus: 6.0`** — the ceiling stays close to the previous total so a long R/go build is not OOM-killed alongside the Telegram gateway; the blast-radius gain of a tighter ceiling was traded away deliberately. `pids_limit` remains the **one measured item**: it MUST be re-forecast for the merged cgroup and recorded with its rationale (a too-tight limit fails as LSP fork storms; a too-loose one weakens containment). |
| R6 | **A documented property is retired.** `odd/tasks/agent-interop-http.md` records the split as "isolation preserved". | That task file gets a **superseded-by** note; the history is not rewritten, but the two documents must not contradict each other silently. |
| R7 | **`/workspace` sharing is unchanged but the boundary shrinks.** | Same uid, one filesystem, one capability set: the shared-workspace model no longer has a container boundary behind it as a second line of defence. |

### 6.3 Non-regressions (asserted, must keep holding)

No published ports · no direct Internet for `robotina` · egress only via `egress-proxy` ·
Squid config and allowlist untouched · no Docker socket · `no-new-privileges:true` ·
`cap_drop: [ALL]` + minimal `cap_add` · core dumps off · bounded logs · secrets only via the
gitignored `.env` · WAL SQLite on native volumes.

## 7. Identity plan for `robotina` (D4)

Requirement (a) has two halves — the container answers to `robotina`, and the **agent**
answers to `robotina`. The identity half is implemented by three layers, one of which is
outside the repository:

1. **Skin (in-repo, authoritative for the agent's displayed name).**
   Ship `hermes/skins/robotina.yaml` with a top-level `name: robotina` and a `branding` block
   setting `agent_name: robotina`. Mount it **read-only** into `<HERMES_HOME>/skins/`
   (`/opt/data/skins/`). Selecting it is `display.skin`, set non-interactively
   (`hermes config set display.skin robotina`) during container startup so a fresh
   `${HOST_DATA_DIR}/hermes` also gets it. Read-only mounting matters: the agent must not be
   able to rewrite its own identity file.
2. **Always-loaded context (guaranteed fallback + behavioral truth).**
   `hermes/context/.hermes.md` is mounted at `/workspace/.hermes.md` and enters every prompt
   as the highest-priority environment facts. It gains an explicit identity statement
   ("you are `robotina`") **and** is rewritten for the merged topology: one container, no
   sibling `opencode` container, `http://127.0.0.1:4096` instead of `http://opencode:4096`,
   the `gh`/credential reality per §6.2 R1 (the old hard rule and its 404-means-delegate
   conclusion die here).
3. **BotFather (outside the repo, documented step).**
   The manual step is exactly one thing: **rename the bot's public Telegram display name to
   `robotina` in BotFather**. It is documented in the setup section of `README.md` (Spanish)
   and `README.en.md` (English). The Telegram `@username` handle is **not** part of this
   change — handles are Telegram-owned, unique and case-insensitive, and the handle MAY remain
   different from the display name. Nothing in this change asks for, requires or verifies an
   `@username` change (§17 answer 3).

Layer 1 makes the agent introduce itself as `robotina`; layer 3 makes the Telegram profile
say `robotina`. Layer 2 makes both true **inside** the prompts. Layer 1 is the primary
mechanism, layer 2 the guaranteed fallback, layer 3 the human/no-repo step.

## 8. State-layout migration (D5)

### 8.1 Target layout

`HOME=/opt/data` for the OpenCode service process tree. Everything OpenCode owns moves to
paths inside the **existing Hermes host bind** (`${HOST_DATA_DIR}/hermes:/opt/data`), except
the two WAL stores, which stay on native Docker volumes:

| Purpose | Today | After merge (D5) | Kind |
| --- | --- | --- | --- |
| OpenCode config | `${HOST_DATA_DIR}/opencode` → `/root/.config/opencode` | `/opt/data/.config/opencode` | inside Hermes bind |
| Git global config | `${HOST_DATA_DIR}/git` → `/root/.config/git` | `/opt/data/.config/git` | inside Hermes bind |
| GOPATH | `${HOST_DATA_DIR}/go` → `/root/go` | `/opt/data/go` | inside Hermes bind |
| engram (WAL SQLite) | `robotina_engram_db` → `/root/.engram` | `robotina_engram_db` → `/opt/data/.engram` | **native volume** |
| OpenCode sessions (WAL SQLite) | `robotina_opencode_db` → `/root/.local/share/opencode` | `robotina_opencode_db` → `/opt/data/.local/share/opencode` | **native volume** |
| Export output | `${HOST_DATA_DIR}/backups` → `/backups` | unchanged | bind |
| Shared code | `${HOST_DATA_DIR}/workspace` → `/workspace` | unchanged, separate bind | bind |
| Hermes state | `${HOST_DATA_DIR}/hermes` → `/opt/data` | unchanged | bind |

The standalone `${HOST_DATA_DIR}/opencode`, `${HOST_DATA_DIR}/git` and `${HOST_DATA_DIR}/go`
host folders **disappear from compose**. `scripts/export-state.sh` stays valid (its loopback
`curl http://127.0.0.1:4096/session` now points at the local server); only its invocation
prefix changes to `docker compose exec robotina …`.

**Ordering constraint to record:** the vendor's `stage2-hook.sh` runs `chown -R $HERMES_HOME`
as root **after the tree is up and before user services**, so it descends into the two nested
volumes and chowns their contents to uid 10000 *before* any WAL writer is active. That is the
desired ownership and it is the reason the nesting is safe on the ordering axis. The
**nesting itself** (named volume inside a bind mount on Docker Desktop for Windows) is the
part that is unverified — see §9 risk 1.

### 8.2 What happens to existing host state (decided: copy-forward, non-blocking)

The merge changes where OpenCode reads its state; it does **not** move anything by itself.
The disposition is **decided** (§17 answer 2): copy-forward, non-blocking, idempotent, and
never-deleting.

- **Copy-forward.** Existing legacy host folders are *copied* into the new `/opt/data/...`
  locations. Nothing is moved; the originals stay.
- **Non-blocking.** The merged container MUST start normally whether or not the migration has
  run. Anything missing is rebuildable, so there is **no migration-completeness gate** and the
  first start MUST NOT wait on it. A missing config simply regenerates (the staged gentle-ai
  overlay is re-applied at every start).
- **Idempotent and safe to re-run.** Each item is copied only when its destination is absent,
  so re-running the procedure never overwrites newer state with older state and never
  duplicates anything.
- **Never delete.** The pre-merge host folders (`opencode/`, `git/`, `go/`) are the rollback
  safety net (§12) and are never deleted by this change. Reclaiming that disk space afterwards
  is an operator decision outside this change's scope.
- **Mechanism is a design question** (§14 Q12): the legacy folders are *siblings* of the
  `${HOST_DATA_DIR}/hermes` bind and are therefore **invisible inside the container**, so the
  copy is either a documented host-side helper/step or a one-off read-only legacy mount during
  the migration run. Both mechanisms satisfy non-blocking and idempotency; this proposal does
  not pick one.

| Existing data | Decided handling |
| --- | --- |
| `${HOST_DATA_DIR}/opencode/` (config, plugins, package-lock) | **Copy** into `${HOST_DATA_DIR}/hermes/.config/opencode/`, idempotently (only when absent) and with **no ordering requirement** relative to the first start. Not moved, so the old folder remains as a cold backup and is never deleted by this change. |
| `${HOST_DATA_DIR}/git/` (git global config) | **Copy** into `${HOST_DATA_DIR}/hermes/.config/git/`, only when absent. Small, user-authored (commit identity), must not be lost — but a missing copy is not fatal to startup. |
| `${HOST_DATA_DIR}/go/` (module cache) | **Do not copy.** It is a rebuildable cache; copying it would be the largest and least valuable part of the migration. The folder is left in place and is never deleted by this change. |
| `robotina_engram_db` volume | **Keep as-is.** The volume is not deleted, so re-mounting the same volume at the new path preserves engram memory with no export/import. Verify by reading memory after `down`/`up`. |
| `robotina_opencode_db` volume | **Keep as-is**, same reasoning — session history survives the path change. |
| `${HOST_DATA_DIR}/backups/` | Untouched. `scripts/export-state.sh` remains the portable-JSON escape hatch and should be run before the migration as a cheap safety net. |
| Old `hermes`, `opencode` container images | `robotina-opencode:local` becomes orphaned; the user may remove it after the merged image is proven. Not removed automatically. |

Nothing is deleted by the change itself. The migration is a documented, re-runnable,
copy-forward procedure in the README setup sections (Spanish `README.md`, English
`README.en.md`), and the old host folders remain in place as the rollback safety net whether
or not the migration was ever run.

## 9. Risks

| # | Risk | Severity | Handling |
| --- | --- | --- | --- |
| 1 | **Nested volume-inside-bind mounts** (`/opt/data/.engram`, `/opt/data/.local/share/opencode`) may not behave on Docker Desktop for Windows. | High — if broken, WAL stores land on the host bind and violate the WAL rule | Flagged as an **implementation risk, not a blocker** (D5). Validate early in `sdd-apply` with `docker compose exec robotina sh -c 'mount | grep -E "\.engram|\.local/share/opencode"'` plus a durability test (`down`/`up` preserves data). If it fails, fall back to the currently-verified `/root`-rooted layout (explore §5 option 1), which needs no nesting — but that is a **decision to bring back to the user**, not a silent substitution. |
| 2 | **The glibc opencode binary may not run on Debian trixie**, or a later `opencode-ai` release may drop `opencode-linux-x64`. | High — the merge's core requirement | Explore already verified `opencode-ai@1.18.32` publishes `opencode-linux-x64`; pin the version and assert `opencode --version` at build time so a break is loud, not silent. |
| 3 | **Readiness race**: s6 says "started", Hermes delegates, gets `Connection refused`. | Medium — user-visible flakiness | Requirement B4 + a design decision on readiness gating (`s6-notifyoncheck` against `GET /global/health`, or a bounded wait in `opencode-init`). Test by `up -d` then immediate delegation. |
| 4 | **`pids_limit` mis-sized** for one cgroup covering Hermes + opencode + LSPs + engram + builds (`mem_limit` / `cpus` are decided: 6g / 6.0, so the remaining exposure is the process-count limit and the shared ceiling itself). | Medium | Re-forecast `pids_limit` with measurements (R5) and record the value with its rationale: too tight fails as LSP fork storms, too loose weakens containment. Verify with a build-and-LSP workload **and** a concurrent R/go build against Telegram traffic, since one cgroup now lets a heavy build starve the gateway. |
| 5 | **`/etc/gitconfig` blind overwrite** could silently drop vendor git config. | Low–Medium | Merge, do not overwrite; diff against the vendor image's file before writing. |
| 6 | **Docs desync** across a 12+ file documentation set (`README.md`, `README.en.md`, `SECURITY.md`, `hermes/`, `openspec/project.md`, `odd/tasks/*`, `scripts/*`, `.env.example`, `compose.yml` comments). | Medium — stale claims are the failure mode this change is about | Docs grep from `openspec/config.yaml` is a named verification recipe; bilingual claims change in the same commit. |
| 7 | **Review workload exceeds the 400-authored-line budget.** The doc set alone is large; compose + Dockerfile + s6 scripts add more. | Medium — delivery process | `ask-on-risk`: re-forecast at `sdd-tasks` and **stop to ask** for a delivery decision. Do not invent a chain strategy, do not infer `size:exception` (§12). |
| 8 | **Secret leak by tooling.** `docker compose config` without `-q` prints every resolved `.env` value. | Medium | Every recipe in this proposal and in the spec/design/tasks phases uses `-q`. Stated in the tasks the agents will run. |
| 9 | **Degraded non-PID-1 mode** (e.g. someone adds `init: true`): Hermes boots, `opencode serve` and engram never start, every delegation fails with `Connection refused`. | Low (guarded) | Remove `init: true`; document that PID 1 must be the image entrypoint; requirement A3 asserts it. |

## 10. Specs touched

`openspec/specs/` is currently empty (only `.gitkeep`), so this change **establishes** the
base capability specs rather than editing existing ones. Proposed capability files (names
provisional — `sdd-spec` owns them):

| Proposed spec | Covers |
| --- | --- |
| `openspec/specs/agent-container/spec.md` | A1–A7: single service `robotina`, naming, PID 1 / s6 constraints, capability set, resource budget, network membership |
| `openspec/specs/opencode-endpoint/spec.md` | B1–B6: loopback binding, host/peer unreachability, readiness, run-as uid, password semantics |
| `openspec/specs/agent-credentials/spec.md` | C1–C5 plus R1/R2: two distinct keys, per-process configuration, secret-handling rules, the documented non-isolation and retired credential invariant |
| `openspec/specs/agent-identity/spec.md` | §7: skin `robotina`, `display.skin`, always-loaded identity statement, BotFather step |
| `openspec/specs/state-layout/spec.md` | §8: D5 layout, WAL-on-native-volume rule, persistence across recreate, migration procedure |
| `openspec/specs/egress-boundary/spec.md` | INV1–INV5 and §6.3: invariants restated as regression guards (allowlist untouched, no published ports, proxy-only egress) |

Also touched as documentation-of-record (not specs): `openspec/project.md` (services table,
coupling map items 1/5/6/7, verification expectations), `odd/tasks/single-robotina-container.md`
(progress + evidence), `odd/tasks/agent-interop-http.md` (superseded note).

## 11. Verification recipes (from `openspec/config.yaml`)

| Layer | Command | Expectation |
| --- | --- | --- |
| Static | `docker compose config -q` | exit 0. **`-q` is mandatory** — the bare form prints `.env` secrets. |
| Inventory | `docker compose config --services` | exactly `robotina`, `egress-proxy` |
| Build | `docker compose build` (per service: `docker compose build robotina`) | exit 0 |
| Runtime | `docker compose up -d && docker compose ps` | exactly two containers, none publishing a port |
| Probes | in-container `docker compose exec robotina sh -c 'curl -fsS http://127.0.0.1:4096/global/health'`; the same URL MUST fail from the host and from `egress-proxy`; per-process key-visibility hash check (§5.C) | as specified per requirement |
| Supervision | `docker compose exec robotina s6-rc -a list` | includes `opencode`, `engram` |
| Docs | stale-claim grep over `README.md`, `README.en.md`, `SECURITY.md`, `hermes/` | no surviving two-container claim |
| Operator access | `grep -n "docker compose exec robotina" README.md README.en.md` | both READMEs document the in-container inspection/export recipes (the only path to the loopback-only server) |
| Secrets | `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'` | no matches |
| Egress guard | `git diff --exit-code -- squid/` | no change |

Two observations are **human checks**, not shell recipes, and must be labelled as such in the
spec: (i) the Telegram bot introduces itself / is displayed as `robotina`; (ii) the user
confirms the accepted regressions in §6.2 are understood.

## 12. Rollback plan

**Unit of revert.** The merge lands as one reversible unit: `compose.yml` (service block,
mounts, `NO_PROXY`, limits), the build directory (`opencode/` → `robotina/`, Dockerfile,
`s6/` service scripts, `overlay.json`), the context file and both Hermes skills, and the docs.
`git revert` of the merge commit restores the previous two-container topology.

**What rollback requires:**

1. `git revert` (or `git checkout <pre-merge-sha> -- compose.yml opencode/ hermes/ …`) on the
   feature branch, then `docker compose config -q && docker compose build`.
2. **No state was destroyed**, by design: the old `${HOST_DATA_DIR}/opencode`, `git/` and
   `go/` host folders are copied from, never moved or deleted (§8.2), and both native volumes
   keep their original names (`robotina_engram_db`, `robotina_opencode_db`) and are re-mounted
   at their old `/root/...` paths by the reverted compose file. Engram memory and OpenCode
   sessions come back with the old topology. Rollback does **not** depend on the migration
   having run at all (§8.2: the migration is non-blocking and never deletes).
3. If the merged container wrote to `/opt/data/.config/opencode` etc., those writes are
   additive inside the Hermes bind; the reverted topology ignores that subtree. No
   de-migration is needed.
4. Remove the `robotina` image and container after the revert; the `opencode` service rebuilds
   from the untouched `ghcr.io/anomalyco/opencode` base.
5. Reverse the documentation revert with the same commit — docs and code revert together so
   no stale claim survives.

**Not reversible automatically:** the Telegram-side BotFather display-name change (§7 layer
3), which the user must undo manually if the rename is rolled back.

## 13. Consequences to accept at approval

Approving this proposal means accepting, explicitly:

1. The retired GitHub credential invariant (R1) — the Telegram-facing agent can reach GitHub.
2. Non-enforceable per-process key isolation (R2) — two distinct keys, but no boundary.
3. Per-container capabilities for the OpenCode process (R3) — measured and documented, not
   mitigated.
4. A single failure domain (R4) and a shared resource budget (R5) fixed at `mem_limit: 6g` /
   `cpus: 6.0`, with `pids_limit` still to be measured and recorded.
5. The D5 state relocation with its nested-mount implementation risk (§9 risk 1) and the
   copy-forward, non-blocking, idempotent migration procedure in §8.2 — the first start is
   never gated on migration completeness.
6. **Loopback-only operator access.** No human can reach the OpenCode server any more, from the
   host or from another container; the only inspection paths are in-container
   (`scripts/export-state.sh`, `docker compose exec robotina …`), and those recipes MUST be
   documented in `README.md` and `README.en.md`. No published port and no host escape hatch is
   added.
7. **The broad PAT is kept as-is** (§17 answer 1): no credential narrowing compensates for the
   R1 reach — the exposure is accepted and documented, not mitigated.

## 14. Open questions for `sdd-spec` / `sdd-design`

These do **not** re-open D1–D5; they are the residual detail the next phases must close.

| # | Question | Owner | How to resolve |
| --- | --- | --- | --- |
| Q1 | Final `pids_limit` for the merged cgroup **and its recorded rationale** (`mem_limit: 6g` and `cpus: 6.0` are already decided, §17 answer 4). | design | measure a running merged container under a build + LSP workload |
| Q2 | Readiness mechanism for `opencode serve`: `s6-notifyoncheck` against `/global/health`, `notification-fd`, or a bounded wait in `opencode-init`. | design | `up -d` then immediate delegation, repeated |
| Q3 | s6 restart policy for the longruns: accept s6's unbounded restart, or add a `finish` script with backoff. | design | deliberate choice, documented |
| Q4 | Measured capability set of the uid-10000 opencode process (`CapEff`/`CapBnd`) — the evidence for R3. | design (verify) | `grep -E "Cap(Eff|Bnd)" /proc/<pid>/status` |
| Q5 | Whether `OPENCODE_SERVER_PASSWORD` is kept (defense-in-depth, rewritten rationale) or removed. `scripts/export-state.sh` and the `opencode-server` skill recipe reference it. | spec / design | decide and document |
| Q6 | Final `overlay.json` merge semantics: whether the staged gentle-ai overlay is re-applied per start by `opencode-init` (current behaviour) and what happens on conflict with `/opt/data/.config/opencode`. | design | inspect the staged tree + overlay merge at build |
| Q7 | Whether a container-side cont-init chown fully replaces `scripts/fix-permissions.ps1` (delete it) or the script is kept and re-documented. Deleting removes an unpinned-root host step (I2). | design | host-state ownership audit; requires user confirmation to delete a host script |
| Q8 | Vendor `/etc/gitconfig` merge semantics — exact lines to append vs replace. | design | read the vendor image's `/etc/gitconfig` |
| Q9 | Repo layout: rename `opencode/` → `robotina/` (build context, Dockerfile, `overlay.json`, `s6/`) — confirmed, but where the s6 service sources live (`robotina/s6/…` vs `hermes/s6/…`) is a design choice. | design | layout decision |
| Q10 | Where `engram` logs after the merge (today's `/var/log/engram.log` is unwritable by uid 10000 — a silently failing redirect). | design | pick a writable path or s6 stdout capture; verify the file is actually written |
| Q11 | Whether the merged service's `restart: unless-stopped` interacts with the single-lifecycle behaviour in a way that needs a healthcheck. | design | runtime observation |
| Q12 | Migration mechanism for §8.2: a documented host-side copy helper/step, or a one-off read-only mount of the legacy host folders during the migration run (the legacy folders are not visible inside the container). | design | pick per §8.2 constraints: idempotent, non-blocking, never-deleting |

## 15. Review workload forecast (provisional, for `sdd-tasks`)

Authored-line risk is **high**. `compose.yml` is a large rewrite of two service blocks into
one, plus a new `s6/` service set, a retargeted Dockerfile (toolchain port), the context file,
both Hermes skills, `SECURITY.md`, `README.md`, `README.en.md`, `.env.example`, `scripts/*`,
and the openspec/odd records. The decisions in §17 add authored surface rather than remove it:
the idempotent migration procedure (documented step and/or helper script) and the in-container
operator recipes now required in **both** READMEs. The estimate therefore remains **over the
400-authored-line review budget**.

Per `ask-on-risk` and `chain_strategy: deferred`: this proposal does **not** choose chaining
and does **not** request `size:exception`. `sdd-tasks` MUST re-forecast after authoring the
breakdown and, if the budget is still exceeded, **stop and ask the user** for a delivery
decision (chained PRs vs single PR) with real numbers. `exception-ok` is not accepted and is
never inferred.

## 16. Language contract

Generated technical artifacts default to **English**. This repository's split is preserved:
`compose.yml` and Dockerfile comments in **Spanish**; `openspec/` artifacts and
`odd/tasks/*.md` in **English**; `README.md` and `SECURITY.md` in **Spanish**;
`README.en.md` in **English**; bilingual measured claims change in the same commit.

## 17. Proposal question round — confirmed answers (closed)

The orchestrator ran this round with the user after the first draft of this proposal. The
answers below are **authoritative and frozen**: `sdd-spec` and `sdd-design` MUST NOT re-open
them. These were product decisions, not harness mechanics, and all five are now closed.

| # | Question | Confirmed answer | Applied in this file |
| --- | --- | --- | --- |
| 1 | Compensating control for the retired credential split: narrow the PAT, or keep it? | **Keep the current PAT as-is.** No narrowing work is part of this change; the Telegram-facing agent's reach to `GITHUB_TOKEN` stays an accepted, documented residual risk. | §6.2 R1, §13 |
| 2 | Existing host state: must the migration block the first start? | **No — copy-forward and non-blocking.** Copy what exists into the new `/opt/data/...` locations and let the container start regardless; anything missing is rebuildable. The migration is idempotent and safe to re-run, and pre-merge host folders are **never deleted** (rollback depends on it). | §8.2, §12, §3.1 |
| 3 | Telegram identity scope: display name only, or also `@username`? | **Display name only.** The BotFather step is exactly: rename the bot display name to `robotina`. No `@username` change is required or requested; the handle is Telegram-owned, unique, and may remain different. | §7 layer 3 |
| 4 | Resource budget for the merged cgroup. | **Keep close to the total: `mem_limit: 6g`, `cpus: 6.0`** (was 2g + 4g and 2.0 + 4.0 CPUs). `pids_limit` is re-forecast for the single cgroup and recorded with its rationale (LSP fork storms vs containment). | §6.2 R5, §5.A A6, §9 risk 4, §13 |
| 5 | Loopback-only operator access: accept, or add an escape hatch? | **Accepted.** No human reaches the OpenCode server any more. The only inspection paths are in-container (`scripts/export-state.sh`, `docker compose exec robotina …`), and those recipes MUST be documented in `README.md` / `README.en.md`. No new published port, no host escape hatch. | §3.1, §11, §13 |

No second question round is required: none of the answers left an ambiguity that changes the
shape of this proposal. The decisions they imply are reflected in the sections named above
rather than left as open items.

---

## Phase result

- The merge is feasible in exactly one direction (D1) and its runtime shape is settled at the
  approach level: one service `robotina`, s6-supervised `opencode serve` + `engram` in the
  vendor's `user2` bundle, Hermes' main program as the container CMD.
- Requirement sets A/B/C plus the frozen invariants (INV1–INV5) are written with a **named shell-level
  proof per requirement**, ready for `sdd-spec` Given/When/Then conversion.
- Security deltas are split into 3 improvements and 7 accepted regressions; the regressions
  the user must sign off on are R1 (GitHub credential invariant retired), R2 (no enforceable
  per-process key isolation), R3 (per-container capabilities), R4/R5 (single lifecycle,
  shared budget).
- Identity is planned in three layers (repo skin + always-loaded context + BotFather), with
  the manual step explicitly outside the repo and narrowed to the **display name only**
  (no `@username` change).
- The D5 state relocation is specified with its ordering constraint, a copy-forward migration
  disposition for existing host state, and the nested-volume risk flagged as implementation
  risk with a verification recipe.
- Rollback is a single revert, made safe by keeping both native volume names and never
  deleting the pre-merge host folders.
- All five product questions from the first draft are decided and recorded (§17): keep the PAT
  as-is, copy-forward non-blocking migration, display-name-only identity, `6g` / `6.0` resource
  ceiling with `pids_limit` still measured, loopback-only operator access with in-container
  recipes documented in both READMEs. Closed items were removed from the open list instead of
  left stale.
- Open questions for `sdd-spec`/`sdd-design` are listed (Q1–Q12); none re-opens D1–D5 or the
  §17 answers.
- Nothing was implemented; no spec/design/tasks artifacts were written; no child subagents
  were launched.
