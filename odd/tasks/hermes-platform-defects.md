# Feature: hermes-platform-defects

## Goal

Triage the runtime defect report the owner pasted (items A1–A10 platform, B11–B12 GitHub
config, C13–C16 working rules already applied), keep **only** what is evidenced against the
running `robotina` stack and fixable in this repository, and fix each confirmed item with a
repro, a fix and a verification recipe.

The owner's instruction was explicit: *"revisa cuáles de estos cambios corresponde, no los des
por buenos sin evidencia"*. So every verdict below carries a measured command, and the items
that do not survive that test are reported as **not applicable** instead of being "fixed" by
editing prose.

Branch: `fix/hermes-platform-defects`, off `main`. Owner: `emiliodavola`.

## Non-goals

- **No merges.** PRs are opened and assigned; merging stays the owner's decision.
- **No model changes.** The mandatory delegated model is a fact to *encode*, never to change.
- Do not reopen C13–C16 (already-applied working rules); they are recorded here and respected.
- Do not patch the vendor Hermes image (`/opt/hermes/**`) or OpenCode. Defects that live
  inside the vendor or in an external service become a report, not a fix.
- No issue beyond this triage list (C16): the owner approved this list only.

## Evidence environment

Measured on 2026-09-24 against the running stack:

- `docker compose ps` → `robotina` (healthy) + `egress-proxy` (healthy), recreated 21 min before.
- `docker version --format '{{.Server.Version}}'` → `29.8.0`.
- Host `gh` 2.101.0, account `emiliodavola`, `viewerPermission: ADMIN`.
- Logs read from inside the container (`/opt/data/logs/*.log`,
  `/opt/data/.local/share/opencode/log/opencode.log`, `/opt/data/cache/scratch/`).

## Triage

| Item | Verdict | Measured evidence | Repo-actionable |
| --- | --- | --- | --- |
| **A1** sessions stall with `info.finish=null` | **Confirmed (mechanism), not fixed** | `opencode.log` carries `permission=external_directory action.action=ask` entries with no human at the prompt; the skill documents the stall only as a manual troubleshooting row ("abort, do not report a result you never got") — there is no detector. | Yes — poll helper + rule |
| **A2** blocking `POST /session/{id}/message` used by default | **Confirmed** | `hermes/skills/opencode-delegation/SKILL.md` still leads its *Recipe* with the blocking endpoint; the async path appears only as a footnote, and `hermes/context/.hermes.md` never mentions it. | Yes — docs + helper |
| **A3** duplicate prompts queued after a cut | **Reported, no log evidence found** | No duplicate-prompt marker in the logs; the defect is plausible (the recipe always creates a fresh session and never checks for an in-flight prompt). Fixed as a defensive rule, not as a proven bug. | Yes — dedupe rule |
| **A4** model substituted without asking (`gpt-5.6-luna`) | **Confirmed** | `hermes/context/.hermes.md` says only "never invent a model"; it does not state the mandatory delegated model. The skill even names `gpt-5.6-luna` as today's default, which is what a delegator lands on by omission. | Yes — context rule |
| **A5** `uv run` re-resolves and times out (300 s) vs `.venv/bin/*` (seconds) | **Confirmed** | `.venv/bin` exists in `/workspace/cv-emilio-davola` and `/workspace/sofer`; `robotina/profile.d/robotina-path.sh` appends `/opt/uv/bin` after the venv, and no rule tells the agent to prefer the project venv. | Yes — context rule |
| **A6** `TMPDIR` points at the pruned scratch, pytest tmpfiles vanish | **Confirmed** | Hermes snapshot exports `TMPDIR="/opt/data/cache/scratch"`; `hermes_constants.py:1052` `SCRATCH_MAX_IDLE_HOURS = 24` + `prune_scratch_dir()`; `doctor_state.py:170` `_PRUNED_CACHE_DIRS = {"scratch","terminal"}`; `export_scratch_tmp_env()` explicitly **never overrides a user-set temp var**, so a compose value wins. | Yes — compose |
| **A7** `.git/hooks/pre-commit` has CRLF + a Windows `INSTALL_PYTHON` | **Confirmed** | `/workspace/llm-conversation-analyzer/.git/hooks/pre-commit` is CRLF (`^M$`) with `INSTALL_PYTHON='C:\Users\elaze\Desktop\llm-conversation-analyzer\.venv\Scripts\python.exe'`. The `sofer` hook is LF and healthy — the defect is per-repo, not global. | Yes — normalizer + policy |
| **A8** `HERMES_WRITE_SAFE_ROOT` blocks subagents under `/workspace/sofer` | **Already fixed — no action** | Live: `HERMES_WRITE_SAFE_ROOT=/opt/data/:/workspace/` (PR #23 / issue #22, merged). The report predates the recreate. | No |
| **A9** "Your request was not processed. Send it again" | **Not applicable — vendor/platform** | No matching line in any `/opt/data/logs/*.log`; the message is user-facing and produced by the vendor Telegram path. Cannot be patched from this repo. | No — vendor report |
| **A10** no visibility of OpenCode's log | **Confirmed, premise partly wrong** | The premise "el server s6 no tiene logger propio" is **false**: `opencode debug paths` → `log /opt/data/.local/share/opencode/log`, and `opencode.log` is 671 KB and live. The real gap is that no runbook names that file or `GET /event`. | Yes — docs |
| **B11** fine-grained PAT had no Administration → `gh repo edit` 403 | **Verified fixed — no action** | `gh repo edit --description "<current>"` → exit 0; `gh api graphql '{viewer{login}}'` → `{"data":{"viewer":{"login":"emiliodavola"}}}`; `gh pr checks 26` no longer 403s (exit 1 is "no checks reported", i.e. CI is disabled by design). | No |
| **B12** Copilot review absent (quota) | **Not applicable — external** | Informational only; explicitly not a gate. | No |
| **C13–C16** single supervised server / `--auto` only on approved tasks / worker file partitioning / 1 issue = 1 PR + no unapproved issues | **Already applied — respected** | No reopening. This triage opens exactly the issues listed below, one PR each, no merges. | No |

## Fix plan (grouped by work unit)

Three report lines can share one artifact, so they share one issue and one PR (reviewable work
unit, C16). The grouping is by artifact, not by report line:

| Issue | Covers | Artifact |
| --- | --- | --- |
| I1 | A1 + A2 + A3 | `robotina/bin/opencode-delegate` (new), `hermes/skills/opencode-delegation/SKILL.md`, `hermes/context/.hermes.md` |
| I2 | A4 + A5 | `hermes/context/.hermes.md` (+ skill cross-reference) |
| I3 | A6 | `compose.yml`, `.env.example`, `README.md`, `README.en.md`, `SECURITY.md` |
| I4 | A7 | `robotina/bin/pre-commit-repair` (new), `hermes/context/.hermes.md`, docs |
| I5 | A10 | `README.md`, `README.en.md`, `SECURITY.md` |

## Tasks

- [ ] T1 — Feature document with the measured triage (this file).
- [ ] T2 — Open the issue set (status:approved, assigned to the owner).
- [ ] T3 — I1: non-blocking delegation helper with stall detection and no double submit.
- [ ] T4 — I2: load the mandatory model rule and the venv-binary rule before delegating.
- [ ] T5 — I3: stable `TMPDIR` outside the pruned scratch.
- [ ] T6 — I4: repair the CRLF/Windows pre-commit hook without `--no-verify`.
- [ ] T7 — I5: document the OpenCode log runbook and `GET /event`.
- [ ] T8 — One PR per issue, each assigned to the owner (no merges).

## Acceptance

Per item, the repro → fix → verification triad, run inside the container:

- A1/A2/A3: simulated stall (a turn left with `finish=null`) aborts and is reported without
  waiting for the human; a second identical submit is a no-op; a long turn is submitted async.
- A4: the mandatory model appears in the context file read before any delegation.
- A5: `.venv/bin/<tool>` is used when present; `uv run` only when resolution is required.
- A6: `TMPDIR` resolves outside `HERMES_HOME/cache/scratch` and survives a `prune_scratch_dir`.
- A7: `git commit` succeeds in the affected repo without `--no-verify`.
- A10: the runbook names the log file and the SSE endpoint, verified by opening both.
