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

## Answers (measured live, 2026-09-28)

**Q1 — yes.** `GET /session/status?directory=%2Ftmp` answered `{"type":"busy"}` while the
unscoped `GET /session/status` answered `{}` at **every one of 32 polls**, including while the
session's `bash` tool part was `running`; the scoped answer flipped to `{}` exactly at
`finish=stop`. `?workspace=/tmp` returned HTTP `500` `UnknownError` on every call.

**Q2 — no.** `POST /api/session/{id}/wait` is a stub: HTTP `503`
`{"_tag":"ServiceUnavailableError","message":"Session wait is not available yet"}` in 10–80 ms both
while idle and while the turn was `busy`. It never blocks. Discarded.

Also measured: an aborted assistant message has **no `finish` field at all** plus
`info.error.name == "MessageAbortedError"`, while an in-progress message carries `finish: null`.
`finish` is a bare `string` in the OpenAPI schema (no enum), observed domain
`{tool-calls, stop, null, absent}`.

## Shape (decided by the measurement)

1. Liveness is answered by the instance that owns the session:
   `GET /session/status?directory=<session.directory>`, with the directory read back from the server
   (`GET /session/{id}` → `.directory`), so a reused `--session` is scoped too.
2. If the scope cannot be resolved, the status degrades to **unknown**, never to closed: that turn is
   bounded by the global timeout (slow but safe).
3. Closure verdicts still come from the session's own messages; the settle window keeps guarding the
   race between the status flip and the message write, and is now only reachable with a *scoped*
   answer.
4. The exit code separates the facts (#51): `3` = ended without a successful final message,
   `5` = aborted by something that is not the helper. Aborts the helper performs itself keep `2` and
   `4`.
5. The spec carries the regression: OD6 now names the instance scope, and its proof exercises
   `--directory` outside `/workspace` — the case that would have caught this.

## Evidence (before/after on the live server, same task, same directory)

| Run | Invocation | Exit | stdout |
| --- | --- | --- | --- |
| image copy (pre-fix) | `/opt/robotina/bin/opencode-delegate --directory /tmp --timeout 120 "…sleep 20… DONE"` | **3** | empty; stderr `el turno cerro sin mensaje final (finish=null)` |
| working tree | `sh -s -- --directory /tmp --timeout 120 "…sleep 20… DONE"` | **0** | `DONE`; stderr `scope: liveness acotada a /tmp` |
| working tree, no `--directory` | `sh -s -- --timeout 90 "Reply with exactly OK"` | **0** | `OK`; stderr `scope: liveness acotada a /workspace` |
| working tree + external abort | background run, then `POST /session/{SID}/abort` | **5** | stderr names `MessageAbortedError` as not-helper |
| working tree, tiny timeout | `sh -s -- --directory /tmp --timeout 3 "…sleep 40…"` | **4** | stderr `timeout global de 3s … (ultimo status: busy, alcance: /tmp)` |

The runs used the spec's own stale-image recipe (`sh -s -- <args> < robotina/bin/opencode-delegate`),
because the helper is baked into the image and this branch does not rebuild it. md5 evidence of what
ran:

```
working tree : 3c4500d29f1336419baf84da730bbf65
HEAD         : 8a0caae03b231f5a015d5d3448d4af82
imagen       : 8a0caae03b231f5a015d5d3448d4af82   (= HEAD, o sea el helper con el bug)
```

Authorized state change for the measurement: one temp copy of the helper in the container's tmpfs
(removed afterwards) and five throwaway sessions under `/tmp`. `/workspace` was never touched, and no
container was restarted, rebuilt or recreated.

## Tasks

- [x] T1 — Branch and this tracker.
- [x] T2 — Measured Q1/Q2 against the live stack (delegated to a read-only verifier, plus one
      throwaway session per question).
- [x] T3 — Implemented the scoped liveness and the exit-code separation in
      `robotina/bin/opencode-delegate`. Syntax checked with the container's own `dash -n`.
- [x] T4 — Amended `openspec/specs/opencode-delegation/spec.md`: OD6 now names the instance scope,
      OD9 feeds it from the server's canonical directory, and a new **OD10** fixes the exit-code
      contract. Added the `--directory` regression scenario and the two measured dead ends.
- [x] T5 — Documented the scope and the exit-code table in the `opencode-delegation` skill and in
      `hermes/context/.hermes.md`, including a troubleshooting row for the stale-image trap.
- [x] T6 — Ran the proofs on the live stack through the spec's stale-image recipe: exit `3` → `0` on
      the same task, no regression without `--directory`, `5` for an external abort, `4` for the
      helper's own timeout.
- [ ] T7 — Commits per work unit, push, PR against `main` assigned to the owner.

## Route declaration

- Classification: **substantial and authorized** (helper logic + spec + skill + live proof).
- Delegation: the live measurement goes to a read-only verifier; the parent owns the helper edit,
  the spec amendment and the branch, because they are one coupled contract change.
- Note: the helper inside the running container is *not* updated by this branch. Proving the fix on
  the live stack requires a rebuild of `robotina:local`, which the owner gates with the phase-2
  recreate window.
