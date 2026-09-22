# Archive report — single-robotina-container

Change: `single-robotina-container`
Phase: `sdd-archive` (openspec artifact store)
Archived to: `openspec/changes/archive/2026-09-22-single-robotina-container/`
Archive date: 2026-09-22
Branch at close: `feat/single-robotina-container-13-archive` (tracker `feat/single-robotina-container`)
Status: **PASS — archived**

---

## 1. Archive status

**PASS.** The change was archived with a non-destructive, byte-preserving composition and a
folder move. No artifact was rewritten, no destructive delta was applied, and the running stack
was not touched (no `up`, `down` or `build` was executed by archive).

- Delta-spec shape: the six change specs are **full new-domain specs** (`## Purpose` /
  `## Verification model` / `## Requirements`), with **zero** `## ADDED` / `## MODIFIED` /
  `## REMOVED` / `## RENAMED` sections. The canonical layer `openspec/specs/` contained only
  `.gitkeep` before this archive. This confirms the parent's reading: the change **establishes**
  the base capability specs rather than merging deltas into predecessors.
- Composition performed: copy of each full-domain change spec into the canonical path, verified
  byte-identical with `cmp` (six of six `IDENTICAL`).
- No `RENAMED` section existed, so no unsupported-operation block was triggered.
- No `MODIFIED`/`REMOVED` operation existed, so the Destructive Merge Guard required no approval.

## 2. Structured status and `actionContext` findings

Consumed native `gentle-ai.sdd-status` v2 as the authoritative read-only projection; archive
readiness was **not** recomputed locally.

| Field | Value |
| --- | --- |
| `changeName` | `single-robotina-container` |
| `artifactStore` | `openspec` |
| `planningHome.mode` | `repo-local` (`C:\Users\elaze\Desktop\robotina\openspec`) |
| `actionContext.mode` | `repo-local` |
| `actionContext.workspaceRoot` | `C:\Users\elaze\Desktop\robotina` |
| `actionContext.allowedEditRoots` | `["C:\Users\elaze\Desktop\robotina"]` |
| `nextRecommended` | `archive` |
| `dependencies` | apply `all_done`, verify `ready`, archive `ready` |
| `taskProgress` | 45 total / 45 completed / 0 pending / `allComplete: true` |
| `artifacts` | proposal `done`, specs `done`, design `done`, tasks `done`, applyProgress `done`, verifyReport `missing` |
| `blockedReasons` | `[]` |
| `notes` | `[]` |
| `relationships.sameDomainActiveChanges` | `[]` |

- **Verify report:** `verifyReport: missing`. Verification was explicitly optional for this
  change; a missing report is not an admission gate, and archive recorded the actual task state
  plus the verification findings available in `apply-progress.md` and the ODD record.
- **Edit confinement:** every path written (six canonical specs, this report, the folder move)
  resolves inside `allowedEditRoots` (`C:\Users\elaze\Desktop\robotina`) and inside the
  authorized `openspec/` surface. No symlinks exist anywhere under `openspec/` (checked with
  `find openspec -type l` → none).
- **Collision check:** `openspec/changes/` contained only this change plus an empty `archive/`;
  the destination `openspec/changes/archive/2026-09-22-single-robotina-container/` did not
  exist. No same-domain active change was reported by native status.

## 3. Artifacts read before acting

| Artifact | Path | State |
| --- | --- | --- |
| Proposal | `openspec/changes/single-robotina-container/proposal.md` | read (full) |
| Explore | `openspec/changes/single-robotina-container/explore.md` | read (present; historical findings intentionally preserved) |
| Design | `openspec/changes/single-robotina-container/design.md` | read (§0–§22 incl. §13.3, §16, §19, §21) |
| Tasks | `openspec/changes/single-robotina-container/tasks.md` | read (full; re-read at the Final Task Completion Gate) |
| Apply progress | `openspec/changes/single-robotina-container/apply-progress.md` | read (slices 01–12 incl. the exhaustive verification-command sections) |
| Specs (6 domains) | `openspec/changes/single-robotina-container/specs/*/spec.md` | read (requirement/scenario inventory + amended sections) |
| SDD config | `openspec/config.yaml` | read (incl. `rules.archive`) |
| Project record | `openspec/project.md` | read |
| ODD tracker | `odd/tasks/single-robotina-container.md` | referenced (verification evidence lives there) |
| Verify report | — | **absent** (optional verification not run) |
| Sync report | — | **absent** (no separate sync phase; archive owns composition) |

`rules.archive` from `openspec/config.yaml` was applied: the final measured service list and the
capability/lifecycle measurements are recorded in §6 of this report (the image digest float is
recorded as an honest gap in §7).

## 4. Domains synced and requirement names

Canonical paths written (new-domain composition; equivalent to `ADDED` for every requirement,
because there was no predecessor):

| Domain | Canonical file | Requirements | Scenarios |
| --- | --- | --- | --- |
| `agent-container` | `openspec/specs/agent-container/spec.md` | 9 | 27 |
| `agent-credentials` | `openspec/specs/agent-credentials/spec.md` | 7 | 17 |
| `agent-identity` | `openspec/specs/agent-identity/spec.md` | 5 | 14 |
| `egress-boundary` | `openspec/specs/egress-boundary/spec.md` | 5 | 15 |
| `opencode-endpoint` | `openspec/specs/opencode-endpoint/spec.md` | 7 | 17 |
| `state-layout` | `openspec/specs/state-layout/spec.md` | 6 | 23 |
| **Total** | | **39** | **113** |

Operation classification: **39 newly established requirements (ADDED semantics), 0 MODIFIED,
0 REMOVED, 0 RENAMED.** Because the canonical layer was empty, every requirement is a new-domain
`ADDED`; no already-applied/pending/unresolved reconciliation was required.

Requirement names, by domain:

- **agent-container:** AC1 Exactly two services, one of them the merged agent · AC2 The container
  answers to the name `robotina` · AC3 PID 1 is the image entrypoint (s6-overlay) · AC4 Merged
  hardening and the six-capability set · AC5 OpenCode and engram are s6-supervised services ·
  AC6 One consolidated resource budget · AC7 `robotina` is an `agents`-only service with no
  published port · AC8 The accepted merged-container regressions are documented with measurements ·
  AC9 The documentation describes one container, not two
- **agent-credentials:** CR1 Two independent API-key inputs · CR2 Hermes' process is configured
  with the Hermes key only · CR3 The OpenCode process is configured with the OpenCode key only,
  process-scoped · CR4 No secret is echoed, logged, or written to a tracked file · CR5
  `GITHUB_TOKEN` is present and the retired invariant is stated · CR6 The non-isolation of
  per-process keys is stated honestly · CR7 The accepted credential regressions are signed off
- **agent-identity:** ID1 A repo-authored read-only skin names the agent `robotina` · ID2 The skin
  is selected at startup without interaction · ID3 The always-loaded context states the identity
  and the merged topology · ID4 The BotFather step is display-name only and documented in both
  READMEs · ID5 The container answers to the name as an egress peer
- **egress-boundary:** EG1 INV1: no published port, no Docker socket, secrets only from `.env` ·
  EG2 INV2: `robotina` has no direct Internet route; all egress goes through `egress-proxy` ·
  EG3 INV3: `NO_PROXY` names `robotina` and keeps loopback · EG4 INV4: `squid/` is byte-identical
  after this change · EG5 INV5: the stack refuses to start without `HOST_DATA_DIR`
- **opencode-endpoint:** EP1 The server listens on loopback `127.0.0.1:4096` only · EP2 The server
  is unreachable from the host · EP3 The server is unreachable from every other container,
  including `egress-proxy` · EP4 The server is ready before Hermes' first delegation · EP5 The
  server process runs as uid 10000 · EP6 `OPENCODE_SERVER_PASSWORD` semantics are re-documented ·
  EP7 In-container operator recipes are documented in both READMEs
- **state-layout:** SL1 `HOME=/opt/data` for the agent process tree · SL2 WAL stores live on native
  volumes mounted inside the bind · SL3 State survives `down` / `up` · SL4 Copy-forward,
  non-blocking, idempotent, never-deleting migration · SL5 The merged service mounts only the
  target layout · SL6 State ownership is fixed from inside the container

**Active same-domain change warnings:** none. No other change under `openspec/changes/*/specs/`
touches any of the six domains.

## 5. Task completion gate and checkbox truth

- Final Task Completion Gate re-read the persisted `tasks.md` immediately before composition:
  **45 `- [x]`, 0 `- [ ]`.** No unchecked implementation task marker remains.
- No stale-checkbox reconciliation was performed and none was needed: there were no unchecked
  lines to repair, and the archive did not modify a single byte of `tasks.md`.
- `sdd-apply` owned task completion; archive only validated it. The task file is preserved
  verbatim (including its historical interim notes and slice amendments).
- Non-critical partial archive approval: **not applicable** — no partial archive, no missing
  required artifact (proposal, specs, design, tasks, apply-progress all present).

## 6. Final state recorded (explicit final-state facts)

These facts were decided or measured **after** the intermediate apply-progress / tasks snapshots
were written, and are recorded here as the final state of record.

1. **`CAP_KILL` defect found and fixed after the first live start.** The capability set is
   **six**, not five: `CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID, KILL`; bounding mask `0xeb`
   (235). Rationale: with `cap_drop: ALL` the root s6 supervisors could not signal the uid-10000
   services, an in-container shutdown wedged, and Docker had to SIGKILL at the stop grace period.
   The uid-10000 processes keep `CapEff=0x0`, so the agent gains nothing. (Design §13.3; spec
   agent-container AC4/AC8; commit `7d9c3d6`.)
2. **Lifecycle contract corrected to measurement.** `hermes gateway run` is the s6 service
   `gateway-default`; a gateway crash is restarted in place (observed pid 188 → 506) while the
   container's `RestartCount` and `StartedAt` stay unchanged. The container exits when the s6
   supervision tree goes down, not when Hermes exits. The earlier claim that a Hermes crash takes
   the container and the other services down was measured false and is replaced by this contract.
3. **Two runtime defects in the supervision slice found on the first live start and fixed**
   (commit `ec66d3f`): (a) s6-overlay executes a oneshot's `up` file as an **execline** script, so
   the shell-style `up` files exited 127 and took `opencode`/`engram` down; (b) the ownership
   self-heal's write test was satisfied by a writable `/opt/data` while `/opt/data/.config` and
   `/opt/data/.local` stayed root-owned, which broke the Telegram connection.
4. **`scripts/fix-permissions.ps1` was deliberately deleted** with explicit user confirmation
   (Q7). The container-side cont-init `robotina/s6/cont-init.d/10-robotina-state` replaces it.
   Its absence is intentional and must not be read as an omission.
5. **Measured values of record:** readiness gate **4.34 / 4.56 / 4.44 s** across three recreate
   cycles against a 120 s bound, zero `ECONNREFUSED`; peak `pids.current` **478 of 1024** over a
   900-sample 1 Hz window under the concurrent worst case, baseline **52**; graceful stop
   **5.50 s** with `ExitCode=0`; `CapBnd=0xeb`, app uid `CapEff=0x0`; nested WAL volumes backed
   by `ext4`, marker absent from the host bind and durable across `down`/`up`; endpoint
   auth-protected (plain probe **401**, credential-aware **200**).
6. **Honest gaps carried into the archived record (not resolved by archive):**
   - the task-26 peak excludes a real Telegram message burst (needs a human writing to the bot);
   - five of the six LSP servers reported connected rather than six;
   - the three legacy host folders (`opencode/`, `git/`, `go/`) are **not observable on this
     host** — it never ran the two-container layout, so they never existed and were deliberately
     not fabricated;
   - the vendor `latest` tag floats: the local tag reports `b2e3eeb0…` while the build resolved
     `9403970a…`; digest pinning is out of scope by design.
7. **Delivery state:** the work is chained on branches under the tracker
   `feat/single-robotina-container` (`feature-branch-chain`, PR per slice). Nothing is pushed and
   no PR exists. Archive did not commit, push or open a PR.

Additional recorded facts: exactly two services at close (`robotina`, `egress-proxy`), ten s6
services live, Telegram connected, `pids_limit: 1024`, `mem_limit: 6g`, `cpus: 6.0`, endpoint
loopback-only and unreachable from host and peers, `squid/` byte-identical, `HOST_DATA_DIR` guard
intact.

## 7. Destructive merge approvals or blockers

- **Destructive merge approvals:** none required — no `REMOVED` requirement and no large
  `MODIFIED` block existed; the change is additive at the spec layer.
- **Blockers:** none. No unresolved operation, no irreconcilable artifact, no missing required
  artifact, no unchecked task, and no critical verification finding. The archive proceeded without
  forcing anything.
- The `scripts/fix-permissions.ps1` deletion happened at **apply** with explicit user confirmation
  and is a revertible unit alongside the rest of the change; it is not an archive-time destructive
  write.

## 8. Move to archive

```
openspec/changes/single-robotina-container/
  -> openspec/changes/archive/2026-09-22-single-robotina-container/
```

- Destination did not exist before the move (collision check passed).
- `openspec/changes/archive/` already existed; it was not recreated destructively.
- The archive is an audit trail: no archived change was deleted or modified, and every active
  artifact was preserved byte-for-byte (move, not copy-and-rewrite).
- Post-move archived path:
  `openspec/changes/archive/2026-09-22-single-robotina-container/`
  containing `proposal.md`, `explore.md`, `design.md`, `tasks.md`, `apply-progress.md`,
  `specs/` (six domains) and this `archive-report.md`.

## 9. Files created / moved (exact paths)

Created (canonical composition):

- `openspec/specs/agent-container/spec.md`
- `openspec/specs/agent-credentials/spec.md`
- `openspec/specs/agent-identity/spec.md`
- `openspec/specs/egress-boundary/spec.md`
- `openspec/specs/opencode-endpoint/spec.md`
- `openspec/specs/state-layout/spec.md`

Created (this report):

- `openspec/changes/archive/2026-09-22-single-robotina-container/archive-report.md`
  (written at `openspec/changes/single-robotina-container/archive-report.md`, then moved with the
  change folder)

Moved (the whole change folder, 10 files + the six spec files):

- `openspec/changes/single-robotina-container/` → `openspec/changes/archive/2026-09-22-single-robotina-container/`

Deleted: none.

## 10. Memory observation IDs

Not applicable — artifact store is `openspec` (single store). No Engram observation was written or
claimed for this phase; persistence of record is the file above.

---

**Archive status: PASS.** Canonical specs established (39 requirements / 113 scenarios across six
domains), archive report written, change folder moved to
`openspec/changes/archive/2026-09-22-single-robotina-container/`, historical task bytes preserved,
running stack untouched, no commit/push/PR performed.
