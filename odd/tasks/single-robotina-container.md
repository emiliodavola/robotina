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
- [x] T3 — SDD explore: map coupling, call sites and what the merge must preserve.- [x] T4 — SDD proposal: PRD for the single `robotina` container.
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
  `OPENCODE_GO_API_KEY`; each process is configured with only its own key (per-process key
  isolation is **not enforceable** at equal uid — see CR6).
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
- 2026-09-22: `sdd-apply` slice 08 (records) — `SECURITY.md` rewritten for the merged reality
  (R1 retired credential invariant with the prompt-injection reach stated; R2 non-enforceable
  per-process isolation at equal uid; R4 single lifecycle; R6 superseded interop task file; R7
  shared workspace with no container boundary; loopback-only `OPENCODE_SERVER_PASSWORD`
  defense-in-depth; engram logs to the container stream; PID-1-must-be-the-entrypoint rule;
  nested-volume layout). `openspec/project.md` updated for the one-container stack; the seven
  stale `OPEN ITEM` spec annotations replaced with `CLOSED BY DESIGN §…` notes (Q1, Q2, Q3, Q5,
  Q7, Q10, Q12); the `odd/tasks/agent-interop-http.md` superseded-by note added.
- **Task 37 outcome (recorded):** `git grep -nE "docker compose confi[g]" -- openspec/config.yaml`
  reported two prose lines naming the static-validation command without a flag on the same line
  (`testing.static_validation.note` and the `apply` rule). Both were reworded to refer to the bare
  form / the static-validation command by description; the re-run reports four hits, every one
  carrying `-q` or `--services` on the same line.
- 2026-09-22: `sdd-apply` slice 11 (measurement evidence + stale-claim corrections) — **tasks 26,
  38, 40, 41 closed**. Task 26 sampled the merged cgroup's `pids.current` at 1 Hz for 900 samples
  with the concurrent worst case running (real OpenCode session exercising the six LSPs, R source
  builds with `Ncpus=6`, `go build -a ./...` + `go vet`, `npm ci` + a parallel `node --test`, plus a
  `basedpyright`/`r-languageserver` fork storm): baseline `52`, min `60`, median `329`, **peak
  `478`**, `pids.max = 1024`. The **only** part not reproduced was a Telegram message burst (the
  long-poll connection is live and counted; originating a burst needs a human or a real message).
  Task 38 applied design §16's pre-committed rule: `478 ≤ 614` → **`pids_limit: 1024` confirmed**,
  `compose.yml` untouched. Task 40 added `SECURITY.md`'s measured evidence (R3 six-bit `0xeb`
  decode, R5 budget + peak, SL2 nesting, gate-failure behaviour) and folded in the 5.50 s/`ExitCode
  0` stop. Task 41 wrote this record's consolidated evidence. Also corrected the stale lifecycle
  claim in `README.md`/`README.en.md` (and their stale `CapBnd=0xcb`), and added the
  MEASURED-CORRECTION note to `explore.md` leaving its findings verbatim. `compose.yml` was **not**
  edited; no commit, push or PR was performed.
- 2026-09-22: `sdd-apply` slice 12 (final verification + rollback safety) — **tasks 42, 43, 44 and
  45 closed; all 45 tasks complete**. Task 42 ran the end-to-end suite on the final tree
  (`docker compose config -q && build && up -d && ps` → exactly `robotina` + `egress-proxy`, both
  healthy) and the credential-aware loopback probe (HTTP **200**, `{"healthy":true,"version":"1.18.32"}`;
  plain probe **401**). Task 43 confirmed `squid/` byte-identical vs the merge base (`ceef812`),
  `NO_PROXY`/`no_proxy` carrying `robotina`/`127.0.0.1`/`egress-proxy`, the mandatory `HOST_DATA_DIR`
  guard refusing to start without it, and no loopback endpoint traffic in the proxy log. Task 44
  confirmed both state volume names unchanged and `scripts/fix-permissions.ps1` deleted (no output);
  the three legacy host folders are **not observable** (they never existed on this host) and are
  recorded as such. Task 45 ran the value-shaped secret audit (no output), the container-log grep (no
  output), the `.env` ignored/untracked check and the CR4 authoring rule (no violations). Also fixed
  A2 (`openspec/project.md` five→six capabilities, `0xeb`) and F1 (task 45's literal grep replaced by
  the value-shaped form, reason recorded). No commit, push or PR was performed.

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
| S5 identity | `feat/single-robotina-container-05-identity` | `4b476a8` | 268 | committed |
| S6 migration & scripts | `feat/single-robotina-container-06-scripts` | `92e1a31` | 194 | committed |
| S7 docs | `feat/single-robotina-container-07-docs` | `fd016b3` | 726 (README pair 679) | committed; `scripts/fix-permissions.ps1` deleted (Q7) |
| S8 records | `feat/single-robotina-container-08-records` | `ddbc0c2` | 968 (SECURITY.md 729) | committed (tasks 34–37, 39) |
| S9 runtime verify | `feat/single-robotina-container-09-measurements` | `175e681` | — | committed: tasks 21, 22, 27 verified; **28 lifecycle proof FAILED** (closed in S10) |
| S10 capability fix | `feat/single-robotina-container-10-capkill` | `7d9c3d6` | — | committed (task 28 closed: six capabilities, corrected lifecycle) |
| S11 measurement evidence | `feat/single-robotina-container-11-evidence` | `2f0da36` | 390 | committed: **tasks 26, 38, 40, 41 closed**; stale lifecycle/`0xcb` claims corrected |
| S12 final verify | `feat/single-robotina-container-12-final` | — (this run) | 373 | **tasks 42, 43, 44, 45 closed** — end-to-end suite, frozen egress + mandatory-input guard, rollback path, secret audit |

Task progress: **45/45** implementation tasks complete (12 through slice 04; +7 in slice 05:
tasks 17–20, 23–25; +4 in slice 06: 13–16; +4 in slice 07: 29–32; +1 in slice 07: 33; +5 in slice
08: 34–37, 39; +3 in slice 09: **21, 22, 27**; +1 in slice 10: **28**; +4 in slice 11: **26, 38, 40,
41**; +4 in slice 12: **42, 43, 44, 45**). **No tasks remain.**

Verified so far without a live stack: `docker compose config -q`, `--services`,
`docker compose build robotina` (exit 0), `docker build --check`, `s6-rc-compile` +
`s6-rc-db check` (exit 0), the backoff sequence, and the cont-init script against real
read-only mounts.

Gated on a live `.env` (needs reissued keys) and `docker compose up`: tasks 18, 22, 27 and the
whole measurement phase — the nested volume-inside-bind proof, the readiness gate, the
measured `CapEff`/`CapBnd`, and `pids.current` under load.

**Status after slice 07 (stack live):** tasks 18, 19, 20, 24 and 25 are measured and complete
(see the slice-05 evidence section); the readiness gate succeeded in ≈4.85 s; capabilities match
design §13. Slice 06 implemented the identity layer (tasks 13–16: skin, `display.skin`, context,
skills), slice 06 scripts (tasks 29–32: migration helper, export-state, `fix-permissions` interim,
`.env.example`) and slice 07 docs (task 33: both READMEs) are complete; Q7 resolved as deletion of
`scripts/fix-permissions.ps1`. Still gated: task 21's 3× recreation loop + gate-failure observation,
task 22 (runtime identity + state-ownership batch — the identity half is implementable now, the SL6
ownership half too; not yet run), tasks 26/38 (peak `pids.current` under the concurrent worst case),
and tasks 27–28.

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

### Final collected evidence (slice 11 — 2026-09-22)

Branch: `feat/single-robotina-container-11-evidence`. Stack live and healthy at capture: two
containers `(healthy)`, ten s6 services, Telegram connected. This is the consolidated evidence
`verify`/`archive` should read; the per-slice sections below keep their own raw output.

**Vendor base digest** — the local `latest` tag still reports slice 02's digest, but the build that
produced the running image resolved a newer one:

```text
$ docker inspect --format '{{index .RepoDigests 0}}' nousresearch/hermes-agent:latest
nousresearch/hermes-agent@sha256:b2e3eeb0c550d262a5d713788ca079e682b9acfc4a0d02ec614bc847bd1087a9
# image actually built (slice 03 build log) resolved:
# nousresearch/hermes-agent@sha256:9403970a9c3c48c557e4afbde8b7c4aae4fd362cce293d550dc4f80f48842408
$ docker inspect --format '{{index .RepoDigests 0}} {{.Id}}' robotina:local
robotina@sha256:b51a742476e1a1dddf95d2393f59b88be5bac8bb92d1703fb2114393f13cabff
```

The tag floats by design (digest pinning is out of scope); the running image is
`robotina:local` @ `sha256:b51a7424…`.

**Service list** — exactly one agent container plus the proxy, PID 1 is the image entrypoint, ten
s6 services:

```text
$ docker compose ps
egress-proxy   Up … (healthy)
robotina       Up … (healthy)
$ docker compose exec robotina tr '\0' ' ' < /proc/1/cmdline
s6-svscan -t0 /run/service          # PID 1 = the supervision tree, not tini/docker-init
$ PATH=/command:$PATH s6-rc -a list
s6rc-oneshot-runner dashboard engram main-hermes opencode opencode-init opencode-ready
fix-attrs legacy-cont-init legacy-services        # 10
```

**Measured versions** (inside the running container): opencode `1.18.32`, gh `2.97.0`, jq `1.7`,
ripgrep `14.1.1`, go `1.24.4`, taplo `0.10.0`, marksman `2026-02-08`, codegraph `1.5.0`, engram
`1.20.0`, gentle-ai `3.1.0`, uv `0.11.6`, node `v26.5.1`, python3 `3.13.5`, R `4.5.0`.

**Nesting (SL2/SL3):** two `ext4` mounts, neither `9p` nor `virtiofs`; the marker written inside
the volume never appears in the host bind and survives `down`/`up`; volume count = 2. Raw output in
§ Slice 05 and in `SECURITY.md` → «Evidencia medida».

**Capabilities (R3, post-`CAP_KILL`):** uid-10000 `opencode serve` (pid 416) keeps
`CapInh/Prm/Eff/Amb = 0x0`, `CapBnd = 0xeb`, `NoNewPrivs: 1`; PID 1 runs with `CapEff/CapBnd =
0xeb`. `0xeb` = 235 = CHOWN+DAC_OVERRIDE+FOWNER+KILL+SETGID+SETUID. Decode in `SECURITY.md` R3.

**`pids` (task 26/38):** baseline `52`/`1024`; over **900 samples at 1 Hz** with the concurrent
worst case running, `min=60`, `median=329`, **`peak=478`**; `pids.max = 1024` (finite). Rule:
`478 ≤ 614` → **1024 confirmed**, `compose.yml` untouched. Full workload list, and the one part that
was **not** reproduced (a Telegram message burst), in `SECURITY.md` → «Evidencia medida».

**Restart observations:** `docker compose stop robotina` = **5.50 s**, `ExitCode=0`, no SIGKILL;
a `pkill` of `opencode serve` recovered in **≈4.4–5 s** with `reinicio #1 en 1s`; killing the gateway
restarted it **in place** while `RestartCount=0` and `StartedAt=2026-09-22T19:26:33.780458019Z` stayed
unchanged, i.e. the container did **not** cycle (corrected contract, slice 10).

**§19.4 auth result:** plain probe → **HTTP 401**; credential-aware probe → **200**
`{"healthy":true,"version":"1.18.32"}`; `ss -ltn` shows only `127.0.0.1:4096`.

**§19.5 interpretation results:** host probe fails with exit 7 and `Get-NetTCPConnection
-LocalPort 4096` = 0 listeners (no port, no false failure); `curl` without `-f` returns exit 0 on
401, so auth is asserted on the **HTTP code**; `mountinfo` sources are VM-side paths and the skin
mount is repo-sourced, not `HOST_DATA_DIR`-sourced; the SL3 engram read command is the one
`scripts/export-state.sh` already uses; the in-container `robotina:4096` probe stays proxy-confounded
and the unconfounded proof is the peer-container refusal. Detail in `SECURITY.md`.

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

## Slice 09 — runtime verification (tasks 21, 22, 27, 28)

Branch: `feat/single-robotina-container-09-measurements`. The stack was already up with live keys
(two healthy containers, ten s6 services, Telegram connected). This slice ran the runtime proofs
for tasks 21, 22, 27 and 28; **tasks 21, 22 and 27 are complete; task 28 is not** (its amended
single-lifecycle proof failed — see below). The stack was left healthy and running:
`egress-proxy` + `robotina` both `(healthy)`, Telegram `Connected to Telegram (polling mode)`,
endpoint `{"healthy":true,"version":"1.18.32"}`, both state volumes present.

Every `pgrep`/`pkill` recipe below uses a character-class pattern and asserts a non-empty match;
an empty match was treated as a FAILURE. No secret value was printed.

### Task 21 — readiness gate across repeated recreations + gate-failure behaviour

Three `docker compose down && docker compose up -d` cycles, each followed by the bounded
credential-aware loopback probe (60 × 2 s):

| Cycle | `StartedAt` | gate log line | cold start |
| --- | --- | --- | --- |
| 1 | `2026-09-22T19:05:59.228674207Z` | `19:06:03.569450221Z opencode listo (intentos=1)` | **≈4.34 s** |
| 2 | `2026-09-22T19:06:26.496136427Z` | `19:06:31.056849886Z opencode listo (intentos=1)` | **≈4.56 s** |
| 3 | `2026-09-22T19:06:53.652872543Z` | `19:06:58.092762695Z opencode listo (intentos=1)` | **≈4.44 s** |

- `probe_exit=0` on all three cycles; the gate was satisfied on its **first** attempt each time
  (`intentos=1`), i.e. the endpoint answered within ≈4.3–4.6 s and always well under the 120 s bound.
- `docker compose logs --since 10m robotina 2>&1 | grep -Ei '127\.0\.0\.1:4096.*(refused|econnrefused)'`
  → **no output** (exit 1): no `ECONNREFUSED` for the delegate ever reached the log. The early
  `curl: (7)` lines are the *verification probe's own* stderr, not container-log lines.

**What s6-overlay does when the gate fails (observed, not inferred).** The gate was forced to fail
in an **isolated throwaway container** (`robotina:local`, `--network none`, fresh `/opt/data`, a
valid opencode key, with only the `opencode-ready/up` file replaced by a one-line `/bin/false`
executable). The failure signal is the same oneshot non-zero exit the real gate would produce
after its bound; forcing it immediately kept the observation inside the session.

```text
s6-rc: info: service opencode-ready: starting
s6-rc: warning: unable to start service opencode-ready: command exited 1
robotina: opencode serve -> 127.0.0.1:4096 (uid 10000)
GATE_TEST_CMD_RAN
opencode server listening on http://127.0.0.1:4096
# docker inspect -> Status=running Running=true ExitCode=0
# S6_BEHAVIOUR_IF_STAGE2_FAILS is unset (0 matches in /proc/1/environ)
```

- **Observed result: s6-overlay continues to the CMD** with a per-service `s6-rc: warning: unable
  to start service opencode-ready: command exited 1`. It does **not** abort the container.
- Confirmed against the real `rc.init` the container runs (`/run/s6/basedir/scripts/rc.init`):
  `set +e; s6-rc -u -- change "$top"; r=$?; set -e; if test "$r" -gt 0 && test "$b" -gt 0; then …
  if test "$b" -ge 2; then haltwith; fi` — with `S6_BEHAVIOUR_IF_STAGE2_FAILS` unset the default
  `b=0`, so neither the warning branch nor the halt branch runs and the CMD is still executed.
- This is design §9.1's D-6 scenario (a degraded start). It is recorded here for `SECURITY.md`
  (task 40) and the README. The throwaway container was removed; the live stack was untouched.

### Task 22 — identity layers + state ownership (ID1, ID2, ID3, ID5, SL6)

Live container:

| Probe | Command | Observed |
| --- | --- | --- |
| Skin present | `ls -l /opt/data/skins/robotina.yaml` | `-rwxrwxrwx 1 root root 1059 … /opt/data/skins/robotina.yaml` |
| Skin read-only | `touch /opt/data/skins/robotina.yaml` | `touch: cannot touch '…/robotina.yaml': Read-only file system` (exit 1) |
| Mount source + `ro` | `grep " /opt/data/skins" /proc/self/mountinfo` | source `/Users/elaze/Desktop/robotina/hermes/skins` (repo path, not under `HOST_DATA_DIR`), options `ro` |
| `display.skin` selected | `grep -niE "skin" /opt/data/config.yaml` | `1965:  skin: robotina` (plus the vendor comment block) |
| Context identity | `grep -c "robotina" /workspace/.hermes.md` | `3` |
| egress identity (ID5) | `printenv NO_PROXY` | `localhost,127.0.0.1,::1,robotina,egress-proxy` (contains `robotina`; no `hermes`/`opencode`) |
| SL6 write as uid 10000 | `s6-setuidgid hermes sh -c "touch /opt/data/.write-test && rm …"` | `writable-as-10000` |
| SL6 ownership | `stat -c "%u:%g" /opt/data` | `10000:10000` |

Fresh-state run (ID2/SL6): `docker compose -p robotina-fresh config -q` → exit 0. The **literal**
`docker compose -p robotina-fresh up -d robotina` **cannot run on this host**: the service declares
`container_name: robotina` (required by AC2), so the fresh project collides with the live
container — `Conflict. The container name "/robotina" is already in use`. Recorded as a deviation
(the spec's "isolated project name" note assumed the container name followed the project). The
observable was proven instead with the same compose file plus a small override that renames the
container (`robotina-fresh`), points `HOST_DATA_DIR` at a fresh temp tree and binds the two nested
volume paths to fresh temp dirs, so the live stack and its volumes were never touched:

- `docker inspect` of the fresh container shows `/opt/data` sourced from the fresh temp `hermes`
  dir and the two nested paths from fresh temp binds (not the named volumes).
- Startup log: `cont-init: info: running /etc/cont-init.d/20-robotina-identity` →
  `✓ Set display.skin = robotina in /opt/data/config.yaml` → `exited 0`; `grep -niE skin
  /opt/data/config.yaml` → `1965:  skin: robotina` (non-interactive selection on a fresh tree).
- `s6-setuidgid hermes … touch/rm` → `writable-as-10000`; `stat -c "%u:%g" /opt/data` → `10000:10000`.

The fresh container and temp dirs were removed; `docker compose ps` confirmed the live stack still
healthy.

### Task 27 — `opencode-init` semantics (AC5, SL4)

- **Idempotency (double-run byte identity):** `sha256sum /opt/data/.config/opencode/opencode.json`
  → `55e23123efb392a90b5df6f82934ecf75b1391c5818630edb9ea97d20e3c8149` before `docker compose
  restart robotina` and the **identical** hash after (`IDEMPOTENT=yes`). The restart log shows the
  oneshot running again (`opencode-init: starting` → `successfully started`) with no config change.
- **Invalid-JSON quarantine:** seeded `{ this is intentionally invalid json` into the file (as uid
  10000), restarted, and observed
  `robotina: /opt/data/.config/opencode/opencode.json no era JSON valido; cuarentenado en
  /opt/data/.config/opencode/opencode.json.invalid-20260922T190450Z`. The quarantine file existed
  (`-rw-r--r-- 1 hermes hermes 36 … opencode.json.invalid-20260922T190450Z`, the user's bytes), the
  oneshot **succeeded**, the container came up `(healthy)`, `jq -e .` on the resulting file →
  `valid-json`, and the endpoint answered `{"healthy":true,"version":"1.18.32"}`. The test
  artifacts (`.opencode.json.verifybak` + the quarantine file) were removed afterwards and the
  config hash confirmed back at `55e23123…`.
- **engram/opencode output observability:** `docker compose logs --tail 200 robotina` → **200
  lines** (non-empty) including `robotina: engram serve (data dir /opt/data/.engram)` and
  `robotina: opencode serve -> 127.0.0.1:4096 (uid 10000)`.

### Task 28 — s6 recovery (verified) and the single-lifecycle proof (FAILED as written; resolved in slice 10)

**s6 recovery — verified.** `pgrep -f "[o]pencode serve"` (non-empty, pid 227) → `pkill -f
"[o]pencode serve"` → the bounded credential-aware probe recovered **without manual
intervention** (`recovery_probe_exit=0`, **5 s**), the service restarted as a new pid (`227` →
`533`), and the `finish` log shows the documented capped backoff:
`robotina: opencode salio (exit=256 sig=15); reinicio #1 en 1s`. The container itself did **not**
restart (`RestartCount=0`), which is the intended s6 behaviour.

**The amended single-lifecycle proof as written FAILED. Do not mark task 28 complete.**

- The literal recipe `docker compose exec robotina sh -c 'pkill -f "[h]ermes gateway"'` cannot
  even signal the process as a root exec: the container runs `cap_drop: [ALL]` with only the five
  capability set (`CapEff=0x00000000000000cb`), so **`CAP_KILL` is dropped** and a uid-0 process
  cannot signal a uid-10000 process — `pkill: killing pid 227 failed: Operation not permitted`. The
  kill was therefore performed as the owning user (`docker compose exec -u hermes …`), which is the
  faithful realization of "kill the process inside the container".
- With the kill performed, the counter assertion **does not hold**: the gateway pid moved
  `612 → 919` (s6 restarted it) while `docker inspect --format '{{.RestartCount}}
  {{.State.StartedAt}}' robotina` stayed `0 2026-09-22T19:06:53.652872543Z`. **Root cause: `hermes
  gateway` is itself an s6-supervised dynamic service** — `/run/service/gateway-default/run` runs
  `hermes gateway run --replace`, supervised by `s6-supervise gateway-default`; the container's main
  program (the `rc.init` child) is a separate `sleep infinity` (pid 306, uid 10000). Killing the
  gateway can never cycle the container.
- Killing the **actual** main program (`rc.init` child `sleep infinity`, pid 306, as uid 10000) does
  start the container's shutdown — the log shows `Terminated` and the `s6-rc: info: service …
  stopping` sequence — but the shutdown **WEDGES**: `s6-rc -v2 -bda change` (pid 1054) waited while
  `opencode` (533), `engram` (222) and `gateway-default` (919) stayed alive, and the container did
  **not** exit. `RestartCount` stayed `0` and `StartedAt` unchanged for the full 180 s observation
  window. **Root cause: the same dropped `CAP_KILL`.** The s6 supervisors run as root without
  `CAP_KILL`, so they cannot signal their uid-10000 children on a bring-down; the tree never comes
  down, PID 1 never exits, and `restart: unless-stopped` (which reacts to PID-1 exit, not to health)
  never fires.
- **Conclusion:** AC8's claim "container exit follows Hermes' main program … the container goes down
  and comes back as one unit" is **not satisfied** with the current supervision topology and
  five-capability set. This is a real finding for `sdd-verify`: either the main program must be the
  supervised unit (vendor change), or `CAP_KILL` must be added (a hardening-set decision), or AC8's
  proof must be re-worded to what the architecture actually guarantees (s6 restarts a service in
  place; the container exits only on an operator/daemon stop). No fix was attempted here — it is a
  design/decision change outside this slice's edit surfaces.
- **Recovery after the observation:** the wedged container was restored cleanly with
  `docker compose up -d --force-recreate robotina`; the stack is healthy and running (see header).

### Stack state at the end of this slice

```text
docker compose ps
egress-proxy   Up … (healthy)   3128/tcp
robotina       Up … (healthy)
docker volume ls | grep -cE '^robotina_(engram|opencode)_db$'   # 2
opencode health  -> {"healthy":true,"version":"1.18.32"}
Telegram         -> [Telegram] Connected to Telegram (polling mode)
```

## Slice 10 — `CAP_KILL` + corrected lifecycle contract (task 28 closed)

Branch: `feat/single-robotina-container-10-capkill`. This slice fixes the defect slice 09 exposed
and amends every artifact that stated something the measurements proved false. The user decided
both halves: (1) add `CAP_KILL` (five → six capabilities, bounding mask `0xeb`); (2) the lifecycle
contract is "s6 supervises and restarts the gateway", not "the container dies with Hermes".

### Changes

- `compose.yml`: `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, KILL]`; the Spanish
  comment records why (s6 must signal its uid-10000 children; the app uid keeps `CapEff=0x0`).
- Spec `agent-container` AC4 (six-capability requirement, mask `0xeb`) and AC8 (lifecycle scenario
  rewritten to the measured contract), both with an explicit AMENDMENT note.
- `design.md`: §6 single-lifecycle statement corrected, §13 Q4 row/table/§14 mask updated,
  §15/§17 compose rows updated, and a new **§13.3 AMENDMENT at apply** recording both decisions;
  §19.1 marked RESOLVED (its proposed amendment was itself wrong).
- `proposal.md`: R4 corrected (and the A4/R3 rows and the §3.1/§4.3/§4.5/phase-result claims that
  repeated the same falsehood).
- `SECURITY.md` (Spanish): R4 corrected, capability entry updated to six with the measured
  `CapEff=0x0`, and a new measured **«Apagado y ciclo de vida»** section.
- `tasks.md`: task 28's proof rewritten to the corrected contract; defect + resolution recorded;
  task 28 checked off after the observations below.

### Verification (observed on the live stack, 2026-09-22)

```text
# recreate with the new capability set
docker compose config -q                                          # exit 0
docker compose up -d --force-recreate robotina                     # Recreated / Started

# masks (task 25/AC4)
docker compose exec robotina sh -c 'grep -E "Cap(Bnd|Eff)" /proc/1/status'
  # PID 1: CapEff=00000000000000eb  CapBnd=00000000000000eb  Uid=0  NoNewPrivs=1
docker compose exec robotina sh -c 'pgrep -f "[o]pencode serve" ...'
  # pid=213 uid=10000  CapEff=0x0  CapPrm=0x0  CapBnd=0xeb  CapAmb=0x0  NoNewPrivs=1
# 0xeb = 235 = CHOWN(1)+DAC_OVERRIDE(2)+FOWNER(8)+KILL(32)+SETGID(64)+SETUID(128)

# graceful shutdown (AC8 amended, F2 closed)
start=$(date +%s%N); docker compose stop robotina; end=$(date +%s%N)
  # Stopping / Stopped; stop_duration_ms=5504 -> 5.50 s
  # ExitCode=0  OOMKilled=false  FinishedAt=2026-09-22T19:25:47.360681404Z
  # log: opencode-ready -> opencode -> main-hermes -> dashboard -> engram -> opencode-init
  #      -> legacy-cont-init -> fix-attrs, all "successfully stopped"; gateway got SIGTERM
  # (before CAP_KILL the same stop wedged and Docker SIGKILLed at the 20 s grace period)

# task-28 recovery proof (AC5)
docker compose exec robotina sh -c 'pgrep -f "[o]pencode serve" | head -1'   # 211
docker compose exec robotina sh -c 'pkill -f "[o]pencode serve"'            # exit 0 (root now has CAP_KILL)
<bounded credential-aware probe 30x2s>                                       # exit 0 in 4.37 s, no manual step
docker compose exec robotina sh -c 'pgrep -f "[o]pencode serve" | head -1'   # 416
logs: "robotina: opencode salio (exit=256 sig=15); reinicio #1 en 1s"

# corrected lifecycle contract (AC8 amended)
before: gateway pid 188 | RestartCount=0 StartedAt=2026-09-22T19:26:33.780458019Z
docker compose exec -u hermes robotina sh -c 'pkill -f "[h]ermes gateway"'   # exit 0
after 20 s: gateway pid 506 | RestartCount=0 StartedAt=2026-09-22T19:26:33.780458019Z
  # GATEWAY_RESTARTED_IN_PLACE=yes  CONTAINER_NOT_CYCLED=yes
  # gateway log: "gateway is now running under s6 supervision (auto-restart on crash ...)"

# final stack state
docker compose ps            # egress-proxy (healthy), robotina Up (healthy)
docker compose exec robotina /command/s6-rc -a list | wc -l                  # 10
curl credential-aware /global/health                                         # {"healthy":true,"version":"1.18.32"}
logs: "[Telegram] Connected to Telegram (polling mode)"
```

### Findings for the parent

- **F1 (resolved).** The slice-09 finding "AC8's container-cycle proof fails" is closed by the
  amendment: the proof asserted a contract that never existed.
- **F2 (resolved).** The non-graceful in-container shutdown is fixed by `CAP_KILL` (5.50 s,
  exit 0).
- **F3 (open, out of scope).** `README.md` line ~345 and `README.en.md` line ~358 still claim
  "if the main program goes down, the container goes with it". They are **not** in this slice's
  allowed edit surfaces, so they were not touched and must be corrected before `verify`/`archive`.
- **F4 (open, out of scope).** `explore.md` (lines ~101, ~257–263, ~574, ~641) records the same
  pre-measurement assumption. It is a frozen phase artifact; a correction note is a parent
  decision, not an apply edit.
- Task 26 (peak `pids.current`), 38, 40, 41 and 42–45 were **not** started, per the slice scope.

## Slice 12 — final verification and rollback safety (tasks 42–45)

Branch: `feat/single-robotina-container-12-final` (cut from slice 11's tip `2f0da36` under
`feature-branch-chain`, tracker `feat/single-robotina-container`). This slice is **verification
only** — no production code changed. It closes the last four tasks and makes two record alignments
(A2 in `openspec/project.md`, F1 in `tasks.md`).

### Task 42 — end-to-end verification suite on the final tree

```text
$ docker compose config -q                                             # exit 0
$ docker compose build                                                 # exit 0, "Image robotina:local Built" (log /tmp/robotina-s12-build.log)
$ docker compose up -d                                                 # exit 0; robotina Recreated + Started
$ docker compose ps
NAME           IMAGE                 COMMAND                  SERVICE        CREATED          STATUS
egress-proxy   ubuntu/squid:latest   "entrypoint.sh -f /e…"   egress-proxy   57 minutes ago   Up 57 minutes (healthy)
robotina       robotina:local        "/opt/hermes/docker/…"   robotina       17 seconds ago   Up (health: starting)
# after ~4 s: robotina Up (healthy)
$ docker compose exec -T robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/global/health'
{"healthy":true,"version":"1.18.32"}                                    # exit 0
# credential-aware status code
$ ... curl -s -o /dev/null -w "%{http_code}\n" "$@" .../global/health   # 200
# plain probe (no -u) — assert the HTTP CODE, not curl's exit (curl without -f exits 0 on a 401)
$ docker compose exec -T robotina sh -c 'curl -s -o /dev/null -w "%{http_code}\n" -m 5 http://127.0.0.1:4096/global/health'
401
$ docker compose exec -T robotina sh -c 'ss -ltn | grep 4096'          # LISTEN 127.0.0.1:4096 only
$ docker compose exec -T robotina sh -c 'tr "\0" " " < /proc/1/cmdline'
/package/admin/s6/command/s6-svscan -d4 -- /run/service               # PID 1 = supervision tree
$ docker compose exec -T robotina sh -c 'grep -E "^(Uid|Gid)" /proc/1/status'   # Uid 0 / Gid 0
$ MSYS_NO_PATHCONV=1 docker compose exec -T robotina /command/s6-rc -a list | wc -l   # 10
logs: "robotina: opencode listo (intentos=1)"; "[Telegram] Connected to Telegram (polling mode)"
```

### Task 43 — frozen egress boundary and mandatory-input guard

```text
$ git merge-base HEAD main                                             # ceef8127fb3c9d5a0f40c27b72ddc1209fa96adc
$ git diff --exit-code $(git merge-base HEAD main)...HEAD -- squid/    # exit 0 (byte-identical)
$ git status --porcelain -- squid/                                     # no output
$ env -u HOST_DATA_DIR docker compose --env-file /dev/null config -q   # exit 1
#   error while interpolating services.robotina.volumes.[].source: required variable
#   HOST_DATA_DIR is missing a value: definir HOST_DATA_DIR en .env, por ej. C:/robotina-data
$ docker compose exec -T robotina sh -c 'printenv NO_PROXY; printenv no_proxy'
localhost,127.0.0.1,::1,robotina,egress-proxy                          # both variables, contains
localhost,127.0.0.1,::1,robotina,egress-proxy                          # robotina, 127.0.0.1, egress-proxy
$ docker compose logs egress-proxy 2>&1 | grep -n "127.0.0.1:4096"     # no output (exit 1)
```

### Task 44 — rollback path intact

```text
$ docker volume ls --format '{{.Name}}' | grep -cE '^robotina_(engram|opencode)_db$'
2                                                                      # both state volumes unchanged
$ git ls-files scripts/fix-permissions.ps1                             # no output (deleted per Q7)
```

The three legacy host folders (`opencode/`, `git/`, `go/` under `${HOST_DATA_DIR}`) **cannot be
observed on this host — they never existed here** (design §7.2: the folders were never created on
the authoring host, which is why the copy-forward migration is a no-op). `HOST_DATA_DIR` contains
only `backups/`, `hermes/` and `workspace/`; `opencode`, `git` and `go` are all **ABSENT**:

```text
$ HOST_DATA_DIR=$(grep -m1 '^HOST_DATA_DIR=' .env | cut -d= -f2- | tr -d "\r"); ls "$HOST_DATA_DIR"
backups  hermes  workspace
$ for d in opencode git go; do [ -e "$HOST_DATA_DIR/$d" ] && echo "$d: EXISTS" || echo "$d: ABSENT"; done
opencode: ABSENT
git: ABSENT
go: ABSENT
```

The task's literal `ls -ld …/opencode …/git …/go` (all three exist) therefore cannot pass here and
is recorded as **not observable**, not fabricated. The rollback story stays intact regardless: both
state volume names are unchanged, git history retains `scripts/fix-permissions.ps1`, and the new
`robotina/` tree plus the removal of `opencode/` are a single revertible unit. **No destructive
action was taken in this slice** (the `up -d` only recreated the container from the rebuilt image).

### Task 45 — final secret-leak audit (value-shaped, per finding F1)

```text
# value-shaped: an assignment whose value looks like a real secret (16+ chars, no placeholder/comment/$-ref)
$ git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN|OPENCODE_SERVER_PASSWORD|HERMES_OPENCODE_GO_API_KEY)=[A-Za-z0-9_./+=-]{16,}' -- ':!*.example'
# no output (exit 1)
$ docker compose logs robotina 2>&1 | grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN|OPENCODE_SERVER_PASSWORD)='
# no output (exit 1)
$ git check-ignore -v .env                                             # .gitignore:6:.env	.env
$ git ls-files .env                                                    # no output
# CR4 authoring rule: every static-validation mention carries -q/--services/--format on the same line
$ git grep -nE "docker compose confi[g]" -- README.md README.en.md SECURITY.md scripts/ openspec/changes/single-robotina-container/design.md openspec/changes/single-robotina-container/tasks.md | grep -vE "config [-]{1,2}(q|services|format)"
# no output (exit 1) — 5 hits, all flagged
```

The literal form `(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+` matches **34 benign
lines** in the untouched tree (empty documentation placeholders, `$VAR`/`${VAR}` shell references,
and `grep "^KEY=" .env` patterns) and is unsatisfiable; the value-shaped form above replaces it in
task 45's text, with the reason recorded there. It still fails if a real secret value lands in a
tracked file.

### Final stack state (after tasks 42–45)

```text
$ docker compose ps
egress-proxy   Up … (healthy)
robotina       Up … (healthy)
$ docker compose exec -T robotina sh -c 'for p in $(pgrep -f "[o]pencode serve"); do …'
pid=211 uid=10000  CapInh/Prm/Eff/Amb=0x0  CapBnd=0xeb  NoNewPrivs=1
logs: "[Telegram] Connected to Telegram (polling mode)"
```

### Findings for the parent

- **A2 (resolved).** `openspec/project.md` said "five capabilities" in the services table (line 29)
  and the coupling map (line 82). Both now read **six capabilities, bounding mask `0xeb`**. No
  unlabelled five-capability wording remains in a non-history artifact; the surviving `0xcb`/five-bit
  mentions are all inside labelled AMENDMENT/history notes.
- **F1 (resolved).** Task 45's literal secret grep is replaced by the value-shaped form and the
  reason is recorded in `tasks.md`.
- **N1 (observation, out of scope).** `odd/tasks/compose-egress-hardening.md:100` still says
  "Hermes needs five capabilities" — that is a **different, historical** ODD feature record for the
  retired two-container layout, not an artifact of this change; left untouched.
- **N2 (observation).** `openspec/changes/single-robotina-container/specs/agent-container/spec.md`
  line ~116 names the original five-capability `0xcb` set, but only inside a labelled
  `AMENDMENT (apply, task 28)` note — honest history, not a contradiction; left untouched.

## Delivery (PRs opened)

Chained PRs, `feature-branch-chain`, tracker `feat/single-robotina-container`. Each child PR's
base is the previous slice, so every diff shows exactly one work unit.

| PR | Base | Head | Diff |
| --- | --- | --- | --- |
| [#3](https://github.com/emiliodavola/robotina/pull/3) | tracker | `…-01-artifacts` | +5005 |
| [#4](https://github.com/emiliodavola/robotina/pull/4) | `…-01-artifacts` | `…-02-compose` | +488 −158 |
| [#5](https://github.com/emiliodavola/robotina/pull/5) | `…-02-compose` | `…-03-image` | +674 −245 |
| [#6](https://github.com/emiliodavola/robotina/pull/6) | `…-03-image` | `…-04-supervision` | +1079 −40 |
| [#7](https://github.com/emiliodavola/robotina/pull/7) | `…-04-supervision` | `…-05-identity` | +403 −92 |
| [#8](https://github.com/emiliodavola/robotina/pull/8) | `…-05-identity` | `…-06-scripts` | +368 −22 |
| [#9](https://github.com/emiliodavola/robotina/pull/9) | `…-06-scripts` | `…-07-docs` | +669 −272 |
| [#10](https://github.com/emiliodavola/robotina/pull/10) | `…-07-docs` | `…-08-records` | +762 −429 |
| [#11](https://github.com/emiliodavola/robotina/pull/11) | `…-08-records` | `…-09-measurements` | +360 −11 |
| [#12](https://github.com/emiliodavola/robotina/pull/12) | `…-09-measurements` | `…-10-capkill` | +518 −80 |
| [#13](https://github.com/emiliodavola/robotina/pull/13) | `…-10-capkill` | `…-11-evidence` | +580 −38 |
| [#14](https://github.com/emiliodavola/robotina/pull/14) | `…-11-evidence` | `…-12-final` | +341 −32 |
| [#15](https://github.com/emiliodavola/robotina/pull/15) | `…-12-final` | `…-13-archive` | +1724 |

Merge bottom-up; retarget each child once its parent lands. The tracker PR to `main` can be
opened only after #3 merges into the tracker, because the tracker branch currently has no diff
against `main`.

**Honest note on PR size:** each PR is one work unit with a clean diff, but several exceed the
~650-line per-slice acceptance because the process record (`apply-progress.md`, 150–270 lines
per slice) travels with its slice. Implementation-only diffs are smaller.

## Next step

**All 45 implementation tasks are complete.** The final tree passed the end-to-end suite
(`docker compose config -q && build && up -d && ps` → exactly `robotina` + `egress-proxy`, both
healthy), the credential-aware loopback probe (HTTP **200**; plain probe **401**), the frozen-egress
and mandatory-input checks (squid byte-identical vs the merge base, `NO_PROXY`/`no_proxy` carry
`robotina`/`127.0.0.1`/`egress-proxy`, missing `HOST_DATA_DIR` refuses to start, no loopback endpoint
traffic in the proxy log), the rollback-path checks (both volume names, `fix-permissions.ps1` deleted,
no destructive action) and the final value-shaped secret audit (no output).

The three legacy host folders could not be observed here (they never existed on this host) and are
recorded as **not observable**. One workload part (a Telegram message burst) remains unreproduced in
the task-26 peak. Both are for `verify`/`archive` to carry, not blockers.

Recommended next phase: **`sdd-archive`** (with `sdd-verify` explicitly optional). Delivery (T10:
branch pushed, PR opened) stays a separate user decision; no commit/push/PR was performed by apply.
