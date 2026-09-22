# Apply progress — single-robotina-container

Cumulative per-slice progress. The original body below is **slice 02**; the sections for
**slices 03, 04 and 05** are appended at the end of this file, in order. Nothing in the earlier
bodies was overwritten or deleted; slice 05 reopens and re-closes two slice-04 tasks (10 and 12)
with the reason recorded.

Slice 02: **`feat/single-robotina-container-02-compose`** (chained PR #2, `feature-branch-chain`,
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

---

# Slice 03 — `feat/single-robotina-container-03-image` (image build context, tasks 5–9)

Appended to the slice-02 body above. Nothing above was modified except the header line, which
now marks this file as cumulative.

## Structured status consumed

- Native `gentle-ai.sdd-status` v2 at the start of this run: `changeName: single-robotina-container`,
  `artifactStore: openspec`, `nextRecommended: apply`, `applyState: ready`,
  `dependencies.apply: ready`, `taskProgress: 4/45`, `blockedReasons: []`, `notes: []`.
- `actionContext`: `mode: repo-local`, `workspaceRoot: C:\Users\elaze\Desktop\robotina`,
  `allowedEditRoots: ["C:\Users\elaze\Desktop\robotina"]`. **No actionContext warnings** raised
  by the status engine. Three apply-observed warnings are recorded under Findings (F1, F4, F5).
- Delivery path present in the parent prompt: chained PRs, `feature-branch-chain`, this slice
  only (tasks 5–9); `size:exception` accepted per slice by the user up to ~650 authored lines.
- Environment: `nousresearch/hermes-agent:latest` present locally; host has build egress.
  `robotina:local` did not exist before this slice.

## Completed tasks (9/45) and their persisted checkbox updates

`openspec/changes/single-robotina-container/tasks.md` was re-read after editing: tasks **1–9**
are `- [x]` (`grep -c '^- \[ \]'` = **36** remaining). Tasks 5–9 were flipped after each
verification command actually ran; the build was run once at the end, as instructed.

| Task | What was done | Verification actually run | Observed result |
| --- | --- | --- | --- |
| 5 | `robotina/Dockerfile` authored: vendor Debian base, six pins + taplo sha256, `SHELL ["/bin/bash","-o","pipefail","-c"]`, the 12 design §2.1 layers, the §2.2 drop list, the §2.3 add list, the glibc-opencode assertion, the tool-inventory assertion, the §3 preserve-then-merge gitconfig, `ENV PATH=$PATH:/opt/uv/bin` appended, no `ENTRYPOINT`/`CMD` | `docker build --check ./robotina`; `docker compose build --progress plain robotina` | `Check complete, no warnings found.`; build **exit 0**, `Image robotina:local Built` (log `/tmp/robotina-build.log`) |
| 6 | `opencode/overlay.json` copied to `robotina/overlay.json`, byte-identical | `sha256sum robotina/overlay.json` vs `git show HEAD:opencode/overlay.json \| sha256sum`; `cmp`; `git status --porcelain`; build | both `55e23123…8149`; `cmp` silent (`IDENTICAL`); status shows `?? robotina/overlay.json` + ` D opencode/overlay.json`; build exit 0 |
| 7 | `robotina/opencode-init.sh` authored (staged gentle-ai tree authoritative except `node_modules`/`package-lock.json`; non-destructive per-key merge with `permission` replaced wholesale; invalid JSON quarantined to `opencode.json.invalid-<stamp>`; atomic write via `mktemp` inside the config dir; `/workspace` warning only) | build step 17/18 runs `sh -n` on it; independent `sh -n` with the vendor Debian `dash` and with host `sh` | build exit 0; dash `sh -n` OK; host `sh -n` OK. Behavioural proof is task 27 (out of scope) |
| 8 | `robotina/healthcheck.sh` authored (credential-aware loopback probe + `pgrep -f "[e]ngram serve"`) | build exit 0; file present in image; compare with compose `healthcheck.test` | build exit 0; `ls -l /opt/robotina/healthcheck.sh` present (`-rwxr-xr-x`); compose test is `["CMD","/opt/robotina/healthcheck.sh"]`; no secret-shaped literal (`grep` → none). The `docker inspect … robotina` half is task-18-gated (see D6) |
| 9 | `opencode/` removed with `rm -rf opencode/` (plain, no `git rm`; the parent owns the index) | `docker compose config -q`; `git status --porcelain -- opencode`; `git ls-files opencode/`; `ls opencode` | `config -q` exit 0; status shows `D opencode/Dockerfile`, `D opencode/entrypoint.sh`, `D opencode/overlay.json`; `ls` → `No such file or directory`. `git ls-files` still lists the 3 index entries because the deletion is un-staged — see D5 |

## TDD Cycle Evidence

**Not applicable.** `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`,
`test_command: null`. The parent prompt did not activate strict TDD. No RED/GREEN table is
produced because no test runner exists and none may be invented.

## Files changed in this slice (authored line counts)

| File | Change | Additions | Deletions |
| --- | --- | --- | --- |
| `robotina/Dockerfile` | new | 305 | 0 |
| `robotina/opencode-init.sh` | new (exec bit set) | 81 | 0 |
| `robotina/healthcheck.sh` | new (exec bit set) | 24 | 0 |
| `robotina/overlay.json` | new path, byte-identical to the deleted `opencode/overlay.json` | 119 (rename, 0 content) | 0 |
| `opencode/Dockerfile` | deleted | 0 | 168 |
| `opencode/entrypoint.sh` | deleted | 0 | 70 |
| `opencode/overlay.json` | deleted (rename pair) | 0 | 119 (rename, 0 content) |
| `openspec/changes/single-robotina-container/tasks.md` | 5–9 `- [ ]` → `- [x]` | 5 | 5 |
| `openspec/changes/single-robotina-container/apply-progress.md` | slice-03 section + cumulative header | new section | 0 |

- **Rename-aware authored total:** 305 + 81 + 24 + 168 + 70 + 5 + 5 = **658 authored changed
  lines** (plus this section). **Raw diff if git does not pair the rename:** 529 additions /
  357 deletions = 886.
- `git status --porcelain` for the slice: ` M odd/tasks/single-robotina-container.md` (pre-existing,
  slice 02/tasks-phase work, untouched here), ` D opencode/{Dockerfile,entrypoint.sh,overlay.json}`,
  ` M openspec/…/tasks.md`, `?? robotina/`.

## Build evidence

- Command: `docker compose build --progress plain robotina` (log `/tmp/robotina-build.log`).
- Result: **exit 0**, `Image robotina:local` built (ID `f732fbca10d1`). Three builds were run in
  total: the first failed on a real defect (D1), the second was green on the design's pins, the
  third re-ran after the assertion fix (D2) and is the delivered artifact.
- Base image resolved by the build: `nousresearch/hermes-agent:latest@sha256:9403970a9c3c48c557e4afbde8b7c4aae4fd362cce293d550dc4f80f48842408`.
  The local tag still reports `b2e3eeb0c550d262a5d713788ca079e682b9acfc4a0d02ec614bc847bd1087a9`
  (slice 02's recorded digest) — see F1.
- glibc-opencode assertion output (build log line 890): `robotina: opencode 1.18.32 es el asset
  glibc x64 (mismo inode que …/opencode-linux-x64/bin/opencode)`; independently reproduced: the
  resolved binary and `opencode-linux-x64/bin/opencode` are the **same inode**, `ldd` shows
  `/lib64/ld-linux-x86-64.so.2`, and no `opencode-linux-musl*` asset exists.
- Tool-inventory assertion ran and passed; independently re-run against the image:
  `gh 2.97.0`, `jq 1.7`, `ripgrep 14.1.1`, `go 1.24.4`, `opencode 1.18.32`, `taplo 0.10.0`,
  `marksman 2026-02-08`, `codegraph 1.5.0`, `engram 1.20.0`, `gentle-ai 3.1.0`, `uv 0.11.6`,
  `node v26.5.1`, `python3 3.13.5` (Hermes venv), `R 4.5.0`, `ss iproute2-6.15.0`, `git 2.47.3`.
- `ENTRYPOINT`/`CMD` parity: vendor `Entrypoint=["/opt/hermes/docker/entrypoint-dispatch.sh"]
  Cmd=null` == `robotina:local` (no override); no `ENTRYPOINT`/`CMD` line exists in the Dockerfile.
- PATH: `/opt/hermes/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/uv/bin`
  — `/opt/uv/bin` **appended last**; `/opt/uv/bin/python3 --version` → `Python 3.13.13`.
- Image files: `/opt/robotina/{opencode-init.sh,healthcheck.sh,overlay.json}`, `sh -n` clean.

## Deviations from design

1. **D1 — marksman uses the glibc asset, not the musl one (design §2.3 claim is false).** The
   first build failed with `exit 127 / /usr/local/bin/marksman: cannot execute: required file not
   found`: `marksman-linux-musl-x64` is dynamically linked against the musl loader, so it cannot
   run on the glibc base. Design §2.3 said "the musl-static binary runs fine on glibc". Fix:
   `marksman-linux-x64` (same release tag, pinned), which is a .NET self-contained binary and
   needs `libicu` already installed by layer 1. Verified in the final image: `marksman --version`
   → `2026-02-08`.
2. **D2 — the design's glibc-opencode assertion (`! grep -qs 'ld-musl' "$bin"`) was replaced.**
   Investigated after the build because the check could not detect the reality: the resolved
   `opencode.exe` is a 185 MB Bun ELF that **embeds** `ld-musl-x86_64.so.1` /
   `ld-musl-aarch64.so.1` as strings, so the grep always matches; and under `set -e` a failing
   `! cmd` does **not** abort the build, so design §2.6 step 3 was a no-op that could never fail.
   Replaced with positive, non-vacuous checks (see Build evidence) and validated with three
   negative controls (different inode rejected; non-glibc/static binary rejected via `ldd`).
3. **D3 — the s6 layer is a single context `COPY` + installer `RUN`, not a literal `COPY s6/`.**
   `robotina/s6/**` is owned by the next slice (tasks 10–12), so a literal `COPY s6/` would make
   this slice's build unresolvable. The `RUN` installs `overlay.json`, the two scripts, and —
   when the tree exists — `s6/cont-init.d/*` into `/etc/cont-init.d` and `s6/s6-rc.d/*` into
   `/etc/s6-overlay/s6-rc.d`, with `sh -n` and `type`/script validation. This slice's build is
   green and the S4 tree will be validated by the same block when it lands.
4. **D4 — the toolchain drop/add lists are partially inaccurate about the vendor base.** Measured:
   the vendor image **already has** `procps` (ps/pgrep/pkill), `ripgrep`, `bash`, `tar`, `xz`,
   `node`, `npm`, `uv`, `git`, `curl`, `python3`; it **lacks** `jq`, `go`, `ss`, `R`, `taplo`,
   `marksman`, `codegraph`, `engram`, `gentle-ai`. `procps` and `ripgrep` are kept in the apt list
   as documented idempotent no-ops (a reinstall is a no-op and guarantees the inventory).
5. **D5 — task 9's `git ls-files opencode/` verify cannot return empty without staging.** The
   parent owns the index, so the deletion is un-staged and `git ls-files` still lists the 3
   entries. The filesystem action is done and verified by `ls` + `git status`; `docker compose
   config -q` (the task's second verify) exits 0.
6. **D6 — task 8's second verify is task-18-gated.** `docker inspect --format
   '{{.Config.Healthcheck.Test}}' robotina` needs a running container (task 18). This slice
   verified the image path and the compose declaration instead.
7. **D7 — the design-pinned `ENGRAM_VERSION`/`GENTLE_AI_VERSION` were restored after an external
   edit.** See F4.

## Findings for the parent (not fixed here — outside tasks 5–9)

- **F1 — the vendor `latest` tag is moving and `docker compose build` re-resolves it.** The base
  digest observed by this session moved `b2e3eeb0…` (slice 02's record) → `4c19daf7…` →
  `9403970a…` (final build). The local tag still reports `b2e3eeb0…`. The design accepts the
  floating tag ("digest recorded at verification"), so this is not a bug — but task 40/41 must
  record the **final** digest `9403970a…`, and slice 02's digest entry is now stale. If the intent
  was "build on the local image without network pull", that needs `docker compose build --pull=false`
  stated in the task, because the default build does pull.
- **F2 — design §2.3's marksman claim is false** (see D1). Worth a spec/design note so `verify`
  does not look for a musl marksman asset.
- **F3 — design §2.6 step 3 is invalid and was a silent no-op** (see D2). If the proof list in the
  specs quotes that grep, it should be amended to the positive check.
- **F4 — an unrecorded external edit changed the Dockerfile version pins mid-slice.** At
  13:47:51 local an editor outside every recorded agent session changed
  `ARG ENGRAM_VERSION=1.20.0 → 2.0.0` and `ARG GENTLE_AI_VERSION=3.1.0 → 3.5.0`; no session JSONL
  contains a write with those values. The design (§2.1 "kept from today"), explore §132/§186 and
  the change record all freeze **1.20.0 / 3.1.0**, so both values were restored, re-verified
  (`sha256sum -c` OK for both releases) and the final build used 1.20.0 / 3.1.0. **This is an
  integrity/race risk**: if the writer was intentional, the pin decision needs to come back as a
  user decision before `verify`/`archive`.
- **F5 — `engram --version` prints a network-update warning when offline** (`dial tcp: lookup
  api.github.com … network is unreachable`) before printing `engram 1.20.0`. Harmless for the
  build (exit 0) but it will appear in task 17/42 output; do not mistake it for a failure.
- **F6 — `Dockerfile` baseline note:** the R `languageserver` layer is the long pole (~3–4 min);
  the whole build ran ~4 min with warm apt/npm layers.
- **F7 — `hermes/skins` still does not exist** (`compose.yml` mounts `./hermes/skins`), so a
  `docker compose up` before task 13 will create a host-side empty directory at that path. That is
  task 13's territory, flagged so `up` in task 18 is not misread as an error.

## Remaining tasks (36) — exact unchecked lines from the persisted artifact

```text
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

## Workload / PR boundary

- **Slice budget vs actual:** the slice forecast S2 was ~220 lines. Actual **rename-aware
  authored = 658** (305 Dockerfile + 105 scripts + 238 deletions + 10 tasks.md); raw without
  rename pairing = 886. The user has accepted `size:exception` per slice up to ~650; 658 is at the
  boundary. It is not reducible without dishonesty: 305 Dockerfile lines are the composition the
  design enumerates section by section (each ordered layer and both assertion blocks), the 238
  deleted lines are the superseded build context the design requires removed, and the scripts are
  the required oneshot/healthcheck logic with their Spanish rationale comments.
- **Recommendation:** keep the accepted per-slice `size:exception`; no re-slicing. If a strict 400
  is preferred, the only cohesive split is 03a (Dockerfile, ~305) and 03b (scripts + `opencode/`
  removal, ~353), but 03b deletes the context that 03a's interface replaces, so the pair is best
  reviewed together.
- **PR boundary:** PR #3 targets `feat/single-robotina-container-02-compose` (or the tracker, per
  the chain) and contains exactly `robotina/{Dockerfile,overlay.json,opencode-init.sh,healthcheck.sh}`,
  the `opencode/` deletions, `openspec/changes/single-robotina-container/tasks.md` (tasks 5–9) and
  this `apply-progress.md`. The next slice (tasks 10–14, s6 supervision) is **not** started.
- No `git commit`, `git push` or PR was created — the parent owns delivery and the index.

## Verification commands run in this slice (exhaustive)

```text
docker build --check ./robotina                                          # Check complete, no warnings found.
docker compose config -q                                                 # exit 0
docker compose config --services                                         # robotina, egress-proxy
docker run --rm -i --entrypoint sh nousresearch/hermes-agent:latest -n < robotina/opencode-init.sh   # OK (Debian dash)
docker run --rm -i --entrypoint sh nousresearch/hermes-agent:latest -n < robotina/healthcheck.sh     # OK
sh -n robotina/opencode-init.sh && sh -n robotina/healthcheck.sh         # OK (host)
docker compose build --progress plain robotina                           # exit 0, Image robotina:local Built (final build)
docker run --rm --network none --entrypoint bash robotina:local -c 'command -v gh jq rg go opencode taplo marksman codegraph engram gentle-ai uv node npm python3 R pgrep pkill ss curl git'   # all resolved
docker run --rm --network none --entrypoint bash robotina:local -c '<version probes>'   # versions as recorded above
docker run --rm --network none --entrypoint bash robotina:local -c 'ldd <opencode-bin>; test <bin> -ef <x64-asset-bin>'   # glibc loader + same inode
docker run --rm --network none --entrypoint bash robotina:local -c '<negative controls>'  # different inode rejected; static binary rejected
for img in nousresearch/hermes-agent:latest robotina:local; do docker inspect --format 'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}' "$img"; done   # identical
sha256sum robotina/overlay.json; git show HEAD:opencode/overlay.json | sha256sum   # 55e23123…8149 both
cmp opencode/overlay.json robotina/overlay.json                          # identical (before opencode/ was removed)
grep -nE '(PASSWORD|TOKEN|KEY|SECRET)=[^"$]' robotina/healthcheck.sh robotina/opencode-init.sh   # no secret-shaped literal
grep -nE '^(ENTRYPOINT|CMD)' robotina/Dockerfile                         # no output (exit 1)
git status --porcelain                                                   # D opencode/*, M tasks.md, ?? robotina/
git ls-files opencode/                                                   # 3 index entries (un-staged — see D5)
```

Every static-validation invocation in this section carries `-q`, `--services` or `--volumes` on
the same line. The bare form was never run and is never written here.

---

# Slice 04 — `feat/single-robotina-container-04-supervision` (s6 tree, tasks 10–12)

Appended to the cumulative body above. Nothing above was modified.

## Structured status consumed

- Native `gentle-ai.sdd-status` v2 at the start of this run: `changeName: single-robotina-container`,
  `artifactStore: openspec`, `nextRecommended: apply`, `applyState: ready`, `dependencies.apply: ready`,
  `taskProgress: 9/45`, `blockedReasons: []`, `notes: []`.
- `actionContext`: `mode: repo-local`, `workspaceRoot: C:\Users\elaze\Desktop\robotina`,
  `allowedEditRoots: ["C:\Users\elaze\Desktop\robotina"]`. **No actionContext warnings** raised by
  the status engine. Three apply-observed findings are recorded under Findings (F1, F3, F5).
- Delivery path present in the parent prompt: chained PRs, `feature-branch-chain`,
  `feat/single-robotina-container` tracker, this slice only (tasks 10–12 plus the Dockerfile s6-block
  activation they require); `size:exception` accepted per slice by the user up to ~650 authored
  lines. No next slice started.
- Environment: `robotina:local` existed from slice 03 and was rebuilt in this slice.

## Completed tasks (12/45) and their persisted checkbox updates

`openspec/changes/single-robotina-container/tasks.md` was re-read after editing: **12 checked**
(`grep -c '^- \[x\]'`), **33 pending** (`grep -c '^- \[ \]'`). Tasks 10, 11 and 12 were flipped to
`- [x]` after their verification command (`docker compose build robotina`) actually ran and was
observed, each supported by the offline s6-rc proof below.

| Task | What was done | Verification actually run | Observed result |
| --- | --- | --- | --- |
| 10 | `robotina/s6/cont-init.d/10-robotina-state` authored: `install -d -o $(id -u hermes) -g $(id -g hermes)` for the six state dirs, the self-heal recursive chown of `/opt/data` (via `find -prune`, see D2/D4), and the explicit bounded `chown -R` on the two nested volume roots. Spanish comments. | `docker compose build --progress plain robotina` (installs + `sh -n`); plus an in-image run of the installed script under real read-only tmpfs mounts | build **exit 0**; installed mode `755`; installed sha256 == repo `37e6bd0b…7347`; script **exit 0**, `robotina: estado listo (uid=10000 gid=10000)`; the six dirs + both volume roots `10000:10000`; the two read-only mounts left `0:0`. Behavioural proof is task 22's SL6 (out of scope) |
| 11 | `robotina/s6/s6-rc.d/{opencode,engram}/**`: `type=longrun`, `run` (`#!/command/with-contenv`, `HOME=/opt/data`, scoped `XDG_*`, key rewritten to the vendor name and the robotina-named copy unset, `cd /workspace`, `exec s6-setuidgid hermes …`), `finish` with capped exponential backoff, and the §5.1 `dependencies.d` files. Spanish comments. | `docker compose build --progress plain robotina` (asserts `type`, `run`+`finish` presence, executability, `sh -n`, dependency files); plus `s6-rc-compile` + `s6-rc-db`; plus a direct execution of the `finish` scripts | build **exit 0**, `robotina: servicio opencode (longrun) validado` and `… engram (longrun) validado`; compile **exit 0**; deps resolved `opencode -> {base, opencode-init, engram}`, `engram -> {base, opencode-init}`; backoff printed `1,2,4,8,16,30,30`; healthy-run reset returns to 1; per-service counters independent; `opencode/run` missing-key guard exits 1 loudly |
| 12 | `robotina/s6/s6-rc.d/{opencode-init,opencode-ready}/**` oneshots (`opencode-ready` polls the credential-aware loopback health endpoint with the 120 s bound) and all four names registered under `robotina/s6/s6-rc.d/user2/contents.d/`. Spanish comments. | `docker compose build --progress plain robotina`; plus offline `s6-rc-compile` and `s6-rc-db contents user2` | build **exit 0**; compile **exit 0**, `s6-rc-db check` **exit 0**; `contents user2` lists exactly `engram, opencode, opencode-init, opencode-ready`; the four services appear in `list services` with the right types. The runtime `s6-rc -a list` half is task-18-gated exactly as the task says |

## TDD Cycle Evidence

**Not applicable.** `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`,
`test_command: null`. The parent prompt did not activate strict TDD. No RED/GREEN table is
produced because no test runner exists and none may be invented.

## Files changed in this slice (authored line counts)

| File | Change | Additions | Deletions |
| --- | --- | --- | --- |
| `robotina/s6/**` (22 files) | new supervision tree: 1 cont-init.d script, 4 service dirs, 7 dependency markers, 4 `user2` bundle entries, 4 `type` files, 2 `finish` scripts | 194 | 0 |
| `robotina/Dockerfile` | s6 install/validation block made unconditional and extended (dependency edges, `user2` entries, longrun `finish`) | 44 | 26 |
| `openspec/changes/single-robotina-container/tasks.md` | tasks 10–12 `- [ ]` → `- [x]` | 3 | 3 |
| `openspec/changes/single-robotina-container/design.md` | **AMENDMENT A1** in §8.1: the self-heal mechanism (`find -prune` over the four `/opt/data` mounts; `chown` has no `--one-file-system`) | 17 | 0 |
| `openspec/changes/single-robotina-container/apply-progress.md` | this cumulative section | new section | 0 |

- **Authored changed lines excluding this section: 194 + 70 + 6 + 17 = 287.** Well inside the
  400-line review budget (and the accepted per-slice ~650). No comment, doc or test was compressed
  to fit.
- The `type` files are `longrun\n`/`oneshot\n` (8 bytes, matching the vendor's trailing newline); the
  7 `dependencies.d/*` markers and the 4 `user2/contents.d/*` entries are zero-byte, exactly like
  the vendor's own (`dashboard`, `main-hermes`).
- `git status --porcelain`: ` M robotina/Dockerfile`, ` M openspec/…/tasks.md`, `?? robotina/s6/`.

## Build evidence

- Command: `docker compose build --progress plain robotina` (log `/tmp/robotina-build-04.log`).
- **Result: exit 0**, `Image robotina:local Built`. Three builds ran: the first failed on a real
  defect (D1), the second on a shell-escaping defect (D2), the third is the delivered artifact.
- Build step `[17/18]` output (the s6 install/validation block):
  `robotina: cont-init.d propio instalado` → `… servicio engram (longrun) validado` →
  `… servicio opencode-init (oneshot) validado` → `… servicio opencode-ready (oneshot) validado` →
  `… servicio opencode (longrun) validado` → `robotina: arbol s6 propio instalado y validado`.
- Installed tree in `robotina:local`: `/etc/cont-init.d/10-robotina-state` (0755); the four service
  dirs under `/etc/s6-overlay/s6-rc.d/` with `run`/`up`+`finish` at 0755 and the §5.1 dependency
  files; `/etc/s6-overlay/s6-rc.d/user2/contents.d/` with the four entries and the vendor `type`
  preserved by the merge (`cp -a` into the existing vendor dir).

## Behavioural evidence (offline, no `up`)

The first real `up` needs a live `.env` and is out of scope for this slice (the placeholder secrets
are revoked). The tree was therefore proved structurally inside the built image:

- `s6-rc-compile /tmp/db /etc/s6-overlay/s6-rc.d /package/admin/s6-overlay-3.2.3.0/etc/s6-rc/sources`
  → **exit 0** (this is the exact command `/init`'s `rc.init` runs), and `s6-rc-db -c /tmp/db check`
  → **exit 0**.
- `s6-rc-db -c /tmp/db list services` contains `opencode`, `engram`, `opencode-init`,
  `opencode-ready`; `list longruns` shows `opencode`/`engram`; `list oneshots` shows
  `opencode-init`/`opencode-ready`.
- `s6-rc-db -c /tmp/db contents user2` → exactly `engram, opencode, opencode-init, opencode-ready`.
- `s6-rc-db -c /tmp/db dependencies opencode` → `legacy-cont-init fix-attrs opencode-init engram`
  (i.e. the §5.1 `base` + `opencode-init` + `engram` edges); `dependencies engram` →
  `base + opencode-init`; `dependencies opencode-ready` → `opencode` (+ the internal
  `s6rc-oneshot-runner`).
- **`user2` activation resolved from the image itself:** s6-overlay 3.2.3.0 ships
  `/package/admin/s6-overlay-3.2.3.0/etc/s6-rc/sources/top/contents.d/user2`, and `rc.init` runs
  `s6-rc -u -t … -- change "$top"`, so the `user2` bundle is brought up. The design §5.4 primary
  (register in `user2`) is correct and the `user/contents.d` contingency should not be needed;
  task 18's runtime `s6-rc -a list` probe remains the final confirmation.
- **`finish` backoff:** with a recent start marker the sequence printed `#1 en 1s`, `#2 en 2s`,
  `#3 en 4s`, `#4 en 8s`, `#5 en 16s`, `#6 en 30s`, `#7 en 30s` (cap); with an old start marker it
  reset to `#1`; `engram` and `opencode` keep independent counters.
- **`opencode/run` guard:** with `ROBOTINA_OPENCODE_GO_API_KEY` unset it prints
  `robotina: falta ROBOTINA_OPENCODE_GO_API_KEY` and exits **1** (never starts degraded).
- **cont-init self-heal** run in-image against real read-only tmpfs mounts at `/opt/data/skins` and
  `/opt/data/skills/stack`: script **exit 0**, both read-only mounts untouched (`0:0`), every
  writable state dir and both volume roots `10000:10000`.
- **`s6-setuidgid`/`s6-rc` are not on the bare image PATH** (`/command` is not in the `docker run
  --entrypoint sh` PATH). `/init` prepends `/command` and exports it (verified in `/init`), and
  `with-contenv` propagates the container environment to services — the vendor's own
  `dashboard/run` relies on the same mechanism, so the unqualified `s6-setuidgid` in our run
  scripts resolves in service context. This is why the build-time validation only needs `sh -n`.

## Deviations from design

1. **D1 — the dependency-file assertion path must include `dependencies.d/`.** The first build
   failed on `test -f "$src/opencode-init/base"`; the §5.1 edge is the marker file
   `opencode-init/dependencies.d/base`. Fixed; the third build validated all seven edges. Design
   §5.1/§5.5 name the services, not the file paths, so no design statement changes.
2. **D2 — `10-robotina-state` cannot use `chown --one-file-system`.** Measured in the image:
   coreutils `chown --help` has **no** `one-file-system` option (0 matches). A plain
   `chown -R /opt/data` would descend into the read-only binds and abort the start. The self-heal
   is therefore implemented as `find /opt/data \( -path … \) -prune -o -exec chown …`, which is a
   faithful realization of design §8.1 step 2's intent (make a fresh tree writable, never abort on
   a mount). **Recorded as design §8.1 AMENDMENT A1**, because it corrects the literal `chown -R`
   statement the design carried.
3. **D3 — the Dockerfile s6 block is no longer conditional.** Slice 03's D3 deliberately guarded it
   because `robotina/s6/**` did not exist. Task 10–12's parent brief required the block to actually
   run, so it now `test -d`s both `s6/cont-init.d` and `s6/s6-rc.d`, asserts the seven dependency
   edges and the four `user2` entries, and (for longruns) the `finish` script, in addition to the
   existing `type`/script/executability/`sh -n` assertions. No other image restructuring.
4. **D4 — the self-heal prune list has four entries, not two.** Design §8.1 names the two nested
   volumes; the compose layout also has **two read-only binds under `/opt/data`**
   (`/opt/data/skins`, `/opt/data/skills/stack`). All four are pruned. Found by inspecting
   `compose.yml`, then proven with real read-only mounts (F4). Covered by AMENDMENT A1.
5. **D5 — tasks 10–12 runtime halves are task-18-gated by their own text.** This slice completed
   them on the build plus the offline `s6-rc-compile`/`s6-rc-db` proof (stronger than checking file
   presence); the `docker compose exec robotina s6-rc -a list` observation stays with the first real
   `up` (task 18), which is out of scope.

## Findings for the parent (not fixed here — outside tasks 10–12)

- **F1 — the parent's “the vendor image already ships `/etc/gitconfig`” is not observed.** The
   vendor base has **no** `/etc/gitconfig` (build log step 15: `robotina: la base vendor no trae
   /etc/gitconfig; no hay nada que preservar`); the built `robotina:local` gets it from Dockerfile
   layer 9. The preserve-then-merge branch is therefore a no-op today. Not a defect, but the fact
   as stated should be corrected in the parent's notes / task 41's record.
- **F2 — `user2` is proven activated by s6-overlay 3.2.3.0** (see Behavioural evidence). Design
   §5.4's contingency (also register in `user/contents.d/`) should not be applied; leave it as the
   documented fallback until task 18 confirms at runtime.
- **F3 — measured CLI contracts:** `engram serve` binds `127.0.0.1:7437` by default and accepts only
   an optional positional port (no host flag), so its loopback bind is already correct;
   `opencode serve` defaults to `--hostname 127.0.0.1 --port 0`, so the run script pins
   `--port 4096` explicitly. Recorded for task 19/EP1 and the `ss -ltn` probe.
- **F4 — `/opt/data/skills/stack` is a second read-only bind under `/opt/data`** (compose mounts
   `./hermes/skills` read-only there). Any recursive ownership pass over `/opt/data` must exclude it
   (D4).
- **F5 — `chown --one-file-system` does not exist** in the image's coreutils chown. If a later slice
   reuses that idiom it will fail at runtime; the `find -prune` form is the working substitute.

## Remaining tasks (33) — exact unchecked lines from the persisted artifact

```text
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

Phases 5–9 (tasks 17–45) remain gated on the first real `up`, which needs a working `.env` with live
keys — explicitly out of scope for this slice. Task 13 (identity) is the next slice.

## Workload / PR boundary

- **Slice budget vs actual:** slice forecast S4 was ~225 authored lines; this slice authored **270
  changed lines** (194 new s6 + 70 Dockerfile + 6 checkbox) **plus this section** — inside the
  400-line review budget and the accepted per-slice `size:exception` up to ~650. No re-slicing is
  needed and nothing was compressed to fit (no comment, doc or test was deleted or restyled).
- **PR boundary:** this slice contains exactly `robotina/s6/**` (new), the s6 block of
  `robotina/Dockerfile`, `openspec/changes/single-robotina-container/tasks.md` (tasks 10–12),
  `openspec/changes/single-robotina-container/design.md` (§8.1 AMENDMENT A1) and this
  `apply-progress.md`. Targeted at the tracker branch `feat/single-robotina-container` under
  `feature-branch-chain`. Task 13 is **not** started.
- No `git commit`, `git push` or PR was created — the parent owns delivery and the index.

## Verification commands run in this slice (exhaustive)

```text
docker build --check ./robotina                                          # Check complete, no warnings found.
sh -n robotina/s6/cont-init.d/10-robotina-state                          # OK (host)
docker run --rm -i --entrypoint sh robotina:local -n < robotina/s6/cont-init.d/10-robotina-state   # OK (image dash)
sh -n <each of the 6 run/up/finish scripts>                              # OK (all)
docker compose build --progress plain robotina                           # exit 0 (final; log /tmp/robotina-build-04.log)
sha256sum /etc/cont-init.d/10-robotina-state                             # 37e6bd0b…7347 == repo
stat -c '%a %n' /etc/cont-init.d/10-robotina-state /etc/s6-overlay/s6-rc.d/{opencode,engram}/{run,finish} /etc/s6-overlay/s6-rc.d/{opencode-init,opencode-ready}/up   # all 755
ls -A /etc/s6-overlay/s6-rc.d/user2/contents.d/                          # engram opencode opencode-init opencode-ready
s6-rc-compile /tmp/db /etc/s6-overlay/s6-rc.d /package/admin/s6-overlay-3.2.3.0/etc/s6-rc/sources   # exit 0
s6-rc-db -c /tmp/db check                                                # exit 0
s6-rc-db -c /tmp/db list services | grep -E '^(opencode|engram|opencode-init|opencode-ready)$'    # 4 lines
s6-rc-db -c /tmp/db contents user2                                       # 4 names
s6-rc-db -c /tmp/db dependencies {opencode,engram,opencode-ready}        # match design §5.1
sh /etc/s6-overlay/s6-rc.d/opencode/finish 0 15   (x7, no-op sleep shim) # backoff 1,2,4,8,16,30,30
sh /etc/s6-overlay/s6-rc.d/opencode/finish 0 15  (old start marker)     # reset to 1
env -u ROBOTINA_OPENCODE_GO_API_KEY HOME=/opt/data sh /etc/s6-overlay/s6-rc.d/opencode/run   # exit 1, loud message
find /opt/data \( -path … -prune … \) -exec chown 10000:10000 {} +       # exit 0; ro mounts untouched
sh -e /etc/cont-init.d/10-robotina-state   (ro tmpfs mounts simulated)   # exit 0; state 10000:10000; ro 0:0
```

Every static-validation invocation in this section carries `-q`, `--services` or `--format` on the
same line. The bare form was never run and is never written here.

---

# Slice 05 — `feat/single-robotina-container-04-supervision` (runtime defect fix + measurement)

Appended to the cumulative body above. Nothing above was modified. This slice did **not** start a
new feature slice: it stays on the slice-04 branch and fixes two real defects the first live `up`
exposed, then runs the measurement set that was forecast-only through slice 04.

## Structured status consumed

- Native `gentle-ai.sdd-status` v2 provided by the parent for this run: `changeName:
  single-robotina-container`, `artifactStore: openspec`, `nextRecommended: apply`, `applyState:
  ready`, `dependencies.apply: ready`, `taskProgress: 12/45`, `blockedReasons: []`, `notes: []`.
- `actionContext`: `mode: repo-local`, `workspaceRoot: C:\Users\elaze\Desktop\robotina`,
  `allowedEditRoots: ["C:\Users\elaze\Desktop\robotina"]`. **No actionContext warnings** raised by
  the status engine. Two apply-observed warnings are recorded under Findings (F1, F2).
- Review-workload gate: the parent prompt carries the resolved delivery path — chained PRs,
  `feature-branch-chain`, `exception-ok` accepted per slice up to ~650 authored lines. This
  slice's authored total is **≈673 changed lines** (148 implementation + ≈525 process record;
  measured by `git diff --numstat` plus `wc -l` for the new untracked script; the process-record
  figure is self-referential and moves a few lines per edit) — **≈23 over** the ~650 approximate
  acceptance, reported rather than hidden. Implementation-only is 148, under the 400 budget.
- Branch: `feat/single-robotina-container-04-supervision`. No child subagent was launched. No
  `git commit`/`push`/PR was performed — the parent owns the index and delivery.

## Reopened tasks (persisted checkbox contract)

Two tasks that slice 04 marked `- [x]` were **defective**. They are reopened here with the reason,
fixed, re-verified at runtime, and left `- [x]` with the new evidence. The persisted tasks
artifact carries a `## Slice 05 — runtime defect fix and re-verification (apply)` section
documenting D1/D2; the checkboxes remain `- [x]` because the fix and the re-verification are done.

| Task | Why it was defective | Fix | New evidence |
| --- | --- | --- | --- |
| 12 | The oneshot `up` files were shell scripts; s6-rc executes them as **execline**, so `set -eu` became the program `set` → `unable to exec set`, `opencode-init` exited 127, and `opencode`/`engram` (its dependents) never started | Both `up` files are one-line execline invocations; the poll moved to `robotina/opencode-ready.sh`; `Dockerfile` now asserts every oneshot `up` is a single-line execline command | `s6-rc -a list` lists all four services; `s6-svstat /run/service/opencode` → `up`; `opencode listo (intentos=1)` |
| 10 | The self-heal test `test -w /opt/data` was satisfied by `hermes:hermes 0700` while `.local`, `.local/share` were root-owned and `.local/state` was absent, so the repair was skipped and Telegram failed with `Permission denied: '/opt/data/.local/state'` | `install -d -o/-g` now owns the intermediate parents and creates `.local/state`/`.cache`; the repair test covers the directories the app actually writes to | `/opt/data/.local/state` → `10000:10000`; `grep -c` for the Permission-denied/telegram-failed pair → `0`; `[Telegram] Connected to Telegram (polling mode)` |

## Newly completed tasks (19/45) and their persisted checkbox updates

`openspec/changes/single-robotina-container/tasks.md` was re-read after editing: **19 checked**
(`grep -c '^- \[x\]'` = 19), **26 pending** (`grep -c '^- \[ \]'` = 26). Tasks 17–20 and 23–25
were flipped to `- [x]` only after their verification commands were actually run (records below).
Tasks 21, 22, 26, 27, 28 and 38 were left `- [ ]` (partial or gated); tasks 13–16 (identity) were
not started and are reported, not implemented.

| Task | Verification actually run | Observed result |
| --- | --- | --- |
| 17 | `docker compose up -d --build --force-recreate robotina` then `command -v` for the 20 tools | build **exit 0**; all 20 resolve (`gh`, `jq`, `rg`, `go`, `opencode`, `taplo`, `marksman`, `codegraph`, `engram`, `gentle-ai`, `uv`, `node`, `npm`, `python3`, `R`, `pgrep`, `pkill`, `ss`, `curl`, `git`) |
| 18 | `docker compose ps`; `tr "\0" " " < /proc/1/cmdline`; `/proc/1/status`; `PATH=/command:$PATH s6-rc -a list`; `docker compose ps --format` ports | exactly `robotina` + `egress-proxy`; PID 1 = `s6-svscan -d4 -- /run/service` (no `tini`/`docker-init`); Uid/Gid `0`; 10 services incl. the four ours; no host mapping |
| 19 | credential-aware probe; same probe without `-u`; host curl; `ss -ltn` | with `-u` exit 0; without `-u` **HTTP 401** (`no_auth_probe_exit=22`) → **auth-protected**; host curl exit 7; only `127.0.0.1:4096` (plus `7437`, `8642`, DNS `127.0.0.11`) — no wildcard bind |
| 20 | `docker run --network agents curlimages/curl` control + refusal; `egress-proxy` `/dev/tcp`; network membership | `egress-proxy:3128` → `400`; `robotina:4096` → connection refused (exit 7); `/dev/tcp/robotina/4096` refused; `agents`={egress-proxy,robotina}, `egress`={egress-proxy} |
| 23 | per-process `OPENCODE_GO_API_KEY` hashes (via `s6-setuidgid hermes`); vendor-patch grep; log secret grep; `GITHUB_TOKEN` | opencode `286c7a04…`, hermes `06c38c58…` → **differ**; vendor-patch grep empty; log secret grep empty; `GITHUB_TOKEN present` |
| 24 | `mount \| grep`; `docker inspect --format` mounts; negative control; `down`/`up`; volume count | 2 `ext4` mounts; marker in `/opt/data/.engram` **absent** from the host bind; marker survived `down`/`up`; volumes = 2 |
| 25 | `/proc/<pid>/status` of the uid-10000 `opencode serve` | `CapInh/Prm/Eff/Amb = 0x0`, `CapBnd = 0x00000000000000cb`, `NoNewPrivs: 1` |

## Defects, root causes, and fixes (detail)

### D1 — s6 oneshot `up` files were not execline (reopens task 12)

- **Observed log:** `s6-rc-oneshot-run: fatal: unable to exec set: No such file or directory`;
  `s6-rc: warning: unable to start service opencode-init: command exited 127`. Because `opencode`
  and `engram` depend on `opencode-init`, neither started (`s6-rc -a list` showed none of the four).
- **Proven root cause:** s6-rc runs a oneshot's `up` **as execline**, not as `sh`. Inside the
  container, `/package/admin/execline/command/execlineb …/opencode-init/up` →
  `execlineb: fatal: unable to exec set`. The old `up` files began `#!/command/with-contenv sh`,
  then comment lines, then `set -eu`; execline treats `#` as comments and takes the first
  non-comment token as the program. The vendor's `.../sources/*/up` files are each a single line
  containing an absolute executable path.
- **Fix:** `opencode-init/up` =
  `/command/with-contenv /usr/bin/env HOME=/opt/data /command/s6-setuidgid hermes /opt/robotina/opencode-init.sh`;
  `opencode-ready/up` = `/command/with-contenv /opt/robotina/opencode-ready.sh` (new image script
  with the bounded credential-aware poll). `robotina/opencode-init.sh` sets `HOME=/opt/data`
  itself. `Dockerfile` installs `opencode-ready.sh` and asserts every oneshot `up` is one command
  line, has no shebang, does not start with `set`, and starts with an existing executable
  absolute path.
- **Re-verified:** post-rebuild `s6-rc -a list` = `s6rc-oneshot-runner dashboard engram main-hermes
  opencode opencode-init opencode-ready fix-attrs legacy-cont-init legacy-services`;
  `s6-svstat /run/service/opencode` = `up (pid 210 pgid 210) …`; log sequence `opencode-init
  successfully started` → `engram` → `opencode` → `opencode-ready successfully started`, with
  `robotina: opencode listo (intentos=1)`.

### D2 — ownership self-heal too shallow (reopens task 10)

- **Observed before the fix:** `root:root /opt/data/.config`, `root:root /opt/data/.local`,
  `root:root /opt/data/.local/share`, `/opt/data/.local/state` absent; Hermes logs
  `[Telegram] Failed to connect to Telegram: [Errno 13] Permission denied: '/opt/data/.local/state'`,
  `Host gateway lock could not be opened (Permission denied: '/opt/data/.local/state')`,
  `telegram failed to connect`.
- **Proven root cause:** the repair guard `s6-setuidgid hermes test -w /opt/data` passed because
  `/opt/data` is `hermes:hermes 0700`; the root-owned children were never repaired. `install -d`
  only applied the owner to the leaf it created.
- **Fix:** `10-robotina-state` lists the intermediate parents in `install -d -o/-g` (`.config`,
  `.local`, `.local/share`, plus `.local/state` and `.cache`), and test a per-directory
  writability list (not just `/opt/data`) before the bounded `find -prune` re-own. The
  read-only-mount prune list is unchanged.
- **Re-verified:** `ls -ld` shows the five dirs `hermes:hermes`; `stat -c '%u:%g'
  /opt/data/.local/state` = `10000:10000`; `docker compose logs robotina | grep -cE
  "Permission denied: '/opt/data/.local/state'|telegram failed to connect"` = `0`;
  `[Telegram] Connected to Telegram (polling mode)` at `2026-09-22T15:18:53`.

## Runtime measurement set (previously forecast-only)

| Measurement | Raw value |
| --- | --- |
| Nested mounts (`mount \| grep -E '\.engram|\.local/share/opencode'`) | `/dev/sdd on /opt/data/.engram type ext4 (rw,relatime)` and `/dev/sdd on /opt/data/.local/share/opencode type ext4 (rw,relatime)` — neither `9p` nor `virtiofs` |
| Nested mount type (Docker) | both `volume` → `/var/lib/docker/volumes/robotina_{engram,opencode}_db/_data` |
| Negative control | marker `.robotina-probe` in the volume; host bind `hermes/.engram` empty (`find` → no entries); volume holds `.robotina-probe`, `engram.db`, `engram.db-shm`, `engram.db-wal` |
| Durability | marker survived `docker compose down` + `docker compose up -d`; `docker volume ls \| grep -cE '^robotina_(engram\|opencode)_db$'` = `2` |
| EP4 cold start | `StartedAt 18:18:31.298` → `opencode listo (intentos=1) 18:18:36.148` = **≈ 4.85 s**, bound 120 s |
| EP4 probe | credential-aware loopback probe exit `0` |
| Capabilities (uid 10000 `opencode serve`, pid 210) | `CapInh=0x0 CapPrm=0x0 CapEff=0x0 CapBnd=0x00000000000000cb CapAmb=0x0 NoNewPrivs=1` |
| `pids` at rest | `pids.current=54`, `pids.max=1024` |
| Key distinctness | opencode `286c7a0450630c7b66902cab2f3bc0e630fd928d687b0f71c5c5d11d4ceb894d`; hermes `06c38c58259c06b50c12d7e513a29202101fdc01e397fd66f13e4ce93ef559f6` → **differ** |
| Duplicate-home (SL1) | `opencode serve` (pid 210) `HOME=/opt/data`; Hermes main program (pid 187, `/opt/hermes/.venv/bin/python3 …/hermes gateway run --replace`) `HOME=/opt/data` |
| Isolation (EP2/EP3) | host `curl 127.0.0.1:4096` → exit 7; `egress-proxy` `/dev/tcp/robotina/4096` → refused; peer container control `400`, `robotina:4096` → refused (exit 7) |
| Not-ours warning (recorded) | 8 × `database directory is on a cross-VM filesystem (virtiofs/9p)` for `state.db`, `response_store.db`, `runs_idempotency.db`, `cron/executions.db`, `kanban.db`, `shared-state.db` — pre-existing Hermes state on the `/opt/data` bind, **not introduced by this change**; left unfixed by instruction |

## TDD Cycle Evidence

**Not applicable.** `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`,
`test_command: null`; the parent prompt did not activate strict TDD. No RED/GREEN table is
produced because no test runner exists and none may be invented.

## Files changed in this slice (authored line counts)

| File | Change | Additions | Deletions |
| --- | --- | --- | --- |
| `robotina/s6/s6-rc.d/opencode-init/up` | rewritten to a one-line execline invocation | 1 | 7 |
| `robotina/s6/s6-rc.d/opencode-ready/up` | rewritten to a one-line execline invocation | 1 | 20 |
| `robotina/opencode-ready.sh` | new image script: bounded credential-aware poll | 35 | 0 |
| `robotina/opencode-init.sh` | `HOME=/opt/data` forced (no inherited-HOME dependency) | 8 | 1 |
| `robotina/Dockerfile` | install + `sh -n` `opencode-ready.sh`; oneshot-`up` execline assertion; explanatory comment block | 28 | 1 |
| `robotina/s6/cont-init.d/10-robotina-state` | intermediate parents owned; meaningful per-directory repair test; comment | 38 | 8 |
| `openspec/changes/single-robotina-container/tasks.md` | slice-05 defect section + tasks 17–20/23–25 checked | 85 | 7 |
| `openspec/changes/single-robotina-container/design.md` | AMENDMENT A2 in §5.1: oneshot `up` is execline, not shell | 19 | 0 |
| `openspec/changes/single-robotina-container/apply-progress.md` | cumulative header + this section (self-referential; count is pre-edit) | 266 | 2 |
| `odd/tasks/single-robotina-container.md` | slice-05 verification-evidence section + slice/status table | 140 | 2 |

- **Implementation-only authored changed lines (the `robotina/` files): 148.** Process-record
  artifacts (`tasks.md`, `design.md`, `apply-progress.md`, `odd/tasks/…`): **≈525**. Total authored
  changed lines: **≈673** — ≈23 over the ~650 approximate per-slice acceptance, reported with a
  `size:exception` note rather than compressed (the overage is the process record: the defect
  evidence and the design amendment, not code). Implementation-only is under the 400 budget. All
  counts are `git diff --numstat` (plus `wc -l` for the new untracked `robotina/opencode-ready.sh`).
  Nothing was compressed or deleted to fit (comments, docs and tests were preserved).
- `git status --porcelain` for the slice: ` M odd/tasks/single-robotina-container.md`,
  ` M openspec/changes/single-robotina-container/tasks.md`, `?? robotina/opencode-ready.sh`,
  plus the tracked-file modifications above.

## Deviations from design

1. **D3 — design §5.1/§9.1 sketches show the oneshot `up` as `#!/command/with-contenv sh` plus a
   shell loop.** That form is invalid for s6-rc. The design's *intent* is preserved (import the
   container environment, run the file work as uid 10000 with `HOME=/opt/data`, keep the bounded
   credential-aware readiness poll); the mechanism is re-expressed as execline `up` lines plus
   image scripts. `design.md` §5.1 should record this (out of this slice's edit scope).
2. **D4 — §9.1's readiness recipe is unchanged** and remains credential-aware; the observed
   auth-protected case (401 without `-u`) means the credential-aware branch is the one that fires.
3. **D5 — the `Dockerfile` build-time assertion goes beyond design §2.6/§5.5** by rejecting a
   shell-`up` at build time. It is additive hardening for a defect class the design did not name.

## Findings for the parent (not fixed here — outside this slice)

- **F1 — the endpoint is auth-protected (HTTP 401 without `-u`).** Design §19.4's apply
  obligation asks to record this and, if so, amend EP1/EP4's recipes in
  `specs/opencode-endpoint/spec.md`. The recipes are **already credential-aware**, so no
  functional amendment is needed, but the EP1/EP4 `NOTE` text should record the observation.
  `specs/` is **outside this session's allowed edit surfaces** (`robotina/`, the two change
  artifacts, `design.md`, and the ODD file), so the edit is reported here instead of performed.
- **F2 — the in-container `robotina:4096` negative-control probe is confounded by the proxy
  environment.** With `http_proxy`/`https_proxy` set, `curl http://172.19.0.3:4096/...` is
  answered by Squid with an `ERR_ACCESS_DENIED` page and exits `0` (no `-f`). The spec scenario
  reads exit 0 as “a listening server”, which is a false positive here. The unconfounded negative
  control is the peer-container probe (connection refused, exit 7), which passed.
- **F3 — Compose process-environment precedence shadowed `.env`.** The running container's keys
  (67 bytes) match the exported shell environment, not the `.env` file (51 bytes), because
  `docker compose` gives the process environment precedence over `.env` for interpolation. The
  task-23 `.env`-reference-equality half therefore could not be asserted in this session; the
  distinctness proof (the two process hashes differ) holds regardless. Recorded, not a defect.
- **F4 — `pids_limit` forecast not yet confirmed against the pre-committed rule.** At rest
  `pids.current=54` (`pids.max=1024`); the design §16 revision rule triggers on the **peak** under
  the concurrent worst case (task 26), which was not run. At rest there is ~19× headroom. Tasks 26
  and 38 stay open.
- **F5 — tasks 13–16 (identity) are not implemented** and task 22 (which depends on them) stays
  open; this matches the parent's instruction not to expand into identity.

## Remaining tasks (26) — exact unchecked lines from the persisted artifact

```text
- [ ] 13. Author `hermes/skins/robotina.yaml` with `name: robotina` and
- [ ] 14. Author `robotina/s6/cont-init.d/20-robotina-identity`: guarded and idempotent
- [ ] 15. Rewrite `hermes/context/.hermes.md` for the merged topology: explicit identity
- [ ] 16. Rewrite `hermes/skills/opencode-server/SKILL.md` for the local server and
- [ ] 21. Verify the readiness gate holds across repeated recreations and that no
- [ ] 22. Verify the identity layers and the state-ownership behaviour at runtime (ID1, ID2,
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

## Workload / PR boundary

- **Slice budget vs actual:** **≈673 authored changed lines** measured by `git diff --numstat`
  (148 implementation + ≈525 process record) — **≈23 over** the user's ~650 approximate per-slice
  acceptance, driven by the process record (defect evidence + design amendment), not by code;
  implementation-only 148 is under the 400 budget. Recommendation: accept the overage as-is; do
  not re-slice (the two runtime defects and their proof are one cohesive work unit).
- **PR boundary:** this slice amends the slice-04 PR contents — `robotina/s6/s6-rc.d/opencode-init/up`,
  `robotina/s6/s6-rc.d/opencode-ready/up`, `robotina/opencode-ready.sh`,
  `robotina/opencode-init.sh`, `robotina/Dockerfile`, `robotina/s6/cont-init.d/10-robotina-state`
  — plus the two change artifacts and `odd/tasks/single-robotina-container.md`. Because the
  defects were introduced by slice 04, this fix belongs on the slice-04 branch, not a new slice.
- No commit, push or PR was created — the parent owns delivery and the index.

## Verification commands run in this slice (exhaustive)

```text
docker compose up -d --build --force-recreate robotina     # exit 0; log /tmp/rebuild-05.log
grep -n 'robotina: servicio … validado' /tmp/rebuild-05.log  # all four services validated
docker compose logs --tail 60 robotina | grep …             # opencode-init/engram/opencode/opencode-ready started
PATH=/command:$PATH s6-rc -a list                           # 10 services incl. our four
PATH=/command:$PATH s6-svstat /run/service/opencode        # up (pid 210 …)
pgrep -x opencode / pgrep -x engram                         # pid 210 / pid 205, uid 10000
command -v <20 tools>                                       # all resolve
docker compose ps                                           # robotina + egress-proxy
tr '\0' ' ' < /proc/1/cmdline                               # s6-svscan -d4 -- /run/service
grep -E '^(Uid|Gid)' /proc/1/status                         # 0 0 0 0
curl -fsS [-u …] -m 5 http://127.0.0.1:4096/global/health   # with -u exit 0; without -u 401
curl -m 5 -sS http://127.0.0.1:4096/global/health           # host: exit 7
ss -ltn                                                     # 127.0.0.1:4096 only
docker run --network agents curlimages/curl …               # control 400; robotina:4096 refused
docker network inspect agents/egress --format               # membership as expected
s6-setuidgid hermes sh -c 'tr \0 \n < /proc/<pid>/environ | grep ^OPENCODE_GO_API_KEY= | sha256sum'   # two differing hashes
s6-setuidgid hermes sh -c '… | grep ^HOME='                 # /opt/data for both processes
grep Cap… /proc/<pid>/status                                # CapEff 0x0, CapBnd 0xcb, NoNewPrivs 1
cat /sys/fs/cgroup/pids.current / pids.max                  # 54 / 1024
mount | grep -E '\.engram|\.local/share/opencode'          # 2 ext4 lines
docker inspect --format '{{range .Mounts}}…' robotina       # 2 volume mounts at nested targets
ls -A <HOST_DATA_DIR>/hermes/.engram                        # empty (negative control)
docker compose down && docker compose up -d                 # marker survived; 2 volumes
git grep -nE '(sed|cat|tee|cp)[^\n]*([/]opt/hermes/(bin|\.venv|docker))' -- robotina/ compose.yml   # no output
docker compose logs robotina | grep -nE '(TOKEN|KEY|PASSWORD)='                                        # no output
git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=[A-Za-z0-9_-]{8,}' -- ':!*.example' # 0
```

Every static-validation invocation in this section carries `-q`, `--services` or `--format` on the
same line. The bare form was never run and is never written here. No token or key value was ever
printed; key comparisons use `sha256sum` only.
