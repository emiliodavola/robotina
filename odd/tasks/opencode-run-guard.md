# Feature: opencode-run-guard

## Goal

Close #78's residual gap: keep `default_agent: gentle-orchestrator` in `robotina/overlay.json` (the
interactive TUI opens on the coordinator — the decision recorded in commit `3588eef`) and close the
**raw-default gap**: a non-interactive `opencode run` without `--agent` resolves to an agent that
coordinates sub-agents and never executes inline, so the work is silently not done. The CLI wrapper
`/opt/robotina/bin/opencode` SHALL refuse that invocation with an actionable message instead. The
delegation path (`opencode-delegate`, and the CLI with `--agent build`) already names the executor
(OD1) and is untouched.

Branch: `fix/issue-78-opencode-run-guard`, off `main`. Owner: `emiliodavola`. Closes #78.

## Non-goals

- **No change to `default_agent`.** It stays `gentle-orchestrator`; `gentle-orchestrator` stays exposed
  and keeps declaring it does not execute (OD2).
- **No change to the TUI.** The interactive surface stays human-driven and may open on the coordinator.
- **No change to `serve`, `debug`, `auth` or any other subcommand**, and no change to the s6 service
  (its run script invokes `opencode serve`, which the guard passes).
- **No image rebuild or container recreate in this change.**

## Diagnosis (measured, read-only, 2026-09-29)

1. `robotina/overlay.json` pins `default_agent: gentle-orchestrator` on purpose; OD1 already records
   the rationale (the TUI opens there) and forbids relying on the merged default for delegation.
2. `gentle-orchestrator`'s own prompt coordinates sub-agents and never executes inline, so a raw
   `opencode run` (no `--agent`) submits a turn that closes without touching the work — the failure is
   silent.
3. **The spec itself carries the defect:** OD3's scenario "The default agent executes with no explicit
   `--agent`" cannot pass under that default and directly contradicts OD1. The residual is therefore
   code **and** spec text.

## Shape

1. `robotina/bin/opencode` (the PATH wrapper): detect the `run` subcommand and refuse it when neither
   `--agent`/`--agent=` nor `-h/--help` is present, exiting `2` with a message naming
   `opencode run --agent build`. Every other subcommand, the TUI, and the real binary escape hatch pass
   through unchanged.
2. Spec `opencode-delegation`: **OD1** gains the guard requirement and its scenarios; **OD3**'s
   default-decides scenario becomes the refusal control, while the mutation proof stays the explicit
   `--agent build` scenario.
3. Docs: the delegation skill's agent rule and `hermes/context/.hermes.md`.

## Tasks

- [x] T1 — Branch and this tracker.
- [ ] T2 — Wrapper guard for `run` without `--agent`; header documents it.
- [ ] T3 — Spec OD1 guard requirement + OD3 default-decides scenario reconciled.
- [ ] T4 — Docs: `hermes/skills/opencode-delegation/SKILL.md` and `hermes/context/.hermes.md`.
- [ ] T5 — Verification (`sh -n`/`dash -n`, refusal exit `2`, help/version passthrough, `serve`
      passthrough, `docker compose config -q`) plus an independent read-only verifier.
- [ ] T6 — Commit per work unit, push, PR against `main` assigned to the owner.

## Pending after this PR

- The wrapper is baked into the image, so the guard reaches `/opt/robotina/bin/opencode` only after a
  rebuild plus `--force-recreate`; until then the proofs use the stale-image recipe
  (`sh -s -- run "<task>" < robotina/bin/opencode`).

## Route declaration

- Classification: **small but non-trivial and authorized** (argument parsing in a baked wrapper +
  spec reconciliation across two requirements + two docs).
- Delegation: the parent owns the coupled wrapper+spec slice; an independent read-only verifier checks
  the refusal semantics, the passthrough set and the spec assertions.
