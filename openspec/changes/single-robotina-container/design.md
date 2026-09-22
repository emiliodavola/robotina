# Design — single-robotina-container

Change: `single-robotina-container` · Branch: `feat/single-robotina-container`
Artifact store: `openspec/` (this file is the artifact of record for the design phase)
Phase: design — **design only**. No Dockerfile, compose, script or doc was edited. This phase
writes this file only.
Upstream inputs (read in full): `proposal.md` (§17 answers frozen), `explore.md` (evidence,
including the parent-supplied read-only inspection of `nousresearch/hermes-agent:latest` in
§1.4 — the raw vendor-image probe output available to this phase), the six spec files in
`specs/` (39 requirements / 113 scenarios), `openspec/config.yaml`, `openspec/project.md`.
Frozen inputs honoured, not re-opened: D1–D5, §17 answers 1–5, INV1–INV5, the spec
requirements. Open questions Q1–Q12 from proposal §14 are decided below.

---

## 0. Contract this design must satisfy

| Constraint | Source | How this design honours it |
| --- | --- | --- |
| `mem_limit: 6g`, `cpus: 6.0` | §17 answer 4 | taken as given; only `pids_limit` is sized here (Q1) |
| `HOME=/opt/data`, two WAL stores on native volumes nested inside the bind | D5 | §7 |
| No explicit capability dropping | D2 | §13 measures and records; it does not mitigate |
| PAT kept as-is, `GITHUB_TOKEN` in the merged container | §17 answer 1, D3 | §10, §17 (docs) |
| Loopback-only server, no escape hatch | §17 answer 5 | §9, §15 |
| Copy-forward, non-blocking, never-deleting migration | §17 answer 2 | §12 |
| Identity = skin `robotina` + context + BotFather display name only | D4, §17 answer 3 | §11 |
| No test runner; verification is shell-level | `openspec/config.yaml` | §18, §19 |
| Static validation only with `-q` (or `--services`/`--format`) | §9 risk 8 | every recipe here carries `-q`; §19.3 records the line-scoped trap this creates |
| Compose comments Spanish, artifacts English | project.md / §16 | compose sketch in §15 keeps Spanish comments; prose here is English |

**Language contract.** This document is English. The compose fragment in §15 keeps this
repository's Spanish comments, because those comments are part of `compose.yml` as it will be
authored in `sdd-apply`; they are shown here as a *sketch*, never as an edit.

**Evidence posture.** Explore's vendor facts (§1.4), the running-image measurements recorded in
`SECURITY.md`, and the repo files read for this phase are treated as verified. Everything that
requires a live container, a build, or the Docker daemon is marked **UNVERIFIED-UNTIL-APPLY**
with the exact recipe that closes it. This phase had no shell and no Docker access: no
measurement was executed here, and no number below claims to be measured.

---

## 1. Decision summary (Q1–Q12)

| # | Question | Decision | Rejected alternative(s) | Rationale anchor |
| --- | --- | --- | --- | --- |
| Q1 | `pids_limit` for the merged cgroup | **1024** (forecast + pre-committed adjustment rule, confirmed by the recipe in §16) | keep 512 (the old per-container value); unlimited; 2048+ | §16 |
| Q2 | Readiness for `opencode serve` | **`opencode-ready` oneshot** that polls `GET /global/health` with a 120 s bound, ordered after the `opencode` longrun and before the CMD | `notification-fd` (opencode emits no readiness byte); `s6-notifyoncheck` (works, but no gate); bounded wait inside `opencode-init` (structurally impossible: it runs *before* the server) | §9.1 |
| Q3 | s6 restart policy for the longruns | **`finish` script with capped exponential backoff (1→30 s), no latch**; backoff counter reset after a healthy run ≥ 10 s | s6 default (immediate unbounded restart); a `down`-file circuit breaker (needs manual intervention, contradicts self-healing) | §9.2 |
| Q4 | Proven capability set for the uid-10000 opencode process | **Measure and record** `CapEff`/`CapBnd`/`CapPrm`/`CapAmb` + `NoNewPrivs`; expected `CapBnd = 0x00000000000000cb`, `CapEff = 0x0`; **no dropping added**; if capabilities are retained, record the fact and escalate to the user as a new decision | adding `capsh`/`setpriv` dropping (D2 forbids); adding `libcap2-bin` for `getpcaps` (not needed: the masks decode by hand) | §13 |
| Q5 | `OPENCODE_SERVER_PASSWORD` | **Keep**, rewrite the rationale as defense-in-depth | remove it and simplify the skill/export helper | §10.3 — the spec's own EP6 proof requires a non-empty match in `README.md`, `README.en.md`, `SECURITY.md` **and** `scripts/export-state.sh`, i.e. retention is effectively forced by the frozen verification contract |
| Q6 | `overlay.json` merge semantics when `$HOME/.config/opencode` already holds state | **Non-destructive, atomic, per-key merge; repo-declared keys win; `node_modules`/`package-lock.json` never touched; invalid JSON is quarantined, never fatal** | clobber-with-staged-tree (destroys user keys); fail-the-start on invalid JSON (bricks the container over a state file) | §8.3 |
| Q7 | `scripts/fix-permissions.ps1` | **Recommend delete; requires user confirmation — not decided here, not deleted in this phase.** Interim (if the user declines or defers): keep the file with a "superseded / not part of setup" header and update its target list | keep-and-re-document as a setup step (re-introduces the unpinned-`alpine:latest`-as-root trap and contradicts I2 and SL6's human check) | §8.4 |
| Q8 | Vendor `/etc/gitconfig` merge | **Preserve-then-merge by key**: copy the vendor file aside, write our settings with `git config --system`, assert the vendor keys survive and a diff is available | blind overwrite (today's behaviour — silently drops vendor config); `GIT_CONFIG_SYSTEM` + `[include]` pointing at a robotina-owned file (hides the vendor file from the system-config view and depends on an env var surviving into every process) | §3.5 |
| Q9 | Repo layout | **`robotina/` replaces `opencode/`**: build context, Dockerfile, `overlay.json`, `s6/` service sources, healthcheck script. `opencode/` is removed in the same commit. `hermes/` stays the read-only mount source (skills, context, skins) | s6 sources under `hermes/s6/` (mixes build-time artifacts with the repo's read-only mount tree); keeping both directories (two Dockerfiles for one service) | §4 |
| Q10 | engram log destination | **s6 → container stdout** (`docker logs`, bounded by the existing json-file rotation), made deterministic by a one-line startup banner from the run script | a writable file under `/opt/data` (unbounded, needs rotation, new ownership path); `/var/log/engram.log` (unwritable by uid 10000 — today's silently failing redirect) | §9.3 |
| Q11 | Healthcheck vs `restart: unless-stopped` | **Add a healthcheck** (`/opt/robotina/healthcheck.sh`: loopback health + engram process) that is **observability only** — it gates nothing and triggers no restart | no healthcheck (a single-lifecycle container can silently lose its loopback endpoint); a healthcheck that some other service depends on (nothing depends on `robotina`) | §9.4 |
| Q12 | Migration mechanism | **Host-side documented helper `scripts/migrate-state.ps1`** (per-path no-overwrite copy) + documented POSIX equivalent in both READMEs, run as an ordinary step | one-off compose override with the legacy folders mounted read-only (adds a temporary mount to compose, leaves residue risk, and uid 10000 cannot read root-owned legacy folders); undocumented per-file manual copies (not reliably idempotent) | §12 |

---

## 2. Image composition (Q: the Dockerfile plan)

Base: `FROM nousresearch/hermes-agent:latest` (D1). Direction is frozen; the reverse is
infeasible (glibc vendor tree, Debian-built s6-overlay, musl opencode binary).

### 2.1 Shape of the build

```
robotina/Dockerfile
  ARG ENGRAM_VERSION / GENTLE_AI_VERSION / MARKSMAN_RELEASE   (kept from today)
  ARG OPENCODE_VERSION / GH_VERSION / TAPLO_VERSION           (new pins)
  SHELL ["/bin/bash", "-o", "pipefail", "-c"]                 (see 2.6)
  1  apt toolchain          jq ripgrep go procps iproute2 + R + R build deps
  2  opencode (glibc)       npm -g opencode-ai@$OPENCODE_VERSION  + assertions
  3  LSPs                   npm -g (3 pinned) + taplo + marksman + R languageserver
  4  gh                     pinned release tarball + checksum
  5  codegraph              npm -g, NO musl shim
  6  uv + CPython 3.13      UV_* under /opt/uv, PATH appended, no /usr/local/bin shadowing
  7  engram                 pinned release + checksum
  8  gentle-ai              pinned release + checksum + staged tree /opt/gentle-ai-stage
  9  /etc/gitconfig         preserve-then-merge (Q8)
  10 s6 + cont-init         COPY s6/..., chmod 0755
  11 /opt/robotina/*.sh     overlay.json, opencode-init.sh, healthcheck.sh
  12 assertions             one prominent block that fails the build loudly (2.6)
  (no ENTRYPOINT, no CMD override)
```

### 2.2 Dropped because the vendor base already provides it

`bash`, `tar`, `xz`, `tzdata`, `ca-certificates`, `node`, `npm`, `uv`, `git`, `curl`,
`python3` (the Hermes venv on PATH). Explore §2.2 is the evidence; the Alpine-era
reinstallations disappear with the Alpine base.

### 2.3 Added (with the reason it is genuinely missing)

| Addition | Why | Pin |
| --- | --- | --- |
| opencode binary | the core of the merge; must be the **glibc** asset (`opencode-linux-x64`) | `opencode-ai@1.18.32` exact; assert `--version` |
| `gh` | `github-private-repos` requires it under D3; also git's credential helper | release tarball + `checksums.txt`, version pinned (measured `2.97.0` today) |
| `jq` | `opencode-init`'s overlay merge | apt (distro-anchored) |
| `ripgrep` | agent toolchain parity | apt |
| `procps` | `pgrep`/`pkill`/`ps` — **the spec's probes depend on them** (AC5, AC8, EP5, CR2/CR3) | apt |
| `iproute2` | `ss` makes EP1's wildcard-bind check decisive instead of "inconclusive" | apt |
| R + `r-base-dev` + `gcc`/`g++`/`gfortran`/`make` + `libxml2-dev`/`libssl-dev`/`zlib1g-dev`/`libuv1-dev`/`libicu-dev`/`libcurl4-openssl-dev`/`pkg-config` | compile R `languageserver` at build; parity with today | apt + CRAN latest (see 2.5) |
| `taplo` | toml LSP in `overlay.json` | pinned upstream release (fallbacks in 2.5) |
| `marksman` | markdown LSP | existing pinned release, **musl-static binary runs fine on glibc** |
| 3 npm LSPs | json / dockerfile / basedpyright | exact existing pins |
| `@colbymchenry/codegraph` | codegraph MCP | `1.5.0` exact, **bundled glibc `node` kept** |
| uv-managed CPython 3.13 | agent Python, off the Hermes venv | `uv python install 3.13` at build (no runtime network) |
| `engram`, `gentle-ai` | memory + artifact generator | existing pinned releases + checksums |
| `go` | parity (`GOPATH=/opt/data/go`) | apt `golang-go` (measured version recorded in README) |
| merged `/etc/gitconfig` | credential helper + `insteadOf` | see 2.4 |

### 2.4 codegraph: the musl shim is dropped, the bundled runtime is kept

Today's Dockerfile deletes the bundled glibc `node` and replaces it with a shim calling
`/usr/bin/node` (Alpine's musl node). On the Debian base the **bundled runtime is correct**,
so the shim and the deletion both disappear: keep the file where it is. Consequence: ~123 MB
of duplicated Node runtime stays in the image. Accepted, because deleting it is exactly what
breaks codegraph (the wrapper resolves `node` next to itself — that is why the shim was placed
at that path) and the image is already R-sized. Assertion: `codegraph --version` exits 0.

### 2.5 Pinning strategy (explicit, per item)

| Item | Pin | Note |
| --- | --- | --- |
| base image | `nousresearch/hermes-agent:latest` (floating, as today) | the merge must not silently introduce a new upgrade policy; the **resolved digest is recorded** in `odd/tasks/single-robotina-container.md` at verification. Digest pinning is a separate operational decision, out of scope |
| URL-fetched releases (opencode, gh, taplo, engram, gentle-ai, marksman) | version + **sha256 verification**, mirroring the existing engram/gentle-ai pattern | no third-party APT sources and no keys are added to the image |
| npm globals (3 LSPs, codegraph) | exact versions | unchanged from today |
| APT packages (jq, ripgrep, go, R, build deps, procps, iproute2) | **distro-anchored** (Debian trixie, fixed by the base), not per-package pins | same policy as the current Alpine image; per-package pinning is unmaintainable and would fight security updates |
| R `languageserver` | CRAN latest, compiled at build | unavoidable; `stopifnot(requireNamespace(...))` assertion kept |
| `taplo` | primary: upstream release pinned + checksum. Fallbacks, in order: Debian `taplo` if trixie carries it; `npm i -g @taplo/cli` | **UNVERIFIED-UNTIL-APPLY**: the exact asset name/checksum must be confirmed at build; the assertion is `taplo --version` plus the toml LSP entry resolving |

Measured versions must be refreshed in `README.md` (Spanish) and `README.en.md` (English) in the
same commit — the bilingual-sync rule, and today's versions table is explicitly "measured, not
pinned".

### 2.6 Build-time assertions: the merge fails loudly, never silently

The glibc-asset risk (§9 risk 2) is the make-or-break item, so it gets the strongest assertion:

```sh
# 1. la version pedida se instalo y el binario arranca (un loader equivocado muere aca)
opencode --version | grep -F "$OPENCODE_VERSION"
# 2. el asset musl NO esta presente y el glibc SI (la causa raiz del riesgo)
g="$(npm root -g)"
test -z "$(find "$g" -maxdepth 3 -path '*opencode-linux-musl*' -print)"
test -n "$(find "$g" -maxdepth 3 -path '*opencode-linux-x64*' -print)"
# 3. cinturon y tirantes: el binario real no referencia el loader musl
#    (si el comando es un wrapper de node, el paso 1 es el que decide: ejecuta el binario real)
bin="$(readlink -f "$(command -v opencode)")"
! grep -qs 'ld-musl' "$bin"
```

Plus one block that asserts every tool the specs' recipes and the runtime depend on exists:
`command -v gh jq rg go opencode taplo marksman codegraph engram gentle-ai uv node npm python3
R pgrep pkill ss curl git` and `--version` for the ones that support it. Rationale: the
verification suite (39 requirements) assumes this toolchain; a missing tool must fail the
**build**, not a probe.

Also asserted at build: `sh -n` on every s6 and cont-init script, `type`/registration
structure of the new service directories (§5.5), and `s6-rc-compile` **if** the vendor's flags
can be mirrored from its own stage2 script (evidence-gated; if they cannot, the structural
checks stand alone and the runtime proof is AC5's `s6-rc -a list`).

`SHELL ["/bin/bash", "-o", "pipefail", "-c"]` is required, not cosmetic: the checksum
verifications are `grep … | sha256sum -c -`, and dash (Debian's `/bin/sh`) has no `pipefail`,
so a non-matching grep would pass the build with empty input.

### 2.7 What the build must NOT do

- Do **not** override `ENTRYPOINT`; do **not** set `CMD` (the vendor `Cmd` is empty, so
  compose's `["gateway", "run"]` stays authoritative).
- Do **not** write anything into `/opt/hermes/**` (CR3's proof greps for exactly that).
- Do **not** create a `/usr/local/bin/python3` symlink: proposal §4.2 freezes "the Hermes venv
  must stay unshadowed". The uv interpreter is exposed at `/opt/uv/bin/python3` and
  `/opt/uv/bin/python`, and `ENV PATH=$PATH:/opt/uv/bin` **appends** to the vendor PATH (never
  prepends), so the venv keeps priority for Hermes' processes. If a probe shows no `python3`
  anywhere on the container PATH (venue may not expose one itself), the appended entry supplies
  it; either way the venv wins when present.
- Do **not** recreate `/var/log` handling; nothing writes there after Q10.

### 2.8 uv interpreter placement after D5

`UV_PYTHON_INSTALL_DIR=/opt/uv/python`, `UV_TOOL_DIR=/opt/uv/tools`,
`UV_TOOL_BIN_DIR=/opt/uv/bin`, `UV_LINK_MODE=copy`, `UV_PYTHON_PREFERENCE=only-managed`.
`/opt/uv` is an **image path outside every mount**, which is what makes it survive recreation
(the alternative — `/opt/data/.local/share/uv` — is shadowed by the Hermes bind at runtime and
would silently lose the baked interpreter, forcing a runtime download that the egress
allowlist does not admit). Runtime `uv tool install` still lands in the container layer and is
lost on recreate; that trade-off is unchanged and already documented.

---

## 3. `/etc/gitconfig` merge semantics (Q8)

Unknown input: whether the vendor image ships `/etc/gitconfig` and what it contains
(evidence-gated). Design, in the Dockerfile:

1. **Preserve:** if `/etc/gitconfig` exists, copy it to `/etc/gitconfig.vendor` (never
   overwritten afterwards). If it does not exist, nothing is copied and the diff below is
   trivially "everything is ours".
2. **Merge by key, never by file:** write our settings with `git config --system`
   (`credential "https://github.com".helper`, `url."https://github.com/".insteadOf`,
   `init.defaultBranch`), so only those keys are set and any vendor key stays untouched.
3. **Assert:** `git config --system --list` shows our three settings **and** every key present
   in `/etc/gitconfig.vendor` (diff of key names, reported in the build log).
4. **Record:** the vendor file's sha256 goes into the build log, so a future vendor change is
   visible instead of silent.

Rejected: today's `printf … > /etc/gitconfig` (a blind overwrite that can silently drop vendor
config — proposal §9 risk 5); and setting `GIT_CONFIG_SYSTEM` to a robotina-owned file with an
`[include]` of the vendor one (needs the variable to reach every process, and makes
`git config --system` stop reflecting the vendor file).

Note: the *global* config is separate and now lives at `/opt/data/.config/git/config`
(`GIT_CONFIG_GLOBAL`, D5), so a merge mistake here is recoverable and visible.

---

## 4. Repo layout (Q9)

```
compose.yml                       # dos servicios (robotina + egress-proxy)
robotina/                         # NUEVO: contexto de build de la imagen fusionada
  Dockerfile                      # comentarios en español
  overlay.json                    # movido desde opencode/ (contenido sin cambios de forma)
  opencode-init.sh                # logica del oneshot (corre como uid 10000)
  healthcheck.sh                  # sonda del healthcheck (Q11)
  s6/
    cont-init.d/10-robotina-state        # dueno/rutas del estado (SL6)
    cont-init.d/20-robotina-identity     # display.skin (idempotente, ID2)
    s6-rc.d/opencode-init/{type,up,dependencies.d/base}
    s6-rc.d/engram/{type,run,finish,dependencies.d/{base,opencode-init}}
    s6-rc.d/opencode/{type,run,finish,dependencies.d/{base,opencode-init,engram}}
    s6-rc.d/opencode-ready/{type,up,dependencies.d/opencode}
    s6-rc.d/user2/contents.d/{opencode-init,engram,opencode,opencode-ready}
hermes/
  context/.hermes.md              # reescrito (ID3)
  skills/opencode-server/SKILL.md # reescrito (endpoint local, no contenedor hermano)
  skills/github-private-repos/SKILL.md  # reescrito (D3)
  skins/robotina.yaml             # NUEVO (D4) — montado read-only
squid/                            # intacto (INV4)
scripts/
  export-state.sh                 # mismo script; cambia el prefijo de invocacion
  migrate-state.ps1               # NUEVO (Q12)
  fix-permissions.ps1             # Q7: eliminacion PENDIENTE de confirmacion del usuario
openspec/, odd/tasks/             # registro del cambio
```

**What happens to `opencode/`:** removed with `git rm -r opencode/` in the same commit that
adds `robotina/`. Its logic is fully ported — `entrypoint.sh` splits into `opencode-init`
(file work, §8.3), the `engram` longrun, and the `opencode` run script; `Dockerfile` becomes
`robotina/Dockerfile`; `overlay.json` moves. Nothing else in the tree references the directory
(§17 of the file-change inventory in §17 below). Rollback is the proposal §12 revert, which
restores the directory and the old image tag. `robotina-opencode:local` becomes orphaned; the
user may remove it after the merged image is proven, and this change does not remove it.

**Why not `hermes/s6/...`:** `hermes/` is the tree whose subpaths are mounted read-only into
the container (`skills`, `context`, `skins`); mixing build-time artifacts into it implies a
mount that does not exist and blurs two different lifecycles (repo-owned read-only content vs
image-baked supervision).

---

## 5. s6 wiring (exact tree, privileges, registration)

### 5.1 Service definitions

| Service | `type` | Script | Dependencies | Notes |
| --- | --- | --- | --- | --- |
| `opencode-init` | `oneshot` | `up` → `exec s6-setuidgid hermes /opt/robotina/opencode-init.sh` | `base` | idempotent file work as the app uid, so everything it writes is owned by 10000 |
| `engram` | `longrun` | `run` | `base`, `opencode-init` | hosts the memory server; stdout → container log |
| `opencode` | `longrun` | `run` | `base`, `opencode-init`, `engram` | hosts `opencode serve` on loopback |
| `opencode-ready` | `oneshot` | `up` | `opencode` | the readiness gate (Q2); runs after the server exists |
| bundle | `user2` (exists in the vendor image) | — | — | we only add files under `contents.d/`; the bundle's own files are not modified |

Both longruns also carry a `finish` script (Q3, §9.2). Every run/up script starts with
`#!/command/with-contenv` — without it the container environment (`x-egress-env`, `TZ`,
`GITHUB_TOKEN`, both API keys, `OPENCODE_SERVER_PASSWORD`) never reaches the service.

### 5.2 The `opencode` run script (sketch, English comments in the file are Spanish per repo convention)

```sh
#!/command/with-contenv sh
set -eu
export HOME=/opt/data
export XDG_CONFIG_HOME=/opt/data/.config XDG_DATA_HOME=/opt/data/.local/share
export XDG_STATE_HOME=/opt/data/.local/state XDG_CACHE_HOME=/opt/data/.cache
export GOPATH=/opt/data/go GIT_CONFIG_GLOBAL=/opt/data/.config/git/config
export ENGRAM_DATA_DIR=/opt/data/.engram
# La clave de OpenCode, con el nombre que espera la herramienta, SOLO para este proceso.
[ -n "${ROBOTINA_OPENCODE_GO_API_KEY:-}" ] || { echo "robotina: falta ROBOTINA_OPENCODE_GO_API_KEY" >&2; exit 1; }
export OPENCODE_GO_API_KEY="$ROBOTINA_OPENCODE_GO_API_KEY"
unset ROBOTINA_OPENCODE_GO_API_KEY
cd /workspace
echo "robotina: opencode serve -> 127.0.0.1:4096 (uid $(id -u hermes))" >&2
exec s6-setuidgid hermes opencode serve --hostname 127.0.0.1 --port 4096
```

Notes that matter to the reviewer:

- `s6-setuidgid hermes` is the same privilege drop the vendor uses for its main program and
  dashboard; it is what makes `Uid: 10000 …` (EP5) and `CapEff` measurement (§13) meaningful.
- `HOME=/opt/data` here is what makes D5's `$HOME/.config/opencode`,
  `$HOME/.config/git`, `$HOME/go`, `$HOME/.engram`, `$HOME/.local/share/opencode` land on the
  D5 targets. `XDG_*` are set **explicitly** so the layout does not depend on opencode's
  undocumented default resolution (explore §5 flagged that as unverified). They are scoped to
  this process tree, deliberately **not** container-wide, so Hermes' environment is not
  perturbed beyond D5's own `GIT_CONFIG_GLOBAL`/`GOPATH`/`ENGRAM_DATA_DIR`.
- `cd /workspace` preserves today's measured behaviour (the server's reported directory).
- The banner line is not decoration: it is what makes AC5's "engram output is observable"
  scenario deterministic for a service that may print nothing on startup, and it carries no
  secret.

### 5.3 The `engram` run script

```sh
#!/command/with-contenv sh
set -eu
export HOME=/opt/data ENGRAM_DATA_DIR=/opt/data/.engram
echo "robotina: engram serve (data dir $ENGRAM_DATA_DIR)" >&2
exec s6-setuidgid hermes engram serve
```

If `engram serve` accepts a listen/host flag (to be read from `engram serve --help` at apply),
bind loopback explicitly — consistent with I1. If it does not, record the measured bind
address (`ss -ltn` from inside the container) in `SECURITY.md` as **parity, not a new
exposure**: engram already ran in the same `agents` network in the pre-merge opencode
container.

### 5.4 `user2` registration, and the honest contingency

The proposal (§4.3) fixes `user2` as the registration bundle, and explore §1.4 records it as
the vendor's empty extension slot. What is **not** verifiable from the repo is *which* bundle
the vendor's stage2 brings up: `user` (proven live — `dashboard` and `main-hermes` run) versus
`user2` (empty today, therefore unproven).

- Primary: register in `user2/contents.d/` exactly as the proposal says.
- Structural assertion at build (§2.6) so a malformed registration cannot ship.
- Runtime proof: `docker compose exec robotina s6-rc -a list | grep -E '^(opencode|engram)$'`
  (AC5) — a **non-empty** match; an empty match is a failure, never a pass.
- **Contingency, if that proof fails on the first real start:** add the same four names to
  `user/contents.d/` as well (s6-rc permits a service to belong to more than one bundle; the
  service still comes up once). This is an implementation discovery with a one-line, already
  specified remedy — not a product decision, and not a silent substitution.

### 5.5 Structure asserted at build

For every new service directory: `type` present with the expected value (`longrun`/`oneshot`),
the named script present and executable, `sh -n` clean, `dependencies.d/*` matching §5.1, and
one `contents.d` entry inside `user2`.

---

## 6. Startup ordering (the sequence, and what Hermes can see when)

| Stage | What runs | What is true when it finishes |
| --- | --- | --- |
| 0 | Docker applies mounts in destination-depth order: `/opt/data` (bind) → `/opt/data/.engram` (volume) → `/opt/data/.local/share/opencode` (volume) | both volumes shadow the corresponding subtrees of the bind (SL2) |
| 1 | PID 1 = the vendor entrypoint → `/init` (stage 1 preinit, stage 2) | s6 tree alive; `AC3`'s PID-1 properties hold |
| 2 | `cont-init.d/01-hermes-setup` (vendor `stage2-hook.sh`), as root | `$HERMES_HOME=/opt/data` validated and bootstrapped; config seeded; skills synced; ownership of `/opt/data` handled by the vendor |
| 3 | `cont-init.d/10-robotina-state` (ours, as root, §8.1) | state dirs exist; ownership/writability self-healed for uid 10000; the two nested volume roots are explicitly chowned |
| 4 | `cont-init.d/20-robotina-identity` (ours, as root → `s6-setuidgid hermes`, §11) | `display.skin: robotina` present in `/opt/data/config.yaml` (guarded, idempotent) |
| 5 | s6-rc up: `user` bundle (vendor) and `user2` bundle (ours), in dependency order: `opencode-init` → `engram` → `opencode` → `opencode-ready` | overlay merged; engram running; server listening on `127.0.0.1:4096`; readiness gate **satisfied** |
| 6 | The CMD (`gateway run`) via the vendor's `main-wrapper.sh` (`HOME=/opt/data`, venv activated, `s6-setuidgid hermes`) | Hermes starts **after** the endpoint is healthy |

Consequences to state plainly:

- **What Hermes can see on its first prompt:** a healthy loopback endpoint, merged config, the
  selected skin, and a shared `/workspace`. It cannot see a "sibling container" because there
  is none (ID3).
- **Single lifecycle (R4), restated accurately:** the container's PID 1 is Hermes' main
  program. When Hermes exits, the container exits and takes `opencode` and `engram` with it;
  `restart: unless-stopped` then restarts the whole unit. There is no partial recovery, and a
  Hermes crash loop now presents as a container restart loop — but recovery is
  container-level, which is *softer* than "a crash leaves nothing running".
- **The reverse direction is deliberately gated:** if `opencode serve` is not healthy within
  the readiness bound, `opencode-ready` fails and the start is not silently degraded (§9.1).

---

## 7. State layout and mounts (D5)

### 7.1 Exact mount table after D5

| Container path | Source | Kind | Notes |
| --- | --- | --- | --- |
| `/opt/data` | `${HOST_DATA_DIR}/hermes` | bind rw | `HOME` for both process trees; holds `.config/opencode`, `.config/git`, `go` |
| `/opt/data/.engram` | volume `robotina_engram_db` | **volume** | WAL store; nested inside the bind (SL2) |
| `/opt/data/.local/share/opencode` | volume `robotina_opencode_db` | **volume** | WAL store; nested inside the bind (SL2) |
| `/workspace` | `${HOST_DATA_DIR}/workspace` | bind rw | unchanged, separate bind |
| `/backups` | `${HOST_DATA_DIR}/backups` | bind rw | unchanged; `export-state.sh` output |
| `/opt/data/skills/stack` | `./hermes/skills` | bind **ro** | unchanged |
| `/opt/data/skins` | `./hermes/skins` | bind **ro** | new (ID1); directory form, see §11.1 |
| `/workspace/.hermes.md` | `./hermes/context/.hermes.md` | bind **ro** | unchanged |
| `/opt/export-state.sh` | `./scripts/export-state.sh` | bind **ro** | unchanged target |
| `/tmp` | — | tmpfs `rw,exec,nosuid,nodev,size=256m,mode=1777` | `exec` is mandatory (OpenTUI `dlopen`) |

Removed: `${HOST_DATA_DIR}/opencode` → `/root/.config/opencode`, `${HOST_DATA_DIR}/git` →
`/root/.config/git`, `${HOST_DATA_DIR}/go` → `/root/go` (SL5). Nothing is renamed: both volume
names stay exactly `robotina_engram_db` / `robotina_opencode_db`, so rollback re-mounts them at
their old `/root/...` paths.

**Two host-side artefacts of the nesting the operator will see** (documented, so they are not
mistaken for the database location): Docker creates
`${HOST_DATA_DIR}/hermes/.engram` and `${HOST_DATA_DIR}/hermes/.local/share/opencode` as
ordinary, empty host directories (mount points), which the volumes then shadow. An empty host
directory at those paths is **expected**; databases there would mean the nesting failed.

### 7.2 Why nesting is safe on the ordering axis

The vendor's `stage2-hook.sh` runs as root in cont-init, before any user service, and
(per proposal §8.2) chowns `$HERMES_HOME` recursively. Those chowns descend into the two
volumes and set their contents to uid 10000 **before a WAL writer exists**. `10-robotina-state`
(§8.1) then re-asserts ownership of the two volume roots, so correctness does not hinge on the
vendor's chown being recursive. Note the coexisting precedent for read-only mounts *inside*
`/opt/data` (today's `hermes/skills` → `/opt/data/skills/stack:ro` already lives there and the
stack runs), which is evidence that the vendor hook tolerates a read-only subtree under
`$HERMES_HOME`; a chown/EROFS error in the first real start is an apply-time observation, not
an assumption (§20).

### 7.3 Verification that nesting works on Docker Desktop for Windows (and the escalation path)

**UNVERIFIED-UNTIL-APPLY.** The positive recipe alone is not enough — a silently ignored
volume would put the DBs on the bind and satisfy "the store is readable". So the proof is
positive **plus a negative control**:

```sh
# 1. ambas rutas son montajes, y no son 9p/virtiofs (SL2)
docker compose exec robotina sh -c 'mount | grep -E "\.engram|\.local/share/opencode"'
# 2. que son volumenes, no el bind (tipos y origenes)
docker inspect --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' robotina
# 3. control negativo: un archivo escrito en el "volumen" NO debe aparecer en el bind del host
docker compose exec robotina sh -c 's6-setuidgid hermes sh -c "echo probe > /opt/data/.engram/.robotina-probe"'
ls -A "$HOST_DATA_DIR/hermes/.engram"          # DEBE estar vacio
# 4. durabilidad: el probe sobrevive a down/up
docker compose down && docker compose up -d
docker compose exec robotina sh -c 'cat /opt/data/.engram/.robotina-probe'
```

- **Pass** = two volume mounts, neither `9p`/`virtiofs`; host-side `hermes/.engram` empty;
  probe present after `down`/`up`. Record in `odd/tasks/single-robotina-container.md` with the
  raw output (SL2's "closed or escalated" scenario).
- **Fail / inconclusive** (a path shows `9p`/`virtiofs`, the host directory contains the probe
  or a `*.db`, or `mount | grep` is empty/missing) → **stop and escalate to the user**. The
  proposed alternative is explore §5 option 1 (the `/root`-rooted layout: `HOME=/root` for the
  opencode tree, volumes at `/root/.engram` and `/root/.local/share/opencode`, no nesting),
  which re-opens D5's `HOME` decision and therefore **cannot** be substituted silently.

### 7.4 `docker compose exec` and the state env vars

`ENGRAM_DATA_DIR`, `GOPATH` and `GIT_CONFIG_GLOBAL` are set **container-wide** (they are paths,
not per-process configuration) so that operator recipes — `docker compose exec robotina sh
/opt/export-state.sh`, `git config --global` — land on the same state the services use.
`exec`-ed shells are the reason this cannot be scoped to the run scripts: an exec'd `engram
export` with a default data dir would silently export an empty store.

---

## 8. Ownership, file work, and `fix-permissions.ps1`

### 8.1 `cont-init.d/10-robotina-state` (runs as root, after the vendor hook)

1. `install -d -o 10000 -g 10000` for `/opt/data/.config/opencode`,
   `/opt/data/.config/git`, `/opt/data/go`, `/opt/data/logs` (reserved, unused),
   `/workspace`, `/backups`.
2. Self-heal, cheap when already correct: if `s6-setuidgid hermes test -w /opt/data` fails,
   `chown -R 10000:10000 /opt/data` (root + `CAP_CHOWN`). This is what makes a freshly created
   host state tree writable with **no host-side privileged step** (SL6).
3. Explicit, bounded `chown -R 10000:10000` on the two nested volume roots (they are mount
   points, so this reaches the store files without walking the whole bind).
4. Environment-derived uid: the scripts derive the target uid from `id -u hermes` (default
   10000) instead of hard-coding it, so a `HERMES_UID` override does not silently break
   ownership. The specs' numeric proofs assume the default 10000; that assumption is stated in
   the docs (§17).

### 8.2 Why this replaces the host step

Today's mandatory host step runs **unpinned `alpine:latest` as root with the host state bind
mounted** (project.md known traps, SECURITY.md) to chown five host folders and two volumes.
After the merge, the container (which already has root at boot and the five capabilities
Hermes needs) does it, before any service, every start, with no third party involved. That is
I2, and it is a net reduction in the privileged surface.

### 8.3 `opencode-init` (oneshot, runs as uid 10000) — the overlay semantics of Q6

Order and semantics (replacing today's `entrypoint.sh` steps 1–2 and 4):

1. **Staged gentle-ai tree is authoritative**: for each top-level entry under
   `/opt/gentle-ai-stage/.config/opencode`, except `node_modules` and `package-lock.json`
   (runtime state that opencode owns), replace the destination entry. Idempotent by
   construction; the way to change these files is the repo + rebuild.
2. **`overlay.json` merge, non-destructive and per key**: our keys win, everything else in the
   user's `opencode.json` survives (`$base * $overlay`), `mcp` and `lsp` merge per key, and
   `permission` is replaced **wholesale** by the overlay's policy — documented as intentional,
   because the overlay's `permission` block is a complete policy and a shallow merge would let
   a stale local rule re-permit an operation the repo denies.
3. **When the destination already holds state (the Q6 case):**
   - *Legacy content migrated by §12*: it is the previously merged file, so the merge is a
     no-op; user keys the overlay does not declare survive; a value the overlay does declare is
     overwritten by the repo's (documented: the repo is authoritative for the keys it declares).
   - *Absent `opencode.json`*: the overlay is installed as the base.
   - *Invalid JSON*: `jq` failure must never brick the container. Quarantine the file to
     `opencode.json.invalid-<timestamp>`, log loudly, install the overlay as the new base, and
     continue. The user's bytes are preserved for repair; only the parse failure is fatal to
     the file, not to the start.
   - *Idempotency*: applying the overlay twice yields the same content (merge of a constant
     onto a value whose declared keys already equal the constant), which is what SL4's
     double-run byte-identity proof needs.
4. **Atomic write**: merge into a temp file **inside the config directory** and `mv` it into
   place, so a concurrent reader never observes a half-written JSON. (Today's `/tmp` temp file
   is cross-device — tmpfs → bind — so the `mv` is a copy, not a rename.)
5. **Ownership**: the whole oneshot runs as uid 10000 via `s6-setuidgid hermes`, so everything
   it writes is already owned correctly and no post-hoc chown is needed.
6. **`/workspace` writability warning**: kept from today's entrypoint, but as an actionable
   warning only — with §8.1 in place the warning should never fire.

### 8.4 `scripts/fix-permissions.ps1` (Q7) — recommendation, not a decision

**Recommendation: delete it**, because §8.1 fully replaces it, I2 is one of this change's
declared improvements, and keeping a host-side, root, unpinned-image script that is no longer
part of setup leaves a documented trap available with no benefit. It also removes the "Requisitos:
PowerShell 7 para `scripts/fix-permissions.ps1`" line and setup step 5 (README.md) and its
English twin — which is exactly SL6's human check ("no numbered setup step instructs running the
host PowerShell helper").

**This phase does not delete it and does not treat it as decided.** Deletion is a destructive
change to a host-facing script and requires explicit user confirmation (`ask-on-risk`). Until
that confirmation arrives, the safe default is:

- keep the file, with its header rewritten to say it is **superseded by the container-side
  cont-init step and no longer part of setup** (its target list drops `opencode`/`git`/`go`,
  which are no longer mounts, and keeps `workspace`/`backups` + the two volumes as a
  repair-only tool), and
- ensure no README/setup text instructs running it.

Both variants satisfy SL6's human check as written (any remaining mention must be explanatory
text about the removal or the Q7 decision).

---

## 9. Readiness, restart policy, logging, healthcheck

### 9.1 Readiness mechanism (Q2)

**Decision: a dedicated `opencode-ready` oneshot** that polls `GET /global/health` with a
bounded retry, ordered after the `opencode` longrun by `dependencies.d/opencode`.

```sh
#!/command/with-contenv sh
# oneshot "up": no declara "listo" hasta que el puerto responde de verdad (B4/EP4)
set -u
url=http://127.0.0.1:4096/global/health
i=0
while [ "$i" -lt 60 ]; do
  if [ -n "${OPENCODE_SERVER_PASSWORD:-}" ]; then
    curl -fsS -m 2 -u "opencode:$OPENCODE_SERVER_PASSWORD" "$url" >/dev/null 2>&1 && { echo "robotina: opencode listo (intentos=$i)" >&2; exit 0; }
  else
    curl -fsS -m 2 "$url" >/dev/null 2>&1 && { echo "robotina: opencode listo (intentos=$i)" >&2; exit 0; }
  fi
  i=$((i+1)); sleep 2
done
echo "robotina: ERROR: opencode serve no respondio en 120 s; el contenedor no arranca degradado" >&2
exit 1
```

- This is the only mechanism that produces a **gate**: s6-rc brings the whole tree up before
  `main-wrapper.sh` execs the CMD (§6), so a satisfied gate means Hermes' first delegation
  cannot race the bind. `s6 "started"` is explicitly *not* treated as "listening".
- `notification-fd` is rejected: it requires the supervised program to write the readiness byte
  itself, and opencode does not.
- `s6-notifyoncheck` is rejected as the primary mechanism: it detects readiness but does not
  hold the start, and it adds a dependency on s6-notifyoncheck's presence/semantics in the
  vendor image that this design cannot verify without a live container. It remains a
  documented fallback if the oneshot proves unworkable at apply.
- **Credential-awareness (important interaction with Q5):** the gate sends
  `-u "opencode:$OPENCODE_SERVER_PASSWORD"` when the variable is non-empty, so keeping the
  password cannot wedge startup. The argv exposure of that form is the same class already
  recorded in `SECURITY.md` for `scripts/export-state.sh` (the value is in the container
  environment anyway).
- **Failure semantics, stated honestly:** a non-ready endpoint after 120 s exits the oneshot
  non-zero, which is an s6 service failure. The *intent* is a loud, non-silent start refusal
  (B4 is a precondition of Hermes' first delegation, and EP4 also requires that no
  `ECONNREFUSED` for `127.0.0.1:4096` reaches Hermes' log — which is impossible if Hermes is
  allowed to start with a dead delegate). What s6-overlay does with the failed oneshot (abort
  the container vs. continue to the CMD) **must be observed once and recorded at apply**; if it
  continues, the degraded start is documented explicitly in `SECURITY.md`/`README` rather than
  implied away. The 120 s bound is a forecast to be confirmed by the measured cold start; the
  bound is raised with a recorded rationale if the measurement needs it.
- **engram is not gated.** Its dependency ordering guarantees it is *started* before opencode,
  exactly like today's `engram serve &` followed by `exec opencode`. A hard gate would need an
  engram health endpoint that this design cannot verify, and inventing one is not acceptable.

### 9.2 Restart policy for the longruns (Q3)

**Decision: `finish` script with capped exponential backoff; unbounded restarts; no latch.**

```sh
#!/command/with-contenv sh
# $1 = codigo de salida, $2 = senal (si lo mato una senal). s6-supervise lo corre antes de reiniciar.
set -u
svc=opencode                       # (engram usa el mismo script con su nombre)
st=/tmp/robotina; mkdir -p "$st"
now=$(date +%s); start=$(cat "$st/$svc.start" 2>/dev/null || echo 0)
if [ $((now - start)) -ge 10 ]; then echo 0 > "$st/$svc.fail"; fi   # corrida sana: reinicia el contador
n=$(cat "$st/$svc.fail" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$st/$svc.fail"
case $n in 1) s=1;; 2) s=2;; 3) s=4;; 4) s=8;; 5) s=16;; *) s=30;; esac
echo "robotina: $svc salio (exit=$1 sig=${2:-0}); reinicio #$n en ${s}s" >&2
sleep "$s"
```

- The `run` script writes `date +%s` to `$st/$svc.start` immediately before `exec`; that is the
  only way a `finish` script can apply a "healthy run" reset (s6-supervise reports the exit
  status, not the runtime).
- Rejected: s6's default (restart immediately, forever) — a crash-looping LSP-heavy process
  would spin against the *shared* 6-CPU cgroup and starve Hermes, which is the R5 starvation
  concern turned into a denial of service against the Telegram gateway. The 30 s cap bounds the
  CPU/log cost of a hopelessly broken service.
- Rejected: a `down`-file circuit breaker — it turns a self-healing failure into one that needs
  an operator, and it adds state/reset rules. The healthcheck (§9.4) already surfaces the
  condition, and the capped backoff keeps retry cheap.
- State files live under `/tmp` (tmpfs), so the counter is cleared on every container restart —
  a fresh container always gets a full restart budget.
- AC5's recovery scenario (`pkill` the server, expect recovery inside its 60 s window) is
  comfortably satisfied by a 1 s first backoff, and a single kill never accumulates failures
  (the reset rule fires on the healthy run before it).

### 9.3 engram log destination (Q10)

**Decision: the container's stdout/log stream**, via s6, with the banner line of §5.3.

- Today's `engram serve > /var/log/engram.log 2>&1 &` silently fails: `/var/log` is root-owned
  0755 and the writer is uid 10000. Nothing about that redirect survives.
- The container log stream is already bounded by the `x-hardening` json-file rotation
  (10 MB × 3), requires no writable path, needs no new ownership, and is captured by the
  single lifecycle.
- A file under `/opt/data` was rejected: it would be unbounded, outside the log rotation, and
  would need rotation and ownership work of its own.
- Operator recipe (must appear in both READMEs):
  `docker compose logs --tail 200 robotina` and a filtered variant for the service banner.
  AC5's scenario is satisfied by the banner line even if engram itself is silent.

### 9.4 Healthcheck (Q11)

**Decision: add one, and make its role explicit — it gates nothing.**

```yaml
    healthcheck:
      test: ["CMD", "/opt/robotina/healthcheck.sh"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 90s
```

`robotina/healthcheck.sh` (image-shipped so the quoting is reviewable and no secret-shaped
string appears in `docker inspect` output): probes `GET /global/health` on loopback — with
`-u "opencode:$OPENCODE_SERVER_PASSWORD"` only when the variable is non-empty — **and** asserts
that an `engram serve` process exists. Its `pgrep` is written with a character-class pattern
(`[e]ngram`) so it cannot match its own shell.

Reasoning (the Q11 "runtime observation" call):

- Docker's `restart: unless-stopped` acts on **PID 1 exit**, not on health status. So the
  healthcheck cannot cause a restart, and it must not be mistaken for recovery machinery.
- Its value is the signal the single-lifecycle container otherwise lacks: Hermes can be running
  while `opencode`/`engram` are down (backed-off crash loop), and that state is invisible in
  `docker compose ps` today. With the healthcheck, the operator sees `unhealthy` and has one
  action (`docker compose restart robotina`).
- No `depends_on: condition: service_healthy` is introduced anywhere: nothing depends on
  `robotina`, and adding a health-gated dependency would imply automatic recovery that does not
  exist.
- Rejected: no healthcheck (keeps `docker compose ps` blind to a dead endpoint).

---

## 10. Credentials and key isolation (agent-credentials, exactly)

### 10.1 Compose-side wiring (option A of explore §6.1; proposal §4.4 is authoritative)

```yaml
    environment:
      <<: *egress-env
      TZ: America/Argentina/Buenos_Aires
      # Clave de Hermes, con el nombre exacto que espera la imagen vendor.
      OPENCODE_GO_API_KEY: ${HERMES_OPENCODE_GO_API_KEY:?definir HERMES_OPENCODE_GO_API_KEY en .env}
      # Clave de OpenCode bajo un nombre propio: el run script de opencode la exporta
      # como OPENCODE_GO_API_KEY SOLO para su proceso (nunca se patchea un archivo vendor).
      ROBOTINA_OPENCODE_GO_API_KEY: ${OPENCODE_GO_API_KEY:?definir OPENCODE_GO_API_KEY en .env}
```

- `OPENCODE_GO_API_KEY` container-wide = the **Hermes** value → CR2 (Hermes sees its own value
  under the vendor name).
- `ROBOTINA_OPENCODE_GO_API_KEY` container-wide = the **OpenCode** value. The `opencode` run
  script exports it under the vendor name for its own process and then `unset`s the
  robotina-named copy, so the server's `/proc/<pid>/environ` carries exactly one
  `OPENCODE_GO_API_KEY` line with the OpenCode value → CR3, and C3's "differs from the Hermes
  hash" holds.
- No vendor file is patched (CR3's grep), which is also why the value travels by environment
  and not by a rewritten config.
- **Honest residual, to be stated in `SECURITY.md` under R2:** because the OpenCode value is
  container-wide under *our* name, the Hermes process's environment also carries that value
  under a name it does not read. `KEY-PROBE` still passes (it hashes the vendor name only), and
  this is inside the accepted "no enforceable isolation at equal uid" regression — but the
  document must say it rather than let the acceptance criterion read as stronger than it is.
- Rejected alternative, recorded because it is tempting: mounting the OpenCode key as a
  root-only Docker secret and dropping it from the container environment. It would reduce the
  residual above, but it contradicts proposal §4.4's approved mechanism, it loses the
  `${VAR:?…}` mandatory-input guard (the secret takes a variable *name*, not an interpolated
  value), it adds a compose-version dependency, and it still leaves the key readable from the
  opencode process's environment — so it buys no real boundary.

### 10.2 Secret-handling rules the implementation must follow

- Never echo a key: the startup banners print service names, pids and paths only.
- Secret-safe distinctness proof is the spec's `KEY-PROBE` + `KEY-REFERENCE` (sha256 of the
  `NAME=value` line, `.env` read with `tr -d "\r"`).
- Every recipe in this change carries `-q` (or `--services`/`--format`) on the static-validation
  command — see §19.3 for the line-scoped trap.
- `docker inspect` is only ever called with a narrow `--format` that excludes `.Config.Env`
  (the healthcheck's own string contains no secret, by §9.4).

### 10.3 `OPENCODE_SERVER_PASSWORD` (Q5) — keep, with a rewritten rationale

Decision: **keep it**, and rewrite its documented meaning as **defense-in-depth only**:

> After the merge the server is loopback-only: no network peer — not the host, not
> `egress-proxy`, not any container on `agents` — can reach port 4096. The password therefore no
> longer separates the agents *from each other over the network*. It remains useful as a second
> lock for a process that reaches loopback without inheriting the container environment, and it
> is **not** a boundary against any process that does inherit it (which, in one container at one
> uid, includes the agent itself).

Why keeping beats removing:

1. The spec's EP6 proof requires a non-empty match for the variable in `README.md`,
   `README.en.md`, `SECURITY.md` **and** `scripts/export-state.sh`; removing the variable would
   make that frozen proof unsatisfiable without a spec amendment.
2. Removing it would force edits to a working helper's auth path and to the `opencode-server`
   skill recipe, i.e. authored surface for zero security gain.
3. Its cost is already accepted and documented (an environment variable readable via
   `docker inspect`, and the `export-state.sh` argv exposure).

---

## 11. Identity wiring (agent-identity)

### 11.1 Skin: file, mount, selection

- **File:** `hermes/skins/robotina.yaml`, with top-level `name: robotina` and
  `branding.agent_name: robotina`. Its full schema is derived from a **vendor-bundled sample
  skin** at apply time (the image's own skins directory is the only authoritative schema
  source; **UNVERIFIED-UNTIL-APPLY**). If the vendor key for the displayed name is not
  `branding.agent_name`, the implementation uses the vendor's actual key and the design records
  the correction — the requirement's observable (the agent displays `robotina`) does not change.
- **Mount:** `./hermes/skins` → `/opt/data/skins`, **read-only**, using the **directory** form.
  - Rationale for the directory over a single-file bind: the target file does not exist in a
    freshly created host state tree, and a single-file bind onto a non-existent target is the
    ambiguous case (Docker may materialise a directory). A directory bind has no such ambiguity,
    and it satisfies ID1's two observations exactly: `ls -l /opt/data/skins/robotina.yaml`
    succeeds, `touch` fails read-only, and the mountinfo source is the repository path.
  - Interpretation note for ID1's second scenario, recorded so a reviewer is not surprised: on
    Docker Desktop the `mountinfo` source is the VM-side path of the repository (for example
    under `/run/desktop/mnt/host/...`), not the Windows path. The scenario's intent — the mount
    comes from the repo, not from `${HOST_DATA_DIR}/hermes/skins` — still holds; verify by
    asserting the source is not under the host data directory.
  - Side effect, accepted and documented: any skin a user had placed in
    `${HOST_DATA_DIR}/hermes/skins` is shadowed. That is the "repo is authoritative over host
    state" semantic ID1 asks for; the shadowed host directory remains untouched on disk.

### 11.2 `display.skin` on a fresh state tree (idempotent, and it must not fight the vendor hook)

`cont-init.d/20-robotina-identity`, running **after** the vendor's `01-hermes-setup` (which
seeds `config.yaml`), as root then `s6-setuidgid hermes`:

1. If `/opt/data/config.yaml` does not exist yet → log a loud warning and exit 0 (never brick
   startup over cosmetics; the identity statement in `.hermes.md` is the guaranteed layer).
2. If the config already selects `skin: robotina` → exit 0 with no write (no churn, no fight).
3. Otherwise run the vendor CLI non-interactively:
   `s6-setuidgid hermes env HOME=/opt/data hermes config set display.skin robotina`.
   - Idempotent by construction (guarded by step 2), so it survives restarts and works on a
     fresh `${HOST_DATA_DIR}/hermes` (ID2).
   - Ordering is the anti-fight mechanism: the vendor hook runs in cont-init *before* us, and
     the main program starts *after* all cont-init, so our write is the last one before Hermes.
   - **UNVERIFIED-UNTIL-APPLY:** the exact subcommand surface (`hermes config set`) and the key
     path (`display.skin`) must be confirmed against the image (`hermes config --help` /
     a vendor sample config). Documented fallback if the CLI differs: set the key with the
     vendor's own mechanism (a small Python edit with `/opt/hermes/.venv/bin/python` + the
     vendored YAML library), keeping the same guards and the same observable.
4. Failure is logged, never fatal: if step 3 fails, the loud line tells the operator which
   layer to fix, and ID2's proofs will fail visibly rather than silently.

### 11.3 Always-loaded context and the two skills (ID3 + R1)

`hermes/context/.hermes.md` is rewritten to the merged topology: it states that the agent is
`robotina`, that there is **one** agent container (no sibling, no `http://opencode:4096`), that
`gh` **is** installed and `GITHUB_TOKEN` **is** present in this container (D3/R1), that a
private-repo `404` is now a **token permissions** problem and never a "delegate/ask for a
token" conclusion, and that the endpoint is `http://127.0.0.1:4096`. `hermes/skills/opencode-server/SKILL.md`
is rewritten for the local server (+ the now-applicable bundled `opencode` CLI skill) and
`hermes/skills/github-private-repos/SKILL.md` for the retired credential split.

**Documentation constraint that is easy to trip (from the frozen proofs), to be enforced in
`apply`:** the rewritten text must not contain the substrings the specs' greps ban —
"sin credencial", "no GitHub credential", "no tiene token", "delegate to opencode",
"delegar a opencode", "does not run inside this container", "no esta instalado", "no rewrite"
(CR5) — nor the affirmative isolation claims banned by CR6, nor the two-container phrases banned
by AC9. Delegation can still be described (e.g. "delegate the work to the local OpenCode
server"): the ban is on the exact retired phrasings, not on the concept.

### 11.4 BotFather (ID4)

One documented manual step in both READMEs: rename the bot's Telegram **display name** to
`robotina`. The instruction must mention the display name and **must not** ask for a `@username`
change (ID4's grep looks for `username` within six lines after every `botfather` mention — so the
word must not appear there in either language).

---

## 12. Migration mechanism (Q12)

Decision: a **host-side documented helper** `scripts/migrate-state.ps1`, plus the same step
documented in `README.md` (Spanish) and `README.en.md` (English), plus a documented POSIX
equivalent (`cp -an` / `rsync -a --ignore-existing`) for non-Windows hosts.

Semantics (exactly SL4's four properties):

| Property | Implementation |
| --- | --- |
| copy-forward, only when absent | walk the source tree, copy **per path** only when the destination path does not exist (recursive for directories). Never a blind recursive overwrite, so a newer destination file is untouched — that is SL4's byte-identity proof, which the helper must therefore satisfy **per file**, not per folder |
| non-blocking | nothing in compose or the image calls the helper; the container starts correctly with the migration never run (SL4's first scenario) |
| idempotent | re-running copies nothing when everything already exists; reported as a summary of copied/skipped counts |
| never delete | no delete/move primitive anywhere in the helper; it finishes by asserting the three legacy folders still exist and that the two copied-from folders are non-empty |

Targets: `${HOST_DATA_DIR}/opencode/` → `${HOST_DATA_DIR}/hermes/.config/opencode/`, and
`${HOST_DATA_DIR}/git/` → `${HOST_DATA_DIR}/hermes/.config/git/`. `${HOST_DATA_DIR}/go/` is
**not** copied (rebuildable cache; SL4's explicit scenario).

**Design-level refinement to the §8.2 table, stated so the reviewer can veto it:** the helper
also skips `node_modules/` inside the legacy opencode folder. That folder is the installed
dependency tree of opencode's plugins, i.e. a rebuildable cache exactly like `go/` (the
destination is repopulated by opencode at runtime, and the entrypoint already refuses to manage
it). `package-lock.json` **is** copied, so a reinstall is deterministic. If the reviewer prefers
byte-for-byte fidelity over migration speed, the change is a one-line flag in the helper — the
§17 answer (copy-forward, non-blocking, never delete) is untouched either way.

Ownership: the copy is a host-side file operation, so the container-side §8.1 chown (which runs
every start) is what makes the copied files writable by uid 10000 — no ordering requirement
between the migration and the first start, as required.

Rejected: a temporary read-only mount of the legacy folders via a compose override + a
container-side copy. It requires a compose file that exists only for the migration (residue
risk), it cannot read root-owned legacy paths as uid 10000, and it re-introduces exactly the
"host state mounted into a helper container" shape that I2 removes.

The READMEs must also carry the two operator notes: run `scripts/export-state.sh` **before**
migrating as a cheap safety net, and the legacy folders are the rollback safety net and are
never deleted by this change.

---

## 13. Measured capability set for the uid-10000 process (Q4)

**No dropping is added (D2).** What ships is measurement plus an honest record.

**Probe** (run as root via `docker compose exec`; never prints a secret; a `pgrep` that matches
nothing is a FAILURE, and the pattern uses a character class so it cannot match its own shell):

```sh
docker compose exec robotina sh -c 'for p in $(pgrep -f "[o]pencode serve"); do echo "pid=$p uid=$(awk "/^Uid/{print \$2}" /proc/$p/status)"; grep -E "Cap(Inh|Prm|Eff|Bnd|Amb)|NoNewPrivs" /proc/$p/status; done'
```

**Expected values** (stated so the document records a fact, not an assumption):

| Field | Expected | Why |
| --- | --- | --- |
| `CapBnd` | `0x00000000000000cb` | the container's bounding set is exactly the five `cap_add` capabilities under `cap_drop: [ALL]`: bit 0 CHOWN (1) + bit 1 DAC_OVERRIDE (2) + bit 3 FOWNER (8) + bit 6 SETGID (64) + bit 7 SETUID (128) = 203 = `0xcb`; capabilities are per-container, so the child inherits this mask |
| `CapEff` / `CapPrm` | `0x0000000000000000` | `s6-setuidgid hermes` performs a uid transition from 0 to a non-zero uid, and the kernel clears the permitted/effective sets on that transition; `NoNewPrivs: 1` prevents regaining anything through `execve`, and the opencode binary carries no file capabilities |
| `CapAmb` | `0x0000000000000000` | no ambient set is raised by the vendor's supervision chain |
| `NoNewPrivs` | `1` | `security_opt: no-new-privileges:true` (AC4 proof) |

**If capabilities turn out to be retained** (`CapEff != 0`):

1. **Record the truth, not the expectation**: write the measured masks into `SECURITY.md`'s R3
   entry, replacing the expected values, and add the decode against the five-cap table.
2. **State the blast radius honestly**: the retained set is the same five capabilities Hermes
   needs. Indoors, `CAP_DAC_OVERRIDE`/`CAP_FOWNER` mean the OpenCode process could read/write
   files owned by any uid **inside** the container (the container's only other uid is the same
   10000, so the practical delta is small); `CAP_SETUID`/`CAP_SETGID` would let it become
   container-root, which is not an escape from the container but is a real privilege step inside
   it. None of the five is `CAP_SYS_ADMIN`, so no new mount/namespace capability is introduced.
3. **Escalate, do not mitigate silently**: D2 was decided under "no extra capability work". A
   retained `CapEff` is a *new* security fact that the user signed nothing about; it goes back
   to the user as an explicit decision (accept-and-document, or a follow-up change that drops
   the capabilities in the run script), exactly like the R-regressions were signed off.
4. Do **not** add `capsh`/`setpriv` dropping in this change, and do **not** add `libcap2-bin` to
   the image for `getpcaps`: the masks are readable from `/proc/<pid>/status` and decode against
   the documented 5-bit table, so `SECURITY.md`'s evidence needs no new package.

---

## 14. Identity of the runtime: uid, `HOME`, and what the proofs assume

- The app uid is whatever the vendor resolves for the `hermes` user (default **10000**). Our
  scripts derive ownership targets from `id -u hermes`, so a `HERMES_UID`/`HERMES_GID` override
  cannot silently corrupt ownership.
- The specs' numeric proofs (EP5's `Uid: 10000 10000 10000 10000`, SL6's `stat -c "%u:%g"`
  expectations, `CapBnd`'s `0xcb`) **assume the default 10000** and no `HERMES_UID` override.
  The docs must say so, because a user who changes `HERMES_UID` would invalidate those recipes
  without invalidating the design.

---

## 15. `compose.yml` delta (anchors, env, mounts, limits, networks, `NO_PROXY`)

Sketch only — **no compose file was edited in this phase**; comments stay Spanish per the
repository convention.

```yaml
# Baseline aplicado a los dos servicios. `pids_limit` SALE del ancla: es un presupuesto
# dimensionado, no una constante de hardening, y ahora difiere 8x entre los dos servicios.
x-hardening: &hardening
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  ulimits:
    core: 0
  stop_grace_period: 20s
  logging:
    driver: json-file
    options:
      max-size: "10m"
      max-file: "3"

# Los agentes solo pueden salir por el proxy. El nombre interno ahora es `robotina`.
x-egress-env: &egress-env
  HTTP_PROXY: http://egress-proxy:3128
  HTTPS_PROXY: http://egress-proxy:3128
  http_proxy: http://egress-proxy:3128
  https_proxy: http://egress-proxy:3128
  NO_PROXY: localhost,127.0.0.1,::1,robotina,egress-proxy
  no_proxy: localhost,127.0.0.1,::1,robotina,egress-proxy

services:
  egress-proxy:            # SIN CAMBIOS (solo conserva su pids_limit: 128 explicito)

  # Unico agente: Hermes (Telegram) + opencode serve + engram, supervisados por s6.
  robotina:
    build:
      context: ./robotina
    image: robotina:local
    container_name: robotina
    restart: unless-stopped
    # Sin `init: true` y sin `user:`: el entrypoint vendor exige ser PID 1 y rechaza uids
    # arbitrarios. Los servicios propios se declaran en el bundle `user2` de s6.
    command: ["gateway", "run"]
    environment:
      <<: *egress-env
      TZ: America/Argentina/Buenos_Aires
      OPENCODE_GO_API_KEY: ${HERMES_OPENCODE_GO_API_KEY:?definir HERMES_OPENCODE_GO_API_KEY en .env}
      ROBOTINA_OPENCODE_GO_API_KEY: ${OPENCODE_GO_API_KEY:?definir OPENCODE_GO_API_KEY en .env}
      GITHUB_TOKEN: ${GITHUB_TOKEN:-}                 # D3: el PAT vive aca, para todos los procesos
      GIT_TERMINAL_PROMPT: "0"
      OPENCODE_SERVER_PASSWORD: ${OPENCODE_SERVER_PASSWORD:-}   # defensa en profundidad (loopback)
      TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:?definir TELEGRAM_BOT_TOKEN en .env}
      TELEGRAM_ALLOWED_USERS: ${TELEGRAM_ALLOWED_USERS:-}
      # Rutas, no configuracion por proceso: las necesitan tambien los `exec` de operador.
      ENGRAM_DATA_DIR: /opt/data/.engram
      GIT_CONFIG_GLOBAL: /opt/data/.config/git/config
      GOPATH: /opt/data/go
    volumes:
      - type: bind                                    # estado de Hermes = HOME de todo el arbol
        source: ${HOST_DATA_DIR:?definir HOST_DATA_DIR en .env, por ej. C:/robotina-data}/hermes
        target: /opt/data
      - type: bind                                    # workspace compartido
        source: ${HOST_DATA_DIR:?definir HOST_DATA_DIR en .env, por ej. C:/robotina-data}/workspace
        target: /workspace
      - type: bind                                    # salida de export-state.sh
        source: ${HOST_DATA_DIR:?definir HOST_DATA_DIR en .env, por ej. C:/robotina-data}/backups
        target: /backups
      - type: bind                                    # skills propias, read-only
        source: ./hermes/skills
        target: /opt/data/skills/stack
        read_only: true
      - type: bind                                    # skin robotina, read-only (D4)
        source: ./hermes/skins
        target: /opt/data/skins
        read_only: true
      - type: bind                                    # contexto siempre cargado, read-only
        source: ./hermes/context/.hermes.md
        target: /workspace/.hermes.md
        read_only: true
      - type: volume                                  # opencode.db (WAL): volumen NATIVO anidado
        source: opencode_db
        target: /opt/data/.local/share/opencode
      - type: volume                                  # engram.db (WAL): volumen NATIVO anidado
        source: engram_db
        target: /opt/data/.engram
      - type: bind
        source: ./scripts/export-state.sh
        target: /opt/export-state.sh
        read_only: true
    tmpfs:
      - /tmp:rw,exec,nosuid,nodev,size=256m,mode=1777   # `exec` obligatorio (dlopen de OpenTUI)
    networks:
      - agents
    mem_limit: 6g          # decision congelada (§17.4)
    cpus: 6.0              # decision congelada (§17.4)
    pids_limit: 1024       # dimensionado para el cgroup fusionado (ver SECURITY.md)
    healthcheck:
      test: ["CMD", "/opt/robotina/healthcheck.sh"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 90s
    <<: *hardening
    cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID]

volumes:
  opencode_db:
    name: robotina_opencode_db   # mismo nombre: el rollback los vuelve a montar en /root/...
  engram_db:
    name: robotina_engram_db

networks:
  agents:
    name: agents
    internal: true
  egress:
    name: egress
    driver: bridge
```

Delta summary a reviewer can diff by hand:

| Area | Change |
| --- | --- |
| anchors | `pids_limit` leaves `x-hardening` and becomes per-service (§16); the anchor's comment drops "tres servicios"; `NO_PROXY`/`no_proxy` swap `hermes`,`opencode` → `robotina` |
| services | the `hermes` and `opencode` blocks are replaced by one `robotina` block: `build: ./robotina`, `image: robotina:local`, `container_name: robotina`, `command: ["gateway","run"]` |
| removed keys | `user:`, `init: true`, `working_dir`, `command: ["serve", …]`, both old `mem_limit`/`cpus` pairs |
| env | both keys under distinct names (§10.1); `ENGRAM_DATA_DIR`/`GIT_CONFIG_GLOBAL`/`GOPATH` become container-wide paths; `TZ`, `GITHUB_TOKEN`, `GIT_TERMINAL_PROMPT`, `OPENCODE_SERVER_PASSWORD`, Telegram vars unchanged in meaning |
| mounts | one bind at `/opt/data` plus the two **nested** volumes; `workspace`, `backups`, `skills`, `context`, `export-state.sh` unchanged; `skins` added; the three legacy host-folder mounts removed (SL5) |
| limits | `mem_limit: 6g`, `cpus: 6.0` (frozen), `pids_limit: 1024` (§16) |
| healthcheck | added, observability only |
| networks | unchanged; `robotina` joins `agents` only (AC7) |
| volumes | both names unchanged, targets re-rooted under `/opt/data` (SL2/SL5) |
| tmpfs | `/tmp` exec kept (single instance now) |
| `cap_add` | unchanged five |

---

## 16. `pids_limit` decision and its confirming measurement (Q1)

**Decision: `pids_limit: 1024`** on the merged service (and `pids_limit` removed from
`x-hardening`, with `egress-proxy` keeping its explicit `128`).

**Why 1024**

1. **Parity with the previous worst case.** Today's two agent cgroups each allow 512, i.e. a
   combined ceiling of 1024. Choosing 1024 means no workload that could run before the merge
   gets truncated by the merge itself — the merge's accepted regression is the *shared* budget
   (R5), not a silently halved one.
2. **The workload is thread-heavy, and threads are PIDs.** The merged cgroup must hold: Hermes'
   Python gateway (main process + asyncio/PTY/skill children), `opencode serve` and its six LSP
   servers (three Node LSPs with several threads each, `marksman`/`taplo` Rust threads, R
   `languageserver`, codegraph's Node runtime), `engram`, every shell/LSP/MCP child, plus user
   builds — and builds are the bursty part (`R` source builds with `Ncpus=6`, `go build ./...`
   under a 6-CPU quota, `npm ci`/test runners with per-CPU workers). A working estimate is
   ~120–200 tasks at rest and ~350–500 during a concurrent build-plus-LSP burst.
3. **Headroom against the failure mode the proposal warns about.** Too tight fails as LSP fork
   storms and mysterious `MCP error -32000`/`EAGAIN`, which are expensive to diagnose; 1024 puts
   the ceiling ~2–3× above the estimated peak while staying finite and modest for containment.
4. **Containment is not lost.** The limit remains finite, and with `cpus: 6.0` a fork storm
   cannot amortise into a long-running resource burn.

**Pre-committed adjustment rule** (so verification can act without re-deciding in the dark):

| Measured peak `pids.current` under the recipe below | Action |
| --- | --- |
| ≤ 614 (60 % of 1024) | **confirm** 1024 and record the measured peak |
| > 614 | raise to the next value that restores ≥ 40 % headroom (1536, then 2048), record the new value and the measured peak in `SECURITY.md` (R5 entry) and in the change record |
| ≤ 256 | keep 1024 anyway: tightening below the previous *combined* per-container budget is a new capacity decision outside this change |

**Measurement that confirms it (to run in `sdd-apply`/`sdd-verify` — no Docker was available to
this phase, so 1024 is a forecast, not a measurement):**

```sh
# linea base
docker compose exec robotina sh -c 'cat /sys/fs/cgroup/pids.current; cat /sys/fs/cgroup/pids.max'
# pico de 1 Hz durante el peor caso concurrente (900 muestras)
docker compose exec robotina sh -c 'i=0; while [ $i -lt 900 ]; do cat /sys/fs/cgroup/pids.current; i=$((i+1)); sleep 1; done | sort -n | tail -1'
```

Worst case driven **in parallel** while sampling:

1. an OpenCode session over the loopback API against a workspace containing `.py`, `.R`,
   `.toml`, `.md`, `.json` and a `Dockerfile`, so all six LSPs are live and scanning;
2. an R source build/install with `Ncpus=6`;
3. `go build ./...` on a mid-size module (GOMODCACHE on `/opt/data/go`);
4. `npm ci && npm test` in a JS repo with a parallel runner;
5. Telegram traffic through the gateway for the duration.

Record the three numbers (baseline, peak, limit) wherever the budget is documented — AC6's
`pids.max` proof, AC8's "budget decision on record" and `SECURITY.md`'s R5 entry all point at
the same value and rationale.

Observation for the record, not a change: `nofile` is not constrained by this change (Docker's
default is high), so `pids.max` is the binding process-count constraint.

---

## 17. File-change inventory (for `sdd-tasks`)

| File | Action | Language |
| --- | --- | --- |
| `compose.yml` | rewrite the two service blocks into one `robotina`; anchors, env, mounts, limits, `NO_PROXY`, healthcheck | Spanish comments |
| `robotina/Dockerfile` | new (composition of §2) | Spanish comments |
| `robotina/overlay.json` | moved from `opencode/` | JSON |
| `robotina/opencode-init.sh` | new (from today's entrypoint steps 1–2, 4) | Spanish comments |
| `robotina/healthcheck.sh` | new (§9.4) | Spanish comments |
| `robotina/s6/**` | new: 2 cont-init scripts, 4 service dirs, `user2` entries | Spanish comments |
| `opencode/**` | **removed** (`Dockerfile`, `entrypoint.sh`, `overlay.json`) | — |
| `hermes/skins/robotina.yaml` | new (D4) | YAML |
| `hermes/context/.hermes.md` | rewrite (identity + merged topology + D3) | English (facts file) |
| `hermes/skills/opencode-server/SKILL.md` | rewrite (local endpoint, no sibling container) | English |
| `hermes/skills/github-private-repos/SKILL.md` | rewrite (credential split retired) | English |
| `scripts/migrate-state.ps1` | new (Q12) | Spanish comments |
| `scripts/export-state.sh` | header comment + invocation prefix | Spanish comments |
| `scripts/fix-permissions.ps1` | **Q7: untouched this phase**; delete (pending confirmation) or re-document as superseded | Spanish comments |
| `README.md` | topology, setup (build step, replaced permission step, migration step, BotFather display name), operator recipes (`docker compose exec robotina …`), persistence table, versions | Spanish |
| `README.en.md` | the same set | English |
| `SECURITY.md` | R1/R2/R3 retired-and-retained, single lifecycle, budget + measured `pids_limit`, capability measurements, `OPENCODE_SERVER_PASSWORD` rationale, engram log destination, nesting result, PID-1-must-be-the-entrypoint | Spanish |
| `.env.example` | the `docker inspect` comment; note the routing of the two keys | Spanish comments |
| `openspec/project.md` | services table, coupling map items, layout, traps, verification expectations | English |
| `openspec/config.yaml` | only if §19.3's wording rule is applied to it (prose line naming the static-validation command) | English |
| `odd/tasks/single-robotina-container.md` | progress, decisions, evidence (digests, measured versions, nesting + capability + `pids` results) | English |
| `odd/tasks/agent-interop-http.md` | superseded-by note (R6) | English |

Language contract: compose/Dockerfile/scripts comments Spanish; `README.md` and `SECURITY.md`
Spanish; `README.en.md` and `odd/tasks/*.md` English; `openspec/` artifacts English. Bilingual
measured claims change in the same commit (AC9's second scenario).

---

## 18. Requirement → design coverage

Every one of the 39 requirements is satisfied by this design. The mapping below groups them; the
design-owned OPEN ITEMS are closed in the sections named.

| Requirement group | Design section that closes it |
| --- | --- |
| AC1–AC3 (one service, name, PID 1/s6) | §4, §15 (no `user:`, no `init: true`), §6 stage 1 |
| AC4 (hardening + five caps) | §15 (anchor unchanged apart from `pids_limit`), §13 |
| AC5 (s6-supervised opencode + engram, observable output, restart on kill) | §5, §9.2, §9.3 |
| AC6 (budget: 6g / 6.0 / finite `pids_limit`) | §15, §16 |
| AC7 (agents-only, no published port) | §15 |
| AC8 (regressions documented with measurements) | §13, §16, §19.2 (proof defect), §17 (`SECURITY.md`) |
| AC9 (docs describe one container) | §11.3, §17 |
| EP1–EP3 (loopback only, unreachable from host/peers) | §5.2 (`--hostname 127.0.0.1`), §15 (no ports) |
| EP4 (ready before first delegation) | §9.1, §6 |
| EP5 (uid 10000) | §5.2, §14 |
| EP6 (`OPENCODE_SERVER_PASSWORD` semantics) | §10.3 |
| EP7 (in-container operator recipes in both READMEs) | §17 (`README.md`, `README.en.md`), §7.4 |
| CR1–CR4 (two inputs, per-process keys, no leak) | §10.1, §10.2 |
| CR5 (GITHUB_TOKEN present, invariant retired) | §11.3, §17 (`SECURITY.md`) |
| CR6 (non-isolation stated) | §10.1 (honest residual), §17 |
| CR7 (human sign-off) | unchanged from the spec; `SECURITY.md`'s R1/R2 entries are the prerequisite |
| INV1–INV5 / EG1–EG5 | §15 (no ports, no socket, `.env` only, `NO_PROXY`, squid untouched, `HOST_DATA_DIR:?`) |
| SL1–SL2 (`HOME=/opt/data`, WAL volumes nested) | §7.1, §7.3 |
| SL3 (persistence across `down`/`up`) | §7.1, §7.3, §12 |
| SL4 (copy-forward migration) | §12 |
| SL5 (only the target mount set) | §7.1, §15 |
| SL6 (in-container ownership fix) | §8.1, §8.4 |
| ID1–ID2 (skin read-only, selected non-interactively) | §11.1, §11.2 |
| ID3 (context identity + topology) | §11.3 |
| ID4–ID5 (BotFather display name, `NO_PROXY` name) | §11.4, §15 |

Design-owned OPEN ITEMS closed: AC6's `pids_limit` value (§16), AC5's observable log path
(§9.3), EP4's readiness mechanism (§9.1), SL4's migration mechanism (§12), ID2's selection
mechanism (§11.2). Proposal Q1–Q12 are all answered in §1.

---

## 19. Spec-proof defects found (require a spec amendment; flagged, not worked around)

These are defects in the **named proofs**, not in the requirements. Each one is reported because
`apply`/`verify` will otherwise chase a false failure — or, worse, record a vacuous pass. None
of them weakens a requirement; each has a minimal, proposed amendment.

### 19.1 AC8's single-lifecycle proof races the restart policy

`pkill -f "hermes gateway"` followed by `docker compose ps` expecting "not running" cannot hold:
the service is `restart: unless-stopped`, so Docker restarts PID 1 within a fraction of a
second and the check (hundreds of milliseconds later) sees a running container again. The
property being asserted is real and should stay asserted; the observation is what needs
fixing. **Proposed amendment:** observe the unit restart instead — capture
`docker inspect --format '{{.RestartCount}} {{.State.StartedAt}}' robotina` before the kill, and
assert after the kill that the counter increased (and `StartedAt` moved), which proves the whole
container went down and came back as one unit, i.e. that `opencode`/`engram` did not survive
independently. The narrow `--format` keeps the secret-safety rule. Flagged as a blocker for
executing AC8's second scenario as written.

### 19.2 `pgrep -f` patterns match their own probe shell

`KEY-PROBE` (`pgrep -f "hermes gateway"`), EP5 (`pgrep -f "opencode serve"`), AC8's capability
scenario and CR2/CR3 all run inside a `sh -c '…'` whose own command line contains the very
pattern. `pgrep` therefore matches the probe shell too: best case it inflates the pid list (EP5
substitutes them into a single `/proc/.../status` path and breaks), worst case a probe passes
against its own shell — a vacuous pass, which the specs' own rule forbids. **Proposed
amendment:** use a character-class pattern (`[h]ermes gateway`, `[o]pencode serve`) and, where a
single pid is substituted, `head -1` plus an assertion that the matched list is non-empty and
excludes `$$`. Also note CR2's own escape hatch applies: the real Hermes command line must be
confirmed once inside the container (`pgrep -af hermes`) and the recipe's pattern corrected in
the same commit if the vendor's shim presents it differently.

### 19.3 CR4's "no recipe uses the non-printing form" grep is line-scoped and hits prose

The proof drops a line only if a non-printing flag appears **on that same line**, so any line —
prose or code — that names the static-validation command without a flag on it is reported. The
repository already contains such lines in **frozen** artifacts (including `proposal.md`'s risk 8
row and `explore.md`) and in the artifacts this change writes, where a warning sentence about the
danger is exactly what a careful author writes. As written, the proof is unsatisfiable because
frozen prose cannot be reworded. **Proposed amendment (pick one, both reviewer-safe):**
(a) scope the grep to the recipe-bearing files (`README.md`, `README.en.md`, `SECURITY.md`,
`scripts/`, plus this change's `design.md`/`tasks.md`) and exclude the frozen explainer
artifacts; or (b) keep the scope and reword only the change's own artifacts so every mention
carries `-q` on the same line, accepting the known frozen offenders as documented exceptions.
**Design rule adopted here regardless:** in every artifact authored by this change, a mention of
the static-validation command carries `-q` (or `--services`/`--format`) on the same line, and
the dangerous form is referred to by description rather than literally. That rule is what this
document does.

### 19.4 EP1/EP4 assume an unauthenticated `/global/health`

Their recipes call the health endpoint with no credentials while Q5 keeps
`OPENCODE_SERVER_PASSWORD`. If the server protects `/global/health` with Basic auth, those
recipes fail whenever a password is set. **Resolution taken by design:** the readiness gate and
the healthcheck are credential-aware (§9.1, §9.4), so the *product* behaviour is correct either
way. **Apply obligation:** record once whether `/global/health` is auth-protected (`curl -fsS`
with and without `-u`) and, if it is, amend EP1/EP4's recipes to use the credential-aware form in
the same commit. Not a blocker — a one-line observation with a specified remedy.

### 19.5 Notes that need an interpretation, not an amendment

- **EP2's host probe**: a failure is expected, but a host that happens to listen on port 4096
  would produce a false failure. Pair it with a host-side check that nothing local listens there
  (and record the result) so "no published port" is not confused with "something else on the
  port".
- **ID1's mount-source wording**: on Docker Desktop the `mountinfo` source is the VM-side path
  of the repository, not the Windows path (§11.1). The intent (repo-sourced, read-only, not
  host-state-sourced) is what must be asserted.
- **SL3's engram read command**: the documented read command this design names is
  `docker compose exec robotina engram export /backups/engram-<stamp>.json` — the same command
  `scripts/export-state.sh` already uses, valid under D5 because `ENGRAM_DATA_DIR` is
  container-wide (§7.4). No new CLI invocation is invented.

---

## 20. Risks and mitigations (design level)

| # | Risk | Severity | Mitigation / tripwire |
| --- | --- | --- | --- |
| D-1 | Nested volume-inside-bind does not behave on Docker Desktop for Windows | High | §7.3: positive + negative-control recipe, recorded in the task file; failure → escalate with the `/root`-rooted fallback as a **user** decision |
| D-2 | A later `opencode-ai` release drops the glibc asset | High | pinned exact version + §2.6 assertions that fail the build loudly (musl absent, x64 present, `--version` matches) |
| D-3 | `user2` is not the bundle the vendor brings up | Medium | AC5's non-empty `s6-rc -a list` proof, plus the documented one-line contingency (§5.4) |
| D-4 | The skin schema or `hermes config set` differs from the assumption | Medium | derive both from the vendor at apply; both have specified fallbacks (§11.1, §11.2); ID1/ID2's greps catch a wrong result |
| D-5 | The readiness gate blocks startup on a slow cold start | Medium | 120 s bound, measured cold start recorded; Docker's `restart: unless-stopped` gives an automatic retry; bound raised with a recorded rationale if the measurement demands it |
| D-6 | Readiness gating turns "delegate broken" into "stack down" | Medium | deliberate and stated (§9.1); the observed s6-overlay failure behaviour is recorded, and if it continues to the CMD, the degraded start is documented explicitly |
| D-7 | Vendor `stage2-hook.sh` errors on a read-only subtree under `/opt/data` | Low–Medium | precedent: `hermes/skills` is already mounted read-only there; first-start log check is an apply obligation; if it errors, the skin mount is the only new one and can be re-evaluated without touching D5 |
| D-8 | `pgrep`/`pkill` patterns do not match the real Hermes/opencode command lines | Low | §19.2: confirm once with `pgrep -af`, correct the patterns in the same commit (the specs explicitly allow this) |
| D-9 | Migration helper mis-handles Windows paths (CRLF, spaces, long paths) | Low–Medium | it reads `HOST_DATA_DIR` with the same parsing as the existing helper, normalises separators, and reports per-path copied/skipped; SL4's double-run byte-identity proof catches an overwrite |
| D-10 | uv-managed interpreter shadowed or lost by the bind | Low | §2.8: `/opt/uv` is outside every mount; `PATH` is appended, never prepended; the CI-of-record assertion is `uv python list --only-installed` at build |
| D-11 | Docs desync across the 15+ file set, or a banned substring survives | Medium | §17 inventory + the banned-substring list in §11.3/§11.4; the specs' greps are the tripwire, run in the same commit |
| D-12 | Review workload exceeds the 400-authored-line budget | Medium | `ask-on-risk`: re-forecast at `sdd-tasks` with real numbers and **stop to ask**; no chain strategy is invented and `size:exception` is never inferred |
| D-13 | Secret leak by tooling while executing the recipes | Medium | every recipe uses `-q`; `docker inspect` only with narrow `--format`; the healthcheck's string carries no secret | 

---

## 21. Rollout and rollback

- **Unit of revert** is unchanged from proposal §12: `compose.yml`, `robotina/` (new) and
  `opencode/` (removed), the s6 sources, the context file and both skills, the skin, the scripts
  and the docs revert as one commit.
- **Nothing is destroyed by the change**: both volumes keep their names and are re-mounted at
  their old paths by the reverted compose file; the legacy host folders are only ever copied
  from (§12) and are never deleted; the migration is non-blocking, so rollback does not depend
  on it having run.
- **Suggested order of work for `apply`** (feeds `sdd-tasks`): compose + image + s6 first, then
  the first `up` and the nesting/readiness/capability measurements, then the migration helper
  and the docs, then the `pids_limit` confirmation, then the `SECURITY.md` evidence entries.
- **Not reversible automatically:** the BotFather display-name change (a Telegram-side action),
  as recorded in the proposal.

## 22. Nothing deferred, nothing re-opened

- No D1–D5, §17 answer, INV1–INV5 or spec requirement is re-opened or weakened by this design.
- `scripts/fix-permissions.ps1` deletion is the **one** item that is explicitly *not* decided
  here: recommended, and gated on user confirmation (§8.4).
- The five spec OPEN ITEMS are closed by §9.1, §9.3, §11.2, §12 and §16.
- §19 lists proof defects that need a *spec* amendment; they are reported rather than silently
  accommodated. If any of them is judged unamendable, AC8's second scenario and CR4's third
  scenario cannot be executed as written — that is the only blocker-class finding in this
  phase.

---

## Phase result

- Image composition is settled end to end: vendor Debian base, explicit drop list, explicit add
  list with a pinning strategy, the glibc-opencode assertion block, the gitconfig
  preserve-then-merge, no musl shim for codegraph, uv outside every mount, and no
  `ENTRYPOINT`/`CMD` override.
- Supervision is settled: `opencode-init` (oneshot, uid 10000), `engram` and `opencode`
  (longruns with `finish`-based capped backoff), `opencode-ready` (the readiness gate), all in
  `user2`, all `#!/command/with-contenv`, with the startup sequence written out and what Hermes
  can see at each stage.
- State layout is settled with the mount table, the two nested WAL volumes, the ordering
  argument, and an explicit nesting verification plus escalation path.
- Credentials, identity, migration, capability measurement, logging, healthcheck, resource
  budget and the compose delta are all decided with their rejected alternatives.
- One item is deliberately left to the user (delete vs keep-re-document
  `scripts/fix-permissions.ps1`), and one class of finding is escalated instead of absorbed
  (the five proof defects in §19).
- Nothing was implemented; no child subagents were launched.
