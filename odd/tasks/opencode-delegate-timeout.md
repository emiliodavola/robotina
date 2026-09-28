# Feature: opencode-delegate-timeout

## Goal

Close #69: the default global timeout of `opencode-delegate` MUST fit a multi-phase turn (survey +
edit + network `uv sync` + git/GitHub), and the flag that raises it MUST be documented where the
agent reads it. Three turns were aborted at the 900 s default on 2026-09-28.

Branch: `fix/issue-69-delegate-timeout`, off `main`. Owner: `emiliodavola`.

## Non-goals

- No change to the liveness or exit-code contract (OD6/OD8/OD10). `--timeout` keeps meaning "budget
  for the whole turn", and exit `4` keeps meaning "the helper aborted on that budget".
- No task-aware dynamic budget. The default is a number, configurable from the environment; the
  guidance to split a multi-phase task into small delegations is documentation, not code.
- No image rebuild or container recreate in this change.

## Diagnosis (measured, read-only against the live stack, 2026-09-28)

1. `grep -n '^TIMEOUT=' /opt/robotina/bin/opencode-delegate` (and the working tree) → `TIMEOUT=900`.
2. `opencode-delegate --help` documents `--agent`, `--directory` and the deprecated `--stall-polls`
   only: `--timeout` and `--interval` appear in the `uso:` line but not in the flag detail, so
   nothing tells the caller the default or how to raise it.
3. The helper already reads `ROBOTINA_OPENCODE_DELEGATE_MODEL` and
   `ROBOTINA_OPENCODE_DELEGATE_AGENT` from the environment; there is no matching knob for the
   timeout, so an operator cannot tune it without editing the image.

## Shape

1. Raise the default to 1800 s.
2. Make it configurable like the other two delegation knobs: `ROBOTINA_OPENCODE_DELEGATE_TIMEOUT`,
   validated as a positive integer, overridden by `--timeout`.
3. Document `--timeout SEC` and `--interval SEC` in `usage()`, and the split-a-multi-phase-task rule
   in the `opencode-delegation` skill and `hermes/context/.hermes.md`.
4. Plumb the new key through `compose.yml` and `.env.example`.
5. Spec: `opencode-delegation` gains an **OD11** requirement — the default budget and the override
   are observable.

## Tasks

- [x] T1 — Branch and this tracker.
- [x] T2 — Helper: default 1800, `ROBOTINA_OPENCODE_DELEGATE_TIMEOUT` override, validated as a
      positive integer; `usage()` documents both time flags and the header lists the env key.
- [x] T3 — `compose.yml`: the new key. `.env.example` is an owner hand-off (see below).
- [x] T4 — Spec `opencode-delegation`: OD11 (default, override, documented flags), plus the
      "issue #69 added the fourth lesson" note in the purpose block.
- [x] T5 — Docs: `hermes/skills/opencode-delegation/SKILL.md` (paragraph + troubleshooting row) and
      `hermes/context/.hermes.md`; `SECURITY.md` records the knob.
- [x] T6 — Static verification: `sh -n`, `--help`, the OD11 greps, `docker compose config -q`, and the
      behavioral proof of the environment override (exit `4`, `timeout global de 3s`); independent
      read-only verifier over the diff and the spec assertions.
- [x] T7 — Commit per work unit, push, PR against `main` assigned to the owner: **PR #72**
      (3 commits: tracker, fix, specs/docs).

## Pending after this PR

- `.env.example`: the repo-local safety guard refuses every `.env*` path to the editor, so the new
  bare `ROBOTINA_OPENCODE_DELEGATE_TIMEOUT=` line is an owner hand-off and is committed to this
  branch once applied — the same path `live-config-drift` T8 took. The key itself is already
  documented in `compose.yml`, the skill, `.hermes.md` and OD11, and its default (`1800`) is baked
  into the compose interpolation, so a missing line in the sample changes nothing at runtime.
- A rebuild plus `--force-recreate` is what puts the new helper in `/opt/robotina/bin`, same as any
  helper change; until then the change is exercised through the stale-image recipe.

## Route declaration

- Classification: **substantial and authorized** (helper + compose + env sample + spec + two docs).
- Delegation: one non-trivial code file (the helper); the rest is prose alignment and plumbing. The
  parent owns the coupled slice, and an independent read-only verifier checks the spec assertions.
