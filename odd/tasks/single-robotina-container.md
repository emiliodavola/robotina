# Feature: single-robotina-container

## Goal

Collapse the two agent containers (`hermes` + `opencode`) into **one** container
named `robotina` that must answer to that name, ships the OpenCode HTTP server on
loopback, and keeps the two agents on **distinct API keys**.

## Problem

The current stack runs Hermes and OpenCode as two containers joined only by an
HTTP hop over the internal `agents` network (`http://opencode:4096`) plus a shared
`/workspace` bind. The user reports that this separation does not work for them
and wants a single container.

## Why it is not just "delete a service"

- Hermes is a vendor image driven by **s6-overlay as PID 1**, running its app as
  uid 10000 and requiring `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID]`.
  It cannot simply be dropped next to another process.
- OpenCode is a **custom image** (`opencode/Dockerfile`) carrying node/npm, uv +
  Python 3.13, R + languageserver, `gh`, engram, gentle-ai artifacts, codegraph and
  six LSP servers. The merge has to preserve that toolchain.
- The egress boundary is a third container (`egress-proxy`). Merging the agents
  must not merge the proxy away.

## Scope

In scope:

- One container, service name `robotina`, based on the Hermes image with the
  OpenCode toolchain added (or equivalent composition compatible with s6-overlay).
- `opencode serve` bound to `127.0.0.1:4096` inside `robotina`.
- Bot identity answers as `robotina`.
- Two distinct API keys preserved with per-process isolation.
- Update `compose.yml`, the Dockerfile, entrypoints/scripts, Hermes skills,
  context facts, `README.md`, `README.en.md`, `SECURITY.md`, `.env.example`.

Out of scope:

- Merging `egress-proxy` (user decision: the egress boundary stays separate).
- Publishing ports.
- Changing the Squid allowlist or the proxy model.
- Exposing the OpenCode TUI/CLI (user chose loopback HTTP server only).

## Constraints

- No direct Internet from `robotina`: egress only through `egress-proxy`.
- Keep `cap_drop: ALL` + explicit `cap_add` set that s6-overlay needs.
- `no-new-privileges:true`, pids/memory/CPU limits, core dumps off, bounded logs.
- State stays in host folders under `HOST_DATA_DIR`; WAL SQLite stays on native
  Docker volumes.
- No commits on `main`: work on a feature branch, merge via PR.
- Secrets only via `.env` (gitignored), never committed.

## Delivery and process

- Workflow: SDD (explicitly requested by the user), interactive execution mode.
- Artifact store: `openspec/` in the repo.
- Delivery strategy: `ask-on-risk`; review budget 400 authored changed lines.
- Branch: `feat/single-robotina-container` (no direct commits to `main`).
- TDD: not declared by the project. Functional checks are shell-level
  (`docker compose config`, `docker compose build`, `docker compose up` +
  in-container probes) plus doc/secret greps. Recorded as ordinary checks.

## Review Workload Forecast (provisional)

`compose.yml` (large rewrite), `opencode/Dockerfile` (retarget base), a new/edited
entrypoint, `hermes/skills/opencode-server/SKILL.md`, `hermes/context/.hermes.md`,
`README.md`, `README.en.md`, `SECURITY.md`, `.env.example`, `scripts/*`.
Estimate: **high** risk of exceeding 400 authored lines. Re-forecast after
`sdd-tasks`; `ask-on-risk` will stop for a chained-PR decision if confirmed.

## Tasks

- [x] T1 — ODD feature document (this file).
- [x] T2 — SDD init: `openspec/config.yaml` + project SDD context.
- [x] T3 — SDD explore: map coupling, call sites and what the merge must preserve.- [ ] T4 — SDD proposal: PRD for the single `robotina` container.
- [x] T5 — SDD spec: 39 requirements / 113 scenarios across six domain specs (+1 corrective amendment).
- [x] T6 — SDD design: image composition, s6 wiring, key isolation, state layout (Q1–Q12 resolved).
- [x] T7 — SDD tasks: 45 tasks in 10 phases + Review Workload Forecast (over budget, chained).
- [ ] T8 — SDD apply: implement compose/Dockerfile/entrypoint/skills/docs.
- [ ] T9 — SDD archive: compose applicable specs, record final state.
- [ ] T10 — Delivery: branch pushed, PR opened (no merge without user decision).

## Acceptance criteria

- `docker compose config` is valid and `docker compose up -d` brings up exactly two
  services: `robotina` and `egress-proxy`.
- The container and its service are both named `robotina`.
- `opencode serve` is reachable at `127.0.0.1:4096` from inside `robotina` and is
  **not** reachable from the host or from any other container.
- Hermes uses only `HERMES_OPENCODE_GO_API_KEY`; OpenCode uses only
  `OPENCODE_GO_API_KEY`; neither process can read the other's key.
- The bot answers/introduces itself as `robotina`.
- `/workspace`, engram state and opencode sessions persist across recreate.
- No direct egress: all outbound goes through `egress-proxy`.
- `README.md`, `README.en.md`, `SECURITY.md`, `.env.example` and Hermes skills
  describe the single-container reality, with no stale two-container claims.

## Resolved decisions (post-explore)

Frozen by the user after the explore phase:

| # | Decision | Consequence |
| --- | --- | --- |
| D1 | Container direction: `FROM nousresearch/hermes-agent:latest` + port the OpenCode toolchain. | The reverse is infeasible (glibc vendor tree vs Alpine/musl opencode image). Verified: npm `opencode-ai@1.18.32` publishes `opencode-linux-x64` (glibc) alongside `-musl`. |
| D2 | Accept and document the security regressions; do **not** add explicit capability dropping. | `SECURITY.md` gains: no per-process key isolation (same uid), GitHub credential reachable by the Telegram-facing agent, single lifecycle, shared capability set. |
| D3 | `GITHUB_TOKEN` stays in the merged container. | The "Hermes has no GitHub credential" invariant is retired; `hermes/context/.hermes.md` and both Hermes skills must be rewritten. |
| D4 | Bot identity = Hermes **skin** `robotina` (`branding.agent_name`) + always-loaded context identity + documented BotFather step. | Ship `hermes/skins/robotina.yaml`, apply `display.skin` at startup, document the Telegram-side rename. |
| D5 | **Consolidate OpenCode state under `/opt/data`.** | `HOME=/opt/data` for the OpenCode service; `$HOME/.config/opencode`, `$HOME/.config/git`, `$HOME/go` land inside the Hermes bind; engram and the OpenCode session DB stay on native volumes mounted at `$HOME/.engram` and `$HOME/.local/share/opencode` (WAL rule). `/workspace` stays a separate bind. The standalone `${HOST_DATA_DIR}/opencode`, `/git`, `/go` mounts disappear. Requires verifying nested volume-inside-bind mounts on Docker Desktop Windows. |

## Progress

- 2026-09-22: SDD preflight resolved (interactive, openspec, ask-on-risk, 400).
  Product decisions: container+identity `robotina`; `opencode serve` on loopback;
  proxy stays separate. SDD agents installed additively in the Pi runtime.
- 2026-09-22: `sdd-init` OK — `openspec/config.yaml` + `openspec/project.md`.
- 2026-09-22: `sdd-explore` OK — `openspec/changes/single-robotina-container/explore.md`.
  Verified the vendor image read-only (Debian 13, node/npm/uv/git/curl already present,
  s6 `user2` bundle empty = extension point, CMD is `/init`'s main program).
  Resolved the blocking question: a glibc opencode build exists on npm.
  Resolved the identity question: Hermes skins (`<HERMES_HOME>/skins/*.yaml`, `display.skin`).
  User decisions D1–D5 recorded above.
- 2026-09-22: `sdd-proposal` OK + user-approved. §17 question round answered: keep the
  broad PAT (documented risk), copy-forward non-blocking migration, BotFather display name
  only, 6g / 6.0 CPUs, loopback-only operator access accepted.
- 2026-09-22: `sdd-spec` OK — 39 requirements / 113 scenarios across six domain specs.
  Then amended once with corrective feedback after `sdd-design` found three blocker-class
  **proof** defects (AC8's single-lifecycle proof raced `restart: unless-stopped`;
  `pgrep -f` patterns matched their own probe shell, risking vacuous passes; CR4's
  line-scoped grep was unsatisfiable against frozen prose) plus credential-aware health
  probes. No requirement text moved.
- 2026-09-22: `sdd-design` OK — `design.md` (Q1–Q12 decided with rejected alternatives).
  Key decisions: `pids_limit: 1024` (forecast, to confirm by measurement), an
  `opencode-ready` oneshot polling `/global/health` as the readiness gate, `finish`-based
  capped backoff for the longruns, keep `OPENCODE_SERVER_PASSWORD` (defense-in-depth),
  `robotina/` replaces `opencode/` with s6 sources under `robotina/s6/`, engram logs to the
  container stream, migration via a host-side helper, nesting proof with escalation path.
- 2026-09-22: `sdd-apply` slice 07 (docs) — both READMEs rewritten for the single-container
  reality (topology, build, removed host permission step, copy-forward migration plus its POSIX
  equivalent, export-before-migrate safety net, BotFather display name only, in-container
  operator recipes, persistence table, measured versions, uid-10000 assumption);
  `scripts/fix-permissions.ps1` deleted (Q7 resolved).

## Delivery plan (decided at sdd-tasks)
- Strategy: **chained PRs**; chain strategy: **`feature-branch-chain`**.
- Tracker branch: `feat/single-robotina-container` (this branch). Only the tracker merges to `main`.
- Slice branches are cut from the tracker; PR #1 targets the tracker, each child PR targets the
  immediate previous slice branch. Merge bottom-up; retarget each child once its parent lands.
- PR #1 is the **process artifacts** (`openspec/**` + `odd/tasks/single-robotina-container.md`),
  kept separate from the implementation review.
- **Review budget policy (user decision, 2026-09-22): `size:exception` accepted per slice**, up to
  roughly 650 authored lines per slice, instead of splitting further. Slices over 400 are
  documented with their measured count rather than re-sliced.

## Slice progress

| Slice | Branch | Commit | Authored lines | Status |
| --- | --- | --- | --- | --- |
| S0 artifacts | `feat/single-robotina-container-01-artifacts` | `3a420ab` | 5,005 | committed |
| S1 compose | `feat/single-robotina-container-02-compose` | `53dc10e` | 449 (646 with the process record) | committed |
| S2 image | `feat/single-robotina-container-03-image` | `68d3d30` | 658 | committed |
| S4 supervision | `feat/single-robotina-container-04-supervision` | committed | 287 (520 with the process record) | committed; **slice-05 fixes appended** (two runtime defects) |
| S5 identity | pending | — | — | pending |
| S6 migration & scripts | pending | — | — | pending |
| S7 docs | pending | — | — | pending |
| S8 records | pending | — | — | pending |
| S9 measurement evidence | pending | — | — | pending |

Task progress: **19/45** implementation tasks complete (12 through slice 04; +7 in slice 05:
tasks 17–20, 23–25, after the two slice-04 defects were fixed and the stack was re-verified live).

Verified so far without a live stack: `docker compose config -q`, `--services`,
`docker compose build robotina` (exit 0), `docker build --check`, `s6-rc-compile` +
`s6-rc-db check` (exit 0), the backoff sequence, and the cont-init script against real
read-only mounts.

Gated on a live `.env` (needs reissued keys) and `docker compose up`: tasks 18, 22, 27 and the
whole measurement phase — the nested volume-inside-bind proof, the readiness gate, the
measured `CapEff`/`CapBnd`, and `pids.current` under load.

**Status after slice 05 (stack live):** tasks 18, 19, 20, 24 and 25 are now measured and complete
(see the slice-05 evidence section); the readiness gate succeeded in ≈4.85 s; capabilities match
design §13. Still gated: task 21's 3× recreation loop + gate-failure observation, task 22 (identity
not implemented), tasks 26/38 (peak `pids.current` under the concurrent worst case), and tasks
27–28.

| PR | Slice | Contents | Est. lines |
| --- | --- | --- | --- |
| 1 | S0 | SDD process artifacts (`openspec/`, `odd/tasks/`) | 4,734 |
| 2 | S1 | `compose.yml` rewrite | ~170 |
| 3 | S2 | `robotina/Dockerfile` + build context (incl. `opencode/` removal) | ~460 |
| 4 | S4 | s6 services + `opencode-init` + healthcheck script | ~225 |
| 5 | S5 | Identity (skin, read-only mount, `display.skin`, BotFather doc) | ~275 |
| 6 | S6 | Migration helper + scripts | ~147 |
| 7 | S7 | README pair (bilingual, same commit) | ~370 |
| 8 | S8 | `SECURITY.md` + records + spec OPEN ITEM alignment | ~240 |
| 9 | S9 | Measurement evidence (`pids_limit`, nesting, capabilities) | ~40 |

Forecast recorded by `sdd-tasks`: process artifacts 4,734 lines; implementation + docs ≈2,060
(range 1,850–2,450); total ≈6,790.

## Apply prerequisites

- Slices S0–S4 need only `docker compose config -q` and `docker compose build`; the current
  `.env` is sufficient (the revoked keys are only used at `up`).
- The measurement phases (nesting proof, readiness, capabilities, `pids_limit`) need
  `docker compose up -d`, which needs a **working** `.env`:
  `TELEGRAM_BOT_TOKEN`, `HERMES_OPENCODE_GO_API_KEY`, `OPENCODE_GO_API_KEY`. The user must
  reissue fresh keys before those slices.

## Open decisions

- **Q7 — `scripts/fix-permissions.ps1`**: the user cancelled the choice. Not decided, not
  invented. Interim safe default from design §8.4: keep the file with a "superseded" header
  and drop it from the setup instructions. Revisit before `sdd-apply` closes.
- **Q7 — RESOLVED in slice 07 (user decision):** `scripts/fix-permissions.ps1` is **deleted**.
  The container-side cont-init (`robotina/s6/cont-init.d/10-robotina-state`) fixes ownership on
  every start, and a host-side root helper on unpinned `alpine` with the host state bind mounted
  is a documented trap with no remaining benefit. `git rm` staged the deletion; neither README
  references it any more.
- **F1 (found in slice 02)**: task 45's secret-leak grep is unsatisfiable as written — the
  repository already has 28 benign matches from documentation placeholders and shell variable
  references. Needs a value-shaped refinement before that task can pass.
- **Environment incident (repaired)**: `sdd-apply` was hard-blocked with
  `package-local-binary-missing` because `<package>/.gentle-ai/v3.5.0/gentle-ai.exe` was absent.
  Repaired by `node scripts/install-gentle-ai.mjs` in the gentle-pi package root.
- **Slice 03 findings**: marksman's musl asset cannot run on the glibc base (the glibc asset
  plus libicu is required), and a negated `grep` under `set -e` is a silent no-op, so the
  glibc-opencode assertion was rewritten as a same-inode check plus an `ldd` proof. Both are
  design-statement corrections still to be folded into `design.md`.
- **Slice 03 anomaly (resolved)**: an unexplained edit changed the `ENGRAM_VERSION` /
  `GENTLE_AI_VERSION` pins mid-slice; the agent restored the design values and the build
  verified green against them.
- **Slice 04 finding (A1, recorded)**: `chown` has no `--one-file-system`, so the root-side
  ownership pass prunes the read-only mounts under `/opt/data`. Adding a new mount there means
  updating the prune list.
- **Corrected**: the vendor base does NOT ship `/etc/gitconfig`; the merged image creates it in
  its own Dockerfile layer. An earlier probe was mislabelled.
- Stale `OPEN ITEM` annotations in the specs still describe Q1/Q2/Q3/Q5/Q7/Q10/Q12 as open;
  `sdd-design` closed them. Needs an alignment task in the apply set.
- Review workload: the SDD artifacts alone are ~3.9k authored lines. Delivery strategy
  decision pending at `sdd-tasks`.

## Verification evidence

### Baseline captured before the compose rewrite (tasks 1–3)

Slice: `feat/single-robotina-container-02-compose`. Host: Docker 29.8.0 / Docker Compose
v5.5.1, Windows + Docker Desktop. **The stack was not running at capture time** and no
agent container existed (`docker ps -a` returned no rows), so every runtime observation is
recorded as unavailable rather than invented.

#### Task 1 — pre-change service inventory and state volumes

Raw output:

```text
$ docker compose config --services
egress-proxy
hermes
opencode
# exit=0

$ docker compose config --volumes
engram_db
opencode_db
# exit=0

$ docker ps -a --format '{{.Names}} {{.Status}} {{.Image}}'
# (no output: no container exists, running or stopped)

$ docker volume ls --format '{{.Name}}'
7d12bdd3138bb229cf2f547cb1c56c017475d727a9a00e1d8d2bfa7e4d67e357
44d2ff58eb6eefd3c83eaf9a8b1bc185c9fa99c42b225c216bcaf5d0413f654b

$ docker volume ls --format '{{.Name}}' | grep -cE '^robotina_(engram|opencode)_db$'
0
# exit=1 (the pipeline's last stage found no match)
```

Interpretation, honestly:

- The assigned expectation was `hermes`, `opencode`, `egress-proxy` for the service list —
  **observed exactly that**.
- The assigned expectation was `2` for the volume grep. **Observed `0`**: neither
  `robotina_engram_db` nor `robotina_opencode_db` exists on this host yet, because the
  pre-change stack was never brought up here. The two anonymous hashes are unrelated
  volumes. The volume *names* are declared in the pre-change `compose.yml`
  (`volumes.engram_db.name`, `volumes.opencode_db.name`) and reappear under the same names
  after the rewrite; they are simply not instantiated until the first `up`.
- **PID-1 command lines of the running two-container topology: unavailable.** No container
  ever ran in this environment, so a `docker compose exec … /proc/1/cmdline` reading cannot
  be produced and MUST NOT be fabricated.
- **Mount list observed at runtime: unavailable.** Recorded instead from the pre-change
  `compose.yml` (declared, not observed):
  - `hermes`: bind `${HOST_DATA_DIR}/hermes` → `/opt/data`; bind `${HOST_DATA_DIR}/workspace`
    → `/workspace`; bind `./hermes/skills` → `/opt/data/skills/stack` (ro); bind
    `./hermes/context/.hermes.md` → `/workspace/.hermes.md` (ro); tmpfs `/tmp`.
  - `opencode`: bind `${HOST_DATA_DIR}/workspace` → `/workspace`; bind
    `${HOST_DATA_DIR}/opencode` → `/root/.config/opencode`; volume `engram_db` →
    `/root/.engram`; volume `opencode_db` → `/root/.local/share/opencode`; bind
    `${HOST_DATA_DIR}/backups` → `/backups`; bind `${HOST_DATA_DIR}/git` →
    `/root/.config/git`; bind `${HOST_DATA_DIR}/go` → `/root/go`; bind
    `./scripts/export-state.sh` → `/opt/export-state.sh` (ro); tmpfs `/tmp`.
  - `egress-proxy`: bind `./squid/squid.conf` → `/etc/squid/squid.conf` (ro); bind
    `./squid/allowlist.txt` → `/etc/squid/allowlist.txt` (ro); tmpfs
    `/var/log/squid`, `/var/spool/squid`, `/run`, `/tmp`.

#### Task 3 — resolved vendor base image digest and measured tool versions

```text
$ docker inspect --format '{{index .RepoDigests 0}}' nousresearch/hermes-agent:latest
nousresearch/hermes-agent@sha256:b2e3eeb0c550d262a5d713788ca079e682b9acfc4a0d02ec614bc847bd1087a9
# exit=0

$ docker inspect --format 'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}} WorkingDir={{json .Config.WorkingDir}}' nousresearch/hermes-agent:latest
Entrypoint=["/opt/hermes/docker/entrypoint-dispatch.sh"] Cmd=null WorkingDir="/opt/hermes"

$ docker inspect --format 'Os={{.Os}} Arch={{.Architecture}} Size={{.Size}}' nousresearch/hermes-agent:latest
Os=linux Arch=amd64 Size=3980271518

$ docker run --rm --network none --entrypoint sh nousresearch/hermes-agent:latest -c '…version probes…'
node: v26.5.1
npm: 11.17.0
uv: uv 0.11.6 (x86_64-unknown-linux-musl)
git: git version 2.47.3
curl: curl 8.14.1 (x86_64-pc-linux-gnu) libcurl/8.14.1 OpenSSL/3.5.7 …
python3: Python 3.13.5
bash: GNU bash, version 5.2.37(1)-release (x86_64-pc-linux-gnu)
```

- The base image is **floating by design** (design §2.5): digest pinning is out of scope;
  the digest above is recorded so a later vendor move is visible.
- **Measured versions are the vendor base's**, and only that. The OpenCode toolchain
  versions the READMEs' table reports (`opencode`, `gh`, `taplo`, `marksman`, `codegraph`,
  `engram`, `gentle-ai`, `go`, `R`, `jq`, `ripgrep`, CPython 3.13) are **not measured here**:
  `robotina-opencode:local` was never built and the old `opencode` image is not present, so
  there is no container to measure them in. They stay as the pre-change README measurement
  until the merged image is built (out of scope for this slice) and re-measured in task 17.
- Vendor runtime identity (observed in the throwaway probe container): `HOME=/root`,
  `HERMES_HOME=/opt/data`, `hermes:x:10000:10000::/opt/data:/bin/sh`, and the vendor image
  ships **no** `/etc/gitconfig` (relevant to the §3 merge: everything is ours then).

#### Task 2 — branch, tree and secret-hygiene precondition

```text
$ git rev-parse --abbrev-ref HEAD
feat/single-robotina-container-02-compose

$ git merge-base --is-ancestor feat/single-robotina-container HEAD && echo descends-from-tracker=yes
descends-from-tracker=yes

$ git status --porcelain
# (no output: clean tree before the compose rewrite)

$ git check-ignore -v .env
.gitignore:6:.env	.env

$ git ls-files .env
# (no output)
```

**Recorded adaptation (the task's assertion was written for a single-branch flow).** The
assigned expectation `git rev-parse --abbrev-ref HEAD → feat/single-robotina-container` does
not apply to a feature-branch chain: this slice lives on
`feat/single-robotina-container-02-compose`, cut from the tracker branch
`feat/single-robotina-container`. The adapted assertions are (a) HEAD is the slice branch,
(b) it **descends from** the tracker branch (`git merge-base --is-ancestor` exits 0), and
(c) the tree was clean before any edit. All three hold above.

Secret-hygiene precondition — **the assigned grep is over-broad and is honestly reported as
such**:

```text
$ git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example' | wc -l
28
```

All 28 pre-existing matches are benign, and every one falls into exactly one class:

1. **Documentation placeholders with an empty value** — `README.md`, `README.en.md`,
   `SECURITY.md` show `TELEGRAM_BOT_TOKEN=` followed by whitespace and a comment, e.g.
   `README.md:91:   TELEGRAM_BOT_TOKEN=                 # @BotFather`. The `.+` matches the
   padding, not a value.
2. **Shell variable references inside recipes** — `OPENCODE_GO_API_KEY="$ROBOTINA_OPENCODE_GO_API_KEY"`
   in `design.md`/`explore.md` and the `grep … "^OPENCODE_GO_API_KEY=" .env` lines in the
   spec/tasks recipes; the right-hand side is a reference or a grep pattern, never a literal
   secret.
3. The grep pattern text itself inside the frozen artifacts.

The precondition this task actually asserts — *no real secret is committed* — was therefore
verified with a value-shaped refinement, which is empty:

```text
$ git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=[A-Za-z0-9_-]{8,}' -- ':!*.example'
# (no output; exit=1)

$ git ls-files .env
# (no output)
```

`.env` is gitignored and untracked, so its values are not reachable through `git grep` at
all. **Finding for the parent:** the literal recipe assigned to task 2 (and repeated in task
45) cannot pass on this repository even before the change; it needs the value-shaped
refinement, or a `:!*.md`-style path exclusion, in a later slice. This slice does not rewrite
`tasks.md` recipes.

## Slice 05 — runtime defect fix and re-verification (slice 04 branch)

Branch: `feat/single-robotina-container-04-supervision`. The first live `up` (stack up, keys live)
exposed **two real defects in slice 04**. Both are fixed, the image is rebuilt, and the stack is
re-verified at runtime. Tasks 10 and 12 were reopened and re-closed; tasks 17–20 and 23–25 are now
complete. **Task progress: 19/45.**

### Defect D1 — the s6 oneshot `up` files were not execline (reopens task 12)

```text
# observed before the fix
docker compose logs robotina
robotina  | s6-rc-oneshot-run: fatal: unable to exec set: No such file or directory
robotina  | s6-rc: warning: unable to start service opencode-init: command exited 127
# proof of the root cause, inside the container
$ /package/admin/execline/command/execlineb /etc/s6-overlay/s6-rc.d/opencode-init/up
execlineb: fatal: unable to exec set: No such file or directory   # exit=127
# the vendor convention: each oneshot up is a single executable path
$ cat /package/admin/s6-overlay/etc/s6-rc/sources/fix-attrs/up
/package/admin/s6-overlay-3.2.3.0/etc/s6-rc/scripts/fix-attrs
```

s6-rc executes a oneshot's `up` **as an execline script**, so the old `#!/command/with-contenv sh`
+ `set -eu` form made `set` the program to exec. `opencode` and `engram` depend on `opencode-init`,
so neither started. Fix: both `up` files are one-line execline invocations
(`opencode-init/up` imports the container env, sets `HOME=/opt/data`, drops to `hermes`;
`opencode-ready/up` runs the new image script `robotina/opencode-ready.sh` with the bounded
credential-aware poll). The `Dockerfile` now asserts every oneshot `up` is one command line, has
no shebang, does not start with `set`, and starts with an existing executable absolute path.

```text
# observed after the rebuild
$ PATH=/command:$PATH s6-rc -a list
s6rc-oneshot-runner dashboard engram main-hermes opencode fix-attrs opencode-init opencode-ready legacy-cont-init legacy-services
$ PATH=/command:$PATH s6-svstat /run/service/opencode
up (pid 210 pgid 210) 25 seconds
# log sequence: opencode-init successfully started -> engram -> opencode -> opencode-ready
robotina  | robotina: opencode listo (intentos=1)
```

### Defect D2 — the ownership self-heal was too shallow (reopens task 10)

```text
# measured before the fix
drwx------ 1 hermes hermes /opt/data
drwxr-xr-x 1 root   root   /opt/data/.config
drwxr-xr-x 1 root   root   /opt/data/.local
drwxr-xr-x 1 root   root   /opt/data/.local/share
ls: cannot access '/opt/data/.local/state': No such file or directory
# Hermes logged
ERROR [Telegram] Failed to connect to Telegram: [Errno 13] Permission denied: '/opt/data/.local/state'
WARNING gateway.run: Host gateway lock could not be opened (Permission denied: '/opt/data/.local/state')
WARNING gateway.run: ✗ telegram failed to connect
```

The repair guard `s6-setuidgid hermes test -w /opt/data` passed (the root is `hermes:hermes 0700`),
so the root-owned children were never repaired. Fix: `10-robotina-state` lists the intermediate
parents in `install -d -o/-g` (`.config`, `.local`, `.local/share`, plus `.local/state` and
`.cache`) and tests a per-directory writability list that covers the directories the app writes to,
not just `/opt/data`, before the bounded `find -prune` re-own. The read-only-mount prune list is
unchanged.

```text
# observed after the rebuild
drwxr-xr-x 1 hermes hermes /opt/data/.config
drwxr-xr-x 1 hermes hermes /opt/data/.local
drwxr-xr-x 1 hermes hermes /opt/data/.local/share
drwxr-xr-x 1 hermes hermes /opt/data/.local/state
$ stat -c '%u:%g' /opt/data/.local/state
10000:10000
$ docker compose logs robotina | grep -cE "Permission denied: '/opt/data/.local/state'|telegram failed to connect"
0
robotina  | [Telegram] Connected to Telegram (polling mode)
```

### Measurement set (previously forecast-only, now measured)

| Item | Raw result |
| --- | --- |
| Nested mounts | `/dev/sdd on /opt/data/.engram type ext4 (rw,relatime)`; `/dev/sdd on /opt/data/.local/share/opencode type ext4 (rw,relatime)` — neither `9p` nor `virtiofs` |
| Nested mount type (Docker) | `volume /var/lib/docker/volumes/robotina_engram_db/_data -> /opt/data/.engram`; `volume …/robotina_opencode_db/_data -> /opt/data/.local/share/opencode` |
| Negative control | marker `.robotina-probe` written inside the volume; host bind `hermes/.engram` empty; the volume holds `.robotina-probe`, `engram.db`, `engram.db-shm`, `engram.db-wal` |
| Durability | marker survived `docker compose down` + `docker compose up -d`; volume count = 2 |
| EP4 cold start | `StartedAt 2026-09-22T18:18:31.298Z` → `opencode listo (intentos=1)` at `18:18:36.148Z` = **≈ 4.85 s** (bound 120 s) |
| Capabilities (uid 10000 `opencode serve`) | `CapInh=0x0 CapPrm=0x0 CapEff=0x0 CapBnd=0x00000000000000cb CapAmb=0x0 NoNewPrivs=1` |
| `pids` at rest | `pids.current=54`, `pids.max=1024` — peak (task 26) not measured |
| Key distinctness (CR2/CR3) | opencode `286c7a04…`, hermes `06c38c58…` → differ; both match the exported shell env (see finding) |
| Duplicate home (SL1) | `opencode serve` `HOME=/opt/data` and Hermes main program `HOME=/opt/data` |
| Isolation (EP2/EP3) | host `curl 127.0.0.1:4096` exit 7; `egress-proxy` `/dev/tcp/robotina/4096` refused; peer control `400`, `robotina:4096` refused (exit 7) |
| Auth protection (EP1/EP4) | with `-u` exit 0; without `-u` **HTTP 401** → the endpoint is auth-protected |
| Not-ours warning | 8 × Hermes `virtiofs/9p` SQLite message (`state.db`, `response_store.db`, `runs_idempotency.db`, `cron/executions.db`, `kanban.db`, `shared-state.db`) — pre-existing Hermes state on the `/opt/data` bind; **not introduced by this change** |

### Findings recorded by slice 05

- The EP1/EP4 `NOTE` in `specs/opencode-endpoint/spec.md` should record the auth-protected
  observation; `specs/` is outside this session's allowed edit surfaces, so it is reported, not
  edited. The recipes are already credential-aware.
- The `.env`-reference half of task 23 could not be asserted: Compose gives the process environment
  precedence over `.env`, so the container used the exported 67-byte keys instead of the `.env`
  51-byte values. Distinctness still holds.
- The in-container `robotina:4096` negative-control probe is confounded by the proxy environment
  (Squid deny page, exit 0); the unconfounded proof is the peer-container refusal.

## Next step

Launch `sdd-init` (T2), then `sdd-explore` (T3).
