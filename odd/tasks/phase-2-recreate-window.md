# Feature: phase-2-recreate-window

## Goal

Prepare the one maintenance window that reconciles the running stack with the repository, so that
`docker compose up -d` is no longer a surprise: the pinned `engram` becomes the one that actually
runs (and moves to the latest release), the `uv` interpreters stop living in the container layer, the
garbage OpenTUI leaves behind stops accumulating, and bumping an `ARG`-pinned tool becomes one
command instead of an archaeology exercise.

Branch: `chore/phase-2-recreate-window`, off `main`. Owner: `emiliodavola`. Reconciles #41 with the
prerequisites of #42 and #43.

## Decisions (owner, 2026-09-28)

- **D-LATEST**: for `engram` the latest release wins — it is a tool that keeps improving. The
  repository must still record *which* version a build produced, so the answer to "what is running?"
  is never a guess.
- **D-STORAGE**: the `uv` interpreters go to a native volume and the OpenTUI leftovers are cleaned at
  boot.

## Non-goals

- **No recreate and no rebuild in this change.** This PR prepares the window; running it stays the
  owner's decision.
- **No bump of `gentle-ai` or `gh`.** They are behind (3.1.0 → 3.7.0 and 2.97.0 → 2.101.0, measured),
  and `gentle-ai` regenerates the whole agent/skill tree at build time: that is its own change with
  its own proof, not a side effect of this one. `scripts/bump-tools.sh --check` reports them.
- **No Dependabot wiring.** Its prerequisite is pinning the two `:latest` images, which is #52.
- No change to the helper fixed in #55, nor to the egress model.

## Diagnosis (measured, 2026-09-28)

1. **The `engram` pin is decorative.** The image ships `/usr/local/bin/engram` 1.20.0 (built
   2026-09-24 20:10) and nobody runs it: `/opt/data/.local/bin/engram` (2.1.0, 2026-09-24 10:17 —
   older than the merge) comes first on `PATH`, and the s6 `run` invokes `engram serve` with no
   absolute path. `ls -l /proc/218/exe` confirms the supervised service executes the HOME copy. Any
   writer of that file changes the agent's memory backend without touching the repository.
2. **`/var/tmp` is 1.9 GB, all of it in the container layer.** 1.4 GB is
   `/var/tmp/opencode/uv-python` (cpython 3.10.20, 3.13.13, 3.14.4) and ~380 MB is 69 files of
   `5.5 MB` — one `.bcd9*.so` per OpenTUI invocation, never cleaned (`compose.yml` already documents
   that OpenTUI extracts a shared object; what was missing is that it keeps it).
3. **The installation is not the opencode server's doing.** That process's environment honours what
   is declared (`UV_PYTHON_INSTALL_DIR=/opt/uv/python`, `TMPDIR=/var/tmp`, read from
   `/proc/223/environ` as the app uid). A **child** process uses a different target, which is why the
   interpreters land beside the garbage.
4. **A retired risk, for the record:** the 1.20.0 binary prints an update banner on `--version`, and
   #42 raised the concern that it would corrupt the MCP stdio stream. Measured with a real
   `initialize` handshake: both 1.20.0 and 2.1.0 answer clean JSON-RPC. The banner is an interactive
   nuisance, not a protocol bug.
5. **Latest versions, measured against the real sources:** `engram` v2.2.1 (currently pinned 1.20.0,
   running 2.1.0), `gh` v2.101.0 (pinned 2.97.0), `gentle-ai` v3.7.0 (pinned 3.1.0), `marksman`
   2026-02-08 and `taplo` 0.10.0 and `opencode-ai` 1.18.32 (all three already current). The v2.2.1
   release publishes the exact asset the Dockerfile expects plus `checksums.txt`.

## Shape

1. **Make the pin effective.** `s6-rc.d/engram/run` execs an absolute path, so what the image baked is
   what runs, whatever the HOME contains.
2. **Make "what runs" assertable.** The Dockerfile records the pinned version into the image's
   environment, and `healthcheck.sh` asserts that the *running* `engram` reports it. That single
   check catches both a shadowing copy and a stale image.
3. **Take the latest, in one command.** `scripts/bump-tools.sh` resolves the latest release for each
   `ARG`-pinned tool and either reports which are behind (`--check`, the default) or rewrites the
   `ARG` in `robotina/Dockerfile` (`--write <tool>`). The pin stays explicit in the repository — an
   auto-latest build would make "what is running" unknowable and would break the checksum discipline
   (`taplo` pins a sha256 precisely because its release publishes none).
4. **Move the interpreters out of the layer.** A native volume for `UV_PYTHON_INSTALL_DIR`, like the
   two WAL databases already have: the interpreters then survive a recreate instead of costing a
   1.4 GB re-download.
5. **Clean the leak at boot.** A new cont-init removes `/var/tmp/.bcd9*.so` and the per-invocation
   scratch under `/var/tmp/opencode/`.
6. **Specs follow the state**, not the other way around: `state-layout` gains the volume and the
   cleanup rule; `agent-container` gains the "what runs is what was pinned" invariant.

## Residual risk (declare it, do not paper over it)

The window moves `engram` from the running **2.1.0** to the pinned **2.2.1** over the *same* WAL
`engram.db`. **Measured 2026-09-28: the readable content of that store is empty.** `engram stats`
reports `Sessions: 0`, `Observations: 0`, and `engram export` writes 135 bytes of empty arrays, while
the volume holds 6.4 MB of `engram.db` + `engram.db-wal` and four `engram mcp` processes (plus the
supervised `engram serve`) are alive with `ENGRAM_DATA_DIR=/opt/data/.engram` pointing at it.

Two consequences, and they pull in opposite directions:

- The version migration has (almost) nothing to migrate, so it is **less** risky than this tracker
  first assumed.
- But a memory backend that reports zero observations is not a memory, and the JSON export protects
  nothing. That discrepancy is a defect of its own, recorded here and to be filed separately — it
  does **not** block the window (the window is about *which* binary runs), but it must never be read
  as "the memory is fine because the export ran".

Secondary finding from the same measurement: four `engram mcp --tools=agent` processes are alive at
once (one per OpenCode session that used the MCP, and none of them reaped), each holding the same
store. That is process accumulation against `pids_limit: 1024`, same family as the OpenTUI leftovers
of #43.

## Window procedure (in this order, one sitting)

**Every step that hands a bare absolute path to `docker exec` needs `MSYS_NO_PATHCONV=1`.** On Git
Bash, `/opt/export-state.sh` becomes `C:/Program Files/Git/opt/export-state.sh` and the step dies with
`cannot open …`. Paths that live **inside** a quoted `sh -c '…'` string are safe: Git Bash does not
rewrite the contents of an argument that does not start with a slash. This was measured the hard way
while checking this very procedure.

1. **Back up the brain's raw bytes while 2.1.0 still owns them.** The CLI export is **not** a backup
   of the brain: measured on 2026-09-28, `engram stats` reports `Sessions: 0` / `Observations: 0` and
   `engram export` writes **135 bytes** of empty arrays, while the volume holds 6.4 MB of
   `engram.db` + `engram.db-wal`. Snapshot the volume read-only instead:

   ```bash
   MSYS_NO_PATHCONV=1 docker run --rm --entrypoint tar \
     -v robotina_engram_db:/data:ro \
     -v "${HOST_DATA_DIR}/backups":/backup \
     robotina:local czf "/backup/engram-volume-$(date +%Y%m%d-%H%M%S).tgz" -C /data .
   ```

   Verified on 2026-09-28: the archive is ~2 MB compressed and carries `engram.db`,
   `engram.db-wal` and `engram.db-shm`. `scripts/export-state.sh` still runs and is what produces
   the portable session export, but the brain's safety net is the volume snapshot.
2. **Build, do not touch the running container.** `docker compose build`. The interpreter volume does
   not exist yet; Docker creates it on the next `up`.
3. **Quarantine the shadow** — `mv`, never `rm`, because it is the agent's state and the new
   healthcheck must be able to see it leave:
   `MSYS_NO_PATHCONV=1 docker compose exec robotina mv /opt/data/.local/bin/engram /opt/data/.local/bin/engram.unused-2.1.0`
4. **Recreate.** `docker compose up -d`. This is where #55's helper fix, the 2.2.1 pin, the
   interpreter volume and the boot cleanup all land at once.
5. **Verify**: `docker compose ps` (both healthy), the engram version pair and the `PATH` resolution
   of AC11, the `var/tmp limpio` line in the logs, and `du -sh /var/tmp` — a fraction of the 1.9 GB
   measured before.

**Why this order and not another:** quarantining before building would make the *old* image's 1.20.0
open a WAL store that 2.1.0 has been writing. The store must be handed from 2.1.0 straight to 2.2.1,
with the JSON export already on disk in case the migration is not what engram promises.

## Tasks

- [x] T1 — Branch and this tracker.
- [x] T2 — `engram` pin effective: absolute path in the s6 `run`, `ENGRAM_VERSION=2.2.1`, version
      recorded in the image, version asserted by `healthcheck.sh`, and the AC11 spec scenario.
- [x] T3 — `uv` interpreters on a native volume (`robotina_uv_python`) and a boot-time cleanup of the
      OpenTUI leftovers, both proven statically and covered by SL7.
- [x] T4 — Specs: `state-layout` (SL7: the volume + the scoped cleanup) and `agent-container`
      (AC11: what runs is what was pinned).
- [x] T5 — Static verification: `docker compose config -q`, `dash -n` on all four touched shell
      files with the container's own parser, and every new spec assertion checked by hand — including
      the version parser against **both** `engram` binaries (1.20.0 with its banner, and 2.1.0).
- [ ] T6 — `scripts/bump-tools.sh` (the one-command "take the latest" for the `ARG`-pinned tools).
      Ships in its own chained PR: it does not touch the container, so the window does not wait for
      its review.
- [ ] T7 — Commits per work unit, push, PR against `main` assigned to the owner (and the chained PR
      for T6 based on this branch).

## Route declaration

- Classification: **substantial and authorized** (compose + Dockerfile + s6 + healthcheck + a new
  script + two specs).
- Delegation: none. The change is one coupled infrastructure slice whose parts reference each other
  (the version recorded in the image is read by the healthcheck; the volume is referenced by compose
  and by the state-layout spec). Splitting it across writers would need more context transfer than
  the work itself.
- The **recreate is explicitly out of scope**: this branch ends at "the declared configuration is
  correct and provable", not at "it is applied".
