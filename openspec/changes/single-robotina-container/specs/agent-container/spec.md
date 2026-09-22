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

### Requirement: AC4 — Merged hardening and the five-capability set

`robotina` SHALL keep `cap_drop: [ALL]` plus exactly the five capabilities Hermes requires
(`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`), `no-new-privileges:true`,
`ulimits.core: 0`, a bounded `pids_limit`, and bounded `json-file` logs.

#### Scenario: The effective capability set is exactly the five required capabilities

- GIVEN the stack is up
- WHEN PID 1's capability masks are read
- THEN the printed masks decode to exactly `cap_chown`, `cap_dac_override`, `cap_fowner`,
  `cap_setgid`, `cap_setuid` (the five-bit mask `0x00000000000000cb`)
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
`/var/log/engram.log` silently fails for uid 10000 — proposal §14 Q10 is the open item for
which observable path is chosen).

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
- NOTE: the restart backoff policy (unbounded restart vs a `finish` script) is proposal §14 Q3,
  owned by `sdd-design`; this scenario asserts recovery, not the delay distribution.

#### Scenario: engram's output is actually observable

- GIVEN the stack is up
- WHEN the container log stream is read
- THEN it is non-empty and contains engram output **or**, if design chose a log file path
  (Q10), that path exists and is non-empty
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
- OPEN ITEM: the final value and its recorded rationale are proposal §14 Q1 (measure a running
  merged container under a build + LSP workload).

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

The merge accepts a single lifecycle and per-container capabilities (proposal §6.2 R3, R4).
SECURITY.md SHALL state the single-lifecycle behavior and SHALL record the **measured**
capability set of the uid-10000 OpenCode process (proposal §14 Q4). No explicit capability
dropping SHALL be added to the OpenCode process (frozen: D2).

#### Scenario: Container exit follows Hermes' main program

- GIVEN the stack is up and the unit's restart counter and start time have been captured
- WHEN the Hermes main program is terminated inside the container
- THEN the container goes down and comes back **as one unit** — the restart counter increases and
  the start time moves, so `opencode`/`engram` did not survive independently
- PROOF:
  1. before: `docker inspect --format '{{.RestartCount}} {{.State.StartedAt}}' robotina`
  2. terminate: `docker compose exec robotina sh -c 'pkill -f "[h]ermes gateway"'`
  3. after: `docker inspect --format '{{.RestartCount}} {{.State.StartedAt}}' robotina` —
     `RestartCount` MUST be greater than in step 1 and `StartedAt` MUST have moved
- NOTE: `restart: unless-stopped` brings PID 1 back within a fraction of a second, so "the
  container is not running" cannot be observed and MUST NOT be the assertion. The unit-restart
  observation proves the same property — one unit went down and came back — without racing the
  restart policy. The narrow `--format` keeps the secret-safety rule (`docker inspect` never
  prints `.Config.Env`).
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
