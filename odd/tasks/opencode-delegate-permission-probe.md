# Feature: opencode-delegate-permission-probe

## Goal

Close #73 in its repo-fixable half: `opencode-delegate`'s named-block detector (A1) must actually
fire. Today a delegation whose tool call reaches `external_directory: ask` hangs until the global
timeout, and the caller gets `4` (timeout) instead of `2` (named block naming the pending request).

Root cause (measured, 2026-09-29): the helper polls `GET /api/session/{id}/permission` — the v2
endpoint — which returns `{"data":[]}` **while the request is pending**, while the v1 endpoint
`GET /permission` lists it with its `sessionID`, `permission` and `patterns`. Six polls over 60 s
against a live hang: scoped always empty, global always non-empty. The probe never saw the block, so
the turn burned the entire budget and the abort left the request dangling on the server.

Branch: `fix/issue-73-delegate-permission-probe`, off `main`. Owner: `emiliodavola`.

## Non-goals

- **No widening of `permission.external_directory`** in `robotina/overlay.json`. The owner decided the
  detectable, deny-by-default posture stays: a read outside the session directory is still blocked,
  it is just named in seconds instead of hanging. (The open item recorded in
  `odd/tasks/opencode-cli-environment.md` T6 remains open and is not settled here.)
- No change to the turn budget (#69 owns it, and the budget is not the cause).
- No work on the `HTTP 403` the Hermes path logs for its default model
  (`muse-spark-1.3-contributor`, "an active OpenCode Go subscription is required"). The owner
  confirmed it was a payment-method problem and it is out of scope; the delegation key itself is
  healthy (measured: `opencode run -m opencode-go/deepseek-v4.1-flash "Reply with exactly OK"` →
  `OK`, exit 0).
- No image rebuild or container recreate: the helper is baked, so the live proofs use the
  stale-image recipe (`sh -s < robotina/bin/opencode-delegate`).

## Diagnosis (measured, read-only against the live stack, 2026-09-29)

1. **The hang.** A delegation created with `--directory /workspace` and told to read
   `/opt/data/cache/delegation/subagent-summary-0-*.txt` (the directory the delegating side writes
   the prompt's inputs into) ended with
   `timeout global de 90s … (ultimo status: busy, alcance: /workspace)` → exit `4`. The running
   helper's md5 is identical to the repository's, so this is the shipped code, not a stale image.
2. **The request exists, the endpoint the helper polls does not see it.** With the request pending:
   - `GET /api/session/ses_…/permission` → `{"data":[]}` (6/6 polls, 60 s);
   - `GET /permission` → `[{"id":"per_…","sessionID":"ses_…","permission":"external_directory",
     "patterns":["/opt/data/cache/delegation/*"],"metadata":{…}}]`.
   The v1 endpoint is the one that carries the fact; the v2 endpoint the helper uses is empty.
   Consequence: `turn_alive=1` + `perms` empty → the probe is a no-op and the turn runs to the
   timeout. Measured on the live server with `curl -u opencode:$OPENCODE_SERVER_PASSWORD`.
3. **The abort leaks the request.** After two timed-out runs, `GET /permission` still listed **two**
   requests belonging to the dead sessions. `POST /permission/{id}/reply` with `{"reply":"reject"}`
   cleared them (`GET /permission` → `[]`). So the helper's own abort does not clear what it leaves
   pending.
4. **The documented exit codes already cover the case**: OD10 assigns `2` to "a named block (a
   pending permission nobody can answer); the helper aborts the turn". Nothing in the exit-code
   contract changes — what changes is that `2` becomes reachable.

## Shape

1. `robotina/bin/opencode-delegate`: the A1 probe asks `GET /permission` and filters the returned
   array by `.sessionID == $SESSION` (the v2 call is replaced, with the measurement in a comment
   saying why). On detection it **rejects** the pending request(s) with
   `POST /permission/{id}/reply` `{"reply":"reject"}` — best-effort, never fatal — then aborts the
   session and exits `2`, naming the permission and its patterns. The probe stays best-effort: an
   unavailable or unparsable response never fails a healthy turn.
2. The same cleanup runs on the global-timeout path before that path aborts, so the helper stops
   leaking requests the server keeps listed.
3. `openspec/specs/opencode-delegation/spec.md`: OD8 names the endpoint that actually carries the
   fact and the reject-before-abort step, and gains a live PROOF that must exit `2` **well before**
   the budget (a proof that passes with the hang present is not a proof).
4. `SECURITY.md`: the observability/troubleshooting entry that already documents the stall records
   the measured answer to "does an out-of-`directory` read error fast or hang?" — it hangs, and this
   is the endpoint that sees it.

## Tasks

- [x] T1 — Branch and this tracker.
- [x] T2 — `robotina/bin/opencode-delegate`: `cleanup_pending_permissions` probes `GET /permission`
      (v1) filtered by `sessionID`, rejects each matching request, and is used by both abort paths
      (named block → `2`, global timeout → `4`), so the helper stops leaving requests listed.
- [x] T3 — `openspec/specs/opencode-delegation/spec.md`: OD8 rewritten (v1 authority, reject before
      abort, best-effort, cleanup on the timeout path) with the live proof asserting exit `2` and an
      empty `GET /permission`; `OD1`–`OD7`, `OD9`–`OD11` untouched. `hermes/skills/opencode-delegation/SKILL.md`
      aligned (the table row for v2 is now marked as not the block probe), and the historical tracker
      `odd/tasks/opencode-delegate-agent-liveness.md` carries a SUPERSEDED note instead of a rewrite.
- [x] T4 — `SECURITY.md`: the measured answer for out-of-directory reads (it hangs) and the v1/v2
      asymmetry.
- [x] T5 — Verification: live differential by the parent (old baked helper: exit `4` at 46 s with a
      request left behind; new copy: exit `2` at 5 s, `GET /permission` → `[]`) and an independent
      read-only verifier over the code, the spec and the docs (no blocker/important findings; one
      stale sentence in a historical tracker, corrected here).
- [ ] T6 — Commit per work unit, push, PR against `main` assigned to the owner.

## Route declaration

- Classification: **substantial and authorized** (owner confirmed: fix the detector, do not widen
  permissions).
- Delegation: one writer for the helper plus its spec and doc slice; one independent read-only
  verifier for the live reproduction and the spec assertions. The parent owns the diagnosis, the
  tracker and the measured record.
- The live reproduction needs a real delegation turn (a small model cost) and a fixture under
  `/opt/data/cache/delegation/`, which the parent creates and removes inside the same proof.
