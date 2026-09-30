# Feature: opencode-delegate-budget-resume

## Goal

Close #79: when `opencode-delegate` aborts a turn on the global budget (exit `4`), it MUST tell the
caller which session it was, how to resume it, and a bounded snapshot of what the turn had already
done; and it MUST warn once when the elapsed time reaches 80% of the budget. Today the helper prints
one line and aborts, so a productive turn's state (a branch already pushed, files already edited)
has to be rediscovered by hand and nothing names `--session`.

Branch: `fix/issue-79-delegate-budget-resume`, off `main`. Owner: `emiliodavola`. Closes #79.

## Non-goals

- **No change to the exit-code contract (OD10) or the liveness contract (OD6/OD7/OD8/OD9).** Exit
  `4` keeps meaning "the helper aborted on the global budget"; `2`, `3` and `5` are untouched.
- **No new knob.** The 80% advisory is always on and fires once. `--timeout` /
  `ROBOTINA_OPENCODE_DELEGATE_TIMEOUT` stay the only budget controls (OD11).
- **No resume automation.** The helper prints the resume command; it never re-sends the task (the
  A3 dedupe stays).
- **No task-aware budget** and **no image rebuild / container recreate in this change.**

## Diagnosis (measured, read-only against the live stack, 2026-09-29)

1. The exit-4 block of `robotina/bin/opencode-delegate` prints a single line
   (`timeout global de ${TIMEOUT}s ... turno abortado`) and aborts. It names neither `--session`
   nor what the turn produced, which is exactly the #79 incident: a 12-skill delegation was aborted
   after pushing its branch, and the caller had to rediscover the pushed state by hand.
2. `GET /session/{sessionID}/diff` returns `SnapshotFileDiff[]`
   (`{file, patch, additions, deletions, status}`); `GET /session/{sessionID}/todo` returns
   `Todo[]` (`{content, status, priority}`). Measured against the live server and its OpenAPI
   (`GET /doc`); both are scoped to the session and cheap.
3. The last assistant message is already parsed into `$assistant` at the timeout check, so the
   "last useful text" needs no extra request.

## Shape

1. On exit `4`, print to **stderr** a bounded progress snapshot (diff file count, per-file status
   with `+/-` lines, todo counts, a truncated last assistant text) and a
   `para retomar: opencode-delegate --session SID ...` hint naming the effective agent, model and
   timeout.
2. Emit a **one-shot** advisory on stderr when `elapsed >= 80%` of the budget, naming elapsed and
   remaining seconds plus the session.
3. **Best-effort end to end:** an unreadable/unexpected endpoint leaves the exit code, the abort and
   the existing message untouched. stdout stays empty on exit `4`.
4. Spec: `opencode-delegation` gains **OD12** (a budget exhaustion names the session and a retry
   path), plus the "#79 added the sixth lesson" note in the purpose block.
5. Docs: the delegation skill's troubleshooting row and `hermes/context/.hermes.md`.

## Tasks

- [x] T1 — Branch and this tracker.
- [x] T2 — Helper: resume hint + snapshot + one-shot 80% advisory; header and `usage()` updated.
- [x] T3 — Spec: OD12 + the #79 purpose note.
- [x] T4 — Docs: `hermes/skills/opencode-delegation/SKILL.md` and `hermes/context/.hermes.md`.
- [x] T5 — Verification: `sh -n`, `--help`, the OD12 proofs (exit `4` carries the hint; the advisory
      fires exactly once; stdout clean), `docker compose config -q`; independent read-only verifier
      over the diff and the spec assertions.
- [ ] T6 — Commit per work unit, push, PR against `main` assigned to the owner.

## Verification (independent, read-only)

`gentle-ai-verify` over `main..HEAD` (2026-09-29): 10/10 checks PASS and no Blocker/High finding. The
four low findings it raised were fixed in this branch:

- **F1** — the resume hint printed no task operand (verbatim it hit `usage; exit 1`, and the identical
  prompt was deduped). Fixed: the template now carries a `"<seguimiento>"` operand and a line naming
  the A3 dedupe; the docs say "re-issue a follow-up task".
- **F2** — the 80% advisory is time-gated, not exit-4-gated, so a turn that crosses 80% and later
  closes keeps the advisory. Fixed: OD12, the skill row and `.hermes.md` now say so, and the control
  scenario is scoped to "closes before 80%".
- **F3** — the scenario-3 proof used a literal path and leaked it. Fixed: `mktemp -d` plus cleanup
  preserving the exit code.
- **F4** — the report call was unguarded under `set -e`. Fixed: `|| true`.

**F5 (not a defect):** the `ultimo texto util` line is code-verified (`.[0:300]`) but was never
observed in the exit-4 runs, because none of them had a text part in the last assistant message.

Observed proofs after the fixes (stale-image recipe, live server, no rebuild): exit `4` with stdout 0
bytes, the `--session` template + `"<seguimiento>"` + dedupe note, `presupuesto al 80%` counted exactly
once, the hermetic dirty-repo proof printing `git (` and ` M f.txt` and leaving nothing behind, and the
healthy control exiting `0` with stdout `OK` and zero advisory/snapshot lines.

## Pending after this PR

- A rebuild plus `--force-recreate` is what puts the new helper in `/opt/robotina/bin`; until the
  maintenance window, the change is exercised through the stale-image recipe of the spec's
  verification model.

## Route declaration

- Classification: **substantial and authorized** (helper + spec + two docs).
- Delegation: one coherent contract slice — the helper, its spec requirement and the two docs that
  teach it. The parent owns the coupled slice (same shape as `opencode-delegate-timeout`), and an
  independent read-only verifier checks the spec assertions against the diff.
