# Apply progress — single-robotina-container

Cumulative per-slice progress. The original body below is **slice 02**; **slice 03** is
appended at the end of this file. Nothing in the slice-02 body was overwritten or deleted.

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
