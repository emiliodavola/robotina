# Feature: opencode-delegate-agent-liveness

## Goal

Make `opencode-delegate` (a) always run the delegated turn on an executing agent and
(b) stop aborting healthy turns. Issue #38. The helper is the second of the two
delegation paths (the first is the `opencode` CLI wrapper); `.hermes.md` already
instructs the caller to name the executor on the CLI path, and the helper is the path
that never does.

## Diagnosis (measured against the running stack, 2026-09-24, OpenCode 1.18.32)

Full evidence: https://github.com/emiliodavola/robotina/issues/38#issuecomment-5824231676

Two independent defects in one helper. Neither is "the orchestrator coordinates".

1. **The agent is never pinned.** `POST /session/{id}/prompt_async` is sent as
   `{model, parts}`. With `robotina/overlay.json` → `default_agent: gentle-orchestrator`,
   both sessions in the report ran as `gentle-orchestrator` (`info.agent`, `info.mode`).
   `GET /session/{id}/children` is `[]` in both, so the orchestrator did *not* coordinate:
   it executed `bash`/`glob`/`read` inline. The defect is "the delegated turn runs on the
   wrong agent", against the stack's own rule. The API accepts `"agent"` in the body of
   `prompt_async` (`additionalProperties: false`), and honours it: measured
   `agent=build`.

2. **The stall detector cannot observe progress, and it is the direct cause of both
   exit 2s.** `assistant_signature` reads `info.tokens`, which is populated only when a
   step closes. During a whole in-progress step the signature is identically
   `0/0/0/0/0`, whatever the work does — in session 1 the message being watched had a
   `glob` **completed** inside it. Controlled reproduction with `agent=build` and a
   `sleep 25` tool:

   ```
   t=2s … t=28s   status=busy agent=build finish=null parts=3 tokens=0/0/0/0/0
   t=32s          status=absent agent=build finish=stop  tokens total 23198
   ```

   So any tool call longer than `STALL_POLLS × INTERVAL` (12 s by default) aborts a
   healthy turn — with `build` too. Raising the threshold moves the window; it does not
   close it. The server exposes the real signal: `GET /session/status` reported `busy`
   for the whole run and dropped the session from the map when it ended.

3. **Secondary, confirmed:** `finish` that is non-null and not `stop` is treated as a
   terminal closure (exit 3). `finish=tool-calls` lands on every intermediate assistant
   message (measured: message 1 `tool-calls`, message 2 `stop`, 5 ms apart), so the branch
   is semantically wrong even though the window is narrow.

## Decisions (user, 2026-09-24)

- **`default_agent` stays `gentle-orchestrator`** (commit `3588eef`, the user's pin). The
  invariant moves to the delegation path: the helper pins the executor explicitly, and
  **OD1 is amended** to say so. The interactive TUI keeps opening on the orchestrator.
- **`--directory` is opt-in.** Default is the server's own cwd (`/workspace`, from
  `cd /workspace` in `robotina/s6/s6-rc.d/opencode/run`). It is *not* derived from the
  caller's `$PWD`: Hermes runs with cwd `/opt/data`, so a derived default would make
  `/workspace` an external directory and reintroduce the `external_directory: ask` hang
  of #27.

## Shape

`robotina/bin/opencode-delegate`:

- `--agent NAME`, default `ROBOTINA_OPENCODE_DELEGATE_AGENT`, default `build`; sent as
  `"agent"` in the `prompt_async` body so the merged `default_agent` never decides. A
  warning (not a refusal) when `NAME` is `gentle-orchestrator`, because that agent
  coordinates and the turn may not converge; the escape hatch stays.
- `--directory PATH`, optional, sent as a `POST /session` query parameter with
  `--data-urlencode` so a path with spaces survives. Absent → server default.
- **Liveness from the server.** Each poll reads `GET /session/status`;
  `busy`/`retry` = the turn is alive. The token signature and the "N polls without
  change" rule are removed: they are not a liveness signal.
- **Terminal decision from the message**, only once the server reports the turn is over
  (`idle`, or the session absent from the map): last assistant message with index ≥
  baseline. `info.error` → 3; `finish=stop` → 0 and print the text; `finish` null or
  unknown → 3.
- **A bounded settle window** (~3 polls) between "server says the turn ended" and the
  verdict, so a status flip that beats the final message write cannot produce a false
  exit 3.
- **Stall = a named blocking condition.** While the turn is alive, a non-empty
  `GET /api/session/{id}/permission` means the turn is waiting on a permission prompt no
  human can answer: abort, exit 2, and name it. That probe is best-effort — an
  unavailable endpoint (older server) must never fail the turn.
- `--stall-polls` stays accepted for compatibility and is **deprecated**: it warns to
  stderr and no longer affects behaviour.
- Exit codes keep their meaning: `0` finished, `2` blocked (aborted), `3` turn error or
  non-`stop` closure, `4` global timeout, `1` usage or transport. Only the *reason* for 2
  changes (a named block instead of a token-signature guess).

Contract artifacts updated in the same commit: `hermes/context/.hermes.md` (always-on
rule) and `hermes/skills/opencode-delegation/SKILL.md`. The spec
`openspec/specs/opencode-delegation/spec.md` gets the amended OD1 plus new OD6–OD8, each
with a runnable shell proof (this repo has no test runner — `openspec/config.yaml` →
`testing.runner: none`).

## Out of scope / rejected

- **Reverting `default_agent` to `build`.** Rejected by the user: the TUI stays on the
  orchestrator and the invariant lives in the delegation path.
- **Deriving `--directory` from `$PWD`.** Rejected: reintroduces the #27 hang.
- **Raising `STALL_POLLS`.** Rejected: the signature cannot move during a step, so a
  larger threshold only delays a false abort.
- **Widening `permission` to silence `external_directory`.** Still the open item recorded
  in `odd/tasks/opencode-cli-environment.md`; untouched here.
- **Refusing `gentle-orchestrator` outright.** Warn only; a caller may legitimately want
  orchestration.

## Tasks

- [x] T1 — Feature document (this file) and the visible todo.
- [x] T2 — `robotina/bin/opencode-delegate`: agent pin, `--directory`, status-based
      liveness, message-based terminal decision, settle window, named-block exit 2,
      deprecated `--stall-polls`.
- [x] T3 — `hermes/context/.hermes.md`: rewrite the `opencode-delegate` bullet to the new
      contract.
- [x] T4 — `hermes/skills/opencode-delegation/SKILL.md`: agent flag, `--directory`, exit
      reasons, and correct the false claim that the overlay sets `default_agent: build`.
- [x] T5 — `openspec/specs/opencode-delegation/spec.md`: amend OD1 (the invariant lives in the
      delegation path) and add OD6 (a long tool call is not a stall), OD7 (intermediate
      `finish=tool-calls` is not terminal), OD8 (a named block is reported), OD9 (`--directory`
      is opt-in); each with its exact proof command.
- [x] T6 — Verify: `sh -n robotina/bin/opencode-delegate`; the OD6–OD9 proofs against the
      running server (the `sleep 30` fixture); `docker compose config -q`; the `--directory`
      opt-in path. Every observed value is recorded below.
- [x] T7 — Work-unit commits on a feature branch, Conventional Commits, `(#38)`.
- [x] T8 — Push the branch and open the PR against `main`, assigned — the user asked for it, with
      an **explicit size exception** (579 added lines vs the repo's 400-line budget;
      `exception_ok: false` means it is never inferred). →
      [#39](https://github.com/emiliodavola/robotina/pull/39).

## Route declaration

T2–T5 are one bounded unit and the multi-file write trigger fires (four non-trivial
files: the helper, two contract docs and the spec). Route: **delegated direct**, one
`gentle-ai-worker`, allowed edit surfaces exactly
`robotina/bin/opencode-delegate`, `hermes/context/.hermes.md`,
`hermes/skills/opencode-delegation/SKILL.md`,
`openspec/specs/opencode-delegation/spec.md`. T1, T6's parent spot check, T7 and T8 stay
inline as parent bookkeeping. Verification of the runtime proofs routes through
`gentle-ai-verify` (read-only).

## Evidence

Verified 2026-09-24 against the running stack (OpenCode 1.18.32). Independent verification ran
read-only through `gentle-ai-verify`, reporting every command one by one.

**Deployment caveat (found by verification).** `robotina/Dockerfile` copies `robotina/bin/`, so
`/opt/robotina/bin/opencode-delegate` in the running container is the *pre-fix* image copy: md5
`f0af91b1c1618cd5bec2628c179558dd`, equal to `git show HEAD:robotina/bin/opencode-delegate`, while
the working-tree file is `8a0caae03b231f5a015d5d3448d4af82`. The literal in-container proofs
therefore exercise stale code and cannot pass until a rebuild + `--force-recreate`; they are
recorded as *not runnable until rebuild*, not as passes. The fix was exercised equivalently with
`docker compose exec -T -u hermes robotina sh -s -- <args> < robotina/bin/opencode-delegate`, and the
stale copy served as the negative control.

| Proof | Observed |
| --- | --- |
| `sh -n robotina/bin/opencode-delegate` | exit 0 |
| `grep -c 'assistant_signature' robotina/bin/opencode-delegate` | `0` |
| `grep -c 'session/status' robotina/bin/opencode-delegate` | `5` |
| `grep -c '/permission' robotina/bin/opencode-delegate` | `2` |
| `grep -c 'agent:$a' robotina/bin/opencode-delegate` | `1` |
| `grep -n '"default_agent"' robotina/overlay.json` | `gentle-orchestrator` (untouched, by decision) |
| `docker compose config -q` | exit 0 |
| OD6 — 30 s tool call, checked-out file | `DONE`, exit 0, session `ses_f2a131143ffeFNIxYSNt6qyj48` |
| OD6 — the same with `--stall-polls 6` (control) | `DONE`, exit 0, deprecation warning on stderr |
| OD6 — negative control, deployed stale copy | exit 2, `tokens congelados en 0/0/0/0/0`, session `ses_f2a0c7eceffenI981IcgHltVAz` |
| OD7 — assistant `info.finish` of the OD6 session | `["tool-calls","stop"]`, helper exit 0 |
| OD1 s4 — trivial delegation, last assistant `.info.agent` | `build`; merged default read inside the container: `gentle-orchestrator` |
| OD9 — no `--directory` | `.directory == "/workspace"` |
| OD9 — invoked with `cd /tmp`, no `--directory` | `.directory == "/workspace"` (the caller's cwd does not leak) |
| OD9 — `--directory /tmp` | `.directory == "/tmp"` |
| OD8 — pending-permission fixture | **inconclusive**: the model emitted `rtk git commit --allow-empty -m probe`, which does not match the `bash: git commit *` ask rule, so nothing was pending. Static proof only. |

Two spec defects found by verification and fixed before committing:

1. OD6–OD9's PROOF commands invoked the baked-in helper with no rebuild caveat, so a verifier
   following them literally would run stale code and wrongly fail the change. The caveat is now a
   bullet in the spec's verification model, with the equivalent `sh -s` form and the md5 check.
2. `SKILL.md` said `--stall-polls` is "deprecated and ignored"; the helper still validates it as a
   positive integer and exits 1 otherwise. Reworded to "accepted and validated for compatibility,
   deprecated, and no longer affects behaviour".

T8 was closed on request: [#39](https://github.com/emiliodavola/robotina/pull/39), one PR against
`main` with the explicit size exception. The native review of the candidate did not run: the RDD
preflight is blocked by a facade/native schema mismatch (the committed-range START returns
`schema-incompatible` with no lineage created and no mutation; the ordinary START yields an empty
candidate whose base-ref slot the capture tool rejects). No recovery route was touched.
