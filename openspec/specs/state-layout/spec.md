# state-layout Specification

## Purpose

Define the observable properties of the merged container's state layout: `HOME=/opt/data` for
the agent process tree, the two WAL SQLite stores on native Docker volumes mounted **inside**
the bind, persistence across `down`/`up`, a copy-forward non-blocking idempotent
never-deleting migration of existing legacy host folders, and ownership fixing performed from
inside the container (frozen: D5, proposal §8, §17 answer 2).

This domain is **new**: `openspec/specs/` was empty before this change, so this file is a
full domain spec and is copied verbatim into `openspec/specs/state-layout/spec.md` at archive
time.

Artifact language: English (proposal §16).

## Verification model

There is no test runner in this repository (`openspec/config.yaml` → `testing.runner: none`).
Every scenario names the exact shell-level observation that proves it.

- Static recipes MUST use `docker compose config -q`; the bare form prints resolved `.env`
  secrets (proposal §9 risk 8) and is forbidden.
- **No vacuous passes**: `pgrep`/`grep`/`find` probes MUST assert non-empty output. `pgrep`
  patterns MUST use a character-class form (`[h]ermes gateway`, `[o]pencode serve`) so the probe
  shell's own command line cannot match itself, and a single-pid substitution MUST take
  `head -1` and assert the pid is non-empty and is not `$$`.
- Host-side recipes read `HOST_DATA_DIR` from the gitignored `.env` **without printing its
  other values**, and strip CRLF (`tr -d "\r"`).
- Implementation risk carried from proposal §9 risk 1: nesting a named volume inside a bind
  mount (`/opt/data/.engram`, `/opt/data/.local/share/opencode`) is **unverified** on Docker
  Desktop for Windows. SL2 is the measurement that closes or refutes it. If it fails, the
  fallback (`/root`-rooted layout) is **a decision to bring back to the user**, never a silent
  substitution.

## Requirements

### Requirement: SL1 — `HOME=/opt/data` for the agent process tree

The OpenCode service process tree SHALL run with `HOME=/opt/data`, so config, git global
config and `GOPATH` resolve inside the existing Hermes host bind.

#### Scenario: The OpenCode process runs with the new home

- GIVEN the stack is up
- WHEN the server process's environment is read
- THEN `HOME=/opt/data`
- PROOF: `docker compose exec robotina sh -c 'p=$(pgrep -f "[o]pencode serve" | head -1); test -n "$p" && test "$p" != "$$" && tr "\0" "\n" < /proc/$p/environ | grep "^HOME="'`
  (non-empty, `HOME=/opt/data`; an empty match is a FAILURE and the `head -1`/`$$` assertions keep
  the probe from reading its own shell)

#### Scenario: Hermes' main program shares the same home

- GIVEN the stack is up
- WHEN the Hermes process's environment is read
- THEN `HOME=/opt/data`
- PROOF: `docker compose exec robotina sh -c 'p=$(pgrep -f "[h]ermes gateway" | head -1); test -n "$p" && test "$p" != "$$" && tr "\0" "\n" < /proc/$p/environ | grep "^HOME="'`
  (non-empty, `HOME=/opt/data`)

#### Scenario: State directories resolve under `/opt/data`

- GIVEN the stack is up and the agent toolchain has been exercised once
- WHEN the config, git and Go paths are queried
- THEN the config directory exists under `/opt/data` and `GOPATH` is `/opt/data/go`
- PROOF:
  `docker compose exec robotina sh -c 'ls -d /opt/data/.config/opencode /opt/data/.config/git'` and
  `docker compose exec robotina sh -c 'go env GOPATH'` (expected `/opt/data/go`)

#### Scenario: Git's global config origin is inside the bind

- GIVEN the stack is up
- WHEN git reports where its global configuration comes from
- THEN every reported origin path is under `/opt/data`
- PROOF: `docker compose exec robotina sh -c 'git config --global --show-origin --list'`
  (every origin path starts with `/opt/data/`)

### Requirement: SL2 — WAL stores live on native volumes mounted inside the bind

`engram.db` and `opencode.db` SHALL live on the native Docker volumes `robotina_engram_db`
and `robotina_opencode_db`, mounted at `/opt/data/.engram` and
`/opt/data/.local/share/opencode` respectively, and SHALL NOT be placed on a Windows bind
mount (WAL over a Windows bind mount can corrupt silently).

#### Scenario: Both stores are volume mounts, not bind mounts

- GIVEN the stack is up
- WHEN the mounts for the two store paths are listed
- THEN both paths are mounted and neither mount is of type `9p` or `virtiofs`
- PROOF: `docker compose exec robotina sh -c 'mount | grep -E "\.engram|\.local/share/opencode"'`
  (exactly two lines; no line contains `9p` or `virtiofs`)

#### Scenario: The two volumes exist under their original names

- GIVEN the change is applied
- WHEN the Docker volumes are listed
- THEN both original volume names are present (so rollback remounts them at their old paths)
- PROOF: `docker volume ls --format '{{.Name}}' | grep -E '^robotina_(engram|opencode)_db$'`
  (two matches)

#### Scenario: The SQLite files are written onto the volumes

- GIVEN the stack has run once and served at least one delegation
- WHEN the store directories are searched for database files
- THEN at least one `*.db` file exists under each store path
- PROOF: `docker compose exec robotina sh -c 'find /opt/data/.engram /opt/data/.local/share/opencode -maxdepth 2 -name "*.db" | sort'`
  (non-empty; empty output is a FAILURE)

#### Scenario: The nested-mount risk is explicitly closed or escalated

- GIVEN the merged stack
- WHEN the mounts and a durability round-trip (`down` / `up`) have been observed
- THEN the result is recorded, and a failure is escalated to the user rather than silently
  replaced by the `/root`-rooted fallback
- PROOF: the two probes above plus SL3's persistence scenario; the outcome MUST be written into
  `odd/tasks/single-robotina-container.md` as evidence (proposal §9 risk 1)

### Requirement: SL3 — State survives `down` / `up`

Agent state SHALL survive a plain `docker compose down` / `docker compose up -d` cycle: the
volumes SHALL NOT be removed, and previously created sessions and engram memory SHALL still
be readable afterwards.

#### Scenario: `down` does not remove the state volumes

- GIVEN the stack is up with state written
- WHEN the stack is brought down and the volumes are listed
- THEN both state volumes still exist
- PROOF: `docker compose down` then
  `docker volume ls --format '{{.Name}}' | grep -cE '^robotina_(engram|opencode)_db$'`
  (expected `2`)

#### Scenario: Session history is a superset after recreation

- GIVEN the stack is up with at least one recorded session, and the export helper available
- WHEN an export is taken, the stack is recreated, and a second export is taken
- THEN every session identifier present in the earlier export is present in the later one
- PROOF:
  `docker compose exec robotina sh -c '/opt/export-state.sh'`
  then `docker compose down && docker compose up -d`
  then `docker compose exec robotina sh -c '/opt/export-state.sh'`, followed host-side by
  `HOST_DATA_DIR=$(grep -m1 '^HOST_DATA_DIR=' .env | cut -d= -f2- | tr -d "\r"); a=$(ls -t "$HOST_DATA_DIR"/backups/*.json | sed -n 2p); b=$(ls -t "$HOST_DATA_DIR"/backups/*.json | sed -n 1p); comm -23 <(grep -o '"id":"[^"]*"' "$a" | sort -u) <(grep -o '"id":"[^"]*"' "$b" | sort -u)`
  (empty output; the assertion is on the session-identifier set whatever the export payload shape)

#### Scenario: engram memory survives the path change

- GIVEN an engram memory exists before the recreation
- WHEN the stack is recreated and the engram store is read with the documented read command
- THEN the memory is still present
- PROOF: `docker compose exec robotina sh -c 'ls -l /opt/data/.engram'` before and after the
  cycle (same store, non-empty), plus the documented engram read command named by design
  (do not invent a CLI invocation)

### Requirement: SL4 — Copy-forward, non-blocking, idempotent, never-deleting migration

Existing pre-merge host state SHALL be handled by a copy-forward procedure: `${HOST_DATA_DIR}/opencode/`
and `${HOST_DATA_DIR}/git/` SHALL be copied into `${HOST_DATA_DIR}/hermes/.config/opencode/`
and `${HOST_DATA_DIR}/hermes/.config/git/` **only when the destination is absent**;
`${HOST_DATA_DIR}/go/` SHALL NOT be copied; the first start SHALL NOT be gated on, or wait
for, the migration; and the pre-merge host folders SHALL NEVER be deleted by this change
(frozen: proposal §17 answer 2, §8.2).

#### Scenario: The stack starts with the migration not run

- GIVEN the legacy host folders untouched and no migrated destination
- WHEN the stack is started
- THEN it comes up and the endpoint answers, with no migration step performed
- PROOF: `docker compose config -q && docker compose up -d && docker compose exec robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/global/health'`
- NOTE: credential-aware, per `opencode-endpoint` EP1's apply obligation (design §19.4); the
  password is never echoed.

#### Scenario: Re-running the migration never overwrites newer state

- GIVEN a migrated destination file with content newer than its legacy source
- WHEN the documented migration step is run twice
- THEN the destination file is byte-identical before and after
- PROOF: capture `sha256sum <destination>` before, run the migration step twice, capture again
  (identical hashes). The exact migration command is the one design names (proposal §14 Q12);
  this scenario constrains the observable, not the mechanism.
- CLOSED BY DESIGN §12: a host-side documented helper `scripts/migrate-state.ps1` (per-path
  copy-forward only when the destination is absent, non-blocking, idempotent, never delete),
  documented in both READMEs with a POSIX equivalent; the legacy folders stay as the rollback
  safety net.

#### Scenario: Nothing is deleted

- GIVEN the migration has been run
- WHEN the legacy host folders are inspected
- THEN all three still exist and the two copied-from folders are non-empty
- PROOF:
  `HOST_DATA_DIR=$(grep -m1 '^HOST_DATA_DIR=' .env | cut -d= -f2- | tr -d "\r"); ls -ld "$HOST_DATA_DIR/opencode" "$HOST_DATA_DIR/git" "$HOST_DATA_DIR/go"` (all three exist)
  and `ls -A "$HOST_DATA_DIR/opencode" "$HOST_DATA_DIR/git"` (non-empty)

#### Scenario: The rebuildable Go cache is not copied

- GIVEN the migration has been run
- WHEN the merged state root is inspected
- THEN the migration did not create a Go cache there
- PROOF: `HOST_DATA_DIR=$(grep -m1 '^HOST_DATA_DIR=' .env | cut -d= -f2- | tr -d "\r"); ls -d "$HOST_DATA_DIR/hermes/go"` (must fail; absence is the expected result)

#### Scenario: Both READMEs document the migration

- GIVEN the merged change
- WHEN both READMEs are searched for the migration instructions
- THEN each README documents the copy-forward step
- PROOF: `grep -ciE "migra|migration|\.config/opencode" README.md README.en.md` (both counts non-zero)

### Requirement: SL5 — The merged service mounts only the target layout

`compose.yml` SHALL NOT declare mounts for the standalone legacy host folders
`${HOST_DATA_DIR}/opencode`, `${HOST_DATA_DIR}/git` and `${HOST_DATA_DIR}/go`. The merged
service's state mounts SHALL be exactly: the Hermes bind at `/opt/data`, the shared workspace
bind, the export-output bind, and the two nested volumes above.

#### Scenario: No legacy host folder is mounted

- GIVEN the merged compose file
- WHEN its `HOST_DATA_DIR` mount sources are listed
- THEN none of them resolves to `opencode`, `git` or `go`
- PROOF: `git grep -n "HOST_DATA_DIR" -- compose.yml | grep -E "/(opencode|git|go)"`
  (no output, exit non-zero)

#### Scenario: The target mount set is present

- GIVEN the merged compose file
- WHEN its `HOST_DATA_DIR` mount sources are listed
- THEN the set is exactly `hermes`, `workspace` and `backups`
- PROOF: `git grep -n "HOST_DATA_DIR" -- compose.yml` (readable inventory, no secrets in a source file)

#### Scenario: The volumes are re-targeted, not renamed

- GIVEN the merged compose file
- WHEN the two state volumes are searched for
- THEN both original names remain, mounted at the new `/opt/data` paths
- PROOF: `git grep -n "robotina_engram_db\|robotina_opencode_db" -- compose.yml`
  (both names present; targets `/opt/data/.engram` and `/opt/data/.local/share/opencode`)

### Requirement: SL6 — State ownership is fixed from inside the container

Ownership of the writable state roots SHALL be established by the container itself at
startup (a root-privileged cont-init step running before user services), so that a freshly
created host state folder is writable by the application uid without a host-side privileged
step. Whether `scripts/fix-permissions.ps1` is deleted or kept and re-documented SHALL NOT be
decided here (Q7 — CLOSED BY DESIGN §8.4, confirmed by the user: the host script is deleted and
the container-side cont-init step replaces it; deleting a host script requires user
confirmation).

#### Scenario: The application uid can write the state root

- GIVEN the stack is up
- WHEN a write is attempted as uid 10000 inside the state root
- THEN the write succeeds
- PROOF: `docker compose exec robotina sh -c 's6-setuidgid hermes sh -c "touch /opt/data/.write-test && rm /opt/data/.write-test" && echo writable-as-10000'`

#### Scenario: The state root is owned by the application uid

- GIVEN the stack is up
- WHEN the state root ownership is read
- THEN owner and group are `10000:10000`
- PROOF: `docker compose exec robotina sh -c 'stat -c "%u:%g" /opt/data'` (expected `10000:10000`)

#### Scenario: A fresh host state tree needs no host-side privileged step

- GIVEN an empty host state directory and an isolated compose project name
- WHEN the merged service starts against it
- THEN the application uid can write its state without any host-side script being run
- PROOF:
  `docker compose -p robotina-fresh up -d robotina` then
  `docker compose -p robotina-fresh exec robotina sh -c 's6-setuidgid hermes sh -c "touch /opt/data/.write-test && rm /opt/data/.write-test" && echo writable-as-10000'`
- CAUTION: use the isolated project name so the fresh-state run cannot collide with the
  running `robotina` container name.

#### Scenario: Human check — the setup no longer requires a host-side permission step

- GIVEN the merged change
- WHEN the reviewer reads the setup sections of both READMEs
- THEN no numbered setup step instructs running the host PowerShell helper
- PROOF: human check; entry point `grep -rniE "fix-permissions" README.md README.en.md SECURITY.md`
  (any remaining match MUST be explanatory text about the removal or the proposal §14 Q7
  decision, never a setup instruction)
