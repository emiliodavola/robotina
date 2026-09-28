# Feature: opencode-delegate-status-scope

## Goal

Close #40 and the contract half of #51: `opencode-delegate` must stop declaring a healthy turn
closed. The measured root cause is that its liveness signal is the **global** session-status map,
while that map only knows the server's own cwd instance; a session created with `--directory`
elsewhere is simply not in it, and the helper reads that absence as "the turn ended".

Branch: `fix/issue-40-delegate-liveness-scope`, off `main`. Owner: `emiliodavola`.

## Non-goals

- No new delegation features, no new flags. The delivered surface stays the same.
- No container recreate, no image rebuild: the helper is bind-coupled only through the image, so
  **the fix reaches the running container only after a rebuild** — that is a phase-2 decision, not
  part of this change.
- No change to the executor-agent pinning of #38 (OD1) nor to the permission probe of OD8.

## Diagnosis (measured)

Evidence already recorded in #40, plus one new API fact found while scoping this change:

1. `GET /session/status` is scoped to the instance of the **server's cwd** (`/workspace`). Measured
   in #40: the same turn is `{"type":"busy"}` for a session created in `/workspace`, and `ABSENT`
   for sessions created in `/tmp` and `/workspace/sofer`, while the turn is provably alive (a
   `bash` tool part in `running`).
2. The helper maps `absent | idle` to `status_over=1`, and once that flag is set it counts
   `SETTLE_POLLS=3` polls (≈6 s) before exiting `3` with `finish=null` — which is the *normal*
   value while a step runs. Hence the false close.
3. `absent` is not a signal about the turn at all: it is a property of the query, not of the
   session. The code comment in the helper already says absence "is not the same as an unreadable
   status", which is exactly backwards.
4. **New:** `GET /doc` declares `GET /session/status` with optional `directory` and `workspace`
   query parameters, and `POST /api/session/{sessionID}/wait` ("Wait for session") as a
   session-scoped endpoint. Neither was ever tested; #40 listed them as unverified options.

## Open questions (being measured, not assumed)

- **Q1** Does `GET /session/status?directory=<the session's own directory>` report the session as
  `busy` while the global call reports it absent? If yes, the fix is a scope correction and the
  polling architecture survives unchanged.
- **Q2** What does `POST /api/session/{id}/wait` actually do: does it block until the turn ends,
  and is it bounded? If it is a clean session-scoped wait, it is a better liveness primitive than
  any status map.

Both are being measured against the live stack before any code is written. The helper can resolve
the session's directory from the API itself (`GET /session/{id}` → `.directory`), so a fix does not
depend on the caller having passed `--directory`.

## Shape (pending the measurement)

1. Liveness must be answered by the instance that owns the session, or by the session itself.
2. "Not in the map" must become **unknown**, never closure. Only a positive answer about the turn
   may end it.
3. A closure verdict needs terminal evidence from the session's own messages; the global timeout
   stays as the outer bound.
4. Exit codes must let the caller tell three different facts apart: a clean close, a turn error or
   close without a final message, and an external abort (today the last two are both `3`).
5. The spec must carry the regression: OD6's proof has to exercise `--directory` ≠ the server cwd,
   which is the case that would have caught this.

## Tasks

- [ ] T1 — Branch and this tracker.
- [ ] T2 — Measure Q1/Q2 against the live stack (delegated, read-only + one throwaway session).
- [ ] T3 — Implement the scoped liveness and the exit-code separation in
      `robotina/bin/opencode-delegate`.
- [ ] T4 — Amend `openspec/specs/opencode-delegation/spec.md`: OD6's liveness scope, a new
      requirement for the exit-code contract, and the `--directory` regression scenario.
- [ ] T5 — Document the resulting exit-code table in the `opencode-delegation` skill and in
      `hermes/context/.hermes.md`.
- [ ] T6 — Run the OD6/OD7 proofs plus the new `--directory` proof against the live stack.
- [ ] T7 — Commits per work unit, push, PR against `main` assigned to the owner.

## Route declaration

- Classification: **substantial and authorized** (helper logic + spec + skill + live proof).
- Delegation: the live measurement goes to a read-only verifier; the parent owns the helper edit,
  the spec amendment and the branch, because they are one coupled contract change.
- Note: the helper inside the running container is *not* updated by this branch. Proving the fix on
  the live stack requires a rebuild of `robotina:local`, which the owner gates with the phase-2
  recreate window.
