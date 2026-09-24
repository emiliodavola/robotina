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
| **A4** model substituted without asking (`gpt-5.6-luna`) | **Confirmed** | `hermes/context/.hermes.md` says only "never invent a model"; it does not state which model is configured. The skill names `gpt-5.6-luna` as "the default", which is what a delegator lands on by omission. Measured: `.env` sets `ROBOTINA_HERMES_MODEL=muse-spark-1.3-contributor` (a promo) and `config.yaml` has `model.default: "muse-spark-1.3-contributor"`; delegations use `deepseek-v4.1-flash`. The ids change over time, so the rule is "read the configured value", never a hardcoded constant. | Yes — context rule |
| **A5** `uv run` re-resolves and times out (300 s) vs `.venv/bin/*` (seconds) | **Not applicable (owner correction)** | The owner corrected the framing: there is **no** global preference, it depends on each project. `.venv/bin` exists in `/workspace/cv-emilio-davola` and `/workspace/sofer`, but a project may legitimately declare `uv`. Recorded as a one-line context note ("follow the runner the project declares"), not as a platform defect. | No |
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
| I2 | A4 | `hermes/context/.hermes.md`, `hermes/skills/opencode-delegation/SKILL.md`, `compose.yml`, `.env.example` |
| I3 | A6 | `compose.yml`, `.env.example`, `README.md`, `README.en.md`, `SECURITY.md` |
| I4 | A7 | `robotina/bin/pre-commit-repair` (new), `hermes/context/.hermes.md`, docs |
| I5 | A10 | `README.md`, `README.en.md`, `SECURITY.md` |

## Tasks

- [x] T1 — Feature document with the measured triage (this file).
- [x] T2 — Open the issue set (status:approved, assigned to the owner): #27–#31.
- [x] T3 — I1: non-blocking delegation helper with stall detection and no double submit (#27, PR #32).
- [x] T4 — I2: read the configured model before delegating, never substitute one (#28, PR #33).
- [x] T5 — I3: stable `TMPDIR` outside the pruned scratch (#29, PR #34).
- [x] T6 — I4: repair the CRLF/Windows pre-commit hook without `--no-verify` (#30, PR #35).
- [x] T7 — I5: document the OpenCode log runbook and `GET /event` (#31, PR #36).
- [x] T8 — One PR per issue, each assigned to the owner (no merges).

## Acceptance

Per item, the repro → fix → verification triad, run inside the container:

- A1/A2/A3: simulated stall (a turn left with `finish=null`) aborts and is reported without
  waiting for the human; a second identical submit is a no-op; a long turn is submitted async.
- A4: the configured model is read from configuration before any delegation (today Hermes `muse-spark-1.3-contributor`, delegation `deepseek-v4.1-flash`), and no id is hardcoded.
- A5: not applicable — per-project decision; the context says to follow the runner the project declares.

## Status (2026-09-24)

Issues opened, all labeled `status:approved` and assigned to `emiliodavola`:

| Issue | Report item | PR | Branch |
| --- | --- | --- | --- |
| #27 | A1–A3 | #32 | `fix/issue-27-opencode-delegate` |
| #28 | A4 | #33 | `fix/issue-28-model-rule` |
| #29 | A6 | #34 | `fix/issue-29-tmpdir` |
| #30 | A7 | #35 | `fix/issue-30-precommit-repair` |
| #31 | A10 | #36 | `fix/issue-31-opencode-log-runbook` |

Not opened: A8 (already fixed by PR #23 / issue #22), A9 (vendor/platform, no log evidence), B11
(verified working), B12 (external quota), C13–C16 (already-applied rules).

No merges. The agent did not restart or recreate the container. `.env.example` was left to the
owner (the harness blocks `.env*` writes), and must be pasted for `ROBOTINA_OPENCODE_DELEGATE_MODEL`
(PR #33) and `ROBOTINA_TMPDIR` (PR #34).

Merge-order note: PRs #34, #35 and #36 touch neighbouring regions of `README.md` /
`README.en.md` (and #34/#36 also `SECURITY.md`); whichever lands second needs a rebase on `main`.
- A6: `TMPDIR` resolves outside `HERMES_HOME/cache/scratch` and survives a `prune_scratch_dir`.
- A7: `git commit` succeeds in the affected repo without `--no-verify`.
- A10: the runbook names the log file and the SSE endpoint, verified by opening both.
