# Tasks — single-robotina-container

Change: `single-robotina-container` · Branch: `feat/single-robotina-container`
Artifact store: `openspec/` (this file is the artifact of record for the tasks phase)
Phase: tasks — **breakdown only**. Nothing was implemented, no design artifact was written,
and no child subagent was launched.
Upstream inputs read in full: `proposal.md` (§17 answers frozen), `explore.md`, `design.md`
(§21 supplies the order of work this list follows), the six specs under `specs/`
(39 requirements / 113 scenarios), `openspec/config.yaml`, `openspec/project.md`,
`odd/tasks/single-robotina-container.md`.

Task order follows design §21: compose + image + s6 first; then the first `up` and the
nesting / readiness / capability / `pids_limit` measurements; then the migration helper and
the documentation; then the `pids_limit` confirmation; then the `SECURITY.md` evidence
entries.

## Verification contract (binding on every task in this file)

- The static-validation command is **always** written with `-q` (or `--services` /
  `--format`) on the same line, here and in every artifact this change authors
  (design §19.3 / agent-credentials CR4). The form that resolves and prints the environment
  file is never written literally.
- `docker inspect` is only ever called with a narrow `--format` that excludes the container
  environment block.
- `pgrep` / `pkill` patterns use a character class (`[o]pencode serve`, `[h]ermes gateway`)
  and every probe asserts a non-empty match — an empty match is a FAILURE, never a pass.
- Language split: this file is English; `compose.yml`, the Dockerfile and script comments stay
  Spanish; `README.md` and `SECURITY.md` Spanish; `README.en.md` and `odd/tasks/*.md` English.
  `README.md` and `README.en.md` change in the same commit.

## Slice 05 — runtime defect fix and re-verification (apply)

Branch: `feat/single-robotina-container-04-supervision` (slice 04, still checked out). The first
real `up` with live keys exposed **two real defects in slice 04**. Both were fixed, the image was
rebuilt, and the stack was re-verified at runtime. **Tasks 10 and 12 are reopened here with their
reason, re-fixed, re-verified and re-closed**; tasks 17–20 and 23–25 are closed by the runtime
evidence below (checkboxes flipped in this file).

### Defect D1 — the s6 oneshot `up` files were not execline (reopens task 12)

- **Evidence (observed):** the container log showed
  `s6-rc-oneshot-run: fatal: unable to exec set: No such file or directory` and
  `s6-rc: warning: unable to start service opencode-init: command exited 127`. `opencode` and
  `engram` both depend on `opencode-init`, so neither started.
- **Root cause (proven):** s6-rc executes a oneshot's `up` **as an execline script**, not a shell
  script. Reproduced inside the container:
  `/package/admin/execline/command/execlineb /etc/s6-overlay/s6-rc.d/opencode-init/up` →
  `execlineb: fatal: unable to exec set`. The `#` lines are execline comments, so the first
  non-comment token (`set`, from `set -eu`) was treated as the program to exec. The vendor's own
  oneshots agree: every `/package/admin/s6-overlay/etc/s6-rc/sources/*/up` is a single line — an
  absolute path to an executable.
- **Fix:** both `up` files are now one-line execline invocations. `opencode-init/up` =
  `/command/with-contenv /usr/bin/env HOME=/opt/data /command/s6-setuidgid hermes /opt/robotina/opencode-init.sh`;
  `opencode-ready/up` = `/command/with-contenv /opt/robotina/opencode-ready.sh`. The bounded
  credential-aware poll moved into the image script `robotina/opencode-ready.sh`.
  `robotina/opencode-init.sh` now sets `HOME=/opt/data` itself (no inherited-HOME dependency).
- **Build-time assertion added (`robotina/Dockerfile`):** every oneshot `up` must be exactly one
  command line, no shebang, not starting with `set`, starting with an absolute path that exists
  and is executable. It fired green on the rebuilt image (`servicio opencode-init (oneshot)
  validado`, `… opencode-ready (oneshot) validado`).
- **Re-verification (observed after rebuild):** `s6-rc -a list` lists `opencode-init`,
  `opencode-ready`, `opencode`, `engram`; `s6-svstat /run/service/opencode` → `up`; log shows
  `service opencode-init successfully started` → `engram` → `opencode` → `opencode-ready
  successfully started`, with `robotina: opencode listo (intentos=1)`.

### Defect D2 — the ownership self-heal was too shallow (reopens task 10)

- **Evidence (measured in the running container before the fix):** `root:root /opt/data/.config`,
  `root:root /opt/data/.local`, `root:root /opt/data/.local/share`, and
  `/opt/data/.local/state` **absent**; Hermes logged `[Telegram] Failed to connect to Telegram:
  [Errno 13] Permission denied: '/opt/data/.local/state'`, `Host gateway lock could not be opened
  (Permission denied: '/opt/data/.local/state')`, and `telegram failed to connect`.
- **Root cause:** step 2 guarded the repair with `s6-setuidgid hermes test -w /opt/data`, which
  succeeds because `/opt/data` is `hermes:hermes 0700`, so the repair was skipped while the nested
  root-owned directories stayed root-owned; `install -d` only fixed the leaf it created.
- **Fix:** `robotina/s6/cont-init.d/10-robotina-state` now (1) `install -d -o/-g` on the
  intermediate parents too (`.config`, `.local`, `.local/share`, plus a created `.local/state` and
  `.cache`) — measured that `install -d` re-applies the owner to pre-existing directories — and
  (2) tests a list of directories the app actually writes to (not just `/opt/data`) before running
  the bounded `find -prune` re-own. The read-only-mount prune list is unchanged (no new mounts
  under `/opt/data`).
- **Re-verification (observed after rebuild):** `/opt/data/.config`, `.local`, `.local/share`,
  `.local/state`, `.cache` all `hermes:hermes`;
  `stat -c %u:%g /opt/data/.local/state` → `10000:10000`; container log `grep -cE "Permission
  denied: '/opt/data/.local/state'|telegram failed to connect"` → `0`; log shows
  `[Telegram] Connected to Telegram (polling mode)`.

### Runtime measurements (tasks 17–20, 23–25)

| Task | Measurement | Observed result |
| --- | --- | --- |
| 17 | `docker compose build robotina` + `command -v` for the 20 tools | build exit 0; all 20 resolve |
| 18 | `docker compose ps`; PID 1; `/proc/1/status`; `s6-rc -a list`; ports | exactly `robotina`, `egress-proxy`; PID 1 = `s6-svscan … /run/service` (no `tini`/`docker-init`); Uid/Gid 0; 10 services; no host mapping |
| 19 | credential-aware probe; probe without `-u`; host curl; `ss -ltn` | with `-u` exit 0; without `-u` **401** (`no_auth_probe_exit=22`) → endpoint **is** auth-protected; host curl exit 7; only `127.0.0.1:4096`, no wildcard |
| 20 | peer probes + network membership | control `egress-proxy:3128` = 400; `robotina:4096` connection refused (exit 7); `egress-proxy` `/dev/tcp` refused; `agents`={egress-proxy,robotina}, `egress`={egress-proxy} |
| 23 | process key hashes; vendor-patch grep; log secret grep; `GITHUB_TOKEN` | opencode `286c7a04…`, hermes `06c38c58…` → **differ**; both match the exported shell env; vendor-patch grep empty; log secret grep empty; `GITHUB_TOKEN` present |
| 24 | nested mounts; negative control; durability; volume names | 2 `ext4` mounts (not 9p/virtiofs); marker in the volume **absent** from the host bind; marker survived `down`/`up`; 2 volumes |
| 25 | `CapEff`/`CapBnd`/`NoNewPrivs` of the uid-10000 `opencode serve` | `CapInh/Prm/Eff/Amb = 0x0`, `CapBnd = 0x00000000000000cb`, `NoNewPrivs: 1` — matches design §13 |

**Deferred and reported, not closed:** task 21 (3× recreation loop + gate-failure observation),
task 22 (identity layers — tasks 13–16 not implemented), task 26 (peak `pids.current` under the
concurrent worst case; at-rest = 54, `pids.max` = 1024), task 38 (needs the task-26 peak), and
tasks 27–28. Two findings need the parent: the endpoint's auth-protection requires the EP1/EP4 NOTE
in `specs/opencode-endpoint/spec.md` to record the observation, but `specs/` is outside this
session's allowed edit surfaces; and the in-container `robotina:4096` negative-control probe is
confounded by the container's proxy environment (Squid answers with a deny page, exit 0), so the
unconfounded proof is the peer-container probe.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | **~6,800 total** — **~4,730 process artifacts** (measured on disk + this file) **+ ~2,060 implementation & documentation** |
| 400-line budget risk | **High** |
| Chained PRs recommended | **Yes** |
| Suggested split | 10 slices, each ≤ 400 lines: `compose.yml` (~170) → `robotina/Dockerfile` (~220) → `opencode/` removal (~240 deletions) → s6 + `opencode-init.sh` + `healthcheck.sh` (~225) → identity (~275) → state migration + scripts (~147) → README pair (~370) → `SECURITY.md` + records + spec alignment (~330) → measurement evidence (~40); the process artifacts as their own already-phase-reviewed PR (~4,730) |
| Delivery strategy | `ask-on-risk` |
| Chain strategy | **pending** (this phase does not choose one) |

```text
Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High
```

### Measured numbers (not adjectives)

Process artifacts already authored by this change (new files on the branch; measured by line
count of each file):

| File | Lines |
| --- | --- |
| `openspec/changes/single-robotina-container/proposal.md` | 517 |
| `openspec/changes/single-robotina-container/explore.md` | 652 |
| `openspec/changes/single-robotina-container/design.md` | 1,328 |
| `specs/agent-container/spec.md` | 318 |
| `specs/agent-credentials/spec.md` | 245 |
| `specs/agent-identity/spec.md` | 174 |
| `specs/egress-boundary/spec.md` | 190 |
| `specs/opencode-endpoint/spec.md` | 238 |
| `specs/state-layout/spec.md` | 276 |
| `odd/tasks/single-robotina-container.md` | 158 |
| `tasks.md` (this file) | 638 |
| **Subtotal** | **4,734** |

Implementation + documentation delta forecast from the task list below:

| Area | Files | Forecast authored lines (additions + deletions) |
| --- | --- | --- |
| Compose | `compose.yml` rewrite | ~170 |
| Image | `robotina/Dockerfile` (~220), `robotina/overlay.json` (pure rename, 0 authored), `robotina/opencode-init.sh` (~80), `robotina/healthcheck.sh` (~25) | ~325 |
| Removal | delete `opencode/Dockerfile` (169) + `opencode/entrypoint.sh` (71) | ~240 |
| Supervision | `robotina/s6/cont-init.d/*` (~85) + 4 service dirs + `user2` (~185) | ~270 |
| Identity | `hermes/skins/robotina.yaml` (~15), `hermes/context/.hermes.md` (~70), both Hermes skills (~190) | ~275 |
| Migration & scripts | `scripts/migrate-state.ps1` (~110), `scripts/export-state.sh` (~12), `scripts/fix-permissions.ps1` (~25) | ~147 |
| Docs | `README.md` (~180) + `README.en.md` (~190) | ~370 |
| Security & records | `SECURITY.md` (~140), `.env.example` (~12), `openspec/project.md` (~50), `odd/tasks/agent-interop-http.md` (~8), spec `OPEN ITEM` alignment (~30) | ~240 |
| Measurement evidence | `SECURITY.md` measured entries + `odd/tasks/single-robotina-container.md` + one `pids_limit` line | ~40 |
| **Subtotal** | | **~2,060** (range 1,850–2,450) |

### Budget verdict

- **Implementation-only reading** (code + config + docs, ~2,060 lines): the 400-line budget is
  **exceeded by ≈ 1,660 lines** — about **5.2×** the budget.
- **Total reading** (~6,790 lines including the process artifacts): the budget is **exceeded by
  ≈ 6,390 lines** — about **17×** the budget.
- **Process artifacts alone** (4,734 lines): **exceeded by ≈ 4,334 lines** — about **11.8×**.

The process artifacts are a distinct review burden: they are the phase-gated output of
`explore` / `propose` / `spec` / `design` / `tasks` and were reviewed incrementally at each
gate. They cannot be brought under 400 lines without re-cutting frozen artifacts.

### Smallest coherent slices (each bounded ≤ 400 lines)

| Slice | Owns | Authored lines | Depends on |
| --- | --- | --- | --- |
| S0 process artifacts | `openspec/changes/single-robotina-container/**` (proposal, explore, design, specs, tasks) + `odd/tasks/single-robotina-container.md` | 4,734 | — (already authored at prior phase gates) |
| S1 compose | `compose.yml` | ~170 | S0 |
| S2 image | `robotina/Dockerfile` + `robotina/overlay.json` (rename, 0 content) | ~220 | S1 |
| S3 removal | delete `opencode/Dockerfile`, `opencode/entrypoint.sh`, `opencode/overlay.json` | ~240 (deletions) | S2 |
| S4 supervision | `robotina/s6/**` (cont-init `10-robotina-state`, 4 service dirs, `user2`) + `robotina/opencode-init.sh` + `robotina/healthcheck.sh` | ~225 | S2 |
| S5 identity | `hermes/skins/robotina.yaml` + `robotina/s6/cont-init.d/20-robotina-identity` + `hermes/context/.hermes.md` + both Hermes skills | ~275 | S4 |
| S6 migration & scripts | `scripts/migrate-state.ps1` + `scripts/export-state.sh` + `scripts/fix-permissions.ps1` | ~147 | S4 |
| S7 docs (bilingual pair, one commit) | `README.md` + `README.en.md` | ~370 | S4, S6 |
| S8 records | `SECURITY.md` (non-measured entries) + `.env.example` + `openspec/project.md` + `odd/tasks/agent-interop-http.md` + spec `OPEN ITEM` alignment | ~240 | S7 |
| S9 measurement evidence | measured entries in `SECURITY.md` (R3 `CapEff`/`CapBnd`, R5 budget + `pids_limit`, SL2 nesting result, EP4 gate behaviour) + `odd/tasks/single-robotina-container.md` evidence + the `pids_limit` line in `compose.yml` | ~40 | S5, S7, S8, design Q1/Q4 measurements and the user's `pids_limit` decision |

**Recommended slicing:** S1 → S2 → S4 → S5 → S6 → S7 → S8 → S9, with S0 as its own PR and S3
kept as an independent deletion PR (splitting the move-across-PRs is safe because after S1
nothing in the tree references `opencode/` any more).
**Cost of this recommendation:** 8 implementation PRs + 1 process-artifact PR in a serial
chain (compose → image → supervision → {identity, migration} → docs → records → evidence); the
tree briefly keeps an unused `opencode/` directory between S2 and S3. Folding S3 into S2 (one
delete-with-replacement work unit, ~460 lines) removes a PR at the price of one slice over
budget. S8 and S9 both touch `SECURITY.md`: S8 owns every non-measured entry, S9 owns only the
measured-value lines, so the two slices do not overlap.

**This phase stops here.** Under `delivery_strategy: ask-on-risk` the delivery decision
(chained PRs vs a single PR, and which chain strategy) is the orchestrator's/user's to make
before `sdd-apply` starts. No chain strategy is chosen here and no `size:exception` is
inferred.

## Measurement-dependent register

| Task | Forecast being closed | Design anchor | Gate |
| --- | --- | --- | --- |
| 24 | nested volume-inside-bind behaves on Docker Desktop Windows | §7.3 | first `up`; failure → escalate to user (no silent `/root` fallback) |
| 25 | measured `CapEff`/`CapBnd`/`CapPrm`/`CapAmb` + `NoNewPrivs` of the uid-10000 opencode process | §13, Q4 | first `up`; `CapEff != 0` → record + escalate (no mitigation, D2) |
| 26 | baseline and peak `pids.current` under the concurrent worst case | §16, Q1 | first `up` |
| 38 | `pids_limit` confirmation via the pre-committed adjustment rule | §16, Q1 | task 26 result |
| 40 | readiness-gate failure behaviour of s6-overlay (abort vs continue to CMD) | §9.1 | task 21 observation |
| 27 | `pids_limit` value as a capacity decision (documented) | §16 | task 38 |

---

## Phase 0 — Baseline and guardrails

- [x] 1. Capture the pre-change baseline for the change record: today's service inventory, the
  running two-container PID-1 command lines, the mount list, and the two state volume names.
  Write the raw output into `odd/tasks/single-robotina-container.md` under
  `## Verification evidence`. Files: `odd/tasks/single-robotina-container.md`.
  - Verify: `docker compose config --services` (expect `hermes`, `opencode`, `egress-proxy`)
    and `docker volume ls --format '{{.Name}}' | grep -cE '^robotina_(engram|opencode)_db$'`
    (expect `2`).

- [x] 2. Confirm the working branch, a clean tree and the secret-hygiene precondition.
  Files: none.
  - Verify: `git rev-parse --abbrev-ref HEAD` → `feat/single-robotina-container`;
    `git check-ignore -v .env` (non-empty); `git ls-files .env` (no output);
    `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'`
    (no output).

- [x] 3. Record the resolved vendor base image digest and the current measured tool versions
  for the change record (design §2.5 — the digest is recorded at verification, digest pinning
  stays out of scope). Files: `odd/tasks/single-robotina-container.md`.
  - Verify: `docker inspect --format '{{index .RepoDigests 0}}' nousresearch/hermes-agent:latest`
    (narrow `--format` only, never the environment block).

## Phase 1 — Compose: one agent service

- [x] 4. Rewrite `compose.yml` into one `robotina` service plus the untouched `egress-proxy`:
  `pids_limit` out of `x-hardening` and per-service (egress keeps its explicit `128`), the
  `NO_PROXY` / `no_proxy` entries swapped to `robotina`, both API keys under distinct names
  (design §10.1), the §7.1 mount table (nested `robotina_engram_db` / `robotina_opencode_db`
  volumes, new read-only `./hermes/skins` → `/opt/data/skins`), tmpfs `/tmp` with `exec`,
  `mem_limit: 6g` / `cpus: 6.0` / `pids_limit: 1024`, the healthcheck, both volume names kept,
  `agents` only, no `user:`, no `init: true`. Keep the Spanish comments.
  Files: `compose.yml`. Depends on: task 1.
  - Verify: `docker compose config -q && docker compose config --services` (exactly
    `egress-proxy` and `robotina`); `git grep -n "docker.sock" -- compose.yml` (no output);
    `git grep -nE '^[[:space:]]+ports:' -- compose.yml` (no output);
    `git grep -n 'HOST_DATA_DIR:?' -- compose.yml` (non-empty);
    `git grep -n "HOST_DATA_DIR" -- compose.yml | grep -E "/(opencode|git|go)"` (no output).

## Phase 2 — Image build context

- [x] 5. Author `robotina/Dockerfile`: vendor Debian base, the four new version pins
  (`OPENCODE_VERSION`, `GH_VERSION`, `TAPLO_VERSION`), `SHELL ["/bin/bash", "-o", "pipefail",
  "-c"]`, the twelve ordered layers of design §2.1, the explicit drop list of §2.2, the add
  list with pins of §2.3, the glibc-opencode assertion block and the tool-inventory assertion
  block of §2.6, the `/etc/gitconfig` preserve-then-merge of §3, `ENV PATH=$PATH:/opt/uv/bin`
  appended (never prepended), and **no** `ENTRYPOINT`/`CMD` override. Spanish comments.
  Files: `robotina/Dockerfile`. Depends on: task 4.
  - Verify: `docker compose build robotina` (exit 0 — the assertion block must fail the build
    loudly on a wrong asset).

- [x] 6. Move `opencode/overlay.json` to `robotina/overlay.json`, content unchanged.
  Files: `robotina/overlay.json`, `opencode/overlay.json`. Depends on: task 5.
  - Verify: `git status --porcelain -- robotina/overlay.json opencode/overlay.json` shows the
    rename; `docker compose build robotina` (exit 0).

- [x] 7. Author `robotina/opencode-init.sh` (the oneshot, runs as uid 10000): staged
  gentle-ai tree authoritative except `node_modules` / `package-lock.json`, non-destructive
  per-key `overlay.json` merge with `permission` replaced wholesale, invalid JSON quarantined
  to `opencode.json.invalid-<timestamp>` (never fatal), atomic write inside the config
  directory, `/workspace` writability warning only. Spanish comments.
  Files: `robotina/opencode-init.sh`. Depends on: task 5.
  - Verify: `docker compose build robotina` (exit 0, the build runs a syntax check on the
    script); the behavioural proof is task 27.

- [x] 8. Author `robotina/healthcheck.sh`: loopback health probe that is credential-aware
  (`-u "opencode:$OPENCODE_SERVER_PASSWORD"` only when the variable is non-empty) plus an
  `engram serve` existence check using a character-class pattern. The file is image-shipped so
  no secret-shaped string appears in `docker inspect` output. Spanish comments.
  Files: `robotina/healthcheck.sh`. Depends on: task 5.
  - Verify: `docker compose build robotina` (exit 0);
    `docker inspect --format '{{.Config.Healthcheck.Test}}' robotina` (after task 18, shows the
    image path, no interpolated secret).

- [x] 9. Remove the superseded build context: `git rm -r opencode/` (its logic is fully ported
  into `robotina/`). Files: `opencode/Dockerfile`, `opencode/entrypoint.sh`,
  `opencode/overlay.json`. Depends on: tasks 5, 6, 7.
  - Verify: `git ls-files opencode/` (no output); `docker compose config -q` (exit 0).

## Phase 3 — s6 supervision tree

- [x] 10. Author `robotina/s6/cont-init.d/10-robotina-state` (runs as root, after the vendor
  `01-hermes-setup`): `install -d -o 10000 -g 10000` for the state directories, the
  self-heal `chown -R` on `/opt/data` only when the app uid cannot write it, an explicit
  bounded `chown -R` on the two nested volume roots, and uid derivation from `id -u hermes`.
  Spanish comments. Files: `robotina/s6/cont-init.d/10-robotina-state`.
  Depends on: task 5.
  - Verify: `docker compose build robotina` (exit 0); the behavioural proof is task 22's SL6
    write test.

- [x] 11. Author the `opencode` and `engram` longruns: `type`, `run` (both
  `#!/command/with-contenv`, `HOME=/opt/data`, `XDG_*` scoped to the opencode process, the key
  rewritten into the vendor name and the robotina-named copy unset, `cd /workspace`,
  `exec s6-setuidgid hermes …`, no secret in any banner), `dependencies.d/*` per design §5.1,
  and the `finish` script with capped exponential backoff (healthy-run reset at ≥ 10 s) for
  both. Spanish comments. Files: `robotina/s6/s6-rc.d/{opencode,engram}/**`.
  Depends on: task 10.
  - Verify: `docker compose build robotina` (exit 0 — the build asserts `type`, script
    presence, executability, `sh -n` and the dependency files).

- [x] 12. Author the `opencode-init` and `opencode-ready` oneshots (`opencode-ready` polls the
  credential-aware loopback health endpoint with the 120 s bound) and register all four names
  under `robotina/s6/s6-rc.d/user2/contents.d/`. Spanish comments.
  Files: `robotina/s6/s6-rc.d/{opencode-init,opencode-ready}/**`,
  `robotina/s6/s6-rc.d/user2/contents.d/*`. Depends on: task 11.
  - Verify: `docker compose build robotina` (exit 0);
    `docker compose exec robotina s6-rc -a list | grep -E '^(opencode|engram)$'` (two lines,
    after task 18). If that match is empty on the first real start, apply design §5.4's
    one-line contingency (add the same names to `user/contents.d/`) and re-run the same probe.

## Phase 4 — Identity

- [x] 13. Author `hermes/skins/robotina.yaml` with `name: robotina` and
  `branding.agent_name: robotina`, deriving the full schema from the vendor-bundled sample
  skin at apply (design §11.1). If the vendor's displayed-name key differs, use the vendor key
  and record the correction in the change record — the observable does not change.
  Files: `hermes/skins/robotina.yaml`. Depends on: task 4.
  - Verify: `git ls-files hermes/skins/robotina.yaml` (non-empty);
    `grep -nE "^(name: robotina| +agent_name: robotina)$" hermes/skins/robotina.yaml`
    (two matches).

- [x] 14. Author `robotina/s6/cont-init.d/20-robotina-identity`: guarded and idempotent
  (`skin: robotina` already present → no write), loud warning and exit 0 when
  `/opt/data/config.yaml` is absent (never brick startup over cosmetics), otherwise
  `s6-setuidgid hermes env HOME=/opt/data hermes config set display.skin robotina`; ordered
  after the vendor hook and before the main program so it cannot fight `stage2-hook.sh`; a
  documented fallback (vendored YAML library via `/opt/hermes/.venv/bin/python`) if the CLI
  differs. Spanish comments. Files: `robotina/s6/cont-init.d/20-robotina-identity`.
  Depends on: task 10.
  - Verify: `docker compose build robotina` (exit 0); the behavioural proofs are task 22.

- [x] 15. Rewrite `hermes/context/.hermes.md` for the merged topology: explicit identity
  statement, one agent container, no sibling opencode container, endpoint
  `http://127.0.0.1:4096`, `gh` installed and `GITHUB_TOKEN` present, and a private-repo
  `404` reframed as a token-permissions problem. Avoid every banned substring listed in
  design §11.3. Files: `hermes/context/.hermes.md`. Depends on: task 4.
  - Verify: `grep -niE "robotina" hermes/context/.hermes.md` (non-empty);
    `grep -rniE "sibling container|contenedor hermano|http://opencode:4096|own container|propio contenedor" hermes/context/.hermes.md`
    (no output); `grep -n "http://127.0.0.1:4096" hermes/context/.hermes.md` (non-empty).

- [x] 16. Rewrite `hermes/skills/opencode-server/SKILL.md` for the local server and
  `hermes/skills/github-private-repos/SKILL.md` for the retired credential split, keeping the
  `OPENCODE_SERVER_PASSWORD` recipe where it is used. Files: both skill files.
  Depends on: task 15.
  - Verify:
    `grep -rniE "sin credencial|no github credential|no tiene token|delegate to opencode|delegar a opencode|does not run inside this container|no esta instalado|no rewrite" hermes/ SECURITY.md`
    (no output) and
    `grep -rniE "claves? (estan |están )?aislad|keys? are isolated|aisladas por proceso|isolated per process|no puede leer la clave del otro|cannot read the other" README.md README.en.md SECURITY.md hermes/`
    (no output).

## Phase 5 — First build, first `up`, and the measurements

- [x] 17. Build the merged image and confirm the tool inventory the verification suite assumes.
  Files: none. Depends on: tasks 9, 12.
  - Verify: `docker compose build robotina` (exit 0);
    `docker compose exec robotina sh -c 'command -v gh jq rg go opencode taplo marksman codegraph engram gentle-ai uv node npm python3 R pgrep pkill ss curl git'`
    (every path printed).

- [x] 18. Bring the stack up for the first time and confirm the container shape: exactly one
  agent container plus the proxy, PID 1 is the vendor entrypoint chain, the s6 database is
  live, nothing is published. Files: none. Depends on: task 17.
  - Verify: `docker compose up -d && docker compose ps` (exactly `robotina` and
    `egress-proxy`); `docker compose exec robotina sh -c 'tr "\0" " " < /proc/1/cmdline'` (no
    `tini`, no `docker-init`); `docker compose exec robotina sh -c 'grep -E "^(Uid|Gid)" /proc/1/status'`
    (both `0`); `docker compose exec robotina s6-rc -a list` (non-empty);
    `docker compose ps --format 'table {{.Name}}\t{{.Ports}}'` (no host mapping).

- [x] 19. Verify the loopback-only endpoint from inside the container and the host, and record
  once whether the health endpoint is auth-protected (design §19.4 apply obligation).
  Files: `odd/tasks/single-robotina-container.md`. Depends on: task 18.
  - Verify: `docker compose exec robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/global/health'`
    (exit 0); the same probe **without** `-u` (record the result); host-side
    `curl -m 5 -sS http://127.0.0.1:4096/global/health` (non-zero exit);
    `docker compose exec robotina sh -c 'ip=$(getent hosts robotina | awk "{print \$1}" | head -1); echo "addr=$ip"; set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; test -n "$ip" && curl -sS "$@" -m 5 "http://$ip:4096/global/health"'`
    (`addr=` non-empty and not loopback; the curl fails);
    `docker compose exec robotina sh -c 'ss -ltn'` (`127.0.0.1:4096` present, no wildcard bind).
    If the endpoint turns out to be auth-protected, amend EP1/EP4's recipes in
    `specs/opencode-endpoint/spec.md` in the same commit.

- [x] 20. Verify the endpoint is unreachable from every network peer and that network
  membership is `agents` only. Files: none. Depends on: task 18.
  - Verify: `docker run --rm --network agents curlimages/curl -m 5 -sS -o /dev/null -w 'control=%{http_code}\n' http://egress-proxy:3128`
    (numeric control code); `docker run --rm --network agents curlimages/curl -m 5 -sS http://robotina:4096/global/health`
    (connect-level refusal, not a name-resolution failure);
    `docker compose exec egress-proxy bash -c 'echo bash-ok'` then
    `docker compose exec egress-proxy bash -c 'exec 3<>/dev/tcp/robotina/4096'` (non-zero);
    `docker network inspect agents --format '{{range .Containers}}{{.Name}} {{end}}'` and
    `docker network inspect egress --format '{{range .Containers}}{{.Name}} {{end}}'`.

- [x] 21. Verify the readiness gate holds across repeated recreations and that no
  `ECONNREFUSED` reaches the log; record what s6-overlay does when the gate fails.
  Files: `odd/tasks/single-robotina-container.md`. Depends on: task 19.
  - Verify: `for i in 1 2 3; do docker compose down && docker compose up -d && docker compose exec robotina sh -c 'j=0; while [ $j -lt 60 ]; do set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 2 http://127.0.0.1:4096/global/health >/dev/null && exit 0; j=$((j+1)); sleep 2; done; exit 1' || exit 1; done`;
    `docker compose logs --since 10m robotina 2>&1 | grep -Ei '127\.0\.0\.1:4096.*(refused|econnrefused)'`
    (no output); record the measured cold start and the gate-failure behaviour.

- [x] 22. Verify the identity layers and the state-ownership behaviour at runtime (ID1, ID2,
  ID3, ID5, SL6). Files: `odd/tasks/single-robotina-container.md`. Depends on: tasks 13, 14,
  15, 18.
  - Verify: `docker compose exec robotina sh -c 'ls -l /opt/data/skins/robotina.yaml'`;
    `docker compose exec robotina sh -c 'touch /opt/data/skins/robotina.yaml'` (read-only
    error); `docker compose exec robotina sh -c 'grep " /opt/data/skins" /proc/self/mountinfo'`
    (source not under the host data directory, `ro`); `docker compose exec robotina sh -c 'grep -niE "skin" /opt/data/config.yaml'`
    (non-empty, `robotina`); `docker compose exec robotina sh -c 'grep -c "robotina" /workspace/.hermes.md'`
    (non-zero); `docker compose exec robotina sh -c 'printenv NO_PROXY'` (contains `robotina`,
    not `hermes`/`opencode`); `docker compose exec robotina sh -c 's6-setuidgid hermes sh -c "touch /opt/data/.write-test && rm /opt/data/.write-test" && echo writable-as-10000'`;
    `docker compose exec robotina sh -c 'stat -c "%u:%g" /opt/data'` (`10000:10000`); and an
    isolated-project fresh-state run:
    `docker compose -p robotina-fresh config -q` then `docker compose -p robotina-fresh up -d robotina`
    then the write test and the skin grep against `robotina-fresh`.

- [x] 23. Verify per-process key configuration and secret hygiene (CR1–CR4): run `KEY-PROBE`
  and `KEY-REFERENCE` and confirm the two hashes are equal to their `.env` references and
  differ from each other, confirm no vendor file under `/opt/hermes` is patched, and confirm no
  secret reaches a tracked file or the log stream. Files: none. Depends on: task 18.
  - Verify: `docker compose exec robotina sh -c '
    for p in $(pgrep -f "[o]pencode serve"); do echo "opencode: $(tr "\0" "\n" < /proc/$p/environ | grep "^OPENCODE_GO_API_KEY=" | sha256sum)"; done
    for p in $(pgrep -f "[h]ermes gateway"); do echo "hermes: $(tr "\0" "\n" < /proc/$p/environ | grep "^OPENCODE_GO_API_KEY=" | sha256sum)"; done'`
    (both lines non-empty) then
    `grep -m1 "^HERMES_OPENCODE_GO_API_KEY=" .env | tr -d "\r" | sed "s/^HERMES_//" | sha256sum`
    and `grep -m1 "^OPENCODE_GO_API_KEY=" .env | tr -d "\r" | sha256sum`;
    `git grep -nE '(sed|cat|tee|cp)[^\n]*([/]opt/hermes/(bin|\.venv|docker))' -- robotina/ compose.yml`
    (no output); `docker compose logs robotina 2>&1 | grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN|OPENCODE_SERVER_PASSWORD)='`
    (no output); `docker compose exec robotina sh -c 'test -n "$GITHUB_TOKEN" && echo present'`;
    `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'`
    (no output).

- [x] 24. **[measurement-dependent]** Prove the nested volume-inside-bind layout positively
  and with a negative control (design §7.3, SL2/SL3), and record the raw output.
  Files: `odd/tasks/single-robotina-container.md`. Depends on: task 18.
  - Verify: `docker compose exec robotina sh -c 'mount | grep -E "\.engram|\.local/share/opencode"'`
    (exactly two lines, neither `9p` nor `virtiofs`);
    `docker inspect --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' robotina`
    (two volume mounts at the nested targets);
    `docker compose exec robotina sh -c 's6-setuidgid hermes sh -c "echo probe > /opt/data/.engram/.robotina-probe"'`
    then host-side `ls -A "$HOST_DATA_DIR/hermes/.engram"` (**must be empty**);
    `docker compose down && docker compose up -d` then
    `docker compose exec robotina sh -c 'cat /opt/data/.engram/.robotina-probe'` (survives);
    `docker volume ls --format '{{.Name}}' | grep -cE '^robotina_(engram|opencode)_db$'` (2).
    **Escalation path:** a `9p`/`virtiofs` mount, a probe that appears in the host directory,
    or an empty/missing `mount | grep` is a **FAIL** → stop and escalate to the user with the
    `/root`-rooted alternative (explore §5 option 1) as a decision; never substitute it
    silently.
    Additional store proof once a delegation has been served:
    `docker compose exec robotina sh -c 'find /opt/data/.engram /opt/data/.local/share/opencode -maxdepth 2 -name "*.db" | sort'`
    (non-empty).

- [x] 25. **[measurement-dependent]** Measure the uid-10000 opencode process's capability masks
  and `NoNewPrivs` (design §13, Q4) and record the values verbatim.
  Files: `odd/tasks/single-robotina-container.md`. Depends on: task 18.
  - Verify: `docker compose exec robotina sh -c 'for p in $(pgrep -f "[o]pencode serve"); do echo "pid=$p uid=$(awk "/^Uid/{print \$2}" /proc/$p/status)"; grep -E "Cap(Inh|Prm|Eff|Bnd|Amb)|NoNewPrivs" /proc/$p/status; done'`
    (at least one `pid=` line — an empty match is a FAILURE).
    Expected `CapBnd = 0x00000000000000cb`, `CapEff`/`CapPrm`/`CapAmb = 0x0`, `NoNewPrivs: 1`.
    **If `CapEff != 0`:** write the measured masks and the decode against the five-capability
    table, and **escalate to the user as a new decision** (accept-and-document or a follow-up
    change). Do **not** add `capsh`/`setpriv`/`libcap2-bin` in this change (D2).

- [ ] 26. **[measurement-dependent]** Sample the merged cgroup's `pids.current` baseline and
  its 1 Hz peak while the worst-case workload runs concurrently (design §16): an OpenCode
  session exercising all six LSPs, an R source build with `Ncpus=6`, `go build ./...`,
  `npm ci && npm test` with a parallel runner, and Telegram traffic for the duration.
  Files: `odd/tasks/single-robotina-container.md`. Depends on: task 18.
  - Verify: `docker compose exec robotina sh -c 'cat /sys/fs/cgroup/pids.current; cat /sys/fs/cgroup/pids.max'`
    (baseline + limit) and
    `docker compose exec robotina sh -c 'i=0; while [ $i -lt 900 ]; do cat /sys/fs/cgroup/pids.current; i=$((i+1)); sleep 1; done | sort -n | tail -1'`
    (peak). Record all three numbers; they feed task 38.

- [x] 27. Verify the `opencode-init` semantics at runtime: overlay idempotency (double-run byte
  identity), the invalid-JSON quarantine path, and engram output observability (AC5, SL4).
  Files: `odd/tasks/single-robotina-container.md`. Depends on: tasks 7, 18.
  - Verify: `docker compose exec robotina sh -c 'sha256sum /opt/data/.config/opencode/opencode.json'`
    before and after `docker compose restart robotina` (identical hashes); seed an
    intentionally invalid `opencode.json`, restart, and confirm the quarantine file
    `opencode.json.invalid-*` exists and the container still comes up;
    `docker compose logs --tail 200 robotina` (non-empty and carries the `engram` / `opencode`
    banner lines).

- [ ] 28. Verify s6 recovery and the single-lifecycle property (AC5, AC8 amended proof).
  Files: `odd/tasks/single-robotina-container.md`. Depends on: task 21.
  - Verify: `docker compose exec robotina sh -c 'pkill -f "[o]pencode serve"'` then the
    bounded credential-aware health probe loop (30 × 2 s) must succeed without manual
    intervention; then capture
    `docker inspect --format '{{.RestartCount}} {{.State.StartedAt}}' robotina`, run
    `docker compose exec robotina sh -c 'pkill -f "[h]ermes gateway"'`, and assert the counter
    increased and `StartedAt` moved. Destructive by design — run last in the session.

## Phase 6 — Migration helper and documentation

- [x] 29. Author `scripts/migrate-state.ps1`: per-path copy-forward **only when the
  destination is absent**, `node_modules/` skipped inside the legacy opencode folder,
  `package-lock.json` copied, no delete/move primitive anywhere, a copied/skipped summary, and
  a closing assertion that the three legacy folders still exist and the two copied-from
  folders are non-empty. Spanish comments. Files: `scripts/migrate-state.ps1`.
  Depends on: task 18.
  - Verify: capture `sha256sum` of a destination file with newer content, run the documented
    migration step twice, re-capture (identical hashes);
    `grep -niE "Remove-Item|Move-Item|rm -rf|Remove-Item -Recurse" scripts/migrate-state.ps1`
    (no output);
    `HOST_DATA_DIR=$(grep -m1 '^HOST_DATA_DIR=' .env | cut -d= -f2- | tr -d "\r"); ls -ld "$HOST_DATA_DIR/opencode" "$HOST_DATA_DIR/git" "$HOST_DATA_DIR/go"`
    (all three exist) and `ls -A "$HOST_DATA_DIR/opencode" "$HOST_DATA_DIR/git"` (non-empty);
    `ls -d "$HOST_DATA_DIR/hermes/go"` (must fail — the Go cache is not copied).

- [x] 30. Update `scripts/export-state.sh`: header comment and the invocation prefix for the
  merged container name, keeping the existing loopback endpoint and the
  `OPENCODE_SERVER_PASSWORD` auth path. Spanish comments. Files: `scripts/export-state.sh`.
  Depends on: task 4.
  - Verify: `grep -n OPENCODE_SERVER_PASSWORD scripts/export-state.sh` (non-empty);
    `grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/`
    (no output).

- [x] 31. `scripts/fix-permissions.ps1` — **undecided item, interim safe default only.**
  Keep the file and rewrite its header to say it is **superseded by the container-side
  cont-init step and no longer part of setup**; drop `opencode` / `git` / `go` from its target
  list (they are no longer mounts) and keep `workspace` / `backups` plus the two volumes as a
  repair-only tool; remove every setup instruction that tells the operator to run it.
  **Deletion is a separate user decision and is NOT taken here.** It must be confirmed by the
  user before any removal, and no task in this change may delete the file. Files:
  `scripts/fix-permissions.ps1`. Depends on: task 10.
  - Verify: `git ls-files scripts/fix-permissions.ps1` (non-empty — the file still exists);
    `grep -rniE "fix-permissions" README.md README.en.md SECURITY.md` returns only
    explanatory text, never a numbered setup step (human reading of the hits).

- [x] 32. Update `.env.example`: document both key names with no values, note the routing of
  the two keys into the merged container, and refresh the `docker inspect` comment to name the
  narrow `--format` rule. Files: `.env.example`. Depends on: task 4.
  - Verify: `git grep -n "HERMES_OPENCODE_GO_API_KEY\|OPENCODE_GO_API_KEY" -- .env.example compose.yml`
    (both names present, no value);
    `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'`
    (no output).

- [x] 33. Rewrite `README.md` (Spanish) and `README.en.md` (English) **in the same commit**
  with: the one-container topology, the build step, the removal of the host permission step,
  the copy-forward migration step plus the documented POSIX equivalent, the safety-net note to
  run `scripts/export-state.sh` before migrating, the BotFather step as **display name only**
  (never an `@username` change), the in-container operator recipes
  (`docker compose exec robotina …`, `docker compose logs --tail 200 robotina`), the
  persistence table (the two nested volumes and the expected empty host mount-point
  directories), the measured tool versions, and the note that the numeric proofs assume the
  default uid 10000. Files: `README.md`, `README.en.md`. Depends on: tasks 29, 30.
  - Verify: `git diff --name-only $(git merge-base HEAD main)...HEAD -- README.md README.en.md`
    (both listed);
    `grep -c "docker compose exec robotina" README.md README.en.md` (both non-zero);
    `grep -ci "botfather" README.md README.en.md` (both non-zero);
    `grep -rniA6 "botfather" README.md README.en.md | grep -iE "username"` (no output);
    `grep -ciE "migra|migration|\.config/opencode" README.md README.en.md` (both non-zero);
    the four stale-claim greps of agent-container AC9 (all empty):
    `grep -rn "http://opencode:4096" README.md README.en.md SECURITY.md hermes/ scripts/`,
    `grep -rniE "dos agentes|dos contenedores|two agent containers|two containers|sibling container|contenedor hermano" README.md README.en.md SECURITY.md hermes/ scripts/`,
    `grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/ .env.example`,
    `grep -rn "docker inspect hermes\|docker inspect opencode" README.md README.en.md SECURITY.md .env.example`.

- [x] 34. Update `openspec/project.md`: services table, coupling map, repository layout,
  known traps, verification expectations and the SDD session configuration, all for the merged
  reality. Files: `openspec/project.md`. Depends on: task 33.
  - Verify: `grep -n "opencode/Dockerfile" openspec/project.md` (no output);
    `grep -c "robotina" openspec/project.md` (non-zero).

- [x] 35. Add the **superseded-by** note to `odd/tasks/agent-interop-http.md` (R6) without
  rewriting its history, and refresh `odd/tasks/single-robotina-container.md`: mark the phase
  tasks complete, correct the stale acceptance line that claims "neither process can read the
  other's key" to the CR6 wording, and replace the `## Next step` pointer.
  Files: `odd/tasks/agent-interop-http.md`, `odd/tasks/single-robotina-container.md`.
  Depends on: task 33.
  - Verify: `grep -niE "superseded" odd/tasks/agent-interop-http.md` (non-empty);
    `git diff --stat -- odd/tasks/agent-interop-http.md` (additions only, no rewrites of the
    existing record); `grep -niE "neither process can read" odd/tasks/single-robotina-container.md`
    (no output).

- [x] 36. Align the stale `OPEN ITEM` annotations in this change's own specs with the design
  decisions that closed them: in `specs/agent-container/spec.md` (Q1, Q3, Q10),
  `specs/opencode-endpoint/spec.md` (Q2, Q5) and `specs/state-layout/spec.md` (Q7, Q12),
  replace each open annotation with a `CLOSED BY DESIGN §…` note naming the section
  (§16, §9.2, §9.3, §9.1, §10.3, §8.4, §12) and the chosen mechanism. Keep every requirement
  text and every named recipe unchanged; this is documentation alignment inside this change's
  own artifacts, not a scope change. Files: the three spec files named above. Depends on: task
  33.
  - Verify: `grep -rn "OPEN ITEM" openspec/changes/single-robotina-container/specs/` (no
    output) and
    `grep -rn "CLOSED BY DESIGN" openspec/changes/single-robotina-container/specs/`
    (at least 7 matches — one per closed question: Q1, Q2, Q3, Q5, Q7, Q10, Q12);
    `grep -rniE "owned by \`sdd-design\`" openspec/changes/single-robotina-container/specs/`
    (no output).

- [x] 37. Conditional wording alignment: check `openspec/config.yaml`'s prose line that names
  the static-validation command against design §19.3's same-line rule; reword only if the
  check reports a line, and record the outcome either way.
  Files: `openspec/config.yaml` (only if the check reports a hit). Depends on: task 36.
  - Verify: `git grep -nE "docker compose confi[g]" -- openspec/config.yaml` — every hit must
    carry `-q` (or `--services` / `--format`) on the same line; record the result in the change
    record. If a hit fails, reword it and re-run the same check.

## Phase 7 — `pids_limit` confirmation

- [ ] 38. **[measurement-dependent]** Apply design §16's pre-committed adjustment rule to the
  task-26 peak and confirm or change the value, recording peak, limit and rationale in one
  place. Files: `compose.yml` (only when the rule raises the value),
  `odd/tasks/single-robotina-container.md`, `SECURITY.md` (R5, finalized in task 40).
  Depends on: task 26.
  - Verify: `docker compose config -q`; `docker compose exec robotina sh -c 'cat /sys/fs/cgroup/pids.max'`
    (finite, never `max`); recorded peak vs limit: ≤ 614 → confirm 1024; > 614 → raise to
    the next value restoring ≥ 40 % headroom (1536, then 2048) and record it; ≤ 256 → keep
    1024 and record the reason.

## Phase 8 — `SECURITY.md` evidence entries

- [x] 39. Rewrite `SECURITY.md`'s non-measured retained entries (Spanish): R1 (credential
  invariant retired, PAT kept as-is, prompt-injection reach stated), R2 (per-process key
  isolation **not enforceable** at equal uid; acceptance expressed as "configured with only its
  own key"), R4 (single lifecycle), R6 (superseded task file), R7 (shared workspace without a
  container boundary), the `OPENCODE_SERVER_PASSWORD` defense-in-depth rationale, engram's log
  destination, the PID-1-must-be-the-entrypoint rule, and the nesting result. Files:
  `SECURITY.md`. Depends on: task 33.
  - Verify: `grep -niE "GITHUB_TOKEN" SECURITY.md` (non-empty);
    `grep -niE "mismo uid|equal uid|no se puede aislar|not enforceable|misma identidad" SECURITY.md`
    (non-empty);
    `grep -n OPENCODE_SERVER_PASSWORD SECURITY.md README.md README.en.md scripts/export-state.sh`
    (non-empty);
    `grep -rniE "solo lo alcanza quien este en la red|puede manejar opencode|can drive opencode|reachable from the host|alcanzable desde el host" README.md README.en.md SECURITY.md`
    (no output);
    `grep -rniE "sin credencial|no github credential|no tiene token|no esta instalado" SECURITY.md`
    (no output).

- [ ] 40. **[measurement-dependent]** Add `SECURITY.md`'s measured evidence entries: R3's
  `CapEff`/`CapBnd` masks with the five-bit decode, R5's budget with the measured `pids_limit`
  and the recorded peak, SL2's nesting result (including the `9p`/`virtiofs` finding), and the
  observed behavior of the container start when the readiness gate fails. Files:
  `SECURITY.md`, `odd/tasks/single-robotina-container.md`. Depends on: tasks 24, 25, 26, 38,
  39.
  - Verify: `grep -n "CapEff\|CapBnd" SECURITY.md` (non-empty);
    `grep -niE "mem_limit|6g|pids_limit" SECURITY.md` (non-empty);
    `grep -niE "9p|virtiofs|mount" SECURITY.md` (nesting result recorded);
    `docker compose exec robotina sh -c 'cat /sys/fs/cgroup/pids.max'` (matches the documented
    value).

- [ ] 41. Finalize the change record: replace the ODD file's `## Verification evidence`
  placeholder with the collected evidence (base digest, measured versions, service list,
  nesting + capability + `pids` results, restart observations, the §19.4 auth result, the §19.5
  interpretation results) and add this change's progress entry.
  Files: `odd/tasks/single-robotina-container.md`. Depends on: task 40.
  - Verify: `grep -c "robotina" odd/tasks/single-robotina-container.md` (non-zero);
    `grep -niE "CapEff|pids|nesting|digest" odd/tasks/single-robotina-container.md`
    (non-empty); `grep -n "_(pending)_" odd/tasks/single-robotina-container.md` (no output).

## Phase 9 — Final verification and rollback safety

- [ ] 42. Run the verification suite end to end on the final tree and record the result.
  Files: `odd/tasks/single-robotina-container.md`. Depends on: task 40.
  - Verify: `docker compose config -q && docker compose build && docker compose up -d && docker compose ps`
    (exactly `robotina` and `egress-proxy`), plus the loopback health probe of task 19.

- [ ] 43. Confirm the frozen egress boundary and the mandatory-input guard survived the merge.
  Files: none. Depends on: task 4.
  - Verify: `git diff --exit-code $(git merge-base HEAD main)...HEAD -- squid/` (exit 0);
    `git status --porcelain -- squid/` (no output);
    `env -u HOST_DATA_DIR docker compose --env-file /dev/null config -q` (non-zero exit);
    `docker compose exec robotina sh -c 'printenv NO_PROXY; printenv no_proxy'` (contains
    `robotina`, `127.0.0.1`, `egress-proxy`); `docker compose logs egress-proxy 2>&1 | grep -n "127.0.0.1:4096"`
    (no output).

- [ ] 44. Confirm the rollback path is intact: both state volume names unchanged, the three
  legacy host folders present and non-empty, the new `robotina/` tree and removal of `opencode/`
  revertible as one unit, and no destructive action taken anywhere.
  Files: none. Depends on: tasks 29, 43.
  - Verify: `docker volume ls --format '{{.Name}}' | grep -cE '^robotina_(engram|opencode)_db$'`
    (2);
    `HOST_DATA_DIR=$(grep -m1 '^HOST_DATA_DIR=' .env | cut -d= -f2- | tr -d "\r"); ls -ld "$HOST_DATA_DIR/opencode" "$HOST_DATA_DIR/git" "$HOST_DATA_DIR/go"`
    (all three exist) and `ls -A "$HOST_DATA_DIR/opencode" "$HOST_DATA_DIR/git"` (non-empty);
    `git ls-files scripts/fix-permissions.ps1` (**no output — the file was deleted** with the
    user's explicit Q7 confirmation; the rollback path stays intact because git history retains
    the script and neither state volume nor any host folder is destroyed, so the deletion is a
    revertible unit alongside the rest of this change).

- [ ] 45. Final secret-leak audit over the whole change, including this file.
  Files: none. Depends on: tasks 42, 43, 44.
  - Verify: `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'`
    (no output); `docker compose logs robotina 2>&1 | grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN|OPENCODE_SERVER_PASSWORD)='`
    (no output); `git check-ignore -v .env` (non-empty) and `git ls-files .env` (no output);
    and the CR4 authoring-rule check —
    `git grep -nE "docker compose confi[g]" -- README.md README.en.md SECURITY.md scripts/ openspec/changes/single-robotina-container/design.md openspec/changes/single-robotina-container/tasks.md | grep -vE "config [-]{1,2}(q|services|format)"`
    (no output; every hit must read the static-validation command with `-q`,
    `--services` or `--format` on the same line).

## Delivery decision (ask-on-risk stop)

- The 400-authored-line budget is exceeded in **both** readings (implementation-only ~2,060
  vs 400; total ~6,790 vs 400).
- `Chained PRs recommended: Yes`; `400-line budget risk: High`.
- **Decision needed before apply: Yes.** Choose between chained PRs (recommended slicing S0–S9
  above) and a single PR. `Chain strategy: pending` — this phase does not choose one, and
  `size:exception` is not accepted and must never be inferred.

## Notes for `sdd-apply`

- Phases 0–4 must land before Phase 5 can run; Phase 5 gates Phases 7, 8 and 9 (the
  measurement-dependent tasks cannot complete without a running merged container).
- `scripts/fix-permissions.ps1` stays in the tree with its `superseded` header (task 31);
  deletion requires explicit user confirmation and is not part of this change's task list.
- **Slice 07 update (apply):** the user confirmed the Q7 deletion, so
  `scripts/fix-permissions.ps1` was removed with `git rm` in the docs slice. The container-side
  cont-init (`robotina/s6/cont-init.d/10-robotina-state`) replaces it. Task 31's historical
  interim text above is preserved; the file itself no longer exists.
- **Slice 07 update (apply):** `scripts/migrate-state.ps1`'s header comment was reworded to drop
  the banned two-container phrasing (agent-container AC9's grep covers `scripts/`). Comment only;
  no behaviour changed.
- **Slice 08 update (apply):** task 44's verification text was corrected — it previously expected
  `git ls-files scripts/fix-permissions.ps1` to print the path ("still present — not deleted"),
  which was written when keeping the file was the interim default. The user has since confirmed
  deletion (Q7), so the corrected check expects **no output** and states the rollback story (git
  history retains the script; no volume or host folder is destroyed).
- **Slice 08 update (apply):** task 37 ran and did report two prose lines in `openspec/config.yaml`
  that named the static-validation command without `-q` on the same line (the `testing.static_validation`
  note and the `apply` rule). Both were reworded to refer to "the bare form"/"the
  static-validation command" by description, and the re-run is clean.
- **Slice 09 update (apply):** tasks 21, 22 and 27 are verified at runtime on the live stack
  (evidence in `odd/tasks/single-robotina-container.md` → `## Slice 09`). **Task 28 stays open:** the
  s6 recovery half passes, but the amended single-lifecycle proof **failed** — the literal
  `pkill -f "[h]ermes gateway"` cannot run as a root exec (`CAP_KILL` is dropped: `EPERM`), and when
  the kill is performed as uid 10000 the gateway is restarted in place by the s6-supervised
  `gateway-default` service while `RestartCount`/`StartedAt` stay unchanged. Killing the real main
  program (`rc.init` child `sleep infinity`) starts the container shutdown but it **wedges** because
  the root s6 supervisors cannot signal the uid-10000 services without `CAP_KILL`; the container
  never exits and `restart: unless-stopped` never fires. This is a defect/decision for `sdd-verify`
  (add `CAP_KILL`, change the main program, or re-word AC8), not an apply fix.
- The five proof defects reported in design §19 are already reflected in the spec recipes;
  tasks 19 and 21 close the two remaining apply obligations, and task 40 records the observed
  gate behaviour.
- Do not treat this file's task numbers as PR boundaries; the slice table above is the PR
  proposal.
