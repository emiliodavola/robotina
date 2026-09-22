# Exploration — single-robotina-container

Status: complete (exploration only — nothing implemented)
Change: `single-robotina-container` · Branch: `feat/single-robotina-container`
Artifact store: `openspec/` (this file is the artifact of record for the explore phase)

Goal: merge the `hermes` and `opencode` agent containers into **one** container named
`robotina` that (a) answers to the name `robotina`, (b) ships the OpenCode HTTP server
bound to loopback `127.0.0.1:4096`, and (c) keeps two distinct API keys. `egress-proxy`
stays a separate container.

Frozen user decisions (from the parent preflight, not re-litigated here):

1. Loopback HTTP server only — no OpenCode CLI/TUI requirement.
2. `egress-proxy` stays separate.
3. Container **and** bot identity both become `robotina`.

---

## 0. Files read for this exploration

| File | Why |
| --- | --- |
| `openspec/config.yaml`, `openspec/project.md` | SDD config, testing/verification contract, coupling map |
| `odd/tasks/single-robotina-container.md` | Change intent, scope, acceptance criteria |
| `compose.yml` | All three services, anchors, mounts, networks |
| `opencode/Dockerfile`, `opencode/entrypoint.sh`, `opencode/overlay.json` | The custom toolchain and its boot order |
| `hermes/context/.hermes.md`, `hermes/skills/opencode-server/SKILL.md`, `hermes/skills/github-private-repos/SKILL.md` | The two-container assumptions that must be rewritten |
| `scripts/export-state.sh`, `scripts/fix-permissions.ps1` | Host-side coupling to service names and uid alignment |
| `README.md`, `README.en.md`, `SECURITY.md`, `.env.example` | Measured claims that become false after the merge |
| `squid/squid.conf`, `squid/allowlist.txt` | Egress boundary (must stay untouched) |
| `odd/tasks/agent-interop-http.md`, `odd/tasks/opencode-config-port.md` | Why the HTTP hop exists; toolchain gotchas |
| Parent-supplied read-only inspection of `nousresearch/hermes-agent:latest` | Vendor image facts (treated as verified evidence, not re-run) |

Not available to this phase: the vendor image filesystem itself, a running Docker daemon,
and any measurement of `HOST_DATA_DIR`. Anything that needs a live probe is marked
**UNVERIFIED** below.

---

## 1. Current-state map (facts, with anchors)

### 1.1 Compose topology

- Three services: `hermes` (vendor image, no `init: true`, `command: ["gateway","run"]`,
  `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID]`), `opencode`
  (`build: ./opencode`, `image: robotina-opencode:local`, `user: "10000:10000"`,
  `init: true`, `command: ["serve","--hostname","0.0.0.0","--port","4096"]`), and
  `egress-proxy` (`ubuntu/squid:latest`, `user: "13:13"`, `read_only: true`).
- Shared anchors: `x-hardening` (`no-new-privileges`, `cap_drop: [ALL]`, `pids_limit: 512`,
  `ulimits.core: 0`, `stop_grace_period: 20s`, json-file logs 10m×3) and `x-egress-env`
  (`HTTP(S)_PROXY=http://egress-proxy:3128`, `NO_PROXY=localhost,127.0.0.1,::1,hermes,opencode,egress-proxy`).
- Networks: `agents` (`internal: true`, no gateway) holds `hermes` + `opencode` +
  `egress-proxy`; `egress` (bridge) holds only `egress-proxy`. No published ports.
- Resource limits today: hermes `mem_limit: 2g`/`cpus: 2.0`, opencode `mem_limit: 4g`/`cpus: 4.0`.

### 1.2 The API-key collision (the core of requirement (c))

```
hermes   env:  OPENCODE_GO_API_KEY: ${HERMES_OPENCODE_GO_API_KEY}   # renamed inside hermes
opencode env:  OPENCODE_GO_API_KEY: ${OPENCODE_GO_API_KEY}          # the opencode value
```

Both containers carry the **same env var name with different values**. This only works
because they are separate processes in separate containers. One container collapses that.

### 1.3 Mount inventory (both services)

| Mount | hermes | opencode |
| --- | --- | --- |
| `${HOST_DATA_DIR}/hermes` → `/opt/data` | bind | — |
| `${HOST_DATA_DIR}/workspace` → `/workspace` | bind | bind |
| `./hermes/skills` → `/opt/data/skills/stack` | bind ro | — |
| `./hermes/context/.hermes.md` → `/workspace/.hermes.md` | bind ro | — |
| `${HOST_DATA_DIR}/opencode` → `/root/.config/opencode` | — | bind |
| `${HOST_DATA_DIR}/backups` → `/backups` | — | bind |
| `${HOST_DATA_DIR}/git` → `/root/.config/git` | — | bind |
| `${HOST_DATA_DIR}/go` → `/root/go` | — | bind |
| `robotina_engram_db` → `/root/.engram` | — | **volume** (WAL) |
| `robotina_opencode_db` → `/root/.local/share/opencode` | — | **volume** (WAL) |
| `./scripts/export-state.sh` → `/opt/export-state.sh` | — | bind ro |
| `/tmp` tmpfs `rw,exec,nosuid,nodev,size=256m` | yes | yes |

Every opencode state path is rooted at `/root` **only because** `HOME: /root` was set on
that service (uid 10000 with `/root` made traversable by `chown -R 10000:10000 /root` in
the Dockerfile). `/root` is an image path, not under `/opt/data` — this is what makes the
merge cheap (see §4).

### 1.4 Vendor image facts (parent-verified, read-only)

- Debian GNU/Linux 13 (trixie); starts as **root**; `hermes` is uid/gid **10000**.
- `Config.User=root`; `Entrypoint=["/opt/hermes/docker/entrypoint-dispatch.sh"]`;
  `Cmd=null`; `WorkingDir=/opt/hermes`; `Volumes={"/opt/data":{}}`.
- Entrypoint: if PID 1 → `exec /init /opt/hermes/docker/main-wrapper.sh "$@"` (full s6
  tree). If **not** PID 1 → warns, sets PATH, runs `stage2-hook.sh`, then
  `exec main-wrapper.sh` — **supervised services are unavailable in that fallback**.
- s6-rc source tree `/etc/s6-overlay/s6-rc.d/`: `dashboard` (longrun), `main-hermes`
  (longrun, `run` = `exec sleep infinity`, depends on `base`), `user` (bundle:
  `dashboard`, `main-hermes`), **`user2` (bundle with an empty `contents.d` — the vendor
  comment says a bundle must not be empty)**.
- The container **CMD is not an s6 service**: `/init` runs it as the "main program" via
  `main-wrapper.sh`, which exports `HOME=/opt/data`, `cd /opt/data`, activates
  `/opt/hermes/.venv`, then `s6-setuidgid hermes` before exec'ing the CMD. When the main
  program exits, the container exits.
- `dashboard/run` is a real longrun gated by `HERMES_DASHBOARD` (default off); it also
  exports `HOME=/opt/data`, `cd /opt/data`, activates the venv, then
  `exec s6-setuidgid hermes hermes dashboard ...`.
- `/etc/cont-init.d/01-hermes-setup` → `stage2-hook.sh`, runs **as root after the tree is
  up and before user services**: bootstraps `$HERMES_HOME` (default `/opt/data`), validates
  and applies `HERMES_UID`/`HERMES_GID` (aliases `PUID`/`PGID`) via `usermod`/`groupmod`,
  **chowns the data volume**, seeds config, syncs skills. It **rejects**
  `docker run --user <arbitrary uid>` with an explicit error.
- Image ENV already set: `HERMES_HOME=/opt/data`, `HERMES_WRITE_SAFE_ROOT=/opt/data`,
  `HERMES_TUI_DIR=/opt/hermes/ui-tui`, `HERMES_LAZY_INSTALL_TARGET=/opt/data/lazy-packages`,
  `PATH=/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:...`.
- Already installed: **node**, **npm**, **uv**, `python3` (the venv), `git`, `curl`.
  **Missing: `gh`, `opencode`, `bun`, `deno`, global `pip`.**
- Ships `/opt/hermes/docker/{s6-rc.d,cont-init.d,main-wrapper.sh,entrypoint-dispatch.sh,
  entrypoint.sh,hermes-exec-shim.sh,tini-shim.sh,stage2-hook.sh,SOUL.md}` and, inside
  `/opt/hermes`, `.env.example` (26 KB) + `cli-config.yaml.example` (120 KB).

### 1.5 What the custom opencode image adds

`FROM ghcr.io/anomalyco/opencode:latest` (Alpine/musl) + `apk` packages (bash, curl, git,
jq, nodejs, npm, uv, ripgrep, tar, xz, tzdata, ca-certificates, R + R-dev + gcc/g++/make/
gfortran + libxml2-dev/openssl-dev/zlib-dev, linux-headers, go, libuv-dev, icu-dev,
curl-dev, pkgconf, taplo, github-cli), uv-managed Python 3.13 (`/usr/local/bin/python3`
symlink), npm-global LSPs (`vscode-langservers-extracted@4.10.0`,
`dockerfile-language-server-nodejs@0.15.0`, `basedpyright@1.39.9`), `marksman`
(musl release), R `languageserver` (compiled at build), `@colbymchenry/codegraph@1.5.0`
with a **musl `node` shim replacing the bundled glibc node**, checksum-verified `engram`
1.20.0 and `gentle-ai` 3.1.0, a staged gentle-ai tree at `/opt/gentle-ai-stage`,
system git config (`credential.helper = !gh auth git-credential`,
`url.https://github.com/.insteadOf = git@github.com:`), `chown -R 10000:10000 /root`,
and `ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]`.

`entrypoint.sh` boot order: re-apply staged gentle-ai tree → merge `overlay.json`
(LSPs + `codegraph`/`gh_grep` MCP + permissions) → `engram serve > /var/log/engram.log &`
→ warn if `/workspace` is not writable → `exec opencode "$@"`.

### 1.6 Historical rationale for the HTTP hop

`odd/tasks/agent-interop-http.md`: the two-container split was a deliberate user decision
("automation without losing isolation"), and its Evidence block calls the isolation
"preserved". The merge therefore retires a documented, intentional property — this is a
product decision already taken by the user, not a defect to fix silently.

---

## 2. Q1 — Image composition: `FROM nousresearch/hermes-agent` vs the reverse

### 2.1 The reverse direction is effectively infeasible

`FROM ghcr.io/anomalyco/opencode` (Alpine/musl) + "add Hermes" would have to move a
**glibc** application tree onto musl: `/opt/hermes/.venv` (CPython built against glibc),
the Debian-built `s6-overlay` binaries, and Debian Python wheels. `odd/tasks/opencode-config-port.md`
gotcha #1 already records the mirror-image finding for the other direction ("rebasing to
Debian is closed: the opencode binary is musl-linked … and with the musl loader on Debian
it dies on C++ symbols"). Both directions hinge on the same libc question; the Hermes side
has no Alpine equivalent at all. **Conclusion: compose the merged image from the vendor
Debian base.**

### 2.2 What the vendor base already covers (so it must be dropped from the port)

| Need | Vendor image | Action after merge |
| --- | --- | --- |
| `bash`, `tar`, `xz`, `tzdata`, `ca-certificates` | Debian base | do not reinstall |
| `node`, `npm` | present | do not reinstall; only verify the npm global prefix is writable at build |
| `uv` | `/usr/local/bin/uv` | do not reinstall |
| `git`, `curl` | present | do not reinstall |
| `python3` | **the Hermes venv** (`/opt/hermes/.venv`), exposed via PATH | keep untouched; install a *separate* uv-managed CPython for agent work and do **not** let a `/usr/local/bin/python3` symlink shadow or replace the venv |

### 2.3 What still has to be added (quantified)

| Addition | Notes |
| --- | --- |
| **opencode binary** | the make-or-break item — see §2.4 |
| `gh` (github-cli) | not in Debian trixie mainline; GitHub apt repo or the release tarball |
| `jq`, `ripgrep` | apt |
| `R`, `r-base-dev` (+ `gcc/g++/gfortran/make`, `libxml2-dev`, `libssl-dev`, `zlib1g-dev`, `libuv1-dev`, `libicu-dev`, `libcurl4-openssl-dev`, `pkg-config`) | needed to compile R `languageserver` at build; the `-dev` set is build-time only and can be pruned |
| `taplo` | not in Debian; npm `@taplo/cli` or the upstream tarball |
| `marksman` | upstream ships a **musl static** binary — a static musl binary runs on glibc, so no change needed |
| 3 npm-global LSPs | `vscode-langservers-extracted@4.10.0`, `dockerfile-language-server-nodejs@0.15.0`, `basedpyright@1.39.9` |
| R `languageserver` | compile at build, then assert `requireNamespace` |
| `@colbymchenry/codegraph@1.5.0` | install **without** the musl node shim: on glibc the bundled `node` is correct |
| `engram` 1.20.0, `gentle-ai` 3.1.0 | checksum-verified releases (unchanged) |
| uv-managed CPython 3.13 | for agent work; keep it off the Hermes venv's PATH slot |
| system `/etc/gitconfig` | credential helper + `insteadOf`; **merge, do not blind-overwrite** — the vendor image may already ship one |
| `go` | Debian `golang`; still needed for `GOPATH=/root/go` |
| `python`/`python3` for agents | decision required: expose `python3` → uv interpreter only in the opencode service's PATH, never container-wide |

### 2.4 The crux risk: libc of the opencode binary

`odd/tasks/opencode-config-port.md` records that the opencode binary in the Alpine image
is **musl-linked** (`/lib/ld-musl-x86_64.so.1`) and that running it with the musl loader on
a Debian base dies on C++ symbols. That statement was about rebasing the *opencode* image;
in the merged image the same constraint applies to the Debian base. So the merged image
needs a **glibc build of opencode**, which the npm package `opencode-ai` should provide
per-platform. **UNVERIFIED** — this must be measured before the design is frozen.

Verification recipe (needs a Docker host):

```bash
# 1. what libc does the current image ship?
docker run --rm --entrypoint sh robotina-opencode:local -c 'file $(command -v opencode); ls -l /lib/ld-musl* 2>/dev/null'
# 2. is there a glibc build available from the npm package / releases?
npm view opencode-ai optionalDependencies --json
# 3. does it actually start on trixie?
docker run --rm --entrypoint sh <merged-image> -c 'opencode --version'
```

If no glibc build exists, the fallback is to keep the musl loader alongside
(`/lib/ld-musl-x86_64.so.1` + musl libs) or to build opencode from source — both are
materially larger work and must be surfaced before `sdd-design`.

---

## 3. Q2 — Running `opencode serve` supervised inside `robotina`

### 3.1 The extension point is `user2`

The vendor ships `user2` as a bundle with an **empty** `contents.d` and a comment that a
bundle must not be empty — i.e. it is the intended slot for site services. `user` is taken
by `dashboard` + `main-hermes`. s6-overlay v3 compiles its service database from
`/etc/s6-overlay/s6-rc.d` **at container start**, so directories added at build time are
picked up.

Proposed shape (design-level, not decided here):

```
/etc/s6-overlay/s6-rc.d/
  opencode-init/   type=oneshot, up=…, depends on base
  engram/          type=longrun, depends on base
  opencode/        type=longrun, depends on base + opencode-init + engram
  user2/contents.d/{opencode-init,engram,opencode}
```

- `opencode-init` (oneshot) absorbs the idempotent file work from today's
  `opencode/entrypoint.sh`: apply the staged gentle-ai tree, merge `overlay.json`, and
  emit the `/workspace` writability warning.
- `engram` (longrun) becomes a real service instead of `engram serve &` inside an
  entrypoint (a longrun run script must `exec` one foreground process).
- `opencode` (longrun) run script:

  ```sh
  #!/command/with-contenv sh
  export HOME=/root ENGRAM_DATA_DIR=/root/.engram GIT_CONFIG_GLOBAL=/root/.config/git/config
  export OPENCODE_GO_API_KEY="$ROBOTINA_OPENCODE_KEY"
  cd /workspace
  exec s6-setuidgid hermes opencode serve --hostname 127.0.0.1 --port 4096
  ```

  `s6-setuidgid hermes` is the same privilege drop the vendor uses for the main program and
  the dashboard, so uid 10000 is preserved. `cd /workspace` keeps the server's reported
  directory at `/workspace` (matching today's measured behaviour).

### 3.2 Interaction with "CMD is the main program"

`/init` brings the whole service tree up and only then execs `main-wrapper.sh` → the CMD
(`gateway run`). So the opencode longrun is **started before** hermes, and opencode must
**not** be the CMD. Consequences:

- The container still dies when the main program (Hermes) exits — opencode's lifetime is
  now coupled to Hermes'. Document it; it is inherent to the merge.
- "service up" ≠ "port listening": s6-rc considers the longrun up when the run script has
  been started. Add readiness (a `s6-notifyoncheck`/`notification-fd` check against
  `GET /global/health`, or a bounded wait in `opencode-init`) so Hermes' first loopback call
  does not race startup. Today this race does not exist because Hermes and opencode are
  separate containers with independent lifecycles.
- Restart semantics: s6-supervise restarts a longrun on exit (unbounded). Decide whether to
  add a `finish` script with backoff, or accept s6's default.
- `restart: unless-stopped` stays on the service; `init: true` must **not** be added (s6
  needs PID 1), and `user:` must **not** be set (stage2-hook rejects arbitrary uids).

### 3.3 The non-PID-1 fallback path

In the vendor's non-PID-1 branch (`docker run --init`, or another PID 1), stage2-hook runs
and `main-wrapper.sh` execs Hermes, but **no s6 service exists** — so `opencode serve` and
`engram` never start. After the merge, Hermes would boot and then fail every delegation with
`Connection refused`. The fallback therefore becomes an **unsupported degraded mode**, not
something to preserve. Recommended handling: leave the vendor entrypoint untouched, remove
`init: true`, and document (README/SECURITY) that PID 1 must be the image entrypoint.

### 3.4 Other s6 details to pin in design

- `#!/command/with-contenv` is required for the container env (`x-egress-env`, TZ,
  secrets) to reach the service.
- Each service dir needs `dependencies.d/base` (as `main-hermes` has) plus the bundle entry.
- Where do service logs go? With no `log/` sub-service, s6-overlay output lands in the
  container's stdout → `docker logs` under the existing json-file rotation. Today's
  `opencode/entrypoint.sh` writes `engram` to `/var/log/engram.log` — as uid 10000 that
  path is **not writable** (root:root 0755), so the redirect silently fails today. The
  merged image must pick a writable log path (e.g. under `/root/.local/state/`, or s6's
  own stdout capture).
- `/tmp` must stay `rw,exec,nosuid,nodev` (hermes already has it; keep it) — OpenTUI's
  `dlopen` trap is documented, and even without the TUI the setting is harmless.

---

## 4. Q3 — uid / HOME / path changes

Today's alignment trick was: **opencode adopts Hermes' uid (10000)**, because the vendor
image validates `HERMES_UID` in 1–65534 and silently discards 0. After the merge there is
one uid space, so the alignment question becomes trivial — and a simplification appears.

### 4.1 Path-by-path

| Path | Today | After merge (proposal) | Notes |
| --- | --- | --- | --- |
| `/opt/data` | hermes HOME (bind `${HOST_DATA_DIR}/hermes`) | unchanged | stage2-hook chowns it to `HERMES_UID` (10000) at every start |
| `/workspace` | shared bind | unchanged | `cd` target for the opencode service |
| `/root/.config/opencode` | bind `${HOST_DATA_DIR}/opencode` | **unchanged target** | ownership must be 10000 |
| `/root/.local/share/opencode` | volume `robotina_opencode_db` | **unchanged** | WAL — see §5 |
| `/root/.engram` | volume `robotina_engram_db` | **unchanged** | WAL — see §5 |
| `/root/.config/git` | bind `${HOST_DATA_DIR}/git` | **unchanged** | `GIT_CONFIG_GLOBAL` |
| `/root/go` | bind `${HOST_DATA_DIR}/go` | **unchanged** | `GOPATH`; go defaults to `$HOME/go` = `/root/go` if `HOME=/root` |
| `/var/log/engram.log` | written as uid 10000 | **must move** | not writable by uid 10000 |
| `/opt/hermes` | vendor app | unchanged | must remain root-owned; uid 10000 must not be able to rewrite it |
| `/opt/export-state.sh` | bind ro | unchanged target | its header comment names `docker compose exec opencode` |

Keeping `HOME=/root` **only for the opencode service's process tree** preserves every host
path, needs no state migration, and — critically — avoids nested mounts entirely, because
`/root` lives in the image layer, not inside the `/opt/data` bind.

### 4.2 Ownership / `scripts/fix-permissions.ps1`

The script exists because host folders freshly created on Windows are root-owned and the
agent (uid 10000) cannot write them under `cap_drop: ALL`. Two observations:

- `${HOST_DATA_DIR}/hermes` is already handled by the vendor's `stage2-hook.sh` (it chowns
  `$HERMES_HOME` as root at start) — which is why the script deliberately excludes it.
- The remaining paths (`opencode`, `go`, `backups`, `git`, `workspace` + the two volumes)
  can be chowned by a **cont-init script of our own**, which runs as root before user
  services. That would make the host-side PowerShell step unnecessary.

If that is done, `scripts/fix-permissions.ps1` can be deleted — which also removes a
documented trap: it runs **unpinned `alpine:latest` as root with host state bind-mounted**
(`openspec/project.md` known traps, `SECURITY.md`). That is a net security improvement and a
documentation reduction, at the cost of one more cont-init script. Flag as a design choice,
not a decision taken here.

### 4.3 Concrete compose edits implied (inventory only, not applied)

- remove `user: "10000:10000"`, `init: true`, `working_dir`, `command` from the opencode
  service; the merged service keeps `command: ["gateway","run"]`;
- move `HOME`, `ENGRAM_DATA_DIR`, `GIT_CONFIG_GLOBAL`, `GIT_TERMINAL_PROMPT` out of
  container-wide `environment:` and into the opencode/engram run scripts (setting `HOME`
  container-wide would be overridden by `main-wrapper.sh` for Hermes but could still leak
  into other cont-init logic — safer to scope it);
- merge `mem_limit`/`cpus` into one value (2g+4g → a single budget) and re-check
  `pids_limit: 512` now that Hermes, opencode, its LSP children, `engram`, and R/go builds
  share one cgroup;
- `cap_add` stays the same five (Hermes needs them) — but see §8.3;
- mount targets for opencode state stay exactly as they are.

---

## 5. Q4 — Persistence and WAL

The repo rule (`openspec/project.md`, `SECURITY.md`) is: `opencode.db` and `engram.db`
force WAL and WAL over a Windows bind mount (virtiofs/9p) can silently corrupt, so both live
on **native volumes**. That rule is unchanged by the merge.

Two viable placements:

1. **Keep `HOME=/root` for the opencode service** → the volumes mount at
   `/root/.engram` and `/root/.local/share/opencode`, which are **not** under the
   `/opt/data` bind. **No nested mounts at all.** This is the low-risk option and is why
   §4 recommends it.
2. **Move opencode's HOME under `/opt/data`** (so all agent state sits in one host folder)
   → the volumes would have to be mounted at `/opt/data/.local/share/opencode` and
   `/opt/data/.engram`, i.e. **nested inside the `/opt/data` bind**. Docker orders mounts by
   destination path depth, so nesting is generally supported, but:
   - `stage2-hook.sh`'s `chown -R $HERMES_HOME` would descend **into** the volumes and
     chown their contents (to `HERMES_UID` = 10000 — which is what we want, and it happens
     before any service starts, so no WAL writer is active);
   - nesting a named volume inside a bind mount on Docker Desktop for Windows is
     **UNVERIFIED** here and would need a measurement before it is relied upon;
   - it also needs opencode to honour `XDG_CONFIG_HOME`/`XDG_DATA_HOME` (or explicit
     `--config`/`--data` flags) so the config keeps landing on the host bind —
     **UNVERIFIED**.

Recommendation to carry into design: option 1 (no nesting, no XDG assumption, zero state
migration). Record option 2 with its two unverified dependencies as the alternative.

`scripts/export-state.sh` stays valid: its internal `curl http://127.0.0.1:4096/session`
works unchanged (loopback is where the server now lives) and `opencode export` still exists
because the binary must be installed to run `serve`. Only its invocation prefix changes
(`docker compose exec robotina …`).

---

## 6. Q5 — Two distinct API keys inside one container

### 6.1 Options, honestly compared

| Option | Mechanism | Verdict |
| --- | --- | --- |
| **A. Distinct values via per-service env** | container env carries both *under distinct names*; the opencode run script exports `OPENCODE_GO_API_KEY="$ROBOTINA_OPENCODE_KEY"` for its own process only; Hermes' main program keeps the vendor-expected name with the Hermes value | **recommended**: each process sees only its own key; `.env` names unchanged; no vendor-file edits |
| B. Two uids (Hermes 10001, opencode 10000) | different uids ⇒ `/proc/<pid>/environ` cross-reads are (usually) blocked | **breaks the shared `/workspace`**: under `cap_drop: ALL` one uid cannot write the other's files, and giving opencode `DAC_OVERRIDE` to compensate weakens the model more than it buys |
| C. cont-init writes per-service env files, mode 0600 | env file owned by the "service user" | **no gain at equal uid** — both processes are uid 10000 and can read each other's files |
| D. One key for both | simplest | violates frozen requirement (c) |

Option A in compose terms:

```yaml
environment:
  # Hermes' main program inherits this name; it is the Hermes value.
  OPENCODE_GO_API_KEY: ${HERMES_OPENCODE_GO_API_KEY:?…}
  # The opencode service's own value, under a distinct name.
  ROBOTINA_OPENCODE_GO_API_KEY: ${OPENCODE_GO_API_KEY:?…}
```

### 6.2 The honest statement (must be documented, not hidden)

Two processes of the **same uid** in the **same container** have **no enforceable
environment boundary**:

- `/proc/<pid>/environ` is the canonical leak path. Whether a given read succeeds depends
  on `ptrace_scope`/Yama and on ancestry (Docker's `s6` spawns Hermes and opencode as
  siblings, not descendants of each other), so a probe may pass while the guarantee does
  not exist. **UNVERIFIED** — and relying on `ptrace_scope` is not a security control.
- `/proc/1/environ` (where compose-level `environment:` lands) is root-owned mode 0400, so
  uid-10000 processes cannot read it directly — but `docker inspect` still shows everything,
  which is the already-accepted residual risk.
- A same-uid process can also read any file the other writes, and can inspect its open file
  descriptors via `/proc/<pid>/fd` (subject to the same ptrace rules).

So the deliverable is: **two distinct keys, each process configured with only its own**
(acceptance criterion as written in `odd/tasks/single-robotina-container.md`), **plus an
explicit "isolation is not achievable in one container" entry in `SECURITY.md`**. If the
user wants a real boundary, the only paths are separate containers (the status quo) or
separate uids with a redesigned workspace-sharing model.

Probe that proves distinctness **without printing either key** (carry into the spec):

```bash
docker compose exec robotina sh -c '
  for p in $(pgrep -f "opencode serve"); do echo "opencode: $(tr "\0" "\n" < /proc/$p/environ | grep "^OPENCODE_GO_API_KEY=" | sha256sum)"; done
  for p in $(pgrep -f "hermes");        do echo "hermes:   $(tr "\0" "\n" < /proc/$p/environ | grep "^OPENCODE_GO_API_KEY=" | sha256sum)"; done'
# two different hashes == two different values; nothing secret is echoed
```

---

## 7. Q6 — Loss of the "Hermes has no GitHub credential" invariant

Today the invariant is load-bearing: it is stated in the highest-priority context file and
enforced by the container boundary. In one container with `GITHUB_TOKEN` present, `gh`
installed, and `/etc/gitconfig` wiring `gh` as git's credential helper, **every process —
including the Telegram-facing agent — has GitHub credentials**. The instructions become
factually false, and the failure mode is inverted: the agent will no longer answer "delegate,
never ask for a token"; it can read private repos and push directly.

### 7.1 Files that must change (exhaustive from this exploration)

| File | What is now false |
| --- | --- |
| `hermes/context/.hermes.md` | "You live in your own container… share neither container nor filesystem"; "`gh` is NOT installed"; "no GitHub credential at all"; "there is no rewrite in this container"; "Private repositories… delegate to OpenCode"; the entire **Hard rule** paragraph and its 404-means-delegate conclusion |
| `hermes/skills/github-private-repos/SKILL.md` | `description`, the two-container capability table, rules 1–5, the "How to delegate a private clone" section, the troubleshooting table |
| `hermes/skills/opencode-server/SKILL.md` | `description`, "does not run inside this container", "sibling container", `http://opencode:4096` (→ `http://127.0.0.1:4096`), the "GitHub credentials do not exist here on purpose" bullet, `related_skills`, the `403`/`NO_PROXY` troubleshooting row |
| `README.md` | "Dos agentes… cada uno en su contenedor"; service table; architecture diagram; the three consequences; Requisitos (PAT "para que OpenCode pueda…"); Puesta en marcha steps 3/5/6; Uso ("Los dos juntos"); Estado y backups (`exec opencode`); Versiones; Decisiones deliberadas; Estructura del repo |
| `README.en.md` | the same set |
| `SECURITY.md` | Garantías table; "Compatibilidad verificada" (PID 1, capabilities); Variables de entorno; the whole "Interoperación Hermes ↔ OpenCode" section incl. "Por qué conviene poner el password"; "Autenticación de GitHub en el contenedor de opencode"; "Persistencia"; "Workspace compartido: por qué opencode corre como uid 10000"; "Cómo le llega una instrucción al agente"; Puntos de atención; Fuera de alcance |
| `.env.example` | line 2 comment (`docker inspect hermes`/`opencode`) |
| `openspec/project.md` | services table, coupling map items 1/5/6/7, verification expectations |
| `scripts/export-state.sh` | header comment (`docker compose exec opencode`) |
| `scripts/fix-permissions.ps1` | rationale text — or delete (§4.2) |
| `odd/tasks/single-robotina-container.md` | progress/verification evidence |
| `odd/tasks/agent-interop-http.md` | historical record — add a "superseded by" note, do not rewrite the history |
| `compose.yml` | the Spanish comments that explain the two-container split, the uid alignment and the `NO_PROXY` entries |

Note: the *bundled* Hermes skill `opencode` ("assumes the CLI is local") becomes
**applicable** after the merge, because the `opencode` binary will exist in the container.
The `opencode-server` skill must say so, otherwise the agent keeps a stale belief in the
opposite direction.

### 7.2 Proposed replacement rule (for the spec phase to refine)

> The GitHub PAT lives in **this** container. `gh` and git's credential helper are available
> to every process here, including you. Never print, echo, log or write the token; never ask
> the user for one. `permission.read` still denies `**/.config/gh/hosts.yml`, `**/.env`,
> `**/.ssh/**`, `**/*.pem`, `**/*.key` — that guards against accidental reads, not against a
> determined agent. Accepted residual risk: any process in this container can read
> `GITHUB_TOKEN` from its environment, and `gh auth token` prints it.

---

## 8. Q7 — Naming, and Q8 — egress/network

### 8.1 Naming (requirement (a))

Required: compose service name `robotina`, `container_name: robotina`, and therefore
`docker compose config --services` → `robotina`, `egress-proxy`; `docker compose build robotina`;
`docker compose exec robotina …`. The image tag becomes something like `robotina:local`
(today `robotina-opencode:local`) and the build directory should be renamed
(`opencode/` → `robotina/`) with `Dockerfile`, `entrypoint.sh`→s6 scripts, and `overlay.json`.
Every doc/script reference to the old service name is a required edit (enumerated in §7.1).

### 8.2 Bot identity = `robotina` (requirement (a), second half)

**Cannot be confirmed from the repository.** The repo contains no bot-name configuration:
`compose.yml` passes only `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, model keys and
`TZ`; identity material lives inside the vendor image and in `${HOST_DATA_DIR}/hermes`.

Candidate mechanisms, in order of likelihood (all **UNVERIFIED**):

1. **`SOUL.md`** — the vendor ships `/opt/hermes/docker/SOUL.md`, and `SECURITY.md` states
   that what is *always* loaded is the cwd context file (`.hermes.md`) **and `SOUL.md`**.
   `stage2-hook.sh` "seeds config" into `$HERMES_HOME`, so a host-side
   `${HOST_DATA_DIR}/hermes/SOUL.md` is the most likely editable identity surface.
2. **`config.yaml` identity keys** — `${HOST_DATA_DIR}/hermes/config.yaml` is documented as
   the file that wins over env vars (`HERMES_MODEL` cannot change the model because "a
   truthy configured model wins over `HERMES_MODEL`"). An identity/name key may live there.
3. **In-repo, guaranteed-to-work fallback** — add an explicit identity line to
   `hermes/context/.hermes.md` (mounted at `/workspace/.hermes.md`, always loaded). This
   makes the agent *introduce itself* as `robotina` even if (1) and (2) are not found, but
   it does **not** change the Telegram display name.
4. **Telegram BotFather** — the bot's public display name/username is owned by BotFather,
   outside this stack entirely. If "answers as `robotina`" means the Telegram profile name,
   the change is a Telegram-side action, not a repo change.

Verification recipes for the design phase:

```bash
docker compose exec robotina sh -c 'ls -la /opt/data | head -40; sed -n "1,40p" /opt/data/SOUL.md 2>/dev/null'
docker compose exec robotina sh -c 'grep -niE "name|persona|identity|soul" /opt/data/config.yaml | head -40'
docker compose exec robotina sh -c 'grep -rniE "you are|assistant name" /opt/hermes --include=*.md --include=*.yaml -l | head'
```

**Open question to report to the user**: which "name" must change — the agent's
self-description (repo-editable) or the Telegram bot's display name (BotFather), or both.

### 8.3 Egress and network (requirement (b) + invariants)

- `agents` network keeps exactly two members: `robotina` + `egress-proxy`. `internal: true`
  and the `egress` bridge are unchanged. Squid config and allowlist are untouched.
- `NO_PROXY` must drop `opencode` and add `robotina`:
  `localhost,127.0.0.1,::1,robotina,egress-proxy`. Loopback (`127.0.0.1`) is already listed,
  so the internal hop never touches Squid.
- Binding `opencode serve` to `127.0.0.1` is **strictly better** than today's `0.0.0.0`:
  today the server is reachable by `egress-proxy` (the documented "Squid co-tenancy"
  escalation in `SECURITY.md`); on loopback it is reachable by nothing outside the container.
  The same loopback URL must fail from the host and from `egress-proxy` — a spec-level
  Given/When/Then scenario.
- Consequence: `OPENCODE_SERVER_PASSWORD` loses its stated rationale. `SECURITY.md` says
  "egress-proxy is the only other member of the `agents` network, so without a password it
  can drive opencode". After the merge no network peer can reach the port, so the password
  becomes defense-in-depth only. Keep the variable (the export script and the skill recipe
  use it; removing it is a separate decision) but rewrite the rationale.
- The Hermes dashboard (`9119`) stays unpublished and off by default
  (`HERMES_DASHBOARD`); unchanged.
- No published ports anywhere; no Docker socket; secrets only via `.env` — all unchanged.

---

## 9. Security-model deltas (the part that must not be glossed over)

**Improvements**

| # | Delta |
| --- | --- |
| I1 | The OpenCode HTTP surface moves from `0.0.0.0:4096` to `127.0.0.1:4096`, removing the `egress-proxy` → opencode pivot path that `SECURITY.md` documented as a real privilege jump. |
| I2 | If the cont-init chown replaces `scripts/fix-permissions.ps1`, the host-side step that ran **unpinned `alpine:latest` as root with host state bind-mounted** disappears. |
| I3 | One fewer container: one fewer network member, one fewer lifecycle, one fewer image to rebuild. |

**Regressions (accepted by the user's product decision — must be documented)**

| # | Delta |
| --- | --- |
| R1 | **The GitHub credential invariant is gone.** `GITHUB_TOKEN` + `gh` + the credential helper are now in the same container as the Telegram-facing agent. Prompt injection into the bot now reaches GitHub directly (read private repos, push), instead of being blocked at the delegation boundary. |
| R2 | **Per-process key isolation is not enforceable.** Same uid, same container: `/proc/<pid>/environ`, `/proc/<pid>/fd` and any file the other process writes are reachable in principle. The acceptance criterion ("each process sees only its own key") is satisfiable; "neither can read the other's" is not. |
| R3 | **Capabilities are per-container, not per-process.** Today opencode runs with pure `cap_drop: ALL`; after the merge the opencode process lives under `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID]`. Whether `s6-setuidgid` clears the effective set for uid 10000 must be **measured**, and if it does not, the run script should drop them explicitly (`capsh --drop=…` / `setpriv --bounding-set=-all`). Do not assume. |
| R4 | **Single lifecycle.** A Hermes crash exits the container and takes opencode and engram with it; today they are independent failure domains. |
| R5 | **Shared resource budget.** 2g + 4g and 2.0 + 4.0 CPUs must become one limit, and `pids_limit: 512` now covers Hermes + opencode + LSP children + engram + R/go builds. Re-forecast before design. |
| R6 | The "isolation preserved" claim recorded in `odd/tasks/agent-interop-http.md` is retired. Say so explicitly rather than letting the two documents contradict each other. |

Verification recipes for the regressions (carry into the spec):

```bash
docker compose exec robotina sh -c 'grep -E "Cap(Eff|Bnd)" /proc/$(pgrep -f "opencode serve")/status'
docker compose exec robotina sh -c 'tr "\0" "\n" < /proc/$(pgrep -f "hermes gateway")/environ | grep -c OPENCODE_GO_API_KEY'
docker compose exec robotina s6-rc -a list
docker compose exec robotina sh -c 'curl -fsS http://127.0.0.1:4096/global/health'
docker run --rm --network agents curlimages/curl -m 5 http://robotina:4096/global/health   # must fail
docker compose exec egress-proxy bash -c 'exec 3<>/dev/tcp/robotina/4096'                  # must fail
```

---

## 10. Open questions (must be answered before or during `sdd-design`)

| # | Question | Why it blocks | How to resolve |
| --- | --- | --- | --- |
| OQ1 | Does a **glibc build** of opencode exist and run on Debian trixie? | Determines whether the merge is feasible at all in the chosen direction | `npm view opencode-ai optionalDependencies`; `file` the current binary; run `opencode --version` on trixie |
| OQ2 | Which mechanism sets the **bot identity** to `robotina` — `SOUL.md`, `config.yaml`, the in-repo `.hermes.md`, or BotFather? | Requirement (a) cannot be specified or verified without it | probes in §8.2 |
| OQ3 | Do `mem_limit`/`cpus`/`pids_limit` need new values? | Capacity decision, and a security-relevant limit | measure a running merged container under load |
| OQ4 | Are capabilities actually cleared for the uid-10000 opencode process? | R3; decides whether the run script must drop them explicitly | `CapEff`/`CapBnd` probe |
| OQ5 | Keep `HOME=/root` for the opencode service, or move it under `/opt/data` (nested mounts + XDG assumptions)? | Mount topology and state migration | prefer `/root`; measure nesting only if the alternative is chosen |
| OQ6 | Does `opencode serve` need readiness gating (`s6-notifyoncheck`) so Hermes' first loopback call does not race? | Startup-ordering correctness | test `docker compose up` then an immediate delegation |
| OQ7 | Should `scripts/fix-permissions.ps1` be deleted (cont-init chown) or kept and re-documented? | Documentation + one fewer privileged host step | decide in design; if deleted, update README/SECURITY steps 5 |
| OQ8 | Does the container-wide `/etc/gitconfig` merge cleanly with whatever the vendor image ships? | Avoid silently dropping vendor git config | `cat /etc/gitconfig` in the vendor image |
| OQ9 | Where does the merged service's state directory live — rename `opencode/` → `robotina/` in the repo? | Repo layout + every doc reference | design decision |
| OQ10 | Is the **review budget** still under 400 authored lines once the doc set in §7.1 is counted? | `ask-on-risk` requires a re-forecast; chaining must not be invented | re-forecast at `sdd-tasks` |

**Not in question (frozen):** loopback-only server; `egress-proxy` separate; container and
bot identity `robotina`; no published ports; no Docker socket; secrets only via `.env`;
Squid allowlist untouched.

---

## 11. Candidate implementation shape (non-binding; input for `sdd-proposal`/`sdd-design`)

1. New build directory `robotina/` (`Dockerfile`, `overlay.json`, `s6/…`); `opencode/`
   retired.
2. `Dockerfile`: `FROM nousresearch/hermes-agent:latest`; add `gh`, `jq`, `ripgrep`, R +
   build deps, `taplo`, `marksman`, the npm LSPs + codegraph (no musl shim), the glibc
   opencode binary, uv-managed CPython, `engram`, `gentle-ai`, the staged gentle-ai tree,
   the merged `/etc/gitconfig`, `go`; `chown` the opencode state roots to 10000; **do not**
   override `ENTRYPOINT`; keep the vendor `CMD` free for compose's `["gateway","run"]`.
3. s6: `opencode-init` (oneshot), `engram` (longrun), `opencode` (longrun), all registered
   in the `user2` bundle, each `dependencies.d/base`.
4. Optional cont-init script: chown the opencode state roots + `/workspace` to 10000
   (replaces `scripts/fix-permissions.ps1`).
5. `compose.yml`: one service `robotina` + `container_name: robotina`; no `user:`, no
   `init: true`; merged limits; updated `NO_PROXY`; the two API keys as in §6.1; all
   opencode mounts preserved verbatim; `cap_add` unchanged.
6. Docs: rewrite the set in §7.1; add the "no per-process isolation in one container" and
   "GitHub credential invariant retired" entries to `SECURITY.md`.
7. Verification: the recipes in §9 plus `docker compose config -q`,
   `docker compose config --services`, `docker compose build`, `docker compose ps`,
   the docs grep and the secrets grep from `openspec/config.yaml`.

---

## 12. Phase result

- The merge is feasible in exactly one direction (`FROM nousresearch/hermes-agent`), and its
  feasibility hinges on a single unverified fact (OQ1: a glibc opencode build).
- The vendor's `user2` bundle and `s6-rc.d` source tree are the natural supervision extension
  point; `opencode serve` becomes a longrun with `s6-setuidgid hermes`, and the container CMD
  stays Hermes' main program.
- Keeping `HOME=/root` for the opencode service preserves every existing mount and avoids
  nested volumes entirely.
- Two distinct keys are achievable; per-process isolation is **not**, and that must be
  documented as a regression rather than implied away.
- The "Hermes has no GitHub credential" invariant is retired and touches at least twelve
  files, including the always-loaded context file and both Hermes skills.
- Bot identity is the one requirement that cannot be traced to the repository: it is an open
  question with four candidate mechanisms.
- Nothing was implemented; no child subagents were used.
