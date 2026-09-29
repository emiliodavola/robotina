# agent-container Specification

## Purpose

Define the observable properties of the merged agent runtime: **exactly one** agent
container named `robotina`, running the vendor s6-overlay tree as PID 1, carrying the
merged hardening set, a single consolidated resource budget, and membership of the
`agents` network only.

This domain is **new**: `openspec/specs/` was empty before this change, so this file is a
full domain spec and is copied verbatim into `openspec/specs/agent-container/spec.md` at
archive time (no delta, no canonical predecessor).

Artifact language: English (proposal §16, `openspec/project.md`).

## Verification model

There is no test runner in this repository (`openspec/config.yaml` → `testing.runner: none`).
Every scenario below names the exact shell-level observation that proves it.

- Static recipes MUST use `docker compose config -q`. The bare form prints resolved `.env`
  secrets (proposal §9 risk 8) and is forbidden.
- Runtime recipes assume `docker compose up -d` completed, unless the scenario says otherwise.
- **No vacuous passes.** Any probe built on `pgrep`/`grep` MUST also assert that it matched
  something; an empty match set is a FAILURE, never a pass. `pgrep`/`pkill` patterns MUST use a
  character-class form (`[h]ermes gateway`, `[o]pencode serve`) so the probe shell's own command
  line cannot match itself, and a recipe that substitutes a single pid MUST take `head -1` and
  assert the pid is non-empty and is not `$$`.
- `docker inspect` MUST always be called with a narrow `--format` that excludes `.Config.Env`;
  the unfiltered form prints secret values.
- `docker network inspect`, `docker volume ls` and `docker inspect --format` are accepted
  extensions of the `runtime` layer in `openspec/config.yaml`. No test runner is introduced.

## Requirements

### Requirement: AC1 — Exactly two services, one of them the merged agent

The stack SHALL define exactly two services: `robotina` and `egress-proxy`. The `hermes`
and `opencode` services SHALL cease to exist as compose services.

#### Scenario: Service inventory is exactly the expected pair

- GIVEN the change is applied on branch `feat/single-robotina-container`
- WHEN the compose service inventory is rendered
- THEN the output lists exactly `robotina` and `egress-proxy`
- PROOF: `docker compose config --services`

#### Scenario: Static validation still passes

- GIVEN the merged compose file
- WHEN compose validates it
- THEN the command exits 0 and prints nothing
- PROOF: `docker compose config -q` (exit 0; the bare `docker compose config` form is forbidden)

#### Scenario: The retired service names survive nowhere

- GIVEN the merged compose file
- WHEN the service inventory is searched for the old service names
- THEN neither `hermes` nor `opencode` appears as a service
- PROOF: `docker compose config --services | grep -E '^(hermes|opencode)$'` (no output, exit non-zero)

### Requirement: AC2 — The container answers to the name `robotina`

The merged service SHALL declare `container_name: robotina`, so `docker compose exec
robotina …` and DNS on the `agents` network both resolve to it.

#### Scenario: The running container is named exactly `robotina`

- GIVEN the stack is up
- WHEN the container names are listed
- THEN the agent container is reported as `robotina`
- PROOF: `docker compose ps --format '{{.Name}}'`

#### Scenario: The name resolves on the `agents` network

- GIVEN the stack is up
- WHEN name resolution for `robotina` is attempted from inside the agent container
- THEN at least one address is returned
- PROOF: `docker compose exec robotina sh -c 'getent hosts robotina'` (non-empty output; empty output FAILS)

### Requirement: AC3 — PID 1 is the image entrypoint (s6-overlay)

`robotina` SHALL NOT declare `user:` and SHALL NOT declare `init: true`. PID 1 SHALL be the
vendor image entrypoint chain, so the s6-overlay supervision tree is live. A foreign init
(`tini`/`docker-init`) or a `user:` override SHALL NOT be present, because the vendor
entrypoint rejects arbitrary uids and the non-PID-1 fallback starts no supervised service.

#### Scenario: PID 1 is not a foreign init

- GIVEN the stack is up
- WHEN PID 1's command line is read
- THEN the vendor entrypoint/s6 chain is shown and the text does NOT contain `tini` or `docker-init`
- PROOF: `docker compose exec robotina sh -c 'tr "\0" " " < /proc/1/cmdline'`

#### Scenario: PID 1 runs as root, proving no `user:` override

- GIVEN the stack is up
- WHEN PID 1's credentials are read
- THEN the real/effective uid and gid are both 0
- PROOF: `docker compose exec robotina sh -c 'grep -E "^(Uid|Gid)" /proc/1/status'`

#### Scenario: The s6 supervision tree is live

- GIVEN the stack is up
- WHEN the s6 service database is queried
- THEN the command succeeds and lists the supervised services (non-empty output)
- PROOF: `docker compose exec robotina s6-rc -a list`

### Requirement: AC4 — Merged hardening and the six-capability set

`robotina` SHALL keep `cap_drop: [ALL]` plus exactly the six capabilities the supervision tree
requires (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `KILL`), `no-new-privileges:true`,
`ulimits.core: 0`, a bounded `pids_limit`, and bounded `json-file` logs.

AMENDMENT (apply, task 28): the set was **five** capabilities in the original requirement
(`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`; bounding mask `0xcb`). Measured at
runtime, `cap_drop: [ALL]` without `KILL` left the root s6 supervisors unable to signal their
uid-10000 services: an in-container shutdown wedged and Docker had to SIGKILL after
`stop_grace_period`. `KILL` restores the supervision mechanics and does **not** widen what the
agent can do — the uid-10000 processes keep `CapEff=0x0` (design §13, amended). The requirement's
meaning is unchanged: a minimal, explicitly enumerated set under `cap_drop: [ALL]`.

#### Scenario: The effective capability set is exactly the six required capabilities

- GIVEN the stack is up
- WHEN PID 1's capability masks are read
- THEN the printed masks decode to exactly `cap_chown`, `cap_dac_override`, `cap_fowner`,
  `cap_setgid`, `cap_setuid`, `cap_kill` (the six-bit mask `0x00000000000000eb`)
- PROOF: `docker compose exec robotina sh -c 'grep -E "Cap(Bnd|Eff)" /proc/1/status'`

#### Scenario: No new privileges can be gained

- GIVEN the stack is up
- WHEN the calling process's `NoNewPrivs` flag is read
- THEN the value is `1`
- PROOF: `docker compose exec robotina sh -c 'grep -i NoNewPrivs /proc/self/status'`

#### Scenario: Core dumps are disabled

- GIVEN the stack is up
- WHEN the core-dump ulimit is read inside the container
- THEN the reported size is `0`
- PROOF: `docker compose exec robotina sh -c 'ulimit -c'`

#### Scenario: Logs are bounded by the json-file rotation

- GIVEN the running container
- WHEN only the log configuration is inspected (never `.Config.Env`)
- THEN the driver is `json-file` with 10 MB per file and 3 files
- PROOF: `docker inspect --format '{{.HostConfig.LogConfig.Type}} {{.HostConfig.LogConfig.Config}}' robotina`
  (expected: `json-file map[max-file:3 max-size:10m]`)

### Requirement: AC5 — OpenCode and engram are s6-supervised services

`opencode` and `engram` SHALL run as **supervised s6 services** visible to s6, not as
backgrounded children of an entrypoint. Their output SHALL be observable through a
documented path or through the bounded container log stream (today's redirect to
`/var/log/engram.log` silently fails for uid 10000 — CLOSED BY DESIGN §9.3: the bounded
container log stream, via s6, is the chosen observable path).

#### Scenario: s6 lists both services

- GIVEN the stack is up
- WHEN the s6 service database is listed
- THEN the listing includes `opencode` and `engram`
- PROOF: `docker compose exec robotina s6-rc -a list | grep -E '^(opencode|engram)$'` (must match two lines)

#### Scenario: A supervised restart happens without manual intervention

- GIVEN the stack is up and the loopback endpoint is healthy
- WHEN the `opencode serve` process is killed inside the container
- THEN s6 restarts it and the health probe succeeds again without any manual command
- PROOF:
  `docker compose exec robotina sh -c 'pkill -f "[o]pencode serve"'` then
  `docker compose exec robotina sh -c 'i=0; while [ $i -lt 30 ]; do set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 2 http://127.0.0.1:4096/global/health >/dev/null && exit 0; i=$((i+1)); sleep 2; done; exit 1'`
- NOTE: the health probe is credential-aware because `OPENCODE_SERVER_PASSWORD` is kept
  (design §10.3), so a password-protected `/global/health` cannot turn this scenario into a
  false failure. The password is never echoed.
- NOTE: the restart backoff policy is CLOSED BY DESIGN §9.2: a `finish` script with capped
  exponential backoff (1→30 s) and a healthy-run reset, with unbounded restarts and no latch;
  this scenario asserts recovery, not the delay distribution.

#### Scenario: engram's output is actually observable

- GIVEN the stack is up
- WHEN the container log stream is read
- THEN it is non-empty and contains engram output **or**, if design chose a log file path
  (Q10 — CLOSED BY DESIGN §9.3: the container log stream is the chosen path, so no separate log
  file exists), that path exists and is non-empty
- PROOF: `docker compose logs --tail 200 robotina` (plus, when design names a file,
  `docker compose exec robotina sh -c 'test -s <design-named-log-path>'`)

### Requirement: AC6 — One consolidated resource budget

The merged service SHALL carry a single consolidated budget for the merged cgroup:
`mem_limit: 6g` and `cpus: 6.0` (frozen: proposal §17 answer 4), plus a finite
`pids_limit` sized for Hermes + opencode + LSP children + engram + R/go builds. The exact
`pids_limit` value SHALL NOT be fixed here (proposal §14 Q1: it MUST be measured and recorded
with its rationale by design/verify).

#### Scenario: The memory ceiling is 6 GiB

- GIVEN the stack is up
- WHEN the container cgroup's memory ceiling is read
- THEN the value is `6442450944` bytes
- PROOF: `docker compose exec robotina sh -c 'cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes'`

#### Scenario: The CPU ceiling is 6.0 CPUs

- GIVEN the stack is up
- WHEN the container cgroup's CPU limit is read
- THEN the quota/period pair is `600000 100000` (or the v1 quota `600000`)
- PROOF: `docker compose exec robotina sh -c 'cat /sys/fs/cgroup/cpu.max 2>/dev/null || cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us'`

#### Scenario: The process count is bounded, not unlimited

- GIVEN the stack is up
- WHEN the container cgroup's PID ceiling is read
- THEN the value is a finite positive integer and is NOT `max`
- PROOF: `docker compose exec robotina sh -c 'cat /sys/fs/cgroup/pids.max'`
- CLOSED BY DESIGN §16: `pids_limit: 1024` on the merged service, confirmed or raised at apply
  by measuring a running merged container under a build + LSP workload (the measured peak itself
  is recorded by the measurement task).

### Requirement: AC7 — `robotina` is an `agents`-only service with no published port

`robotina` SHALL join the `agents` network only, SHALL NOT join the `egress` network, and
SHALL publish no port.

#### Scenario: Network membership is exactly `agents`

- GIVEN the stack is up
- WHEN the `agents` and `egress` network memberships are listed
- THEN `agents` contains `robotina` and `egress-proxy`, and `egress` contains only `egress-proxy`
- PROOF:
  `docker network inspect agents --format '{{range .Containers}}{{.Name}} {{end}}'` and
  `docker network inspect egress --format '{{range .Containers}}{{.Name}} {{end}}'`

#### Scenario: No port is published

- GIVEN the stack is up
- WHEN the published ports are listed
- THEN the agent container reports no host port mapping
- PROOF: `docker compose ps --format 'table {{.Name}}\t{{.Ports}}'`

#### Scenario: No `ports:` key exists in the compose file

- GIVEN the merged compose file
- WHEN the source is searched for a `ports` mapping
- THEN nothing is found
- PROOF: `git grep -nE '^[[:space:]]+ports:' -- compose.yml` (no output, exit non-zero)

### Requirement: AC8 — The accepted merged-container regressions are documented with measurements

The merge accepts **one** container lifecycle shared by every process inside it, and
per-container capabilities (proposal §6.2 R3, R4). SECURITY.md SHALL state the **measured**
lifecycle behavior — s6 supervises `gateway-default` (`hermes gateway run`) and restarts it in
place, so a Hermes gateway crash does **not** cycle the container; the container's PID 1 is the
s6 supervision tree and the container exits when that tree goes down — and SHALL record the
**measured** capability set of the uid-10000 OpenCode process (proposal §14 Q4). No explicit
capability dropping SHALL be added to the OpenCode process (frozen: D2).

AMENDMENT (apply, task 28): the requirement originally stated that the container's main program
was Hermes and that a Hermes exit took the container down. Measured at runtime, `hermes gateway`
runs as the s6-supervised service `gateway-default` (restarted in place, `RestartCount`
unchanged), and the container's main program is a separate `rc.init` child. The scenario below
was rewritten to the measured contract. The accepted consequence (proposal R4) is that the
gateway and the rest of the container are **one** failure domain, not two — the merge does not
give the gateway a private restart.

#### Scenario: A gateway crash is restarted by s6 and does not cycle the container

- GIVEN the stack is up and the unit's restart counter and start time have been captured
- WHEN the `hermes gateway` process is terminated inside the container
- THEN s6 restarts the `gateway-default` service in place (a new, non-empty gateway pid) while the
  container's `RestartCount` and `StartedAt` stay **unchanged** — the container did not cycle
- PROOF:
  1. before: `docker inspect --format '{{.RestartCount}} {{.State.StartedAt}}' robotina`
  2. terminate as the owning uid — the faithful "kill the process inside the container" form
     (with `KILL` readmitted by AC4 a root exec can now signal uid 10000 too, but the recipe keeps
     the uid-10000 form):
     `docker compose exec -u hermes robotina sh -c 'pkill -f "[h]ermes gateway"'`
  3. after: `docker compose exec robotina sh -c 'pgrep -f "[h]ermes gateway" | head -1'` prints
     a **non-empty** pid that differs from the one captured in step 1 (an empty match is a
     FAILURE, never a pass), and
     `docker inspect --format '{{.RestartCount}} {{.State.StartedAt}}' robotina` is unchanged
- NOTE: the container surviving the gateway kill is now the **expected** result, not a failure:
  `gateway-default` is an s6 service, so the gateway's lifetime belongs to the supervision tree,
  not to the container.
- NOTE: the container exits when the **s6 supervision tree** (PID 1) goes down — an operator
  `docker compose stop robotina`/`docker kill` of PID 1 — and `restart: unless-stopped` then
  brings the whole unit back. With `KILL` in the capability set (AC4, amended) that shutdown is
  graceful inside the grace period instead of relying on SIGKILL; the measured stop duration is
  recorded in SECURITY.md.
- NOTE: the narrow `--format` keeps the secret-safety rule (`docker inspect` never prints
  `.Config.Env`).
- CAUTION: destructive by design — run it at the end of a verification session, before
  restarting the stack.

#### Scenario: The measured OpenCode capability set is on record

- GIVEN the stack is up
- WHEN the uid-10000 OpenCode process's capabilities are read
- THEN the masks are recorded in SECURITY.md as measured evidence
- PROOF: `docker compose exec robotina sh -c 'for p in $(pgrep -f "[o]pencode serve"); do echo "pid=$p uid=$(awk "/^Uid/{print \$2}" /proc/$p/status)"; grep -E "Cap(Inh|Prm|Eff|Bnd|Amb)|NoNewPrivs" /proc/$p/status; done'`
  plus `grep -n "CapEff\|CapBnd" SECURITY.md` (non-empty)
- NOTE: the loop MUST print at least one `pid=` line — a `pgrep` that matches nothing is a
  FAILURE (no vacuous pass) — and the character-class pattern keeps the probe shell's own
  command line from matching itself. This is the same probe design §13 specifies.

#### Scenario: The budget decision is on record

- GIVEN the change is applied
- WHEN SECURITY.md is read for the resource-budget entry
- THEN the 6g / 6.0 ceiling and the re-forecast `pids_limit` with its rationale are stated
- PROOF: `grep -niE "mem_limit|6g|pids_limit" SECURITY.md` (non-empty)

### Requirement: AC9 — The documentation describes one container, not two

Every tracked document that describes the topology SHALL describe **one** agent container
named `robotina`. No surviving claim may state two agent containers, an independent OpenCode
lifecycle, or the `http://opencode:4096` endpoint. The Spanish and English documents SHALL
not contradict each other on any measured claim.

#### Scenario: No stale two-container claim survives

- GIVEN the merged change
- WHEN the documentation set is searched for the retired topology
- THEN nothing is found
- PROOF (all four must be empty):
  `grep -rn "http://opencode:4096" README.md README.en.md SECURITY.md hermes/ scripts/`
  `grep -rniE "dos agentes|dos contenedores|two agent containers|two containers|sibling container|contenedor hermano" README.md README.en.md SECURITY.md hermes/ scripts/`
  `grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/ .env.example`
  `grep -rn "docker inspect hermes\|docker inspect opencode" README.md README.en.md SECURITY.md .env.example`

#### Scenario: The bilingual pair stays in sync

- GIVEN the change set
- WHEN the files changed against the base branch are listed
- THEN `README.md` and `README.en.md` are either both changed or both unchanged
- PROOF: `git diff --name-only $(git merge-base HEAD main)...HEAD -- README.md README.en.md`

#### Scenario: `openspec/project.md` matches the merged reality

- GIVEN the merged change
- WHEN the project record is searched for the retired build directory and for the new name
- THEN the old build path is gone and the merged name is present
- PROOF: `grep -n "opencode/Dockerfile" openspec/project.md` (no output, exit non-zero) and
  `grep -c "robotina" openspec/project.md` (non-zero)

### Requirement: AC10 — Hermes' write guard covers the shared workspace

The `robotina` service SHALL set `HERMES_WRITE_SAFE_ROOT` to the `os.pathsep`-separated list
`/opt/data/:/workspace/`, widening the vendor image's `/opt/data/`-only default by exactly one
entry: the shared workspace. Both entries are directories, so both carry a trailing slash.
`HERMES_HOME` SHALL remain `/opt/data`, and widening the safe root SHALL NOT weaken the
credential denylist.

#### Scenario: The compose default is the widened list

- GIVEN the change is applied
- WHEN the compose source is read
- THEN the default value of `HERMES_WRITE_SAFE_ROOT` is `/opt/data/:/workspace/`
- PROOF: `grep -n 'HERMES_WRITE_SAFE_ROOT:' compose.yml`
  (shows `${ROBOTINA_HERMES_WRITE_SAFE_ROOT:-/opt/data/:/workspace/}`; the *resolved* value is
  intentionally not asserted here because a shell environment variable or a `.env` override
  legitimately takes precedence over the default)

#### Scenario: The compose file still validates

- GIVEN the change is applied
- WHEN compose validates the file
- THEN the command exits 0 and prints nothing
- PROOF: `docker compose config -q` (exit 0; the bare `docker compose config` form is forbidden)

#### Scenario: The guard admits the workspace and still denies outside every root

- GIVEN the stack is up with the widened value
- WHEN the write guard classifies paths
- THEN a path under the workspace is allowed while a path outside every root is denied
- PROOF:
  `docker compose exec -T robotina /opt/hermes/.venv/bin/python -c 'import sys; sys.path.insert(0, "/opt/hermes"); from agent.file_safety import get_write_denied_error as d; print(d("/workspace/sofer/tests/conftest.py") is None, d("/tmp/x.py") is not None)'`
  (prints `True True`)

#### Scenario: `HERMES_HOME` and its writes are unchanged

- GIVEN the stack is up with the widened value
- WHEN the Hermes home is read and a path under it is classified
- THEN the home is `/opt/data` and a write there is allowed
- PROOF: `docker compose exec -T robotina printenv HERMES_HOME` (prints `/opt/data`) and
  `docker compose exec -T robotina /opt/hermes/.venv/bin/python -c 'import sys; sys.path.insert(0, "/opt/hermes"); from agent.file_safety import get_write_denied_error as d; print(d("/opt/data/state.txt") is None)'`
  (prints `True`)

#### Scenario: Widening the safe root does not weaken the credential denylist

- GIVEN the stack is up with the widened value
- WHEN the write guard classifies credential and system paths
- THEN they stay denied even though `/workspace/` is allowed
- PROOF:
  `docker compose exec -T robotina /opt/hermes/.venv/bin/python -c 'import sys; sys.path.insert(0, "/opt/hermes"); from agent.file_safety import get_write_denied_error as d; print(d("/etc/passwd") is not None, d("/opt/data/.env") is not None)'`
  (prints `True True`)

#### Scenario: A trailing slash is notation, not semantics

- GIVEN the configured value carries a trailing slash on each directory entry
- WHEN the guard resolves the safe roots
- THEN it normalizes them to `/opt/data` and `/workspace`
- PROOF:
  `docker compose exec -T robotina /opt/hermes/.venv/bin/python -c 'import sys; sys.path.insert(0, "/opt/hermes"); from agent.file_safety import get_safe_write_roots; print(sorted(get_safe_write_roots()))'`
  (prints `['/opt/data', '/workspace']`)

### Requirement: AC11 — The binary the image pins is the binary that runs

For a tool the image pins, the supervised process SHALL NOT depend on a `PATH` resolution that the
agent's own home directory can shadow, and the container healthcheck SHALL compare the version that
runs with the version the image recorded. Measured origin: `engram` ran as **2.1.0** from a copy in
the agent's home (older than the merge) under a Dockerfile pin of **1.20.0**, and nothing surfaced
it — the same image could have had its memory backend replaced by anyone able to write that file
(#42).

#### Scenario: The supervised service execs an absolute path

- GIVEN the change is applied
- WHEN the s6 run script of `engram` is read
- THEN it execs the image's binary by absolute path, not by name
- PROOF: `grep -c 'exec s6-setuidgid hermes /usr/local/bin/engram serve' robotina/s6/s6-rc.d/engram/run`
  (must be exactly 1)

#### Scenario: The healthcheck compares running against pinned

- GIVEN a container whose image recorded `ROBOTINA_ENGRAM_VERSION`
- WHEN the healthcheck runs
- THEN it fails when the binary reports another version, and when `PATH` resolves `engram` to
  anything other than the image's copy
- PROOF:
  `docker compose exec robotina sh -c 'echo "$ROBOTINA_ENGRAM_VERSION"; /usr/local/bin/engram --version'`
  (the two versions MUST match) together with
  `docker compose exec robotina sh -c 'command -v engram'` (must print `/usr/local/bin/engram`)
- NOTE: the `PATH` assertion is the one that catches the shadow, and it fails until the shadowing
  copy in the agent's home is quarantined. That quarantine is part of the maintenance window
  procedure, not of the image build — deliberate, so the state change stays visible instead of
  happening inside a build.

### Requirement: AC12 — Runtime-provisioned tooling lands inside the bind and is invocable by name

Tools the agent installs at runtime (`uv tool install`) SHALL land inside the bind — `UV_TOOL_DIR`
under `/opt/data` — and their executables SHALL be linked into a directory that is already on the
stack's `PATH` (`UV_TOOL_BIN_DIR=/opt/data/.local/bin`). The image's managed interpreter SHALL keep
its own location and its own volume: a baked artifact and a runtime artifact have **opposite**
persistence requirements, and one variable set must not conflate them.

Measured origin (#44): the agent installed `kaggle` into `/opt/data/cache/uv-tools` — neither the
declared `UV_TOOL_DIR` nor a persistent location — and linked it into `/opt/data/bin`, which is
**not on the `PATH`**, so `command -v kaggle` failed while the tool was installed **and** its
credential was in place. Before that, the declared `UV_TOOL_DIR=/opt/uv/tools` did not exist at all,
and had it existed it would have lived in the container layer: gone on every recreate.

#### Scenario: The declared directories are in the bind and the bin directory is on the `PATH`

- GIVEN the change is applied
- WHEN the running container's `uv` environment and `PATH` are read
- THEN the tool directory is under `/opt/data`, the bin directory is on the `PATH`, and the
  interpreter directory is the volume
- PROOF:
  `docker compose exec robotina sh -c 'printf "TOOL=%s\nBIN=%s\nPY=%s\n" "$UV_TOOL_DIR" "$UV_TOOL_BIN_DIR" "$UV_PYTHON_INSTALL_DIR"; case ":$PATH:" in *":$UV_TOOL_BIN_DIR:"*) echo "BIN EN PATH";; *) echo "BIN FUERA DEL PATH";; esac'`
  (`TOOL` must start with `/opt/data/`, `BIN` must be `/opt/data/.local/bin`, `PY` must be
  `/opt/uv/python` — backed by the `robotina_uv_python` volume — and the last line must print
  `BIN EN PATH`)

#### Scenario: The interpreter directory is writable by the app uid

- GIVEN the change is applied and the container is running
- WHEN the interpreter volume root is checked as the app uid
- THEN the app uid owns it and can write in it, because `uv` writes its staging `.temp` there
- PROOF:
  `docker compose exec -T robotina sh -c 'test "$(stat -c %u /opt/uv/python)" = "$(id -u hermes)" && test "$(stat -c %g /opt/uv/python)" = "$(id -g hermes)" && echo OWNED-BY-APP'`
  (must print `OWNED-BY-APP`) together with
  `docker compose exec -T robotina sh -c 'PATH=/command:$PATH; s6-setuidgid hermes test -w /opt/uv/python && echo WRITE-OK || echo WRITE-DENIED'`
  (must print `WRITE-OK`; `WRITE-DENIED` is the exact FAILURE of #70, measured on 2026-09-28)
- NOTE: the re-own runs in the boot cont-init `10-robotina-state`, so a rebuilt and recreated
  container is what makes this pass; until then the checked-out change is exercised by the static
  proofs and the assertions above stay red on the running container on purpose.

#### Scenario: A runtime-installed tool is resolvable by name

- GIVEN a tool installed with the declared configuration
- WHEN the agent looks it up by name
- THEN it resolves, and it resolves from the bin directory above
- PROOF:
  `docker compose exec -T -u hermes robotina sh -c 'command -v kaggle && kaggle --version'`
  (must print the wrapper path under `/opt/data/.local/bin` and the CLI version; a bare
  `not found` is the exact FAILURE this requirement exists to prevent)

#### Scenario: The image does not depend on those two variables

- GIVEN a fresh container with no runtime-installed tools
- WHEN the image's own inventory is asserted
- THEN the build installs only the managed interpreter, so moving `UV_TOOL_DIR`/
  `UV_TOOL_BIN_DIR` cannot change the image
- PROOF: `grep -cE '^RUN .*uv tool install' robotina/Dockerfile` (must be 0; the pattern names the
  **code**, not the prose — the header comment mentions `uv tool install` on purpose, and a proof that
  matches comments is not a proof)

### Requirement: AC13 — The shadow-prone pinned tools publish their pin and resolve from the image

AC11 established the published-pin invariant for `engram`. Today that invariant covers exactly **two**
tools: `engram` and `gentle-ai`. The agent can place a copy of either in its own HOME, in
`/opt/data/.local/bin` — the directory the stack's `PATH` puts **before** `/usr/local/bin`, so a copy
there shadows the baked binary unnoticed. For each of
those two the image SHALL publish the pin it baked (`ENV ROBOTINA_<TOOL>_VERSION=${<TOOL>_VERSION}`,
sourced from the same `ARG`) and the container healthcheck SHALL compare the version the absolute
binary reports against the published pin **and** require `command -v <tool>` to resolve to the image's
own copy in `/usr/local/bin`. The build publishes the pin; the healthcheck detects drift.

The scope is deliberately bounded, not universal. The Dockerfile pins **six** tools through an `ARG`
(`ENGRAM_VERSION`, `GENTLE_AI_VERSION`, `MARKSMAN_RELEASE`, `OPENCODE_VERSION`, `GH_VERSION`,
`TAPLO_VERSION`), but only `engram` and `gentle-ai` publish a `ROBOTINA_*_VERSION` pin and are checked
by the healthcheck. The other four (`marksman`, `opencode-ai`, `gh`, `taplo`) are **not** covered yet;
extending the invariant to them is a follow-up, not part of this change. This requirement SHALL NOT be
read as a general obligation the repository already meets.

Measured origin (#74): `gentle-ai` was the **shadow-prone** tool left without the invariant — `engram`
already carried it (AC11), and the remaining four are not covered at all.
`ROBOTINA_GENTLE_AI_VERSION` was **unset** in the running container while `ARG GENTLE_AI_VERSION=3.1.0`
was baked; `/usr/local/bin` is `root:root` mode 755 and the s6 services run as `hermes` (uid 10000),
so `gentle-ai`'s in-container self-upgrade can never succeed — it stages `<binary>.new` beside the
destination for an atomic rename and dies with `EACCES` on the temp file. The correct update path
(`scripts/bump-tools.sh --write <tool>` + rebuild) appeared in **0** mentions across `README.md`,
`README.en.md` and `SECURITY.md`, and the repository had **no `AGENTS.md`** for the agent to read.
Upstream's opaque `EACCES` is out of scope here: this stack owns making the failure unnecessary and
loud, not patching the updater.

#### Scenario: The published-pin scope is exactly engram and gentle-ai today

- GIVEN the change is applied
- WHEN the Dockerfile's pins are counted
- THEN exactly two `ENV ROBOTINA_*_VERSION` lines exist (`engram` and `gentle-ai`), while all six
  ARG-pinned tools are present — adding a third pin or dropping one of the two FAILS this proof, so
  the requirement's claim cannot silently drift from the implementation
- PROOF:
  `grep -cE '^ENV ROBOTINA_[A-Z_]+_VERSION=' robotina/Dockerfile` (must be exactly 2) together with
  `grep -nE '^ENV ROBOTINA_(ENGRAM|GENTLE_AI)_VERSION=' robotina/Dockerfile` (must list exactly the
  `ROBOTINA_ENGRAM_VERSION` and `ROBOTINA_GENTLE_AI_VERSION` lines) and
  `grep -nE '^ARG (ENGRAM_VERSION|GENTLE_AI_VERSION|MARKSMAN_RELEASE|OPENCODE_VERSION|GH_VERSION|TAPLO_VERSION)=' robotina/Dockerfile`
  (must list all six ARG-pinned tools; the four without a matching `ENV` are the uncovered follow-up)

#### Scenario: The healthcheck passes when the pin matches

- GIVEN a container whose `/usr/local/bin/gentle-ai` reports the pinned version
- WHEN the repository's healthcheck runs with the pin matching
- THEN all four checks pass and the command exits 0
- PROOF:
  `a="$(sed -n 's/^ARG GENTLE_AI_VERSION=//p' robotina/Dockerfile)"; docker compose exec -T -e ROBOTINA_GENTLE_AI_VERSION="$a" robotina sh -s < robotina/healthcheck.sh`
  (exit 0; the pin is read from the Dockerfile, so the proof survives a version bump)
- NOTE: this is the stale-image recipe used elsewhere in this file: the run reads the **repository's**
  copy of the healthcheck through `sh -s`, so the proof stays valid against the running image until the
  next rebuild bakes the check in. The `[ -n "${ROBOTINA_GENTLE_AI_VERSION:-}" ]` guard is what makes a
  pre-change container — one that does not publish the variable — skip the fourth check instead of
  failing falsely.

#### Scenario: The healthcheck fails on a pin mismatch

- GIVEN the running binary reports its baked version
- WHEN the repository's healthcheck runs against a pin that does not match
- THEN it exits non-zero and names both versions on stderr
- PROOF:
  `docker compose exec -T -e ROBOTINA_GENTLE_AI_VERSION=9.9.9 robotina sh -s < robotina/healthcheck.sh`
  (exit 1; stderr names `9.9.9` and the running baked version)
- NOTE: `9.9.9` is deliberately **not** a real version; it is a literal chosen only to fail the
  comparison, and it is the one hardcoded value these proofs keep on purpose.

#### Scenario: The healthcheck fails when a copy shadows the baked binary

- GIVEN a fake `gentle-ai` executable under `/tmp/ga-shadow`, placed ahead of `/usr/local/bin` on the `PATH`
- WHEN the repository's healthcheck runs with the pin matching
- THEN it exits non-zero and names the resolved path on stderr
- PROOF:
  `a="$(sed -n 's/^ARG GENTLE_AI_VERSION=//p' robotina/Dockerfile)"; docker compose exec -T -e ROBOTINA_GENTLE_AI_VERSION="$a" robotina sh -c 'mkdir -p /tmp/ga-shadow && printf "#!/bin/sh\necho shadow\n" > /tmp/ga-shadow/gentle-ai && chmod 0755 /tmp/ga-shadow/gentle-ai; PATH=/tmp/ga-shadow:$PATH sh -s; rc=$?; rm -rf /tmp/ga-shadow; exit $rc' < robotina/healthcheck.sh`
  (exit 1; stderr names `/tmp/ga-shadow/gentle-ai`)
- NOTE: the fixture is created and removed inside the same command, so no shadowing copy survives the
  proof, and the absolute-path version check still passes — it is the `PATH` assertion that catches the
  shadow, exactly as in AC11.
