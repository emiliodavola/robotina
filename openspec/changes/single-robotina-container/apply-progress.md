# Apply progress — single-robotina-container

Slice: **`feat/single-robotina-container-02-compose`** (chained PR #2, `feature-branch-chain`,
tracker `feat/single-robotina-container`).
Artifact store: `openspec/`. Language: this file is English (per repository convention for
process artifacts).
Apply mode: **standard** — `openspec/config.yaml` declares `strict_tdd: false` and
`testing.runner: none`, so there is **no test runner** and no RED/GREEN cycle to record. All
proof is shell-level, per the repository's verification model.

## Structured status consumed

- Native `gentle-ai.sdd-status` v2, read-only, re-read at the start of this run:
  `changeName: single-robotina-container`, `artifactStore: openspec`,
  `nextRecommended: apply`, `applyState: ready`, `dependencies.apply: ready`,
  `taskProgress: 0/45`, `blockedReasons: []`, `notes: []`.
- `actionContext`: `mode: repo-local`, `workspaceRoot: C:\Users\elaze\Desktop\robotina`,
  `allowedEditRoots: ["C:\Users\elaze\Desktop\robotina"]`.
- **actionContext warnings:** none raised by the status engine. Two apply-observed warnings
  are recorded below (the over-broad secret grep, and the vendor `HOME=/root`).
- Delivery decision present in the parent prompt: chained PRs, `feature-branch-chain`, this
  slice only. No next slice started. No `git commit`/`push`/PR performed.
- Environment: the repaired package-local `gentle-ai` binary worked; the previously reported
  `package-local-binary-missing` blocker did not recur.

## Completed tasks (4/45) and their persisted checkbox updates

`openspec/changes/single-robotina-container/tasks.md` now shows `- [x]` for tasks **1, 2, 3, 4**
(re-read after the edit to confirm). Checkboxes were flipped as each task's verification
command was actually run and observed, not in a batch at the end.

| Task | What was done | Verification actually run | Observed result |
| --- | --- | --- | --- |
| 1 | Pre-change baseline written to `odd/tasks/single-robotina-container.md` → `## Verification evidence` | `docker compose config --services` | `egress-proxy`, `hermes`, `opencode` (exit 0) |
| 1 | " | `docker volume ls --format '{{.Name}}' \| grep -cE '^robotina_(engram\|opencode)_db$'` | **`0`** (exit 1) — expected `2`; recorded honestly (the stack never ran here, so neither named volume is instantiated) |
| 1 | " | `docker ps -a`, declared mount table from pre-change `compose.yml` | No container ever existed → PID-1 command lines and runtime mount list recorded as **unavailable**, never fabricated |
| 2 | Branch / clean-tree / secret-hygiene precondition; adaptation recorded | `git rev-parse --abbrev-ref HEAD`; `git merge-base --is-ancestor feat/single-robotina-container HEAD`; `git status --porcelain`; `git check-ignore -v .env`; `git ls-files .env` | `feat/single-robotina-container-02-compose`; `descends-from-tracker=yes`; clean tree; `.gitignore:6:.env\t.env`; no output |
| 2 | " | `git grep -nE '(TELEGRAM_BOT_TOKEN\|OPENCODE_GO_API_KEY\|GITHUB_TOKEN)=.+' -- ':!*.example'` | **28 matches, all benign** (documentation placeholders with empty values, shell variable references, the grep pattern text). Refined value-shaped grep `…=[A-Za-z0-9_-]{8,}` → no output (exit 1) |
| 3 | Vendor base digest + measured tool versions written to the same evidence section | `docker inspect --format '{{index .RepoDigests 0}}' nousresearch/hermes-agent:latest` | `nousresearch/hermes-agent@sha256:b2e3eeb0c550d262a5d713788ca079e682b9acfc4a0d02ec614bc847bd1087a9` |
| 3 | " | `docker run --rm --network none --entrypoint sh nousresearch/hermes-agent:latest -c '…'` | node `v26.5.1`, npm `11.17.0`, uv `0.11.6`, git `2.47.3`, curl `8.14.1`, python3 `3.13.5`, bash `5.2.37`; `HOME=/root`, `HERMES_HOME=/opt/data`, `hermes:x:10000:10000::/opt/data`, no `/etc/gitconfig`. The OpenCode toolchain versions are **unavailable** (merged image not built; old `opencode` image absent) and are recorded as such |
| 4 | `compose.yml` rewritten: one `robotina` service + untouched `egress-proxy` | `docker compose config -q && docker compose config --services` | exit 0; exactly `egress-proxy`, `robotina` |
| 4 | " | `git grep -n "docker.sock" -- compose.yml` | no output (exit 1) |
| 4 | " | `git grep -nE '^[[:space:]]+ports:' -- compose.yml` | no output (exit 1) |
| 4 | " | `git grep -n 'HOST_DATA_DIR:?' -- compose.yml` | 3 matches (lines 163, 167, 171) — non-empty |
| 4 | " | `git grep -n "HOST_DATA_DIR" -- compose.yml \| grep -E "/(opencode\|git\|go)"` | no output (exit 1) |

## TDD Cycle Evidence

**Not applicable.** `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`,
`test_command: null`, all three test layers `available: false`. The parent prompt did not
activate strict TDD. No RED/GREEN table is produced because no test runner exists and none may
be invented. Verification is the shell-level suite above (static `docker compose config -q`,
source greps, narrow-format `docker inspect`).

## Files changed in this slice

| File | Change | Authored lines (additions + deletions) |
| --- | --- | --- |
| `compose.yml` | rewritten (one `robotina` service; `hermes`/`opencode` blocks removed; anchors, env, mounts, limits, `NO_PROXY`, healthcheck) | 126 + 153 = **279** |
| `odd/tasks/single-robotina-container.md` | baseline + digest + measured-versions + branch/secret evidence under `## Verification evidence` | 161 + 1 = **162** |
| `openspec/changes/single-robotina-container/tasks.md` | tasks 1–4 `- [ ]` → `- [x]` | 4 + 4 = **8** |
| `openspec/changes/single-robotina-container/apply-progress.md` | new (this file) | new file |
| **Total authored changed lines (excluding this new file)** | | **≈449** |

`git diff --numstat` for the first two: `126 153 compose.yml`, `161 1 odd/…md`. `tasks.md` is
4 lines flipped in place (4 additions, 4 deletions).

## Deviations from design

1. **Task 2's branch assertion adapted (recorded, not silently failed).** The task was written
   for a single-branch flow (`→ feat/single-robotina-container`). Under `feature-branch-chain`
   this slice is on `feat/single-robotina-container-02-compose`; the adapted assertions are
   HEAD = slice branch, descends from the tracker branch (exit 0), and a clean tree before
   edits. All three hold. Recorded in the evidence section.
2. **Task 1's volume expectation could not be met and is reported as `0`, not `2`.** The stack
   was never brought up in this environment, so `robotina_engram_db` / `robotina_opencode_db`
   do not exist yet. Both names remain declared (unchanged) in `compose.yml`; the `up` that
   instantiates them is task 18, out of scope for this slice.
3. **Task 3 records measured vendor-base versions only.** The OpenCode toolchain versions are
   unobservable until `robotina/Dockerfile` exists (task 5) and the merged image is built
   (task 17) — both out of scope here. Marked unavailable instead of copied from the README
   table.
4. **`compose.yml` header/comment text updated** from "dos agentes" to the single-container
   model, because leaving the two-agent prose in place would contradict the file it documents.
   Comments remain **Spanish** (language contract). No comment was deleted to fit the budget.

## Findings for the parent (not fixed here — outside this slice)

- **F1 — the literal secret-grep recipe is unsatisfiable, pre-existing.** The assigned
  `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'`
  matches 28 benign lines in the untouched tree (documentation placeholders whose value is
  empty, shell variable references, and the grep pattern text itself). It appears in **task 2**
  (done) and **task 45** (future). Task 45 will not pass as written. Suggested later-slice fix:
  use `…=[A-Za-z0-9_-]{8,}` (value-shaped) or exclude the markdown artifacts.
- **F2 — the vendor image's `HOME` is `/root`, not `/opt/data`.** Measured on the base image.
  `compose.yml` intentionally does not set `HOME` (design §15's sketch does not either), so
  SL1's Hermes-`HOME=/opt/data` assertion depends on the vendor entrypoint or on the s6 run
  scripts (task 11) setting it. Worth confirming in the supervision slice, before task 22's
  SL1 proof runs.
- **F3 — `./robotina/` build context does not exist yet** (task 5). `docker compose config -q`
  and `--services` do not require it, so this slice's proofs pass; `docker compose build` will
  require it in the next slice.

## Remaining tasks (41) — exact unchecked lines from the persisted artifact

```text
- [ ] 5. Author `robotina/Dockerfile`: vendor Debian base, the four new version pins
- [ ] 6. Move `opencode/overlay.json` to `robotina/overlay.json`, content unchanged.
- [ ] 7. Author `robotina/opencode-init.sh` (the oneshot, runs as uid 10000): staged
- [ ] 8. Author `robotina/healthcheck.sh`: loopback health probe that is credential-aware
- [ ] 9. Remove the superseded build context: `git rm -r opencode/` (its logic is fully ported
- [ ] 10. Author `robotina/s6/cont-init.d/10-robotina-state` (runs as root, after the vendor
- [ ] 11. Author the `opencode` and `engram` longruns: `type`, `run` (both
- [ ] 12. Author the `opencode-init` and `opencode-ready` oneshots (`opencode-ready` polls the
- [ ] 13. Author `hermes/skins/robotina.yaml` with `name: robotina` and
- [ ] 14. Author `robotina/s6/cont-init.d/20-robotina-identity`: guarded and idempotent
- [ ] 15. Rewrite `hermes/context/.hermes.md` for the merged topology: explicit identity
- [ ] 16. Rewrite `hermes/skills/opencode-server/SKILL.md` for the local server and
- [ ] 17. Build the merged image and confirm the tool inventory the verification suite assumes.
- [ ] 18. Bring the stack up for the first time and confirm the container shape: exactly one
- [ ] 19. Verify the loopback-only endpoint from inside the container and the host, and record
- [ ] 20. Verify the endpoint is unreachable from every network peer and that network
- [ ] 21. Verify the readiness gate holds across repeated recreations and that no
- [ ] 22. Verify the identity layers and the state-ownership behaviour at runtime (ID1, ID2,
- [ ] 23. Verify per-process key configuration and secret hygiene (CR1–CR4): run `KEY-PROBE`
- [ ] 24. **[measurement-dependent]** Prove the nested volume-inside-bind layout positively
- [ ] 25. **[measurement-dependent]** Measure the uid-10000 opencode process's capability masks
- [ ] 26. **[measurement-dependent]** Sample the merged cgroup's `pids.current` baseline and
- [ ] 27. Verify the `opencode-init` semantics at runtime: overlay idempotency (double-run byte
- [ ] 28. Verify s6 recovery and the single-lifecycle property (AC5, AC8 amended proof).
- [ ] 29. Author `scripts/migrate-state.ps1`: per-path copy-forward **only when the
- [ ] 30. Update `scripts/export-state.sh`: header comment and the invocation prefix for the
- [ ] 31. `scripts/fix-permissions.ps1` — **undecided item, interim safe default only.**
- [ ] 32. Update `.env.example`: document both key names with no values, note the routing of
- [ ] 33. Rewrite `README.md` (Spanish) and `README.en.md` (English) **in the same commit**
- [ ] 34. Update `openspec/project.md`: services table, coupling map, repository layout,
- [ ] 35. Add the **superseded-by** note to `odd/tasks/agent-interop-http.md` (R6) without
- [ ] 36. Align the stale `OPEN ITEM` annotations in this change's own specs with the design
- [ ] 37. Conditional wording alignment: check `openspec/config.yaml`'s prose line that names
- [ ] 38. **[measurement-dependent]** Apply design §16's pre-committed adjustment rule to the
- [ ] 39. Rewrite `SECURITY.md`'s non-measured retained entries (Spanish): R1 (credential
- [ ] 40. **[measurement-dependent]** Add `SECURITY.md`'s measured evidence entries: R3's
- [ ] 41. Finalize the change record: replace the ODD file's `## Verification evidence`
- [ ] 42. Run the verification suite end to end on the final tree and record the result.
- [ ] 43. Confirm the frozen egress boundary and the mandatory-input guard survived the merge.
- [ ] 44. Confirm the rollback path is intact: both state volume names unchanged, the three
- [ ] 45. Final secret-leak audit over the whole change, including this file.
```

Phases 5–9 (tasks 17–45) are gated on the first real `up`, which needs a working `.env` with
live keys — explicitly out of scope for this slice.

## Workload / PR boundary

- **Slice budget vs actual:** forecast for S1 (`compose.yml`) was ~170 lines; the composed
  slice — compose rewrite **plus** the task 1/3 evidence the parent assigned to it — authored
  **≈449 changed lines**, over the 400-line review budget by ≈49.
- It is **not** reducible without dishonesty: the compose rewrite touches ~279 lines because
  two service blocks collapse into one and the Spanish comments document the new topology; the
  evidence is 162 lines of raw output plus the honest "unavailable" records. The rules forbid
  deleting comments, docs, or evidence to fit the budget, and one honest slicing pass was
  already taken by `sdd-tasks`.
- **Recommendation:** accept a `size:exception` for slice 02 (**`exception-ok` is not claimed;
  the parent/user owns that acceptance**), or — if the parent prefers a strict 400 — split this
  slice into two PRs: **02a** `compose.yml` only (~279) and **02b** the change-record evidence
  (~162). Both are cohesive; 02b has no runtime effect.
- **PR boundary:** PR #2 targets the tracker branch `feat/single-robotina-container` and
  contains exactly `compose.yml`, `odd/tasks/single-robotina-container.md`,
  `openspec/changes/single-robotina-container/tasks.md`, and this `apply-progress.md`. The next
  slice (`robotina/Dockerfile` + build context, tasks 5–9) is **not** started.
- No commit, push, or PR was created — the parent owns delivery.

## Verification commands run in this slice (exhaustive)

```text
docker compose config -q                                   # exit 0
docker compose config --services                           # egress-proxy, robotina (exit 0)
docker compose config --volumes                            # engram_db, opencode_db (pre-edit baseline)
git grep -n "docker.sock" -- compose.yml                   # no output (exit 1)
git grep -nE '^[[:space:]]+ports:' -- compose.yml          # no output (exit 1)
git grep -n 'HOST_DATA_DIR:?' -- compose.yml               # 3 matches (lines 163/167/171)
git grep -n "HOST_DATA_DIR" -- compose.yml | grep -E "/(opencode|git|go)"   # no output (exit 1)
git rev-parse --abbrev-ref HEAD                            # feat/single-robotina-container-02-compose
git merge-base --is-ancestor feat/single-robotina-container HEAD            # exit 0
git status --porcelain                                     # empty before edits
git check-ignore -v .env                                   # .gitignore:6:.env\t.env
git ls-files .env                                          # no output
git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'   # 28 benign matches
git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=[A-Za-z0-9_-]{8,}' -- ':!*.example'   # no output
docker inspect --format '{{index .RepoDigests 0}}' nousresearch/hermes-agent:latest   # sha256:b2e3eeb0…
docker inspect --format 'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}} …' nousresearch/hermes-agent:latest
docker run --rm --network none --entrypoint sh nousresearch/hermes-agent:latest -c '…version probes…'
```

Every static-validation invocation in this slice, in this file, and in the artifacts written
carries `-q`, `--services` or `--volumes` on the same line. The bare form was never run and is
never written here.
