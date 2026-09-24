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

### Requirement: AC10 — Hermes' write guard covers the workspace project

The `robotina` service SHALL set `HERMES_WRITE_SAFE_ROOT` to the `os.pathsep`-separated list
`/opt/data:/workspace/sofer`, widening the vendor image's `/opt/data`-only default by exactly
one workspace project prefix. `HERMES_HOME` SHALL remain `/opt/data`, and `/workspace` as a
whole SHALL NOT become writable.

#### Scenario: The effective value is the widened list

- GIVEN the change is applied
- WHEN the compose service environment is rendered
- THEN `HERMES_WRITE_SAFE_ROOT` resolves to `/opt/data:/workspace/sofer`
- PROOF: `docker compose config --format json | grep -o '"HERMES_WRITE_SAFE_ROOT": *"[^"]*"'`
  (prints exactly `"HERMES_WRITE_SAFE_ROOT": "/opt/data:/workspace/sofer"`; the `grep` filter is
  mandatory so no other resolved `.env` value reaches stdout, and the bare, unfiltered command
  stays forbidden)

#### Scenario: The guard admits the project and still denies outside it

- GIVEN the stack is up with the widened value
- WHEN the write guard classifies paths
- THEN a path under `/workspace/sofer` is allowed while a sibling workspace path is denied
- PROOF:
  `docker compose exec -T robotina /opt/hermes/.venv/bin/python -c 'import sys; sys.path.insert(0, "/opt/hermes"); from agent.file_safety import get_write_denied_error as d; print(d("/workspace/sofer/tests/conftest.py") is None, d("/workspace/other/x.py") is not None)'`
  (prints `True True`)

#### Scenario: `HERMES_HOME` and its writes are unchanged

- GIVEN the stack is up with the widened value
- WHEN the Hermes home is read and a path under it is classified
- THEN the home is `/opt/data` and a write there is allowed
- PROOF: `docker compose exec -T robotina printenv HERMES_HOME` (prints `/opt/data`) and
  `docker compose exec -T robotina /opt/hermes/.venv/bin/python -c 'import sys; sys.path.insert(0, "/opt/hermes"); from agent.file_safety import get_write_denied_error as d; print(d("/opt/data/state.txt") is None)'`
  (prints `True`)

#### Scenario: The added prefix is one project, not the whole workspace

- GIVEN the change is applied
- WHEN the configured value is read from the compose source
- THEN the list contains `/workspace/sofer` and never a bare `/workspace`
- PROOF: `grep -n 'HERMES_WRITE_SAFE_ROOT' compose.yml` (the added root is `/workspace/sofer`)
