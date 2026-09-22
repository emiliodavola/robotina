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

## Delivery plan (decided at sdd-tasks)

- Strategy: **chained PRs**; chain strategy: **`feature-branch-chain`**.
- Tracker branch: `feat/single-robotina-container` (this branch). Only the tracker merges to `main`.
- Slice branches are cut from the tracker; PR #1 targets the tracker, each child PR targets the
  immediate previous slice branch. Merge bottom-up; retarget each child once its parent lands.
- PR #1 is the **process artifacts** (`openspec/**` + `odd/tasks/single-robotina-container.md`),
  kept separate from the implementation review.

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
- Stale `OPEN ITEM` annotations in the specs still describe Q1/Q2/Q3/Q5/Q7/Q10/Q12 as open;
  `sdd-design` closed them. Needs an alignment task in the apply set.
- Review workload: the SDD artifacts alone are ~3.9k authored lines. Delivery strategy
  decision pending at `sdd-tasks`.

## Verification evidence

_(pending)_

## Next step

Launch `sdd-init` (T2), then `sdd-explore` (T3).
