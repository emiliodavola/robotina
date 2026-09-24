# opencode-delegation Specification

## Purpose

Define the observable properties of delegating a task to OpenCode from inside `robotina`: the
task must land on an **executor**, and a long turn must be driven through a **non-blocking**
path so a slow agent loop is never mistaken for a finished job. This domain exists because a
real delegation failed on both counts — the task landed on `gentle-orchestrator`, whose prompt
coordinates sub-agents and never executes inline, and Hermes held the blocking
`POST /session/{id}/message` open until its own transport timed out. This file is the durable
replacement for the stack-specific knowledge deleted in commit `6ec5fad`
(`hermes/skills/opencode-server/SKILL.md`).

Artifact language: English.

## Verification model

There is no test runner in this repository (`openspec/config.yaml` → `testing.runner: none`).
Every scenario names the exact shell-level observation that proves it.

- Static recipes MUST use `docker compose config -q`; the bare form prints resolved `.env`
  secrets and is forbidden.
- **No vacuous passes.** Probes built on `pgrep`/`grep` MUST assert they matched something;
  empty output is a FAILURE. `pgrep` patterns MUST use a character-class form
  (`[o]pencode serve`) so the probe shell's own command line cannot match itself.
- **Credential-awareness.** `OPENCODE_SERVER_PASSWORD` is kept, so every in-container HTTP
  probe uses the positional-parameter form below, which survives any password character and
  never echoes the value:

  ```sh
  set --
  [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"
  curl -fsS "$@" -m 5 http://127.0.0.1:4096/global/health
  ```

- `GET /config/providers` serializes provider credentials in plain text (`SECURITY.md`): read
  it in place and never dump its body into a log, transcript or issue.
- The merged config `/opt/data/.config/opencode/opencode.json` is produced by the image's
  `opencode-init` oneshot; a value from the source overlay does not reach it until the image is
  rebuilt and the container force-recreated.
- **Delegation probes run as the `hermes` user** (`docker compose exec -T -u hermes robotina …`).
  That is the agent's own environment and it is what makes `HOME=/opt/data`, so the merged stack
  config is the one OpenCode loads. Run as `root`, `HOME` is `/root`, OpenCode bootstraps a
  config-less state there, and a delegation fails with a bare
  `{"name":"UnknownError",…,"ref":"err_…"}`. HTTP probes do not need this; they talk to the
  already-running supervised server.

## Requirements

### Requirement: OD1 — The merged configuration selects an executing agent as `default_agent`

The merged `/opt/data/.config/opencode/opencode.json` SHALL set `default_agent` to an agent
that executes (`build`), and SHALL NOT leave it on the coordinating agent
(`gentle-orchestrator`).

#### Scenario: The merged configuration names the executor

- GIVEN the stack is up and the image has been rebuilt and the container force-recreated
- WHEN the merged config's `default_agent` is read inside the container
- THEN it prints `build` and does not print `gentle-orchestrator`
- PROOF: `docker compose exec -T robotina python3 -c "import json;print(json.load(open('/opt/data/.config/opencode/opencode.json')).get('default_agent'))"`
  (output MUST be exactly `build`; empty output or `gentle-orchestrator` is a FAILURE)

#### Scenario: The repo overlay is the source of that key

- GIVEN the change is applied
- WHEN the source overlay is searched for the key
- THEN the `"default_agent": "build"` line is present
- PROOF: `grep -n '"default_agent": "build"' robotina/overlay.json` (non-empty; an empty match is a FAILURE)

### Requirement: OD2 — `gentle-orchestrator` stays reachable and still declares it does not execute

`gentle-orchestrator` SHALL remain exposed by the server, and its description SHALL still
declare that it coordinates rather than executes, so the reason not to delegate a task to it
stays observable.

#### Scenario: The orchestrator is still exposed

- GIVEN the stack is up
- WHEN the agent list is requested from inside the container
- THEN it contains `gentle-orchestrator`
- PROOF: `docker compose exec -T robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/agent' | grep -c '"gentle-orchestrator"'`
  (must be ≥ 1; 0 is a FAILURE)

#### Scenario: Its description still says it does not execute inline

- GIVEN the stack is up
- WHEN the orchestrator's description is read from the same response
- THEN it still declares that it does not do work inline
- PROOF: `docker compose exec -T robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/agent' | grep -c 'never does work inline'`
  (must be ≥ 1; 0 is a FAILURE)

### Requirement: OD3 — A delegated CLI task actually mutates a file

A bounded task delegated with `opencode run` SHALL change the file it was asked to change, and
the post-condition SHALL be the file's contents — never the model's own claim of success. The
delegation MUST run as the `hermes` user (see the verification model): that is what makes
`HOME=/opt/data` and therefore the merged stack config the one OpenCode loads.

#### Scenario: The CLI edits a throwaway repository

- GIVEN the stack is up
- WHEN a task is delegated with `opencode run --agent build -m opencode-go/deepseek-v4-flash`
  against a throwaway git repository under `/tmp`
- THEN the corrected line is present in the file
- PROOF: `docker compose exec -T -u hermes robotina sh -c 'set -e; d=$(mktemp -d /tmp/od3.XXXXXX); cd "$d"; git init -q; git config user.email od3@robotina.local; git config user.name od3; printf "def add(a, b):\n    return a - b\n" > calc.py; git add calc.py; git commit -qm init; opencode run --agent build -m opencode-go/deepseek-v4-flash "Fix the bug in calc.py so add() adds. Do not change anything else." >run.log 2>&1; grep -n "return a + b" calc.py'`
  (must print the corrected line; empty output or a non-zero exit is a FAILURE)
- NOTE: the run's own message is captured in `run.log` inside the throwaway directory for the
  operator and is NOT the assertion — the file is. The log goes there and not to `/tmp`: a
  `/tmp` path created by an earlier root-run probe is root-owned, and the next `hermes`-user run
  then fails on the redirect instead of on the delegation.

#### Scenario: The default agent executes with no explicit `--agent`

- GIVEN the stack is up
- WHEN the same delegation is repeated without `--agent`, so the merged `default_agent` decides
- THEN the file is still mutated, which a coordinating agent that never executes could not do
- PROOF: `docker compose exec -T -u hermes robotina sh -c 'set -e; d=$(mktemp -d /tmp/od3def.XXXXXX); cd "$d"; git init -q; git config user.email od3@robotina.local; git config user.name od3; printf "def mul(a, b):\n    return a + b\n" > m.py; git add m.py; git commit -qm init; opencode run -m opencode-go/deepseek-v4-flash "Fix the bug in m.py so mul() multiplies. Do not change anything else." >run.log 2>&1; grep -n "return a \* b" m.py'`
  (must print the corrected line; this is the end-to-end proof that OD1's config key has the
  intended effect, because with `gentle-orchestrator` as the default the file is not edited)

#### Scenario: The assertion is not vacuous

- GIVEN the same starting content used by the scenarios above
- WHEN the corrected-content patterns are matched against the unfixed content
- THEN neither matches, so a match on the fixed file is real
- PROOF: `docker compose exec -T robotina sh -c 'printf "def add(a, b):\n    return a - b\n" > /tmp/od3-orig.py; if grep -q "return a + b" /tmp/od3-orig.py; then echo "FAIL: control matched"; exit 1; else echo "control: unfixed content does not match"; fi'`
  (must print the control line; `FAIL` or a non-zero exit is a FAILURE)

### Requirement: OD4 — The provider catalogue is read, never guessed

A delegation SHALL choose its `modelID` from `GET /config/providers`, and the provider that
resolves credentials in this container SHALL be `opencode-go`.

#### Scenario: `opencode-go` is present in the catalogue

- GIVEN the stack is up
- WHEN the provider catalogue is requested from inside the container
- THEN `opencode-go` appears in it
- PROOF: `docker compose exec -T robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/config/providers' | grep -c '"opencode-go"'`
  (must be ≥ 1; 0 is a FAILURE)

#### Scenario: The chosen model appears in the same response

- GIVEN the stack is up
- WHEN the same response is searched for a `modelID` chosen from it
- THEN the chosen model is present
- PROOF: `docker compose exec -T robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/config/providers' | grep -c '"deepseek-v4.1-flash"'`
  (must be ≥ 1; 0 is a FAILURE)
- NOTE: the `modelID` MUST be taken from this response, never from memory. The response body
  serializes provider keys, so grep it in place and never paste it into a log or transcript.

### Requirement: OD5 — Exactly one supervised `opencode serve` runs, and no second server exists

Exactly one `opencode serve` process SHALL run, it SHALL be the s6-supervised service, and no
listener SHALL exist on any other port (in particular `4097`).

#### Scenario: Exactly one server process matches

- GIVEN the stack is up
- WHEN the server processes are counted
- THEN exactly one matches
- PROOF: `docker compose exec -T robotina sh -c 'pgrep -fc "[o]pencode serve"'`
  (must print `1`; empty output or any other count is a FAILURE)

#### Scenario: The matched process is the supervised service

- GIVEN the stack is up
- WHEN the s6 service state is read
- THEN the `opencode` service is up
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T robotina /command/s6-svstat /run/service/opencode`
  (non-empty and reporting `up`; an empty match or an error is a FAILURE. `s6-svstat` is not on
  `PATH`, and Git Bash rewrites an absolute argument without `MSYS_NO_PATHCONV=1`)

#### Scenario: No listener exists on port 4097

- GIVEN the stack is up and `ss` or `netstat` exists in the image
- WHEN the listening sockets are listed
- THEN `4096` is present and `4097` is absent
- PROOF: `docker compose exec -T robotina sh -c 'ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null' | grep -c ':4097'`
  (must be 0) together with the same listing's `grep -c ':4096'` (must be ≥ 1, the control that
  proves the listing is real). If neither tool exists, the scenario is skipped as
  inconclusive, never reported as passing.
