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

Issue #38 added a second measured lesson to the same domain: a turn's liveness cannot be inferred
from its token counters (OpenCode fills them only when a step closes, so an in-progress step reads
`0/0/0/0/0` while it works), and the delegation path must pin the executor itself, because the
merged `default_agent` is the coordinating agent on purpose.

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
- **The helper is baked into the image.** `robotina/Dockerfile` copies `robotina/bin/`, and
  `/opt/robotina/bin/opencode-delegate` is not a bind mount, so a proof that invokes it inside the
  container exercises the image's copy, not the working tree. Any change to the helper needs a
  rebuild **and** `--force-recreate` before its scenarios can pass; until then the checked-out file
  is exercised equivalently with
  `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -s -- <args> < robotina/bin/opencode-delegate`.
  Reporting the literal command as a pass against a stale image is a vacuous pass and is forbidden;
  the md5 of the container copy against `git show HEAD:robotina/bin/opencode-delegate` and against
  the working-tree file proves which code ran.

## Requirements

### Requirement: OD1 — Every delegation path names the executor explicitly

`robotina/overlay.json` MAY pin `default_agent` to the coordinating agent
(`gentle-orchestrator`) so the interactive TUI opens there, and the merged configuration SHALL
expose a non-empty `default_agent`. Because that default does not have to execute, **every
delegation path that must get work done SHALL name the executor explicitly**: the CLI with
`--agent build`, and `opencode-delegate` with `agent` in its `prompt_async` body (its `--agent`
flag, default `build`). A delegated turn SHALL therefore run on `build` even when the merged
`default_agent` is `gentle-orchestrator`.

Rationale, measured: the helper sent `{model, parts}` only, both sessions of issue #38 ran with
`info.agent = "gentle-orchestrator"`, and `gentle-orchestrator` coordinates sub-agents instead of
executing. Commit `3588eef` pins the orchestrator as the config default on purpose, so the
invariant lives in the delegation path and not in the config default.

#### Scenario: The merged configuration exposes a non-empty default agent

- GIVEN the stack is up and the image has been rebuilt and the container force-recreated
- WHEN the merged config's `default_agent` is read inside the container
- THEN it prints a non-empty value (today `gentle-orchestrator`)
- PROOF: `docker compose exec -T robotina python3 -c "import json;print(json.load(open('/opt/data/.config/opencode/opencode.json')).get('default_agent'))"`
  (empty output is a FAILURE; the value itself is configuration and MUST NOT be asserted)

#### Scenario: The repo overlay is the source of that key

- GIVEN the change is applied
- WHEN the source overlay is searched for the key
- THEN a `"default_agent"` line is present
- PROOF: `grep -n '"default_agent"' robotina/overlay.json` (non-empty; an empty match is a FAILURE)

#### Scenario: The helper sends the agent in the request body

- GIVEN the change is applied
- WHEN the helper's submit body is searched
- THEN the body carries the agent field
- PROOF: `grep -c 'agent:$a' robotina/bin/opencode-delegate` (must be ≥ 1; 0 is a FAILURE)

#### Scenario: A delegated turn lands on the executor, not on the merged default

- GIVEN the stack is up and the merged `default_agent` is the coordinating agent
- WHEN a delegation is made through `opencode-delegate` and its session messages are read
- THEN the last assistant message reports `agent == "build"`
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina /opt/robotina/bin/opencode-delegate --timeout 180 "Reply with exactly OK"`
  (capture the `session: ses_…` line it prints to stderr), then
  `MSYS_NO_PATHCONV=1 docker compose exec -T robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 10 "http://127.0.0.1:4096/session/<SID>/message" | jq -r "[.[] | select(.info.role==\"assistant\")] | last | .info.agent"'`
  (must print `build`; `gentle-orchestrator` or empty is a FAILURE. It is non-vacuous only while
  the merged default is the orchestrator, which is the case this requirement exists for)
- NOTE: the helper in the running container comes from the image, so this scenario needs the
  rebuild + force-recreate described in the verification model; before that, exercise the
  checked-out file with the equivalent `sh -s -- <args> < robotina/bin/opencode-delegate` form.

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

### Requirement: OD6 — A long tool call does not abort a healthy turn

`opencode-delegate` SHALL use the server's own session status (`GET /session/status`) as its
liveness signal and SHALL NOT abort a turn whose tool call outlives any fixed poll threshold. The
removed rule (`info.tokens` frozen for `STALL_POLLS` polls) SHALL NOT return: OpenCode fills those
counters only when a step closes, so during an in-progress step the signature is identically
`0/0/0/0/0` no matter what the turn does — measured: a healthy `sleep 25` froze it for 28 s while a
`glob` completed inside the same message.

#### Scenario: A 30 s tool call finishes

- GIVEN the stack is up
- WHEN a delegation asks for a 30 s tool call
- THEN the helper exits 0 and prints the answer
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina /opt/robotina/bin/opencode-delegate --timeout 180 "Run the shell command sleep 30 and then reply with exactly DONE"`
  (must exit `0` and print `DONE`; exit `2` or `4` is a FAILURE)

#### Scenario: The token-signature rule is gone and the status endpoint is used

- GIVEN the change is applied
- WHEN the helper's source is searched
- THEN the old signature function is absent and the status endpoint is present
- PROOF: `grep -c 'assistant_signature' robotina/bin/opencode-delegate` (must be 0) together with
  `grep -c 'session/status' robotina/bin/opencode-delegate` (must be ≥ 1)

#### Scenario: The non-vacuous control — the flag that used to trigger the abort is inert

- GIVEN the same 30 s tool call
- WHEN the delegation is repeated with `--stall-polls 6`, the exact threshold that aborted the
  healthy turn before this change
- THEN it still exits 0
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina /opt/robotina/bin/opencode-delegate --stall-polls 6 --timeout 180 "Run the shell command sleep 30 and then reply with exactly DONE"`
  (must exit `0` and print `DONE`; the deprecation warning on stderr is informational and is NOT
  the assertion)

### Requirement: OD7 — An intermediate `finish=tool-calls` is not a terminal closure

`opencode-delegate` SHALL NOT treat `info.finish == "tool-calls"` as the end of a turn. Measured:
`tool-calls` lands on every intermediate assistant message and the next assistant message is created
right after it, so reading that value as a closure aborts a turn that is still working.

#### Scenario: A two-step turn closes on `stop` and still exits 0

- GIVEN a delegation whose turn needs a tool call and then a final answer
- WHEN the helper finishes and its session messages are read
- THEN the helper exited 0, and the session's assistant messages go from `tool-calls` to `stop`
- PROOF: run the 30 s tool-call delegation of OD6, capture the `session: ses_…` line from stderr,
  then
  `MSYS_NO_PATHCONV=1 docker compose exec -T robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 10 "http://127.0.0.1:4096/session/<SID>/message" | jq -c "[.[] | select(.info.role==\"assistant\") | .info.finish]"'`
  (must print a list whose first element is `"tool-calls"` and whose last element is `"stop"`,
  while the delegation itself exited `0`)

### Requirement: OD8 — A named block is reported instead of guessed

While the turn is alive, `opencode-delegate` SHALL probe the session's pending permission requests
(`GET /api/session/{id}/permission`); a non-empty result SHALL abort the session and exit `2`,
naming the block on stderr. The probe SHALL be best-effort: an unavailable or unparsable response
SHALL NOT fail the turn.

#### Scenario: The helper probes the pending-permission endpoint

- GIVEN the change is applied
- WHEN the helper's source is searched
- THEN the pending-permission endpoint is present
- PROOF: `grep -c '/permission' robotina/bin/opencode-delegate` (must be ≥ 1; 0 is a FAILURE)

#### Scenario: A pending permission aborts with exit 2 and names the block (conditional)

- GIVEN a delegation whose tool call reaches a permission rule set to `ask` in
  `robotina/overlay.json` (`bash: git commit *`) and no human to answer it
- WHEN the helper polls
- THEN it aborts the session and exits `2`, with the pending permission on stderr
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina /opt/robotina/bin/opencode-delegate --timeout 120 "Run exactly this shell command: git commit --allow-empty -m probe. Then reply with exactly DONE"`
  (must exit `2` and print the pending permission on stderr)
- NOTE: this scenario needs the fixture to actually reach the `ask` rule. A model that rewrites the
  command (measured: one run emitted `rtk git commit --allow-empty -m probe`, which does not match
  the rule) leaves nothing pending and the run then ends on the global timeout. If no permission ask
  can be produced in the run, the scenario is skipped as **inconclusive**, never reported as
  passing.

### Requirement: OD9 — `--directory` is opt-in and never derived from the caller's cwd

`opencode-delegate` SHALL create its session in the server's own cwd (`/workspace`) unless
`--directory PATH` is given, and SHALL send that path as the `directory` query parameter of
`POST /session`, percent-encoded. It SHALL NOT derive the session cwd from `$PWD`: Hermes runs with
cwd `/opt/data`, so a derived default would make `/workspace` an external directory and reintroduce
the `external_directory: ask` hang of the original incident.

#### Scenario: Without the flag the session uses the server's cwd

- GIVEN a delegation made with no `--directory`
- WHEN the created session is read
- THEN its `directory` is `/workspace`
- PROOF: run any delegation, capture the `session: ses_…` line, then
  `MSYS_NO_PATHCONV=1 docker compose exec -T robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 10 "http://127.0.0.1:4096/session/<SID>" | jq -r .directory'`
  (must print `/workspace`)

#### Scenario: The caller's cwd does not leak into the session

- GIVEN a delegation invoked from a different cwd (`/tmp`) with no `--directory`
- WHEN the created session is read
- THEN its `directory` is still `/workspace`
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -c 'cd /tmp && /opt/robotina/bin/opencode-delegate --timeout 180 "Reply with exactly OK"'`
  (capture the session id, then read `.directory` as above; anything other than `/workspace` is a
  FAILURE)

#### Scenario: `--directory` opts into another root

- GIVEN a delegation with `--directory /tmp`
- WHEN the created session is read
- THEN its `directory` is `/tmp`
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina /opt/robotina/bin/opencode-delegate --directory /tmp --timeout 180 "Reply with exactly OK"`
  (capture the session id, then read `.directory` as above; must print `/tmp`)
