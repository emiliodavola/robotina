# Apply progress — single-robotina-container

Cumulative per-slice progress. The original body below is **slice 02**; the sections for
**slices 03, 04, 05, 06 and 07** are appended at the end of this file, in order. Nothing in the earlier
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

---

# Slice 06 — `feat/single-robotina-container-05-identity` (identity layer, tasks 13–16)

Appended to the cumulative body above. Nothing above was modified except the header line, which now
marks this file as cumulative through slice 06.

## Structured status consumed

- Native `gentle-ai.sdd-status` v2 provided by the parent: `changeName: single-robotina-container`,
  `artifactStore: openspec`, `nextRecommended: apply`, `applyState: ready`, `dependencies.apply: ready`,
  `taskProgress: 19/45`, `blockedReasons: []`, `notes: []`.
- `actionContext`: `mode: repo-local`, `workspaceRoot: C:\Users\elaze\Desktop\robotina`,
  `allowedEditRoots: ["C:\Users\elaze\Desktop\robotina"]`. **No actionContext warnings** raised by
  the status engine. Two apply-observed findings are recorded under Findings (F1, F2).
- Review-workload gate: the parent prompt carries the resolved delivery path — chained PRs,
  `feature-branch-chain`, tracker `feat/single-robotina-container`, current slice branch
  `feat/single-robotina-container-05-identity`, `exception-ok` accepted per slice (~650 authored
  lines). `tasks.md`'s forecast (`Decision needed before apply: Yes`, `Chained PRs recommended:
  Yes`, `400-line budget risk: High`) is satisfied by that resolved path. This slice implements
  tasks 13–16 only.
- `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`, `test_command: null`; the
  parent prompt did not activate strict TDD.
- No child subagent was launched. No `git commit`/`git push`/PR was performed — the parent owns the
  index and delivery. No token or key value was ever printed.

## Completed tasks (23/45) and their persisted checkbox updates

`openspec/changes/single-robotina-container/tasks.md` was re-read after editing: **23 checked**
(`grep -c '^- \[x\]'`), **22 pending** (`grep -c '^- \[ \]'`). Tasks 13, 14, 15 and 16 were flipped
to `- [x]` only after their verification commands were actually run and observed.

| Task | What was done | Verification actually run | Observed result |
| --- | --- | --- | --- |
| 13 | `hermes/skins/robotina.yaml` authored from the vendor-bundled sample schema (`name` / `description` / `branding` / `tool_prefix`; missing keys inherit `default`) | `git ls-files hermes/skins/robotina.yaml`; `git ls-files --others --exclude-standard`; `git check-ignore -v`; `grep -nE "^(name: robotina| +agent_name: robotina)$"` | `git ls-files` **empty** (untracked; index owned by the parent — see D1); `--others` prints `hermes/skins/robotina.yaml`; check-ignore exit **1** (not ignored); grep → exactly **2 matches** (line 16 `name: robotina`, line 21 `  agent_name: robotina`) |
| 14 | `robotina/s6/cont-init.d/20-robotina-identity` authored: guarded, idempotent, missing-config → loud warning + exit 0, otherwise `display.skin=robotina` as uid 10000 with `HOME=/opt/data`; ordered after the vendor hooks; Spanish comments; documented Python/YAML fallback | `docker compose build robotina`; in-image `sh -n`; the live recreate; idempotency re-run; missing-config branch in a throwaway container | build **exit 0**, `cont-init.d propio instalado`, installed `/etc/cont-init.d/20-robotina-identity` 0755, image `sh -n` OK; startup ran it **after** `01-hermes-setup`/`015-supervise-perms`/`02-reconcile-profiles`/`10-robotina-state` and printed `✓ Set display.skin = robotina …` + `robotina: skin de identidad 'robotina' seleccionada (display.skin)`, exit 0; re-run → rc 0, no write; missing config → warning line + rc 0 |
| 15 | `hermes/context/.hermes.md` rewritten for the merged topology (identity `robotina`, one container, local endpoint, `gh` + `GITHUB_TOKEN` present, `404`→token permissions); English | the three task greps; in-container `grep -c robotina /workspace/.hermes.md` | grep 1 non-empty (lines 1,6,7 …); grep 2 (banned two-container phrases) **no output**, rc 1; grep 3 → line 14 `http://127.0.0.1:4096`; container file shows **3** `robotina` matches |
| 16 | `hermes/skills/opencode-server/SKILL.md` rewritten for the local server (loopback, CLI present, `OPENCODE_SERVER_PASSWORD` recipe kept) and `hermes/skills/github-private-repos/SKILL.md` for the retired credential split; English | both task greps; in-container skill greps | grep B (isolation claims) **no output**, rc 1; grep A has **one residual match** `SECURITY.md:302` (see F1, outside this slice's edit surfaces); in-container `opencode-server` has **6** `127.0.0.1:4096`, `github-private-repos` has **3** `GITHUB_TOKEN` |

## Runtime identity evidence (the observable, not the file)

Recreate with the new image: `docker compose up -d --force-recreate robotina` → exit 0, container
`healthy`.

| Probe | Command | Observed result |
| --- | --- | --- |
| Active skin resolves to `robotina` (vendor CLI) | `s6-setuidgid hermes env HOME=/opt/data hermes skin list` | `* robotina  user  Identity skin for the robotina stack …` (star on `robotina`) |
| `display.skin` reads back as the `hermes` user | `s6-setuidgid hermes env HOME=/opt/data hermes config get display.skin` | `robotina` |
| Persisted key | `grep -niE "skin" /opt/data/config.yaml` | `1965:  skin: robotina` |
| Engine resolves the displayed name | `init_skin_from_config(load_config())` + `get_active_skin()` in the vendor venv | `active_skin = robotina`, `branding.agent_name = robotina`, `tool_prefix = '┊'` |
| Skin reaches the container **read-only** | `ls -l /opt/data/skins/robotina.yaml`; `touch`; `grep " /opt/data/skins" /proc/self/mountinfo` | present; `touch` → `Read-only file system`, rc 1; mount source `/Users/elaze/Desktop/robotina/hermes/skins` options `ro,noatime` |
| Context reaches the always-loaded path | `grep -c robotina /workspace/.hermes.md`; `grep -n http://127.0.0.1:4096` | `3`; line 14 |
| Stack still healthy | `docker compose ps`; `PATH=/command:$PATH s6-rc -a list`; `docker compose logs robotina \| grep -i telegram` | `robotina` + `egress-proxy` both `(healthy)`; 10 services incl. our four; `[Telegram] Connected to Telegram (polling mode)` |

## TDD Cycle Evidence

**Not applicable.** `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`,
`test_command: null`; the parent prompt did not activate strict TDD. Verification is the shell-level
suite above (source greps, vendor-CLI output, `/proc/self/mountinfo`).

## Files changed in this slice (authored line counts)

| File | Change | Additions | Deletions |
| --- | --- | --- | --- |
| `hermes/skins/robotina.yaml` | new (identity skin, read-only mount) | 21 | 0 |
| `robotina/s6/cont-init.d/20-robotina-identity` | new (guarded, idempotent `display.skin` selection) | 63 | 0 |
| `hermes/context/.hermes.md` | rewritten for the merged topology | 32 | 24 |
| `hermes/skills/opencode-server/SKILL.md` | rewritten for the local server | 22 | 26 |
| `hermes/skills/github-private-repos/SKILL.md` | rewritten for the retired credential split | 43 | 37 |
| `openspec/changes/single-robotina-container/tasks.md` | tasks 13–16 `- [ ]` → `- [x]` | 4 | 4 |
| `openspec/changes/single-robotina-container/design.md` | **AMENDMENT A3** in §11: the vendor `SOUL.md` persona layer | 6 | 0 |
| `openspec/changes/single-robotina-container/apply-progress.md` | this cumulative section + header | new section | 0 |

- **Implementation-only authored changed lines: 21 + 63 + 56 + 48 + 80 = 268** — inside the 400-line
  review budget and well inside the accepted per-slice `size:exception` (~650).
- Process-record lines (`tasks.md` 8 + `design.md` 6 + this section): the section is
  self-referential and moves a few lines per edit.
- `git status --porcelain` for the slice: ` M hermes/context/.hermes.md`,
  ` M hermes/skills/github-private-repos/SKILL.md`, ` M hermes/skills/opencode-server/SKILL.md`,
  `?? hermes/skins/`, `?? robotina/s6/cont-init.d/20-robotina-identity`, plus the two changed change
  artifacts.
- Nothing was compressed or deleted to fit the budget (comments, docs and evidence preserved).

## Deviations from design

1. **D1 — task 13's `git ls-files` literal check cannot return non-empty without staging.** The
   parent owns the index and prior slices did not stage (slice 03's D5), so the new skin file is
   untracked: `git ls-files` prints nothing. The observable the task intends is proven by
   `git ls-files --others --exclude-standard hermes/skins/robotina.yaml` (prints the file) plus
   `git check-ignore -v` (exit 1 → not ignored). Same deviation class as D5; no design statement
   changes.
2. **D2 — the skin file's comments are English, the cont-init's are Spanish.** The parent's language
   contract makes `hermes/` context/skills English; the skin lives in the same agent-facing tree, so
   it follows that convention. The cont-init is shell in `robotina/`, so its comments stay Spanish
   per the repository rule. No design statement changes.
3. **D3 — design §11.1's "derive the schema from a vendor-bundled sample skin" resolved to a real
   file**, `/opt/hermes/skills/autonomous-ai-agents/hermes-agent/templates/skin.yaml`, and the vendor
   key for the displayed name **is** `branding.agent_name`, so §11.1's fallback ("if the vendor key
   differs, use the vendor key") was not needed. No correction required.
4. **D4 — design §11.2's `hermes config set display.skin robotina` needed no `--force`.** Verified
   live: the vendor CLI accepted the key and wrote `skin: robotina`. The documented Python/YAML
   fallback remains unused, as designed.

## Findings for the parent (not fixed here — outside tasks 13–16)

- **F1 — task 16's verify-A cannot be fully clean within this slice's edit surfaces.** The grep
  `grep -rniE "sin credencial|…" hermes/ SECURITY.md` still matches `SECURITY.md:302`:
  ``Verificado: con el password puesto, `sin credencial -> 401`, `con credencial -> 200`,``.
  `SECURITY.md` is a documentation-slice file (tasks 39–40, outside this run's allowed edit surfaces:
  `hermes/`, `robotina/`, the change artifacts, the ODD file). The `hermes/` half of the grep is now
  clean; the parent should close the `SECURITY.md` half in the docs slice.
- **F2 — the vendor SOUL.md persona layer (design AMENDMENT A3).** `/opt/data/SOUL.md` is
  vendor-seeded (`$HOST_DATA_DIR/hermes/SOUL.md`, outside the repo) and still opens
  `You are Hermes Agent, built by Nous Research.` The displayed name is `robotina` (skin +
  `display.skin`) and `.hermes.md` carries the explicit identity statement, so ID3's observable
  holds; the residual vendor persona sentence is host state this change does not edit. Reported for
  `verify`/`archive`; a follow-up could customize SOUL.md or add an identity key if the persona
  sentence must also change.
- **F3 — the identity artifacts split across two delivery mechanisms.** `hermes/skins/robotina.yaml`
  and `hermes/context/.hermes.md` are bind mounts (live on edit; only a recreate is needed), while
  `robotina/s6/cont-init.d/20-robotina-identity` is image-shipped (needs a rebuild). This slice did
  both (build + `--force-recreate`) and proved each at runtime.

## Remaining tasks (22) — exact unchecked lines from the persisted artifact

```text
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

Task 22 (the runtime identity + state-ownership verification batch) now has its identity half
implementable but stays open because it also covers the SL6 ownership scenarios and was not assigned
to this slice; it is **not** started here.

## Workload / PR boundary

- **Slice budget vs actual:** slice forecast S5 (identity) was ~275 authored lines; this slice
  authored **268 implementation lines** plus the process record (checkboxes + design amendment + this
  section) — inside the 400-line budget and the accepted per-slice `size:exception`.
- **PR boundary:** this slice contains exactly `hermes/skins/robotina.yaml` (new),
  `hermes/context/.hermes.md`, `hermes/skills/opencode-server/SKILL.md`,
  `hermes/skills/github-private-repos/SKILL.md`,
  `robotina/s6/cont-init.d/20-robotina-identity` (new),
  `openspec/changes/single-robotina-container/tasks.md` (tasks 13–16),
  `openspec/changes/single-robotina-container/design.md` (§11 AMENDMENT A3) and this
  `apply-progress.md`. Targeted at the tracker branch `feat/single-robotina-container` under
  `feature-branch-chain`. Tasks 17+ and the docs slices are **not** started.
- No `git commit`, `git push` or PR was created — the parent owns delivery and the index.

## Verification commands run in this slice (exhaustive)

```text
git rev-parse --abbrev-ref HEAD                                  # feat/single-robotina-container-05-identity
git status --porcelain                                           # clean before edits
git ls-files hermes/skins/robotina.yaml                          # empty (untracked; see D1)
git ls-files --others --exclude-standard hermes/skins/robotina.yaml   # hermes/skins/robotina.yaml
git check-ignore -v hermes/skins/robotina.yaml                   # no output, exit 1
grep -nE "^(name: robotina| +agent_name: robotina)$" hermes/skins/robotina.yaml   # 2 matches
sh -n robotina/s6/cont-init.d/20-robotina-identity               # OK (host)
docker compose build robotina                                    # exit 0 (log /tmp/robotina-build-05-id.log)
docker run --rm --entrypoint sh robotina:local -c 'ls -l /etc/cont-init.d/20-robotina-identity && sh -n …'   # 0755; sh -n OK
docker compose up -d --force-recreate robotina                   # exit 0 (log /tmp/robotina-up-05-id.log)
docker compose logs robotina | grep -iE "20-robotina-identity|display.skin"   # ran after vendor hooks; Set display.skin = robotina; exit 0
docker compose exec robotina sh /etc/cont-init.d/20-robotina-identity         # rc 0, no write (guard)
docker run --rm --entrypoint sh robotina:local -c '<missing-config variant>'  # loud warning, rc 0
s6-setuidgid hermes env HOME=/opt/data hermes skin list          # * robotina user …
s6-setuidgid hermes env HOME=/opt/data hermes config get display.skin         # robotina
grep -niE "skin" /opt/data/config.yaml                           # 1965: skin: robotina
s6-setuidgid hermes env HOME=/opt/data PYTHONPATH=/opt/hermes /opt/hermes/.venv/bin/python -c '<engine probe>'   # active_skin=robotina agent_name=robotina
ls -l /opt/data/skins/robotina.yaml; touch /opt/data/skins/robotina.yaml      # present; Read-only file system (rc 1)
grep " /opt/data/skins" /proc/self/mountinfo                     # source = repo hermes/skins, options ro
grep -c robotina /workspace/.hermes.md; grep -n http://127.0.0.1:4096 /workspace/.hermes.md   # 3; line 14
grep -niE "robotina" hermes/context/.hermes.md                   # non-empty
grep -rniE "sibling container|contenedor hermano|http://opencode:4096|own container|propio contenedor" hermes/context/.hermes.md   # no output (rc 1)
grep -n "http://127.0.0.1:4096" hermes/context/.hermes.md        # line 14
grep -rniE "sin credencial|no github credential|no tiene token|delegate to opencode|delegar a opencode|does not run inside this container|no esta instalado|no rewrite" hermes/ SECURITY.md   # 1 match: SECURITY.md:302 (F1)
grep -rniE "claves? (estan |están )?aislad|keys? are isolated|aisladas por proceso|isolated per process|no puede leer la clave del otro|cannot read the other" README.md README.en.md SECURITY.md hermes/   # no output (rc 1)
docker compose ps --format 'table {{.Name}}\t{{.Status}}'        # robotina + egress-proxy (healthy)
docker compose exec robotina sh -c 'PATH=/command:$PATH s6-rc -a list'   # 10 services incl. our four
docker compose logs robotina | grep -i telegram                  # Connected to Telegram (polling mode)
```

Every static-validation invocation in this section carries `-q`, `--services` or `--format` on the
same line; the bare `docker compose config` form was never run and is never written here. No token
or key value was ever printed.

---

# Slice 07 — `feat/single-robotina-container-06-scripts` (migration helper + scripts, tasks 29–32)

Appended to the cumulative body above. Nothing above was modified. The file-internal numbering
continues at **slice 07** because the previous section — authored on branch
`feat/single-robotina-container-05-identity` — already used the heading `Slice 06`; the branch
name for this run is `feat/single-robotina-container-06-scripts`.

## Structured status consumed

- Native `gentle-ai.sdd-status` v2 at the start of this run: `changeName: single-robotina-container`,
  `artifactStore: openspec`, `nextRecommended: apply`, `applyState: ready`,
  `dependencies.apply: ready`, `taskProgress: 23/45`, `blockedReasons: []`, `notes: []`.
- `actionContext`: `mode: repo-local`, `workspaceRoot: C:\Users\elaze\Desktop\robotina`,
  `allowedEditRoots: ["C:\Users\elaze\Desktop\robotina"]`. **No actionContext warnings** raised by
  the status engine. Two apply-observed warnings are recorded under Findings (F1, F2).
- Delivery decision present in the parent prompt: chained PRs, `feature-branch-chain`, this slice
  only (tasks 29–32); `size:exception` accepted per slice by the user up to ~650 authored lines.
- Apply mode: **standard** — `openspec/config.yaml` declares `strict_tdd: false`,
  `testing.runner: none`, `test_command: null`.

## Completed tasks (27/45 cumulative, 4/4 of this slice) and their persisted checkbox updates

`openspec/changes/single-robotina-container/tasks.md` re-read after editing: tasks **29, 30, 31,
32** are `- [x]` (`grep -c '^- \[ \]'` = **18** remaining). Each checkbox was flipped after that
step's verification command actually ran and was observed.

| Task | What was done | Verification actually run | Observed result |
| --- | --- | --- | --- |
| 29 | `scripts/migrate-state.ps1` authored: per-path copy-forward (create tree, never overwrite a file), `node_modules/` skipped in the legacy opencode folder, `package-lock.json` copied, no delete/move primitive, copied/skipped summary, closing assertion (three legacy folders intact; `opencode`/`git` non-empty), Spanish comments, optional `-DataDir` override for synthetic fixtures | synthetic fixture under a Windows temp dir (never the real `HOST_DATA_DIR`): newer destination file + legacy `opencode` (with `node_modules` + `package-lock.json`), `git`, `go`, empty `hermes/`; migration run **twice** | run 1: `2 copiados, 1 omitidos, 1 node_modules omitido`; run 2: `0 copiados, 3 omitidos, 1 node_modules omitido`; both exit 0; destination `config.json` hash `7d052acf…` **identical before/after both runs**; `hermes/.config/opencode/package-lock.json` copied; destination `node_modules` **absent**; `hermes/go` **absent**; legacy tree intact |
| 29 | " | `grep -niE "Remove-Item\|Move-Item\|rm -rf\|Remove-Item -Recurse" scripts/migrate-state.ps1` | no output (exit 1) |
| 29 | " | `HOST_DATA_DIR=$(grep -m1 '^HOST_DATA_DIR=' .env …); ls -ld "$HOST_DATA_DIR/opencode" "$HOST_DATA_DIR/git" "$HOST_DATA_DIR/go"` | **all three absent** (exit 2) — recorded honestly: `HOST_DATA_DIR = C:\Users\elaze\Desktop\robotina-data` contains only `backups`, `hermes`, `workspace`; the two-container stack never ran here, so the legacy layout never existed on this host. **Not observable on this host**; proven instead on the synthetic fixture above |
| 29 | " | `ls -d "$HOST_DATA_DIR/hermes/go"` (must fail) | absent on the fixture (exit 2) and on the host (no `go` anywhere) |
| 30 | `scripts/export-state.sh` header and invocation prefix updated to the merged container name; loopback endpoint and `OPENCODE_SERVER_PASSWORD` auth path unchanged | `grep -n OPENCODE_SERVER_PASSWORD scripts/export-state.sh` | 2 matches (lines 29 and 32) — non-empty |
| 30 | " | `grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/` | **3 residual hits, all in docs**: `README.md:190`, `README.en.md:198`, `SECURITY.md:360`. `scripts/` and `hermes/` are clean. Reported as **pending-on-docs** (next slice owns the README pair and `SECURITY.md`) |
| 30 | " | `sh -n scripts/export-state.sh`; `grep -n 127.0.0.1:4096 scripts/export-state.sh` | `sh -n` OK; loopback line 34 present |
| 31 | `scripts/fix-permissions.ps1` kept (not deleted, not renamed, not moved); header rewritten to say it is **superseded by the container-side cont-init and no longer part of setup**; `$Subdirs` narrowed to `@('backups','workspace')`; the two volumes kept; the stale `user:` line removed | `git ls-files scripts/fix-permissions.ps1` | prints the path (exit 0) — the file still exists |
| 31 | " | `grep -rniE "fix-permissions" README.md README.en.md SECURITY.md` | **8 residual hits, all docs** (README.md:63/120/259, README.en.md:71/128/270, SECURITY.md:479/484). `README.md:120` / `README.en.md:128` are still **numbered setup steps**, and `SECURITY.md:479` still lists `opencode, go, backups, git` as targets. Reported as **pending-on-docs** (task 33 rewrites the README pair, task 39 the `SECURITY.md` text) |
| 31 | " | `grep -nE "Subdirs\|Volumes" scripts/fix-permissions.ps1`; `[Parser]::ParseFile` | `$Subdirs = @('backups','workspace')`, `$Volumes = @('robotina_engram_db','robotina_opencode_db')`; parse OK for both PS1 files |
| 32 | `.env.example` rewritten: both key names documented with **empty values**, the two-key routing explained (vendor-expected name carries the Hermes value; `ROBOTINA_OPENCODE_GO_API_KEY` carries the OpenCode value), and the `docker inspect` note replaced with the narrow `--format` rule | `git grep -n "HERMES_OPENCODE_GO_API_KEY\|OPENCODE_GO_API_KEY" -- .env.example compose.yml` | both names present in `.env.example` (lines 17–18, no value) and in `compose.yml` (126/128/130) |
| 32 | " | whole-file audit `grep -nE '=[^[:space:]]+' .env.example` | no non-empty values (exit 1) |
| 32 | " | `git grep -nE '(TELEGRAM_BOT_TOKEN\|OPENCODE_GO_API_KEY\|GITHUB_TOKEN)=.+' -- ':!*.example'` | non-empty, **all benign and pre-existing** (see F1) — `README*.md`/`SECURITY.md` placeholder recipes (`NAME=` + comment), shell references in `design.md`/`explore.md`/specs, and `robotina/s6/s6-rc.d/opencode/run:24`. No new leak; `.env.example` is excluded by `:!*.example` |

## TDD Cycle Evidence

**Not applicable.** `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`,
`test_command: null`. The parent prompt did not activate strict TDD. No RED/GREEN table is produced
because no test runner exists and none may be invented. Verification is the shell/PowerShell suite
above plus the synthetic-fixture behavioural proof for task 29.

## Files changed in this slice (authored line counts)

| File | Change | Additions | Deletions |
| --- | --- | --- | --- |
| `scripts/migrate-state.ps1` | new | 134 | 0 |
| `scripts/fix-permissions.ps1` | header + target list + tail rewritten | 16 | 13 |
| `.env.example` | header expanded with the two-key routing and the `--format` rule | 16 | 3 |
| `scripts/export-state.sh` | header + invocation prefix | 2 | 2 |
| `openspec/changes/single-robotina-container/tasks.md` | 29–32 `- [ ]` → `- [x]` | 4 | 4 |
| `openspec/changes/single-robotina-container/apply-progress.md` | this section (cumulative append) | new section | 0 |

- **Implementation authored total (excluding process artifacts):** 134 + 16 + 13 + 16 + 3 + 2 + 2
  = **186 changed lines** — well inside the 400-line budget and the accepted per-slice
  `size:exception`. With the 8 process lines in `tasks.md`, the reviewable delta is **194**.
- `git diff --numstat`: `.env.example 16 3`, `scripts/fix-permissions.ps1 16 13`,
  `scripts/export-state.sh 2 2`, `tasks.md 4 4`; `scripts/migrate-state.ps1` is new/untracked (134).

## Deviations from design

1. **D1 — `migrate-state.ps1` gained an optional `-DataDir` parameter the design did not name.**
   The documented mode still reads `HOST_DATA_DIR` from `.env` (design §12's only documented
   invocation). The parameter exists so the migration can be exercised against a synthetic fixture
   without touching the real host state — which is the only way to verify task 29 on a host where
   the legacy folders never existed. The default behaviour, the copy-forward semantics and the
   never-delete invariant are unchanged.
2. **D2 — design §12's `node_modules` skip is implemented as "any directory named `node_modules`
   at any depth", not just the top level.** The design calls it a rebuildable cache; the plugin
   tree can nest, so the broader match is the faithful reading of "skipped inside the legacy
   opencode folder". No observable change for the common top-level case.
3. **D3 — the `-DataDir` fixture run is the *real* task-29 proof, and the literal host greps are
   reported as not-observable.** See Findings F2. The task's host-side `ls -ld` over
   `opencode`/`git`/`go` cannot pass on this host because the layout was never present; the
   invariant it checks (the migration must not remove or empty the legacy folders) is proven on the
   fixture instead.

## Findings for the parent (not fixed here — outside tasks 29–32)

- **F1 — the literal secret-grep recipe is still unsatisfiable and pre-existing** (carried from
  slice 02's F1). `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'`
  matches only benign lines: documentation placeholders whose value is empty followed by a comment,
  shell variable references in `design.md`/`explore.md`/the specs, the `robotina/s6/s6-rc.d/opencode/run:24`
  export, and the `odd/`+`apply-progress` recipe text. Task 45 will need the value-shaped refinement
  (`…=[A-Za-z0-9_-]{8,}`) to close clean. Not a leak, and **not introduced by this slice**.
- **F2 — the legacy `opencode/`, `git/`, `go/` folders do not exist on this host.**
  `HOST_DATA_DIR = C:\Users\elaze\Desktop\robotina-data` holds only `backups`, `hermes`,
  `workspace`. This is expected: the two-container stack never ran here, so the migration scenario is
  hypothetical on this host. Task 29's host greps are therefore recorded as **not observable on this
  host, the legacy layout never existed here** — the folders were neither invented nor created to
  make a grep pass, and the migration was proven against a synthetic fixture instead.
- **F3 — task 30's and task 31's verification greps are both blocked by the docs slice.**
  The residual `docker compose exec opencode` hits (`README.md:190`, `README.en.md:198`,
  `SECURITY.md:360`) and the `fix-permissions` hits (`README.md:120`/`README.en.md:128` are still
  numbered setup steps; `SECURITY.md:479` still lists `opencode, go, backups, git`) are in
  `README.md`, `README.en.md` and `SECURITY.md` — files rewritten by **task 33 and task 39**, outside
  this slice's allowed edit surfaces. Both tasks are marked complete with this portion explicitly
  **pending-on-docs**; they must be re-run after the docs slice to close clean.
- **F4 — the container is up with live keys and was not touched.** No `docker` command in this
  slice restarted, recreated or inspected the running stack; the fixture ran entirely under the host
  temp dir with a standalone `pwsh` process. Telegram connectivity and the two healthy containers
  are unaffected.

## Remaining tasks (18) — exact unchecked lines from the persisted artifact

```text
- [ ] 21. Verify the readiness gate holds across repeated recreations and that no
- [ ] 22. Verify the identity layers and the state-ownership behaviour at runtime (ID1, ID2,
- [ ] 26. **[measurement-dependent]** Sample the merged cgroup's `pids.current` baseline and
- [ ] 27. Verify the `opencode-init` semantics at runtime: overlay idempotency (double-run byte
- [ ] 28. Verify s6 recovery and the single-lifecycle property (AC5, AC8 amended proof).
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

The next slice (task 33, the bilingual README pair) is **not** started. Tasks 33–45 stay out of scope
for this run.

## Workload / PR boundary

- **Slice budget vs actual:** implementation delta **186 authored lines** (194 with the `tasks.md`
  flips), inside the 400-line budget and the accepted per-slice `size:exception` (~650). No budget
  pressure and no code compression was needed.
- **PR boundary:** this slice contains exactly `scripts/migrate-state.ps1` (new),
  `scripts/export-state.sh`, `scripts/fix-permissions.ps1`, `.env.example`,
  `openspec/changes/single-robotina-container/tasks.md` (tasks 29–32) and this `apply-progress.md`.
  Targeted at the tracker branch `feat/single-robotina-container` under `feature-branch-chain`,
  current branch `feat/single-robotina-container-06-scripts`. No `git commit`, `git push` or PR was
  created — the parent owns delivery and the index.

## Verification commands run in this slice (exhaustive)

```text
git rev-parse --abbrev-ref HEAD                                  # feat/single-robotina-container-06-scripts
git status --porcelain                                           # clean before edits
# --- task 29: synthetic fixture (never the real HOST_DATA_DIR) ---
rm -rf <FIX>; mkdir -p <FIX>/{opencode/node_modules/foo,git,go/pkg/mod/example.com,hermes/.config/opencode}
printf 'CONFIG-LEGACY' > <FIX>/opencode/config.json
printf 'MODULE'        > <FIX>/opencode/node_modules/foo/index.js
printf '{"lockfileVersion":3}' > <FIX>/opencode/package-lock.json
printf '[user]'        > <FIX>/git/config
printf 'cache'         > <FIX>/go/pkg/mod/example.com/mod.txt
printf 'DESTINO-MAS-NUEVO' > <FIX>/hermes/.config/opencode/config.json
pwsh -NoProfile -File scripts/migrate-state.ps1 -DataDir <FIX_WIN>   # run 1: exit 0, 2 copiados/1 omitido/1 node_modules omitido
pwsh -NoProfile -File scripts/migrate-state.ps1 -DataDir <FIX_WIN>   # run 2: exit 0, 0 copiados/3 omitidos/1 node_modules omitido
sha256sum <FIX>/hermes/.config/opencode/config.json                  # 7d052acf… identical before/after both runs
cat <FIX>/hermes/.config/opencode/config.json                        # DESTINO-MAS-NUEVO (never overwritten)
find <FIX>/hermes -mindepth 1                                        # .config/git/config, .config/opencode/{config.json,package-lock.json}; no node_modules
grep -niE "Remove-Item|Move-Item|rm -rf|Remove-Item -Recurse" scripts/migrate-state.ps1   # no output (exit 1)
HOST_DATA_DIR=$(grep -m1 '^HOST_DATA_DIR=' .env | cut -d= -f2- | tr -d '\r')
ls -ld "$HOST_DATA_DIR/opencode" "$HOST_DATA_DIR/git" "$HOST_DATA_DIR/go"   # all absent (exit 2) — not observable on this host
ls -A "$HOST_DATA_DIR"                                          # backups, hermes, workspace
ls -d <FIX>/hermes/go                                            # absent (exit 2)
# --- task 30 ---
grep -n OPENCODE_SERVER_PASSWORD scripts/export-state.sh         # lines 29, 32
grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/   # 3 hits: README.md:190, README.en.md:198, SECURITY.md:360
sh -n scripts/export-state.sh                                    # OK
grep -n "docker compose exec robotina" scripts/export-state.sh  # line 12
grep -n 127.0.0.1:4096 scripts/export-state.sh                   # line 34
# --- task 31 ---
git ls-files scripts/fix-permissions.ps1                         # scripts/fix-permissions.ps1
grep -rniE "fix-permissions" README.md README.en.md SECURITY.md  # 8 hits (README 63/120/259, README.en 71/128/270, SECURITY 479/484)
grep -nE "Subdirs|Volumes" scripts/fix-permissions.ps1          # @('backups','workspace'); two volumes
pwsh -NoProfile -Command '[Parser]::ParseFile(...)'              # parse OK (both PS1 files)
# --- task 32 ---
git grep -n "HERMES_OPENCODE_GO_API_KEY\|OPENCODE_GO_API_KEY" -- .env.example compose.yml   # both names, no value
grep -nE '=[^[:space:]]+' .env.example                           # no non-empty values (exit 1)
git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'     # benign pre-existing hits (F1)
# --- cleanup ---
rm -rf <FIX>                                                     # fixture removed
```

Every static-validation invocation in this section carries `-q`, `--services` or `--format` on the
same line; the bare `docker compose config` form was never run and is never written here. No token
or key value was ever printed.

---

# Slice 07 — `feat/single-robotina-container-07-docs` (bilingual READMEs + Q7 deletion)

Appended to the cumulative body above. Nothing above was modified except the header line, which now
marks this file as cumulative through slice 07.

## Structured status consumed

- Native `gentle-ai.sdd-status` v2 provided by the parent: `changeName: single-robotina-container`,
  `artifactStore: openspec`, `nextRecommended: apply`, `applyState: ready`, `dependencies.apply:
  ready`, `taskProgress: 27/45`, `blockedReasons: []`, `notes: []`.
- `actionContext`: `mode: repo-local`, `workspaceRoot: C:\Users\elaze\Desktop\robotina`,
  `allowedEditRoots: ["C:\Users\elaze\Desktop\robotina"]`. **No actionContext warnings** raised by
  the status engine; one apply-observed finding (F1) is recorded below.
- Review-workload gate: the parent prompt carries the resolved delivery path — chained PRs,
  `feature-branch-chain`, tracker `feat/single-robotina-container`, current slice branch
  `feat/single-robotina-container-07-docs`, `exception-ok` accepted per slice (~650 authored
  lines). `tasks.md`'s forecast (`Decision needed before apply: Yes`, `Chained PRs recommended:
  Yes`, `400-line budget risk: High`) is satisfied by that resolved path. This slice implements
  task 33 plus the now-confirmed deletion of `scripts/fix-permissions.ps1`.
- `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`, `test_command: null`; the
  parent prompt did not activate strict TDD.
- No child subagent was launched. No `git commit`/`git push`/PR was performed — the parent owns the
  index and delivery. `git rm` (staging the deletion) was explicitly assigned and performed. No token
  or key value was ever printed.

## Completed task (28/45) and its persisted checkbox update

`openspec/changes/single-robotina-container/tasks.md` now shows `- [x]` for task **33** (flipped
in place). Counts after the edit: `grep -c '^- \[x\]'` = **28**, `grep -c '^- \[ \]'` = **17**.

| Task | What was done | Verification actually run | Observed result |
| --- | --- | --- | --- |
| 33 | `README.md` (Spanish) and `README.en.md` (English) rewritten in one working-tree change for the single-container reality: topology + what replaced the previous layout, `docker compose build robotina`/`up -d`, the removed host permission step (ownership now fixed by the container's cont-init), the copy-forward migration (`scripts/migrate-state.ps1`) plus a documented POSIX `cp -an`/`rsync --ignore-existing` equivalent, the export-before-migrate safety net, the BotFather display-name-only step, in-container operator recipes (loopback-only endpoint, s6 in `/command`, `MSYS_NO_PATHCONV=1`), the persistence table (two nested WAL volumes + expected empty host mount points), measured versions, and the uid-10000 assumption | the task's six named greps plus AC9's four stale-claim greps, task 30's and task 31's greps (see «Verification commands» below) | all task-33 greps green on the READMEs; AC9 residuals are **SECURITY.md only** (pending-on-records, see F1) |
| Q7 | `scripts/fix-permissions.ps1` deleted (`git rm` staged it) per the user's explicit decision; the two READMEs no longer mention it; `scripts/migrate-state.ps1`'s header comment reworded to drop the banned two-container phrasing (AC9 covers `scripts/`) | `git rm`; `git status --porcelain`; `grep -rniE "fix-permissions" README.md README.en.md`; AC9-2 grep over `scripts/` | `D  scripts/fix-permissions.ps1` staged; `git ls-files scripts/` = `export-state.sh`, `migrate-state.ps1`; no README hit; `scripts/` AC9-2 clean |

## TDD Cycle Evidence

**Not applicable.** `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`,
`test_command: null`; the parent prompt did not activate strict TDD. No RED/GREEN table is produced
because no test runner exists and none may be invented. Verification is the documentation grep suite
below.

## Files changed in this slice (authored line counts)

| File | Change | Additions | Deletions |
| --- | --- | --- | --- |
| `README.md` | rewritten (Spanish) | 224 | 109 |
| `README.en.md` | rewritten (English) | 231 | 115 |
| `scripts/migrate-state.ps1` | header comment reworded (comment only) | 1 | 1 |
| `scripts/fix-permissions.ps1` | **deleted** (`git rm`, staged) | 0 | 45 |
| `openspec/changes/single-robotina-container/tasks.md` | task 33 checked + two slice-07 notes | ~13 | ~2 |
| `odd/tasks/single-robotina-container.md` | Q7 resolution + slice-07 progress line | ~13 | ~1 |
| `openspec/changes/single-robotina-container/apply-progress.md` | cumulative header + this section | new section | 0 |

- **Authored changed lines (implementation/docs, excluding this file and the two change records):**
  README.md **333** (224+109) + README.en.md **346** (231+115) + `migrate-state.ps1` **2** +
  `fix-permissions.ps1` deletion **45** = **726**. The README pair alone is **679** authored lines
  (forecast S7 was ~370).
- **Budget:** implementation/docs **726** — **≈76 over** the user's ~650 per-slice approximate
  acceptance, and the README pair alone is 679 vs the 400-line budget. It is **not** reducible
  without dishonesty: task 33 requires both files rewritten in the same commit, and each file must
  carry ten mandated content blocks (topology, build, removal of the host step, migration + POSIX
  equivalent, safety net, BotFather, operator recipes, persistence table, versions, uid-10000 note)
  in its own language. Nothing was compressed or deleted to fit (no section, table or note was
  dropped).
- **Recommendation:** accept the overage for this slice as-is (the two READMEs are one cohesive
  bilingual work unit by task text); do **not** re-slice. `exception-ok` is the parent/user's to
  accept, not claimed here.
- `git status --porcelain` for the slice: ` M README.en.md`, ` M README.md`,
  ` M scripts/migrate-state.ps1`, `D  scripts/fix-permissions.ps1` (staged), plus the two change
  artifacts and the ODD file after their edits.

## Deviations from design

1. **D1 — the deletion is the user's decision, not this slice's.** Task 31 (design §8.4) left
   `scripts/fix-permissions.ps1` in the tree as an interim safe default and stated no task in this
   change may delete it. The user was asked explicitly and chose deletion in this session; task 31's
   historical text is preserved and the resolution is recorded (tasks.md slice-07 note; ODD
   `Open decisions`). The file is deleted and the deletion is staged.
2. **D2 — the README clone branch was corrected.** The old READMEs cloned
   `security/egress-hardening`, which is already merged into `main`; the rewrite clones the tracker
   branch `feat/single-robotina-container` and says `main` is the default. Documentation truth fix,
   no design statement changes.
3. **D3 — `PowerShell 7` moved from a hard requirement to an optional Windows-migration
   requirement.** It existed only for `fix-permissions.ps1` (now deleted) and is still needed for
   `scripts/migrate-state.ps1`, so it is documented as optional and scoped to the migration, with
   the POSIX equivalent for Linux/macOS. This follows the parent's instruction («Remove the
   PowerShell 7 requirement if it existed only for that script»).
4. **D4 — `scripts/migrate-state.ps1`'s header comment reworded.** Its first comment line contained
   `layout de dos contenedores`, which agent-container AC9's grep bans across `scripts/`. One
   comment line changed; no behaviour. Necessary so the docs slice's own verification is clean
   outside `SECURITY.md`.

## Findings for the parent (not fixed here — outside this slice)

- **F1 — the AC9 stale-claim greps still have `SECURITY.md` residuals.** The four greps return:
  `SECURITY.md:271,282,319` (`http://opencode:4096`); `SECURITY.md:3,259,334,467`
  (`dos agentes`/`dos contenedores`); `SECURITY.md:360` (`docker compose exec opencode`);
  `SECURITY.md:128` (`docker inspect hermes`, `docker inspect opencode`). Also `SECURITY.md:479,484`
  still instruct running `scripts/fix-permissions.ps1` (now a deleted file) and `SECURITY.md:302`
  carries the retired `sin credencial` phrasing. `SECURITY.md` is rewritten by the **records** slice
  (tasks 39–40), not this one. **Recorded as pending-on-records; not edited here.**
- **F2 — the exact task-33 proof `git diff --name-only $(git merge-base HEAD main)...HEAD --` is
  empty until the parent commits.** The parent owns the index and did not commit, so the
  `...HEAD` form sees no change; the working-tree equivalent (`git diff --name-only --`) lists both
  `README.md` and `README.en.md`. The bilingual-pair property holds in the working tree; the
  committed form will hold once the parent commits this slice.
- **F3 — task 30's dry-run grep now has fewer hits.** Slice 06 recorded 3 hits for
  `grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/`
  (README.md:190, README.en.md:198, SECURITY.md:360). This slice removed the two README hits; the
  remaining one is `SECURITY.md:360`, pending-on-records. Task 30 itself is already `- [x]`.
- **F4 — the version table is measured, not inherited.** Measured live in the running containers
  this session: opencode 1.18.32, Squid 6.13, gh 2.97.0, git 2.47.3, Go 1.24.4, uv 0.11.6, jq 1.7,
  ripgrep 14.1.1, Python 3.13.5, Node v26.5.1, R 4.5.0, engram 1.20.0, gentle-ai 3.1.0,
  taplo 0.10.0, marksman 2026-02-08, codegraph 1.5.0. Go is the image's own toolchain
  (`go version go1.24.4 linux/amd64`), matching slice 03's build record.
- **F5 — the host nested mount-point directories are empty and exist.** Verified host-side:
  `${HOST_DATA_DIR}` = `backups`, `hermes`, `workspace`, and
  `hermes/.engram` + `hermes/.local/share/opencode` exist and are empty (the volumes shadow them).
  The persistence table documents exactly this.

## Remaining tasks (17) — exact unchecked lines from the persisted artifact

```text
- [ ] 21. Verify the readiness gate holds across repeated recreations and that no
- [ ] 22. Verify the identity layers and the state-ownership behaviour at runtime (ID1, ID2,
- [ ] 26. **[measurement-dependent]** Sample the merged cgroup's `pids.current` baseline and
- [ ] 27. Verify the `opencode-init` semantics at runtime: overlay idempotency (double-run byte
- [ ] 28. Verify s6 recovery and the single-lifecycle property (AC5, AC8 amended proof).
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

Tasks 21, 22, 26, 27, 28 are runtime-verification tasks not assigned to this slice; 34–45 are the
records / spec-alignment / measurement slices that follow.

## Workload / PR boundary

- **PR boundary:** this slice contains exactly `README.md`, `README.en.md`,
  `scripts/migrate-state.ps1` (comment), the deletion of `scripts/fix-permissions.ps1` (staged),
  `openspec/changes/single-robotina-container/tasks.md` (task 33 + slice-07 notes),
  `odd/tasks/single-robotina-container.md` (Q7 + progress) and this `apply-progress.md`. Targeted
  at the tracker branch `feat/single-robotina-container` under `feature-branch-chain`. The records
  slice (34–45) is **not** started.
- No `git commit`, `git push` or PR was created — the parent owns delivery and the index.

## Verification commands run in this slice (exhaustive, with observed output)

```text
# --- task 33, the six named greps ---
git diff --name-only <merge-base HEAD main>...HEAD -- README.md README.en.md   # empty (not committed yet; see F2)
git diff --name-only -- README.md README.en.md                               # README.en.md, README.md
grep -c "docker compose exec robotina" README.md README.en.md                # README.md:9  README.en.md:9
grep -ci "botfather" README.md README.en.md                                  # README.md:3  README.en.md:3
grep -rniA6 "botfather" README.md README.en.md | grep -iE "username"          # no output (exit 1)
grep -ciE "migra|migration|\.config/opencode" README.md README.en.md          # README.md:12  README.en.md:13
# --- AC9's four stale-claim greps (READMEs clean; SECURITY.md residual) ---
grep -rn "http://opencode:4096" README.md README.en.md SECURITY.md hermes/ scripts/   # SECURITY.md:271,282,319
grep -rniE "dos agentes|dos contenedores|two agent containers|two containers|sibling container|contenedor hermano" README.md README.en.md SECURITY.md hermes/ scripts/   # SECURITY.md:3,259,334,467
grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/ .env.example   # SECURITY.md:360
grep -rn "docker inspect hermes\|docker inspect opencode" README.md README.en.md SECURITY.md .env.example   # SECURITY.md:128
# --- task 30 / task 31 / SL5 greps ---
grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/   # SECURITY.md:360 only
grep -rniE "fix-permissions" README.md README.en.md SECURITY.md              # SECURITY.md:479,484 only
grep -rniE "fix-permissions" README.md README.en.md                          # no output (exit 1)
# --- deletion staged ---
git rm scripts/fix-permissions.ps1                                           # rm 'scripts/fix-permissions.ps1'
git status --porcelain -- scripts/fix-permissions.ps1                        # D  scripts/fix-permissions.ps1
git ls-files scripts/                                                        # scripts/export-state.sh, scripts/migrate-state.ps1
git diff --cached --numstat -- scripts/fix-permissions.ps1                    # 0  45  scripts/fix-permissions.ps1
# --- measured facts used in the README ---
docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'        # egress-proxy + robotina, both Up (healthy)
docker compose exec -T egress-proxy squid -v | head -2                       # Squid Cache: Version 6.13
docker compose exec -T robotina sh -c '<tool version probes>'               # opencode 1.18.32, gh 2.97.0, taplo 0.10.0, marksman 2026-02-08, codegraph 1.5.0, gentle-ai 3.1.0, uv 0.11.6, node v26.5.1, python 3.13.5, R 4.5.0, git 2.47.3, go 1.24.4, jq 1.7, rg 14.1.1
ls -A "$HOST_DATA_DIR"                                                       # backups, hermes, workspace
ls -ld "$HOST_DATA_DIR/hermes/.engram" "$HOST_DATA_DIR/hermes/.local/share/opencode"   # both exist; ls -A empty (expected mount points)
```

Every static-validation invocation in this section carries `-q`, `--services` or `--format` on the
same line; the bare `docker compose config` form was never run and is never written here. No token
or key value was ever printed — version probes and greps only, never `.env` values.

---


---

# Slice 08 — `feat/single-robotina-container-08-records` (records: SECURITY.md + project.md + spec alignment, tasks 34, 35, 36, 37, 39)

Appended to the cumulative body above. Nothing above was modified except the header line, which
now marks this file as cumulative through slice 08.

## Structured status consumed

- Native `gentle-ai.sdd-status` v2 provided by the parent: `changeName: single-robotina-container`,
  `artifactStore: openspec`, `nextRecommended: apply`, `applyState: ready`,
  `dependencies.apply: ready`, `taskProgress: 28/45 complete, 17 pending`, `blockedReasons: []`,
  `notes: []`.
- `actionContext`: `mode: repo-local`, `workspaceRoot: C:\Users\elaze\Desktop\robotina`,
  `allowedEditRoots: ["C:\Users\elaze\Desktop\robotina"]`. **No actionContext warnings** raised by
  the status engine. Two apply-observed findings (F1, F2) are recorded below.
- Review-workload gate: the parent prompt carries the resolved delivery path — chained PRs,
  `feature-branch-chain`, tracker `feat/single-robotina-container`, current slice branch
  `feat/single-robotina-container-08-records`, `exception-ok` accepted per slice (~650 authored
  lines, user decision). `tasks.md`'s forecast (`Decision needed before apply: Yes`, `Chained PRs
  recommended: Yes`, `400-line budget risk: High`) is satisfied by that resolved path. This slice
  implements tasks 34, 35, 36, 37 and 39 only.
- `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`, `test_command: null`; the
  parent prompt did not activate strict TDD.
- No child subagent was launched. No `git commit`/`git push`/PR was performed — the parent owns the
  index and delivery. No token or key value was ever printed.

## Completed tasks (33/45 cumulative, 5/5 of this slice) and their persisted checkbox updates

`openspec/changes/single-robotina-container/tasks.md` was re-read after editing: **33 checked**
(`grep -c '^- \[x\]'` = 33), **12 pending** (`grep -c '^- \[ \]'` = 12). Tasks 34, 35, 36, 37 and
39 were flipped to `- [x]` only after their verification commands actually ran and were observed.

| Task | What was done | Verification actually run | Observed result |
| --- | --- | --- | --- |
| 34 | `openspec/project.md` rewritten for the merged reality: one-agent services table (`robotina` + `egress-proxy`), the post-merge coupling map (PID 1 = image entrypoint / s6; five capabilities; uid alignment; per-process key wiring; egress proxy separate; `/tmp exec`), repository layout (`robotina/`, `hermes/skins`, `scripts/migrate-state.ps1`; no `opencode/`), networks/persistence (nested volumes), conventions, verification expectations, SDD session configuration (feature-branch-chain + per-slice `size:exception`), and the traps (execline oneshot `up`, `chown` has no `--one-file-system`, Dockerfile change does not recreate, `HOST_DATA_DIR` mandatory) | `grep -n "opencode/Dockerfile" openspec/project.md`; `grep -c "robotina" openspec/project.md`; plus the banned exec/inspect grep | no output (exit 1); **`17`**; `docker compose exec (hermes\|opencode)` / `docker inspect (hermes\|opencode)` → no output (exit 1) |
| 35 | Added the **superseded-by** note to `odd/tasks/agent-interop-http.md` (additions only, history preserved) and refreshed `odd/tasks/single-robotina-container.md`: T4 flipped complete, the acceptance line corrected to the CR6 wording, the slice-progress table updated (S5–S7 committed, S8 in progress), the stale "identity not implemented" status rewritten, and the `## Next step` pointer replaced | `grep -niE "superseded" odd/tasks/agent-interop-http.md`; `git diff --stat -- odd/tasks/agent-interop-http.md`; `grep -niE "neither process can read" odd/tasks/single-robotina-container.md` | 1 match (line 3); **7 insertions, 0 deletions** (pure additions); no output (exit 1) |
| 36 | Replaced every stale `OPEN ITEM`/`owned by sdd-design` annotation in the change's own specs with a `CLOSED BY DESIGN §…` note: agent-container AC5 (Q10 → §9.3), AC5 NOTE (Q3 → §9.2), AC5 scenario (Q10 → §9.3), AC6 (Q1 → §16); opencode-endpoint EP4 (Q2 → §9.1), EP6 (Q5 → §10.3); state-layout SL4 (Q12 → §12), SL6 (Q7 → §8.4, user-confirmed deletion) | `grep -rn "OPEN ITEM" …/specs/`; `grep -rn "CLOSED BY DESIGN" …/specs/`; `grep -rniE "owned by \`sdd-design\`" …/specs/` | no output (exit 1); **8 matches** across the three files (≥ 7, one per Q1/Q2/Q3/Q5/Q7/Q10/Q12); no output (exit 1) |
| 37 | Checked `openspec/config.yaml`'s prose against design §19.3's same-line rule; the check **did** report two lines naming the command without a flag (`testing.static_validation.note`, the `apply` rule), so both were reworded to refer to "the bare form"/"the static-validation command" **by description**, and the check was re-run | `git grep -nE "docker compose confi[g]" -- openspec/config.yaml` (before and after); recorded in `odd/tasks/single-robotina-container.md` and `tasks.md` notes | before: 6 hits, two without a flag (lines 39, 106). after: **4 hits, every one carrying `-q` or `--services` on the same line** (lines 37, 43, 105, 108) |
| 39 | `SECURITY.md` rewritten (Spanish) for the merged reality, keeping the still-true measured content and adding the required non-measured entries: R1 (credential invariant retired, PAT kept as-is, prompt-injection reach stated), R2 (per-process key isolation **not enforceable** at equal uid; acceptance = "each process is configured with only its own key"), R4 (single lifecycle), R6 (superseded interop task file), R7 (shared workspace with no container boundary), the loopback-only `OPENCODE_SERVER_PASSWORD` defense-in-depth rationale, engram's log destination (container stream), the PID-1-must-be-the-entrypoint rule, and the nested-volume layout narrative. Measured values deliberately left to task 40 in a `## Evidencia medida` placeholder. | the five task-39 greps (below) plus the AC9 stale-claim greps over the docs set | all five task-39 greps as expected (non-empty / non-empty / non-empty / no output / no output); all four AC9 greps now clean across `README*`, `SECURITY.md`, `hermes/`, `scripts/`, `.env.example` |

## SECURITY.md content baseline (task 39, before → after)

The file was pervasively two-container (`hermes`/`opencode` as separate services). The rewrite
removed every stale claim the change's AC9 grep bans and added the four "columns of the merge"
sections the task enumerates.

```text
# before the rewrite (residuals owned by the records slice, from slice 07's F1)
SECURITY.md:271,282,319  http://opencode:4096
SECURITY.md:3,259,334,467 dos agentes / dos contenedores
SECURITY.md:360          docker compose exec opencode
SECURITY.md:128          docker inspect hermes / docker inspect opencode
SECURITY.md:302          "sin credencial -> 401"
SECURITY.md:479,484      instructions to run scripts/fix-permissions.ps1
# after
grep -rn "http://opencode:4096" README.md README.en.md SECURITY.md hermes/ scripts/   # no output
grep -rniE "dos agentes|dos contenedores|two agent containers|two containers|sibling container|contenedor hermano" README.md README.en.md SECURITY.md hermes/ scripts/   # no output
grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/ .env.example   # no output
grep -rn "docker inspect hermes\|docker inspect opencode" README.md README.en.md SECURITY.md .env.example   # no output
grep -rniE "claves? (estan |están )?aislad|keys? are isolated|aisladas por proceso|isolated per process|no puede leer la clave del otro|cannot read the other" README.md README.en.md SECURITY.md hermes/   # no output
```

The one remaining `fix-permissions` mention in `SECURITY.md` is explanatory text about the Q7
deletion (the container-side cont-init replaces it), never a setup instruction — the form task 31
explicitly allows.

## TDD Cycle Evidence

**Not applicable.** `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`,
`test_command: null`; the parent prompt did not activate strict TDD. No RED/GREEN table is produced
because no test runner exists and none may be invented. Verification is the documentation grep
suite above.

## Files changed in this slice (authored line counts)

| File | Change | Additions | Deletions |
| --- | --- | --- | --- |
| `SECURITY.md` | rewritten (Spanish) for the merged reality | 383 | 346 |
| `openspec/project.md` | rewritten (English) for the merged reality | 72 | 49 |
| `odd/tasks/single-robotina-container.md` | T4 checked, CR6 acceptance wording, slice table + status refresh, `## Next step` replaced, task-37 outcome recorded | 33 | 11 |
| `openspec/changes/single-robotina-container/tasks.md` | tasks 34–37/39 checked, task 44 verification text corrected, slice-08 notes | 18 | 6 |
| `odd/tasks/agent-interop-http.md` | superseded-by note | 7 | 0 |
| `openspec/changes/single-robotina-container/specs/agent-container/spec.md` | 4 `CLOSED BY DESIGN` notes | 10 | 7 |
| `openspec/changes/single-robotina-container/specs/opencode-endpoint/spec.md` | 2 `CLOSED BY DESIGN` notes | 7 | 5 |
| `openspec/changes/single-robotina-container/specs/state-layout/spec.md` | 2 `CLOSED BY DESIGN` notes | 7 | 3 |
| `openspec/config.yaml` | two prose lines reworded (task 37) | 2 | 2 |
| `openspec/changes/single-robotina-container/apply-progress.md` | this cumulative section | new section | 0 |

- **Authored changed lines excluding this section: 383+346 + 72+49 + 33+11 + 18+6 + 7 + 10+7 +
  7+5 + 7+3 + 2+2 = 968.** The `SECURITY.md` rewrite alone is **729** authored lines (383+346);
  it is the required scope of task 39 (the file is the Spanish security record and was written
  for the retired two-container topology start to finish).
- **Budget:** 968 vs the accepted per-slice `size:exception` of ~650 — **≈318 over**. It is **not**
  reducible without dishonesty: the file had to be rewritten rather than patched because the stale
  `hermes`/`opencode` split runs through the guarantees table, the image-compatibility section, the
  topology/interop section, persistence, GitHub auth and the shared-workspace section; patching
  would either leave banned claims or produce a self-contradicting document. Nothing was compressed
  or deleted to fit (no section, table, measured excerpt or rationale was dropped).
- **Recommendation:** accept the overage for this slice as-is; do **not** re-slice. `size:exception`
  is the parent/user's to accept, not claimed here.
- `git status --porcelain` for the slice: ` M SECURITY.md`, ` M openspec/project.md`,
  ` M odd/tasks/agent-interop-http.md`, ` M odd/tasks/single-robotina-container.md`,
  ` M openspec/config.yaml`, ` M openspec/changes/single-robotina-container/tasks.md`,
  ` M openspec/changes/single-robotina-container/specs/{agent-container,opencode-endpoint,state-layout}/spec.md`.

## Deviations from design / task text

1. **Task 44's verification text was corrected (parent-instructed, task-text only).** It expected
   `git ls-files scripts/fix-permissions.ps1` to print the path ("still present — not deleted"),
   written when keeping the file was the interim default. The user has since decided to delete it
   (Q7), so the check now expects **no output** and states the rollback story (git history retains
   the script; neither state volume nor any host folder is destroyed, so the deletion reverts as one
   unit). No file was recreated to satisfy the old text. Observed now: `git ls-files
   scripts/fix-permissions.ps1` → no output; `git status --porcelain -- scripts/` clean.
2. **The R6 superseded-by note was inserted after the H1 title, not appended at the end.** It is a
   7-line pure addition; the existing record is byte-identical (`git diff --stat` = 7 insertions,
   0 deletions).
3. **`openspec/project.md` keeps `grep`-bannable strings out but names the retired layout in the
   historical/known-traps context only** where it is explanatory (e.g. "The legacy `opencode/`,
   `git/` and `go/` folders are no longer mounted"). The task-34 checks pass.

## Findings for the parent (not fixed here — outside tasks 34–39)

- **F1 — this slice is over the accepted ~650-line per-slice budget (968), driven by the required
  `SECURITY.md` rewrite (729).** Reported with a `size:exception` recommendation rather than
  compressed. If a strict budget is preferred, the only cohesive split is 08a (`SECURITY.md`, 729 —
  itself over 400) and 08b (`project.md` + specs + config + ODD, 239); splitting does not bring 08a
  under 400.
- **F2 — no YAML parser was available on the authoring host** (`python`/`pyyaml` and `js-yaml` are
  both absent), so `openspec/config.yaml` could not be machine-parsed after the task-37 edit. The
  edit was confined to the text inside an existing `>-` block scalar and an existing double-quoted
  list item, with indentation and quoting unchanged; `docker compose` does not read this file, so
  no runtime path depends on it. Flagged for a parser-backed check at `sdd-verify` if desired.
- **F3 — the remaining task-44 host greps cannot pass on this authoring host** (the legacy
  `opencode/`, `git/`, `go/` folders never existed here; `HOST_DATA_DIR` holds only `backups`,
  `hermes`, `workspace`). Only the `fix-permissions` line was corrected in this slice, as
  instructed; the folder-existence half stays as written for an environment that has the legacy
  layout.
- **F4 — measured `SECURITY.md` entries (task 40) are deliberately absent.** A `## Evidencia medida`
  placeholder states what the measurement task will add; the `CapEff`/`CapBnd` and
  `mem_limit|6g|pids_limit` greps both return **no output** in `SECURITY.md` after this slice. The
  `9p|virtiofs` grep still matches the pre-existing WAL-hazard prose (the general virtiofs/9p
  corruption explanation, unchanged from the original file), not a measured nesting result — task 40
  must add the actual nesting measurement.

## Remaining tasks (12) — exact unchecked lines from the persisted artifact

```text
- [ ] 21. Verify the readiness gate holds across repeated recreations and that no
- [ ] 22. Verify the identity layers and the state-ownership behaviour at runtime (ID1, ID2,
- [ ] 26. **[measurement-dependent]** Sample the merged cgroup's `pids.current` baseline and
- [ ] 27. Verify the `opencode-init` semantics at runtime: overlay idempotency (double-run byte
- [ ] 28. Verify s6 recovery and the single-lifecycle property (AC5, AC8 amended proof).
- [ ] 38. **[measurement-dependent]** Apply design §16's pre-committed adjustment rule to the
- [ ] 40. **[measurement-dependent]** Add `SECURITY.md`'s measured evidence entries: R3's
- [ ] 41. Finalize the change record: replace the ODD file's `## Verification evidence`
- [ ] 42. Run the verification suite end to end on the final tree and record the result.
- [ ] 43. Confirm the frozen egress boundary and the mandatory-input guard survived the merge.
- [ ] 44. Confirm the rollback path is intact: both state volume names unchanged, the three
- [ ] 45. Final secret-leak audit over the whole change, including this file.
```

## Workload / PR boundary

- **Slice budget vs actual:** **968 authored changed lines** (729 `SECURITY.md`, 121 `project.md`,
  94 across the specs/ODD/tasks/config deltas) — ≈318 over the accepted per-slice `size:exception`
  (~650), entirely because `SECURITY.md` is a required full rewrite. Recommendation: accept as-is;
  no re-slicing (see F1).
- **PR boundary:** this slice contains exactly `SECURITY.md`, `openspec/project.md`,
  `openspec/config.yaml`, the three spec files under
  `openspec/changes/single-robotina-container/specs/`, `odd/tasks/agent-interop-http.md`,
  `odd/tasks/single-robotina-container.md`, `openspec/changes/single-robotina-container/tasks.md`
  (tasks 34–37, 39 + task 44 text) and this `apply-progress.md`. Targeted at the tracker branch
  `feat/single-robotina-container` under `feature-branch-chain`. The measurement slice (38, 40, 41)
  and the final verification/rollback slice (42–45) are **not** started.
- No `git commit`, `git push` or PR was created — the parent owns delivery and the index.

## Verification commands run in this slice (exhaustive, with observed output)

```text
# --- task 34 ---
grep -n "opencode/Dockerfile" openspec/project.md                       # no output (exit 1)
grep -c "robotina" openspec/project.md                                  # 17
grep -rniE "docker compose exec (hermes|opencode)|docker inspect (hermes|opencode)" openspec/project.md   # no output (exit 1)
# --- task 35 ---
grep -niE "superseded" odd/tasks/agent-interop-http.md                  # line 3 (exit 0)
git diff --stat -- odd/tasks/agent-interop-http.md                      # 1 file changed, 7 insertions(+), 0 deletions
grep -niE "neither process can read" odd/tasks/single-robotina-container.md   # no output (exit 1)
# --- task 36 ---
grep -rn "OPEN ITEM" openspec/changes/single-robotina-container/specs/  # no output (exit 1)
grep -rn "CLOSED BY DESIGN" openspec/changes/single-robotina-container/specs/   # 8 matches
grep -rniE "owned by `sdd-design`" openspec/changes/single-robotina-container/specs/   # no output (exit 1)
# --- task 37 ---
git grep -nE "docker compose confi[g]" -- openspec/config.yaml          # 6 hits before (39, 106 without a flag); 4 hits after (37, 43, 105, 108, all flagged)
# --- task 39 ---
grep -niE "GITHUB_TOKEN" SECURITY.md                                    # lines 114, 263, 447, 594
grep -niE "mismo uid|equal uid|no se puede aislar|not enforceable|misma identidad" SECURITY.md   # lines 274, 275
grep -n OPENCODE_SERVER_PASSWORD SECURITY.md README.md README.en.md scripts/export-state.sh       # SECURITY 113/323/328/344/467; README 116/176/195; README.en 126/185/204; export-state 29/32
grep -rniE "solo lo alcanza quien este en la red|puede manejar opencode|can drive opencode|reachable from the host|alcanzable desde el host" README.md README.en.md SECURITY.md   # no output (exit 1)
grep -rniE "sin credencial|no github credential|no tiene token|no esta instalado" SECURITY.md   # no output (exit 1)
# --- AC9 stale-claim greps (docs set) after the rewrite ---
grep -rn "http://opencode:4096" README.md README.en.md SECURITY.md hermes/ scripts/             # no output (exit 1)
grep -rniE "dos agentes|dos contenedores|two agent containers|two containers|sibling container|contenedor hermano" README.md README.en.md SECURITY.md hermes/ scripts/   # no output (exit 1)
grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/ .env.example   # no output (exit 1)
grep -rn "docker inspect hermes\|docker inspect opencode" README.md README.en.md SECURITY.md .env.example   # no output (exit 1)
grep -rniE "claves? (estan |están )?aislad|keys? are isolated|aisladas por proceso|isolated per process|no puede leer la clave del otro|cannot read the other" README.md README.en.md SECURITY.md hermes/   # no output (exit 1)
# --- task 44 corrected check ---
git ls-files scripts/fix-permissions.ps1                                # no output (the file is deleted)
# --- appended-artifact re-read ---
grep -c '^- \[x\]' openspec/changes/single-robotina-container/tasks.md  # 33
grep -c '^- \[ \]' openspec/changes/single-robotina-container/tasks.md  # 12
# --- CR4 authoring-rule check over the changed docs ---
git grep -nE "docker compose confi[g]" -- README.md README.en.md SECURITY.md scripts/ openspec/changes/single-robotina-container/design.md openspec/changes/single-robotina-container/tasks.md | grep -vE "config [-]{1,2}(q|services|format)"   # no output (exit 1)
```

Every static-validation invocation in this section carries `-q`, `--services` or `--format` on the
same line; the bare `docker compose config` form was never run and is never written here. No token
or key value was ever printed.

---

# Slice 09 — `feat/single-robotina-container-09-measurements` (runtime verification, tasks 21, 22, 27, 28)

Appended to the cumulative body above. Nothing above was modified. This slice is **verification
only** — no production code changed; the deliverable is the runtime evidence plus the persisted
task checkboxes.

## Structured status consumed

- Native `gentle-ai.sdd-status` v2 provided by the parent: `changeName: single-robotina-container`,
  `artifactStore: openspec`, `nextRecommended: apply`, `applyState: ready`, `dependencies.apply:
  ready`, `taskProgress: 33/45 complete, 12 pending`, `blockedReasons: []`, `notes: []`.
- `actionContext`: `mode: repo-local`, `workspaceRoot: C:\Users\elaze\Desktop\robotina`,
  `allowedEditRoots: ["C:\Users\elaze\Desktop\robotina"]`. **No actionContext warnings** raised by
  the status engine; the three apply-observed findings (F1–F3) are recorded below.
- Review-workload gate: the parent prompt carries the resolved delivery path — chained PRs,
  `feature-branch-chain`, tracker `feat/single-robotina-container`, current slice branch
  `feat/single-robotina-container-09-measurements`, `exception-ok` accepted per slice (~650 authored
  lines, user decision). This slice implements tasks **21, 22, 27, 28 only**; heavy-load sampling
  (26) and the measured evidence entries (38, 40, 41) were deliberately excluded.
- `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`, `test_command: null`; the
  parent prompt did not activate strict TDD.
- No child subagent was launched. No `git commit`/`git push`/PR was performed — the parent owns the
  index and delivery. No token or key value was ever printed; key-touching probes used `sha256sum`
  only. The stack was left **healthy and running** (explicitly required).

## Completed tasks (36/45 cumulative, 3/4 of this slice) and their persisted checkbox updates

`openspec/changes/single-robotina-container/tasks.md` was re-read after editing: **36 checked**
(`grep -c '^- \[x\]'`), **9 pending** (`grep -c '^- \[ \]'`). Tasks 21, 22 and 27 were flipped only
after their verification commands actually ran and were observed. **Task 28 stays `- [ ]`** — its
s6-recovery half passed but its amended single-lifecycle proof failed.

| Task | What was done | Verification actually run | Observed result |
| --- | --- | --- | --- |
| 21 | Readiness gate across 3 `down`/`up` cycles + the `ECONNREFUSED` log check + the gate-failure behaviour | the exact 3-cycle loop; the `--since 10m` refused/econnrefused grep; an isolated throwaway container with `opencode-ready/up` = `/bin/false`; the real `/run/s6/basedir/scripts/rc.init` | all 3 cycles `probe_exit=0`, gate satisfied at `intentos=1`; cold starts ≈4.34 / 4.56 / 4.44 s; refused-econnrefused grep **no output**; **gate failure → s6-overlay continues to the CMD** (`s6-rc: warning: unable to start service opencode-ready: command exited 1` then the CMD ran), `S6_BEHAVIOUR_IF_STAGE2_FAILS` unset |
| 22 | Identity layers ID1/ID2/ID3/ID5 and state ownership SL6, live + fresh-tree | the 8 live probes; `docker compose -p robotina-fresh config -q`; the literal `up` (collides); the renamed-container fresh run + inspect + cont-init log | skin present and `ro` (repo source); `touch` → `Read-only file system`; `skin: robotina` (1965); `.hermes.md` count `3`; `NO_PROXY` has `robotina`; write test `writable-as-10000`; `stat` `10000:10000`; fresh run selects the skin non-interactively and is writable as 10000 |
| 27 | `opencode-init` idempotency, invalid-JSON quarantine, log observability | `sha256sum` before/after `restart`; seed invalid JSON + restart + `jq -e .` + endpoint; `docker compose logs --tail 200` | hashes identical (`55e23123…8149`, `IDEMPOTENT=yes`); `cuarentenado en …/opencode.json.invalid-20260922T190450Z`; container healthy; resulting JSON valid; 200 log lines incl. both service banners |
| 28 (partial) | s6 recovery **verified**; single-lifecycle amended proof attempted | `pkill -f "[o]pencode serve"` (as uid 10000) + bounded probe; `pkill -f "[h]ermes gateway"` (root → EPERM, then uid 10000); rc.init-child kill; 180 s RestartCount/StartedAt watch | recovery in **5 s**, pid 227→533, `reinicio #1 en 1s`; gateway kill → s6 restarts it in place (`gateway-default`, 612→919), `RestartCount=0`, `StartedAt` unchanged; killing the real main program (`sleep infinity`) starts the shutdown but it **wedges** (no `CAP_KILL`), container never exits |

## TDD Cycle Evidence

**Not applicable.** `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`,
`test_command: null`; the parent prompt did not activate strict TDD. Verification is the shell-level
runtime suite above; no test runner exists and none may be invented.

## Files changed in this slice (authored line counts)

| File | Change | Additions | Deletions |
| --- | --- | --- | --- |
| `odd/tasks/single-robotina-container.md` | Slice 09 evidence + slice-progress/status table + `## Next step` | see `git diff --numstat` | — |
| `openspec/changes/single-robotina-container/tasks.md` | tasks 21/22/27 `- [ ]` → `- [x]` + slice-09 note | 3 flips + note | 0 |
| `openspec/changes/single-robotina-container/apply-progress.md` | this cumulative section | new section | 0 |

- **Implementation-only authored changed lines: 0** (verification slice; no `compose.yml` /
  `robotina/` / `hermes/` change). The delta is the process record only, which is inside the
  accepted per-slice `size:exception`. Nothing was compressed or deleted to fit the budget.
- `git status --porcelain` for the slice: ` M odd/tasks/single-robotina-container.md`,
  ` M openspec/changes/single-robotina-container/tasks.md`,
  ` M openspec/changes/single-robotina-container/apply-progress.md`.

## Deviations from task text / design

1. **Task 28's kill had to run as uid 10000, not root.** The literal `docker compose exec robotina
   sh -c 'pkill …'` runs as root, and the container drops `CAP_KILL` (`CapEff=0x00000000000000cb`),
   so root gets `EPERM`. The kill was realized with `docker compose exec -u hermes …`. The `AC5`
   scenario text should either use `-u hermes`/`s6-svc` or note the capability constraint.
2. **Task 21's gate-failure observation used an isolated throwaway container, not the live stack.**
   The real gate would have had to time out for its full 120 s bound; forcing the same oneshot to
   exit non-zero immediately (`/bin/false` as its `up`) produced the identical failure signal
   (non-zero oneshot exit) inside the session and left the live stack untouched.
3. **Task 22's literal fresh-project command cannot pass on this host.** `container_name: robotina`
   (AC2) makes `docker compose -p robotina-fresh up -d robotina` collide with the live container.
   The observable was proven with the same compose file plus a renaming/isolating override. The
   spec's “isolated project name” CAUTION assumed the container name followed the project.
4. **No `specs/` edit was made** (outside this session's allowed surfaces); the two spec
   clarifications that this slice surfaces (task-28 kill user, task-22 fresh command) are reported
   for `sdd-verify` rather than edited.

## Findings for the parent (not fixed here)

- **F1 — the amended single-lifecycle proof fails; the s6 recoverability and the container lifecycle
  are two different things.** `hermes gateway` is the s6 service `gateway-default`, so killing it
  can never cycle the container. The main program (`rc.init` child) is a separate `sleep infinity`,
  and killing it wedges the shutdown because the root s6 supervisors have no `CAP_KILL` to stop the
  uid-10000 services. **AC8's “container goes down and comes back as one unit” is not satisfied.**
  Needs a decision: add `CAP_KILL`, make the supervised gateway the main program, or re-word AC8 to
  the guarantee the architecture actually provides.
- **F2 — the same missing `CAP_KILL` makes an in-container `docker stop`-style shutdown non-graceful.**
  Task 21's `docker compose down` cycles still succeeded, but each one relies on Docker's stop grace
  + SIGKILL from the host; the s6 tree's own bring-down cannot stop the uid-10000 children. This is
  worth noting in `SECURITY.md`/the README operator notes.
- **F3 — `s6-svstat`/`CAP_KILL` detail for task 40:** the observed gate-failure behaviour is “s6-overlay
  continues to the CMD” (degraded start), which design D-6 required to be recorded explicitly if
  observed. Task 40 should fold this in together with the measured capabilities.

## Remaining tasks (9) — exact unchecked lines from the persisted artifact

```text
- [ ] 26. **[measurement-dependent]** Sample the merged cgroup's `pids.current` baseline and
- [ ] 28. Verify s6 recovery and the single-lifecycle property (AC5, AC8 amended proof).
- [ ] 38. **[measurement-dependent]** Apply design §16's pre-committed adjustment rule to the
- [ ] 40. **[measurement-dependent]** Add `SECURITY.md`'s measured evidence entries: R3's
- [ ] 41. Finalize the change record: replace the ODD file's `## Verification evidence`
- [ ] 42. Run the verification suite end to end on the final tree and record the result.
- [ ] 43. Confirm the frozen egress boundary and the mandatory-input guard survived the merge.
- [ ] 44. Confirm the rollback path is intact: both state volume names unchanged, the three
- [ ] 45. Final secret-leak audit over the whole change, including this file.
```

## Workload / PR boundary

- **Slice budget:** implementation delta **0 authored code lines**; the process record is the whole
  delta and stays inside the accepted per-slice `size:exception`. No re-slicing needed.
- **PR boundary:** this slice contains exactly `odd/tasks/single-robotina-container.md`,
  `openspec/changes/single-robotina-container/tasks.md` (tasks 21/22/27 + the slice-09 note) and this
  `apply-progress.md`, on branch `feat/single-robotina-container-09-measurements`. Targeted at the
  tracker branch `feat/single-robotina-container` under `feature-branch-chain`. The measurement
  slice (26, 38, 40, 41) and the final audit (42–45) are **not** started.
- No `git commit`, `git push` or PR was created — the parent owns delivery and the index.

## Verification commands run in this slice (exhaustive, with observed output)

```text
# --- task 22, live ---
docker compose exec -T robotina sh -c 'ls -l /opt/data/skins/robotina.yaml'          # -rwxrwxrwx root root 1059
docker compose exec -T robotina sh -c 'touch /opt/data/skins/robotina.yaml'          # Read-only file system (exit 1)
docker compose exec -T robotina sh -c 'grep " /opt/data/skins" /proc/self/mountinfo' # repo source, ro
docker compose exec -T robotina sh -c 'grep -niE "skin" /opt/data/config.yaml'       # 1965: skin: robotina
docker compose exec -T robotina sh -c 'grep -c "robotina" /workspace/.hermes.md'     # 3
docker compose exec -T robotina sh -c 'printenv NO_PROXY'                            # ...robotina,egress-proxy
docker compose exec -T robotina sh -c 'PATH=/command:$PATH s6-setuidgid hermes sh -c "touch /opt/data/.write-test && rm /opt/data/.write-test" && echo writable-as-10000'   # writable-as-10000
docker compose exec -T robotina sh -c 'stat -c "%u:%g" /opt/data'                    # 10000:10000
# --- task 22, fresh project ---
docker compose -p robotina-fresh config -q                                            # exit 0
docker compose -p robotina-fresh up -d robotina                                       # conflict: /robotina in use
docker compose -p robotina-fresh -f compose.yml -f <override> up -d robotina          # fresh robotina-fresh started
docker inspect --format '{{range .Mounts}}…' robotina-fresh                           # fresh sources; vol paths are fresh binds
docker compose -p robotina-fresh … logs robotina | grep 'display.skin'                # Set display.skin = robotina; exited 0
docker rm -f robotina-fresh                                                           # cleanup
# --- task 27 ---
docker compose exec -T robotina sha256sum /opt/data/.config/opencode/opencode.json    # 55e23123…8149
docker compose restart robotina                                                       # oneshot re-runs
docker compose exec -T robotina sha256sum /opt/data/.config/opencode/opencode.json    # identical -> IDEMPOTENT=yes
# seed invalid json as hermes + restart
docker compose logs --since 2m robotina | grep cuarentenado                           # …invalid-20260922T190450Z
docker compose exec -T robotina sh -c 'jq -e . …/opencode.json >/dev/null && echo valid-json'   # valid-json
docker compose logs --tail 200 robotina | grep -E 'robotina: (opencode serve|engram serve)'      # both banners
# --- task 21 ---
for i in 1 2 3; do docker compose down && docker compose up -d && <bounded credential-aware probe>; done   # probe_exit=0 ×3
docker compose logs --since 10m robotina 2>&1 | grep -Ei '127\.0\.0\.1:4096.*(refused|econnrefused)'      # no output
# gate-failure throwaway (isolated)
docker run -d --name robotina-gatefail --network none -v <up>:/etc/s6-overlay/s6-rc.d/opencode-ready/up:ro robotina:local sh -c 'echo GATE_TEST_CMD_RAN; sleep 600'
docker logs robotina-gatefail | grep -E 'opencode-ready|GATE_TEST_CMD_RAN'             # warning … command exited 1; GATE_TEST_CMD_RAN
docker rm -f robotina-gatefail                                                         # cleanup
# --- task 28 ---
docker compose exec -u hermes -T robotina sh -c 'pgrep -f "[o]pencode serve" | head -1'   # 227
docker compose exec -u hermes -T robotina sh -c 'pkill -f "[o]pencode serve"'            # exit 0
docker compose exec -T robotina sh -c '<bounded credential-aware probe>'               # exit 0 in 5 s
docker compose logs --since 3m robotina | grep reinicio                                # opencode salio …; reinicio #1 en 1s
docker compose exec -u hermes -T robotina sh -c 'pkill -f "[h]ermes gateway"'         # exit 0; s6 restarts gateway-default
docker inspect --format '{{.RestartCount}} {{.State.StartedAt}}' robotina               # unchanged 0 2026-09-22T19:06:53.652872543Z
docker compose exec -u hermes -T robotina sh -c 'kill 306'                              # rc.init child; shutdown wedges
# 180 s watch: status=running RestartCount=0 StartedAt_changed=no (all 18 samples)
docker compose up -d --force-recreate robotina                                          # recovery; healthy again
```

Every static-validation invocation in this section carries `-q`, `--services` or `--format` on the
same line; the bare `docker compose config` form was never run and is never written here. No token
or key value was ever printed.

---

# Slice 10 — `feat/single-robotina-container-10-capkill` (defect fix + contract amendment, task 28)

Appended to the cumulative body above. Nothing above was modified. This slice **fixes the defect
slice 09 exposed** and **amends every artifact that stated something the measurements proved
false**. It is the only slice so far that changes a frozen design decision, so the amendment is
explicit in `design.md` §13.3, spec `agent-container` AC4/AC8 and proposal R4.

## Structured status consumed

- Native `gentle-ai.sdd-status` v2 provided by the parent: `changeName: single-robotina-container`,
  `artifactStore: openspec`, `nextRecommended: apply`, `applyState: ready`, `dependencies.apply:
  ready`, `taskProgress: 36/45 complete, 9 pending`, `blockedReasons: []`, `notes: []`.
- `actionContext`: `mode: repo-local`, `workspaceRoot: C:\Users\elaze\Desktop\robotina`,
  `allowedEditRoots: ["C:\Users\elaze\Desktop\robotina"]`. **No actionContext warnings** raised
  by the status engine. Apply-observed findings are recorded below (F1–F5).
- Review-workload gate: the parent prompt carries the resolved delivery path — chained PRs,
  `feature-branch-chain`, tracker `feat/single-robotina-container`, current slice branch
  `feat/single-robotina-container-10-capkill`, `exception-ok` accepted per slice (~650 authored
  lines, user decision). This slice implements **task 28 only**; tasks 26, 38, 40, 41 and 42–45
  were explicitly out of scope and were not started.
- `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`, `test_command: null`; the
  parent prompt did not activate strict TDD.
- No child subagent was launched. No `git commit`/`git push`/PR was performed — the parent owns the
  index and delivery. No token or key value was ever printed; key-touching probes used `sha256sum`
  only. The stack was left **healthy and running** (explicitly required).

## Completed task (37/45 cumulative, 1/1 of this slice) and its persisted checkbox update

`openspec/changes/single-robotina-container/tasks.md` was re-read after editing: **37 checked**
(`grep -c '^- \[x\]'`), **8 pending** (`grep -c '^- \[ \]'`). **Task 28 is now `- [x]`** — its
proof text was rewritten to the corrected contract *and* its verification was actually run and
observed before the checkbox was flipped.

| Task | What was done | Verification actually run | Observed result |
| --- | --- | --- | --- |
| 28 | Defect resolved: `KILL` added to `cap_add` (six capabilities, mask `0xeb`); lifecycle contract corrected; task proof rewritten | `docker compose config -q`; `docker compose up -d --force-recreate robotina`; PID-1 and uid-10000 mask probes; `docker compose stop robotina` timed; `pkill -f "[o]pencode serve"` + bounded credential-aware probe; `pkill -f "[h]ermes gateway"` as uid 10000 + `RestartCount`/`StartedAt` watch; `s6-rc -a list`; Telegram log grep | config exit 0; PID 1 `CapEff=CapBnd=0xeb`; opencode (uid 10000) `CapEff=0x0`, `CapBnd=0xeb`; stop **5.50 s**, `ExitCode=0`, no SIGKILL; recovery **4.37 s** without manual step (pid 211→416); gateway restarted in place (pid 188→506) with `RestartCount=0`/`StartedAt` unchanged; 10 s6 services; Telegram connected |

## TDD Cycle Evidence

**Not applicable.** `openspec/config.yaml` → `strict_tdd: false`, `testing.runner: none`,
`test_command: null`; the parent prompt did not activate strict TDD. Verification is the shell-level
runtime suite below; no test runner exists and none may be invented.

## Files changed in this slice (authored line counts)

`git diff --numstat` (additions / deletions) at the time of writing, excluding this file:

| File | Change | Additions | Deletions | Authored |
| --- | --- | --- | --- | --- |
| `compose.yml` | `KILL` added to `cap_add`; Spanish comment records why (s6 must signal uid-10000 children; app uid keeps `CapEff=0x0`; mask `0xeb`) | 10 | 2 | 12 |
| `openspec/…/specs/agent-container/spec.md` | AC4 six-capability requirement + mask `0xeb`; AC8 lifecycle scenario rewritten; both with AMENDMENT notes | 50 | 21 | 71 |
| `openspec/…/design.md` | §6 single-lifecycle corrected; §13 Q4/table/§14 mask; §15/§17 rows; new §13.3 amendment; §19.1 RESOLVED | 81 | 18 | 99 |
| `openspec/…/proposal.md` | R4 corrected (plus A4/R3 rows and the §3.1/§4.3/§4.5/phase-result claims that repeated the same falsehood) | 18 | 9 | 27 |
| `SECURITY.md` | R4 corrected; capability entry six + measured `CapEff=0x0`; new measured «Apagado y ciclo de vida» section | 50 | 12 | 62 |
| `odd/tasks/single-robotina-container.md` | task-28 header + new «Slice 10» evidence section + `## Next step` rewrite | 92 | 8 | 100 |
| `openspec/…/tasks.md` | task 28 proof rewritten, defect + resolution recorded, `- [ ]` → `- [x]`, task 25 expectation updated, slice-10 note | 37 | 10 | 47 |
| **Subtotal (excluding this file)** | | **338** | **80** | **418** |

- **Implementation-only authored changed lines: 12** (`compose.yml`). The rest is the honest
  amendment of the artifacts the measurement proved wrong plus the change record. Nothing was
  compressed or deleted to fit the budget, and no comment/doc/evidence line was removed.
- `git status --porcelain` for the slice: ` M SECURITY.md`, ` M compose.yml`,
  ` M odd/tasks/single-robotina-container.md`, ` M openspec/…/design.md`,
  ` M openspec/…/proposal.md`, ` M openspec/…/specs/agent-container/spec.md`,
  ` M openspec/…/tasks.md`, ` M openspec/…/apply-progress.md` (this file).

## Deviations from task text / design

1. **The design decision was amended, not silently absorbed.** `design.md` §13.3 is the single
   place where `apply` changed a frozen decision (five → six capabilities; container-CMD lifecycle
   → s6-supervised gateway). Both were user decisions taken in this slice and both are recorded
   as amendments in the design, the spec and the proposal.
2. **Task 28's kill can now run as root.** With `CAP_KILL` present, the literal
   `docker compose exec robotina sh -c 'pkill -f "[o]pencode serve"'` succeeds (exit 0), so the
   slice-09 workaround (`-u hermes`) is no longer needed for the opencode half. The gateway half
   was still run as uid 10000 (`-u hermes`) because the task's corrected proof says so, and because
   that is the faithful "kill the process inside the container" realization; root would also work
   now, but the spec recipe is uid-10000 and was kept executable as written.
3. **The slice-09 "AC8 amendment" was itself wrong and is superseded.** Slice 09 proposed
   asserting a unit restart (`RestartCount`/`StartedAt` move). Measured: `gateway-default` is an
   s6 service, so the counter never moves. The corrected AC8 asserts the opposite observation
   (restart in place, counter unchanged). `design.md` §19.1 carries the RESOLVED note.
4. **No `README.md`/`README.en.md` edit was made** — they are outside this slice's allowed edit
   surfaces, though they carry the stale claim (F1).

## Findings for the parent (not fixed here)

- **F1 (open — must be fixed before `verify`/`archive`).** `README.md` (~line 345) and
  `README.en.md` (~line 358) still claim "if the main program goes down, the container goes with
  it". The measured contract contradicts it. Both files are outside this slice's allowed edit
  surfaces, so they were not touched.
- **F2 (open, decision).** `explore.md` (~lines 101, 257–263, 574, 641) records the same
  pre-measurement assumption. It is a frozen phase artifact; correcting it (or adding a note) is a
  parent decision, not an apply edit.
- **F3 (resolved).** Slice-09 F1/F2 (AC8 fails; shutdown non-graceful) are closed by this slice.
- **F4 (record for task 40).** Task 40 must now fold in the **six-capability** masks, the **5.50 s**
  stop and the slice-09 gate-failure observation. The old five-capability/`0xcb` wording is stale.
- **F5 (observation, not a defect).** The `--force-recreate` kills the previous gateway, which then
  logs `Previous gateway life … exited UNCLEANLY` on the next boot. Expected for a forced recreate;
  do not mistake it for a crash.

## Remaining tasks (8) — exact unchecked lines from the persisted artifact

```text
- [ ] 26. **[measurement-dependent]** Sample the merged cgroup's `pids.current` baseline and
- [ ] 38. **[measurement-dependent]** Apply design §16's pre-committed adjustment rule to the
- [ ] 40. **[measurement-dependent]** Add `SECURITY.md`'s measured evidence entries: R3's
- [ ] 41. Finalize the change record: replace the ODD file's `## Verification evidence`
- [ ] 42. Run the verification suite end to end on the final tree and record the result.
- [ ] 43. Confirm the frozen egress boundary and the mandatory-input guard survived the merge.
- [ ] 44. Confirm the rollback path is intact: both state volume names unchanged, the three
- [ ] 45. Final secret-leak audit over the whole change, including this file.
```

## Workload / PR boundary

- **Slice budget vs actual:** implementation delta **12 authored lines** (`compose.yml`); the whole
  slice is **418 authored changed lines** excluding this section, inside the accepted per-slice
  `size:exception` (~650). No re-slicing needed and no `size:exception` is newly requested.
- **PR boundary:** this slice contains exactly `compose.yml`, `SECURITY.md`,
  `odd/tasks/single-robotina-container.md`, `openspec/…/specs/agent-container/spec.md`,
  `openspec/…/design.md`, `openspec/…/proposal.md`, `openspec/…/tasks.md` and this
  `apply-progress.md`, on branch `feat/single-robotina-container-10-capkill`. Targeted at the
  tracker branch `feat/single-robotina-container` under `feature-branch-chain`. The measurement
  slice (26, 38, 40, 41) and the final audit (42–45) are **not** started.
- No `git commit`, `git push` or PR was created — the parent owns delivery and the index.

## Verification commands run in this slice (exhaustive, with observed output)

```text
# --- artifact validation + recreate ---
docker compose config -q                                                              # exit 0
docker compose up -d --force-recreate robotina                                         # Recreated / Started

# --- masks (AC4 amended) ---
docker compose exec -T robotina sh -c 'grep -E "^(Uid|Gid)|Cap(Inh|Prm|Eff|Bnd|Amb)|NoNewPrivs" /proc/1/status'
# Uid: 0 0 0 0 / Gid: 0 0 0 0 / CapInh 0x0 / CapPrm 0xeb / CapEff 0xeb / CapBnd 0xeb / CapAmb 0x0 / NoNewPrivs 1
docker compose exec -T robotina sh -c 'for p in $(pgrep -f "[o]pencode serve"); do echo "pid=$p uid=$(awk "/^Uid/{print \$2}" /proc/$p/status)"; grep -E "Cap(Inh|Prm|Eff|Bnd|Amb)|NoNewPrivs" /proc/$p/status; done'
# pid=213 uid=10000 / CapInh 0x0 / CapPrm 0x0 / CapEff 0x0 / CapBnd 0xeb / CapAmb 0x0 / NoNewPrivs 1
# re-checked after the recovery kill: pid=416 uid=10000 CapEff=0x0 CapBnd=0xeb NoNewPrivs=1

# --- graceful shutdown (AC8 amended / slice-09 F2) ---
start=$(date +%s%N); docker compose stop robotina; end=$(date +%s%N)
# Stopping / Stopped ; stop_duration_ms=5504 -> 5.50 s
docker inspect --format 'ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}} FinishedAt={{.State.FinishedAt}}' robotina
# ExitCode=0 OOMKilled=false FinishedAt=2026-09-22T19:25:47.360681404Z
docker compose logs --tail 40 robotina | grep -iE 's6-rc|successfully stopped|SIGTERM'
# opencode-ready -> opencode -> main-hermes -> dashboard -> engram -> opencode-init -> legacy-cont-init -> fix-attrs, all successfully stopped; gateway Shutdown context: signal=SIGTERM

# --- task 28 recovery proof (AC5) ---
docker compose up -d robotina                                                            # Started; health=healthy
docker compose exec -T robotina sh -c 'pgrep -f "[o]pencode serve" | head -1'           # 211
docker compose exec -T robotina sh -c 'pkill -f "[o]pencode serve"'                    # exit 0 (root now has CAP_KILL)
docker compose exec -T robotina sh -c '<bounded credential-aware probe 30x2s>'          # exit 0 in 4.37 s
docker compose exec -T robotina sh -c 'pgrep -f "[o]pencode serve" | head -1'           # 416
docker compose logs --since 2m robotina | grep -E 'salio|reinicio'                       # opencode salio (exit=256 sig=15); reinicio #1 en 1s

# --- corrected lifecycle contract (AC8 amended) ---
docker compose exec -T robotina sh -c 'pgrep -f "[h]ermes gateway" | head -1'           # 188
docker inspect --format '{{.RestartCount}} {{.State.StartedAt}}' robotina                # 0 2026-09-22T19:26:33.780458019Z
docker compose exec -u hermes -T robotina sh -c 'pkill -f "[h]ermes gateway"'          # exit 0
sleep 20
docker compose exec -T robotina sh -c 'pgrep -f "[h]ermes gateway" | head -1'           # 506  (new, non-empty)
docker inspect --format '{{.RestartCount}} {{.State.StartedAt}}' robotina                # 0 2026-09-22T19:26:33.780458019Z  (unchanged)
# GATEWAY_RESTARTED_IN_PLACE=yes ; CONTAINER_NOT_CYCLED=yes
docker compose logs --since 1m robotina | grep -i 's6 supervision'                       # gateway is now running under s6 supervision (auto-restart on crash ...)

# --- final stack state ---
docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'                   # egress-proxy Up (healthy) 3128/tcp ; robotina Up (healthy)
docker compose exec -T robotina sh -c '<credential-aware /global/health>'                # {"healthy":true,"version":"1.18.32"}
docker compose exec -T robotina /command/s6-rc -a list | wc -l                           # 10
docker compose logs --since 5m robotina | grep -i 'Connected to Telegram'                # [Telegram] Connected to Telegram (polling mode)
```

Every static-validation invocation in this section carries `-q`, `--services` or `--format` on the
same line; the bare `docker compose config` form was never run and is never written here. No token
or key value was ever printed.

