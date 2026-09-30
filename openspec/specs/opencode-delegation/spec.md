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

Issue #40 added the third: **a status map is not a fact about a turn, it is a fact about the
instance that was asked.** `GET /session/status` answers for the cwd given as `directory` (the
server's own cwd when the parameter is omitted), so a session created with `--directory` elsewhere
is absent from the unscoped answer *while it runs*, and reading that absence as a closure lost
healthy turns.

Issue #69 added the fourth: **the turn's time budget must fit a multi-phase task by default, and it
must be configurable.** Three delegated turns that combined a survey, an edit, a network step
(`uv sync`) and a git/GitHub push were aborted by the previous 900 s default.

Issue #73 added the fifth: **the named-block detector must probe the endpoint that actually carries
the fact, and clean up what it aborts.** Measured on 2026-09-29 against a live hanging request: the
endpoint the helper polled, `GET /api/session/{id}/permission` (v2), returned `{"data":[]}` on 6 of
6 polls over 60 s while `GET /permission` (v1) listed the request with its `sessionID`. So the
detector was a no-op and an `external_directory: ask` delegation burned the whole budget to exit
`4` instead of exiting `2` naming the block. The abort also left the request listed on the server;
a v1 reject clears it.

Issue #79 added the sixth: **a budget exhaustion must name the session and a retry path, because a
turn that ran out of time is not the same fact as a turn that stalled.** Measured on 2026-09-29: a
12-skill delegation was aborted at the global timeout **after** pushing its branch, and the helper
printed a single line with neither the session id nor the `--session` flag, so the caller had to
rediscover the pushed work by hand. The same measurement showed that `GET /session/{id}/diff`
returns `[]` even after the agent wrote a file, so the snapshot reads `git status` of the session
directory instead.

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

The CLI wrapper `/opt/robotina/bin/opencode` SHALL enforce that rule for the non-interactive path: it
SHALL refuse `opencode run` when no `--agent` is present, exiting `2` with a message that names
`--agent build`, so the raw default can never silently leave the work unexecuted. The interactive TUI,
`--help`, and every other subcommand SHALL pass unchanged, and `/usr/local/bin/opencode` remains the
escape hatch.

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

#### Scenario: The CLI wrapper refuses a `run` that does not name the executor

- GIVEN the change is applied
- WHEN the wrapped `opencode` CLI is invoked as `run "<task>"` with no `--agent` and no `--help`
- THEN it exits non-zero with a message naming `--agent build`, and submits nothing
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -s -- run "say hi" < robotina/bin/opencode`
  (must exit `2` and stderr must carry `nombra el ejecutor`) together with the non-vacuous controls
  `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -s -- run --help < robotina/bin/opencode`
  (must NOT print the refusal) and
  `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -s -- --version < robotina/bin/opencode`
  (must print a version, proving the wrapper still reaches the real binary)
- NOTE: the wrapper is baked into the image, so this uses the stale-image recipe of the verification
  model; after a rebuild and `--force-recreate` the same proof runs against
  `/opt/robotina/bin/opencode`. The guard exists because the merged default does not execute (see the
  rationale above).

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

#### Scenario: The default-decides path is refused instead of silently unexecuted

- GIVEN the stack is up and the merged `default_agent` is the coordinating agent
- WHEN the same delegation is repeated without `--agent`, so the merged `default_agent` would decide
- THEN the wrapper refuses it before any turn is submitted, naming `--agent build`
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -s -- run "Fix the bug in m.py so mul() multiplies. Do not change anything else." < robotina/bin/opencode`
  (must exit `2` and print the refusal on stderr with stdout empty; the guard refuses before `exec`, so
  no turn is submitted — a non-2 exit or a missing refusal is a FAILURE)
- NOTE: this is the non-vacuous control for OD1. Before this requirement the same invocation went to
  `gentle-orchestrator`, which never executes inline, and the file stayed unedited — a silent no-op.
  The mutation proof lives in the scenario above, which names `--agent build` explicitly. The wrapper
  is baked, so the stale-image recipe trumps the running copy until the maintenance window.

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

`opencode-delegate` SHALL use the server's own session status **of the instance that owns the
session** (`GET /session/status?directory=<path>`, with the path read back from the session itself,
`GET /session/{id}` → `.directory`) as its liveness signal, and SHALL NOT treat the absence of a
session from any status map as a closure unless that map was queried for the session's own
instance. When the scope cannot be resolved the status SHALL degrade to unknown, never to closed.
It SHALL NOT abort a turn whose tool call outlives any fixed poll threshold. The
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

#### Scenario: A session outside the server's cwd is not declared closed

- GIVEN a delegation with `--directory` pointing outside `/workspace`
- WHEN the turn runs a tool call and then answers
- THEN the helper exits `0` and prints the answer, even though the **unscoped** status map never
  listed that session at any point of the turn
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina /opt/robotina/bin/opencode-delegate --directory /tmp --timeout 120 "Run the shell command sleep 20 and then reply with exactly DONE"`
  (must exit `0` and print `DONE`; exit `3` with `finish=null` is the exact FAILURE this requirement
  exists to prevent)
- NOTE: measured before the fix, verbatim on the live stack: `VIEJO_EXIT=3` with
  `opencode-delegate: el turno cerro sin mensaje final (finish=null)`. Across 32 polls the unscoped
  `GET /session/status` answered `{}` every time — including while the session's `bash` tool part
  was `running` — while `GET /session/status?directory=%2Ftmp` answered `{"type":"busy"}` and
  flipped to `{}` exactly at `finish=stop`. With the fixed helper, on the same stack with the same
  task and directory: exit `0`, prints `DONE`, and stderr carries `scope: liveness acotada a /tmp`.

#### Scenario: The liveness query carries the session's own scope

- GIVEN the change is applied
- WHEN the helper's source is searched
- THEN the scoped status URL is present and a verdict is never taken from an unscoped one
- PROOF: `grep -c 'status_url="\$BASE/session/status?directory=' robotina/bin/opencode-delegate`
  (must be exactly `1`: the URL that is actually queried carries the scope) together with
  `grep -c '"$BASE/session/status"' robotina/bin/opencode-delegate` (must be 0)
- NOTE: the assertions name the **code**, not the prose. A comment that documents the scoped URL or
a discarded endpoint is not a violation; a call site is.

#### Scenario: Endpoints that cannot answer are not used

- GIVEN the same change
- WHEN the helper's source is searched
- THEN the two endpoints measured as dead ends are absent
- PROOF: `grep -c 'status?workspace=' robotina/bin/opencode-delegate` (must be 0) together with
  `grep -c '\$BASE/api/session/.*/wait' robotina/bin/opencode-delegate` (must be 0)
- NOTE: measured on OpenCode 1.18.32 — `GET /session/status?workspace=/tmp` returned HTTP `500`
  `UnknownError` on every call, and `POST /api/session/{id}/wait` returned HTTP `503`
  `{"_tag":"ServiceUnavailableError","message":"Session wait is not available yet"}` in 10–80 ms
  both while idle and while a turn was `busy`: it never blocks. Neither returns until a version
  proves otherwise.

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

### Requirement: OD8 — A named block is reported and cleaned instead of guessed

While the turn is alive, `opencode-delegate` SHALL probe the session's pending permission requests
via `GET /permission` (v1) filtered by `sessionID`, and SHALL NOT rely on
`GET /api/session/{id}/permission` (v2), which was measured returning `{"data":[]}` while the
request was pending. A non-empty result SHALL reject the pending request(s) with
`POST /permission/{id}/reply` and body `{"reply":"reject"}`, then abort the session and exit `2`,
naming the block on stderr. The probe and the cleanup SHALL be best-effort: an unavailable,
unparsable or failed response SHALL NOT fail the turn nor change the exit code. The same cleanup
SHALL run on the global-timeout path before it aborts, so the helper stops leaving requests listed
on the server.

Measured origin (2026-09-29, request pending on the live server, read with
`curl -u "opencode:$OPENCODE_SERVER_PASSWORD"`): `GET /api/session/{id}/permission` returned
`{"data":[]}` on 6 of 6 polls over 60 s, while `GET /permission` listed the request as
`{"id":"per_…","sessionID":"ses_…","permission":"external_directory","patterns":["/opt/data/cache/delegation/*"],…}`.
The consequence was a hang: a delegation created with `--directory /workspace` and told to read
`/opt/data/cache/delegation/subagent-summary-0-*.txt` ended on
`timeout global de 90s … (ultimo status: busy, alcance: /workspace)` with exit `4`. The abort does
not clear the request either: after two timed-out runs `GET /permission` still listed **two**
requests from dead sessions, and `POST /permission/{id}/reply` with `{"reply":"reject"}` cleared
them (`GET /permission` → `[]`).

#### Scenario: The helper probes the v1 endpoint, not the empty v2 one

- GIVEN the change is applied
- WHEN the helper's source is searched
- THEN the v1 pending-permission endpoint is called and no v2 call site remains
- PROOF: `grep -c '\$BASE/permission' robotina/bin/opencode-delegate` (must be ≥ 1) together with
  `grep -c 'api/session/\$SESSION/permission' robotina/bin/opencode-delegate || true` (must print `0`; a
  v2 call site is the defect this requirement removes — the `|| true` is there because `grep -c`
  exits `1` when it prints `0`, and a `set -e` wrapper around this line would abort on a passing
  assertion)
- NOTE: the assertions name the **code**, not the prose. A comment that documents the v2 dead end is
  not a violation; a call site is. `grep -c '/permission'` alone would be vacuous, because both the
  v1 and the v2 call sites match it.

#### Scenario: A pending permission aborts with exit 2 and names the block (conditional)

- GIVEN a delegation whose tool call reaches a permission rule set to `ask` in
  `robotina/overlay.json` (`bash: git commit *`) and no human to answer it
- WHEN the helper polls
- THEN it rejects the request, aborts the session, and exits `2`, with the pending permission on
  stderr
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina /opt/robotina/bin/opencode-delegate --timeout 120 "Run exactly this shell command: git commit --allow-empty -m probe. Then reply with exactly DONE"`
  (must exit `2` and print the pending permission on stderr)
- NOTE: this scenario needs the fixture to actually reach the `ask` rule. A model that rewrites the
  command (measured: one run emitted `rtk git commit --allow-empty -m probe`, which does not match
  the rule) leaves nothing pending and the run then ends on the global timeout. If no permission ask
  can be produced in the run, the scenario is skipped as **inconclusive**, never reported as
  passing.

#### Scenario: The detector fires instead of hanging

- GIVEN a fixture file that an agent's tool call can only reach through the `external_directory`
  `ask` rule, written under the agent's own cache root `/opt/data/cache/delegation/` (the path family
  measured to reach `ask`)
- WHEN the delegation is told to read it and no human answers
- THEN the helper exits `2` **well before** the budget, with the named-block sentence on stderr
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -c 'HOME=/opt/data; printf "linea\n" > /opt/data/cache/delegation/probe-permission-$$.txt; opencode-delegate --agent build --directory /workspace --timeout 120 "Read the file /opt/data/cache/delegation/probe-permission-$$.txt with the read tool and reply with its first line. If the read fails, reply exactly READ-FAILED."; rc=$?; rm -f /opt/data/cache/delegation/probe-permission-$$.txt; exit $rc'`
  (must exit `2`, with stderr carrying
  `el turno quedo bloqueado esperando una permission que ningun humano puede contestar`; an exit `4`,
  or any completion, is the exact FAILURE this requirement prevents)
- NOTE: the helper is baked into the image, so a run against a stale image exercises the old code.
  Until the rebuild + `--force-recreate`, exercise the checked-out file with the verification model's
  `sh -s` form, wrapping the fixture create/remove around it in the same in-container shell (the
  outer `sh -c` gets its script as an argument, so its stdin is free for the piped helper):
  `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -c 'HOME=/opt/data; printf "linea\n" > /opt/data/cache/delegation/probe-permission-$$.txt; sh -s -- --agent build --directory /workspace --timeout 120 "Read the file /opt/data/cache/delegation/probe-permission-$$.txt with the read tool and reply with its first line. If the read fails, reply exactly READ-FAILED."; rc=$?; rm -f /opt/data/cache/delegation/probe-permission-$$.txt; exit $rc' < robotina/bin/opencode-delegate`
  (must exit `2` with the same named-block sentence; an exit `4`, or any completion, is a FAILURE).

#### Scenario: No request is left dangling after the block

- GIVEN the detector fired, as in the proof above
- WHEN the server's pending-permission list is read
- THEN it lists nothing for that session
- PROOF: `docker compose exec -T robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/permission'`
  (must print `[]`; a listed request from the just-aborted session is a FAILURE)

#### Scenario: The probe is best-effort and never fails a healthy turn

- GIVEN a delegation whose turn never reaches a permission rule, so nothing is pending
- WHEN the helper polls the pending-permission endpoint
- THEN the turn closes normally and the helper exits `0`
- PROOF: the OD6 30 s delegation (exit `0`, prints `DONE`) — its turn reaches no `ask` rule, so the
  `GET /permission` probe returns no request for its session, yet the run still ends `0`
- NOTE: the same guard covers an unavailable endpoint. The probe captures the response with
  `2>/dev/null || true` and only acts on a successful `jq -e`, so a server without `/permission` (or
  an unparsable body) leaves the turn running to its normal close; a failed reject never changes the
  exit code either, on both the `2` and the `4` paths.

### Requirement: OD9 — `--directory` is opt-in and never derived from the caller's cwd

`opencode-delegate` SHALL create its session in the server's own cwd (`/workspace`) unless
`--directory PATH` is given, and SHALL send that path as the `directory` query parameter of
`POST /session`, percent-encoded. It SHALL NOT derive the session cwd from `$PWD`: Hermes runs with
cwd `/opt/data`, so a derived default would make `/workspace` an external directory and reintroduce
the `external_directory: ask` hang of the original incident.

The same directory — read back from the server (`GET /session/{id}` → `.directory`), not echoed from
the caller's argument — SHALL scope the liveness query of OD6, so that `--session` on a pre-existing
session is scoped correctly even when the caller passed no `--directory`.

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

### Requirement: OD10 — The exit code names which fact happened

`opencode-delegate` SHALL separate, by exit code, the facts a caller must be able to tell apart:

| Code | Meaning |
| --- | --- |
| `0` | the turn closed with `finish=stop`; stdout carries the answer |
| `1` | usage error, or a transport/parse failure |
| `2` | a named block (a pending permission nobody can answer): the helper aborts the turn |
| `3` | the turn ended without a successful final message — a turn error, a terminal `finish` other than `stop`, or a close with no final message |
| `4` | the global timeout: the helper aborts the turn |
| `5` | the turn was aborted by something that is **not** this helper (`MessageAbortedError`) |

`5` SHALL mean "someone else aborted the session": an abort the helper performs itself keeps its
own code (`2` for the named block, `4` for the timeout). Before this requirement an external abort
and a close with no final message were both `3`, so a caller could not tell "your turn ended badly"
from "your turn was killed".

Measured: an aborted assistant message has **no `finish` field at all** and carries
`info.error = {"name":"MessageAbortedError","data":{"message":"Aborted"}}`, while an in-progress
message carries `finish: null`. `finish` alone cannot separate those two facts; the error name is the
discriminator. `finish` is declared as a bare `string` in the OpenAPI schema — no enum — with an
observed domain of `{tool-calls, stop, null, absent}`.

#### Scenario: An external abort is reported as an abort, not as a turn error

- GIVEN a delegation whose session is aborted by someone else while its turn runs
- WHEN the helper polls
- THEN it exits `5` and names the abort on stderr
- PROOF: start a delegation with a 30 s tool call in the background, read its `session: ses_…` line
  from stderr, `POST /session/{SID}/abort` from inside the container, then assert the helper's exit
  code is `5`
- NOTE: measured — the background run exited `5`, and stderr carried
  `opencode-delegate: el turno fue abortado (MessageAbortedError) en la session ses_…; el abort no lo hizo este helper`

#### Scenario: The helper's own aborts keep their own codes

- GIVEN a named block (`2`) or a global timeout (`4`)
- WHEN the helper aborts the turn itself
- THEN the exit code is `2`/`4`, never `5`
- PROOF: the OD8 named-block proof, and a deliberately tiny `--timeout 3` against a turn that keeps
  running (must exit `4`)

#### Scenario: A clean close still reports 0

- PROOF: the OD6 30 s proof (exit `0`, prints `DONE`) and the OD6 `--directory` proof (exit `0`,
  prints `DONE`)

### Requirement: OD11 — The turn's time budget fits a multi-phase task by default and is configurable

`opencode-delegate` SHALL default its global turn budget to **1800 seconds** — measured (#69): three
multi-phase turns (survey + edit + network + git/GitHub) exceeded the previous 900 s default — SHALL
read that default from `ROBOTINA_OPENCODE_DELEGATE_TIMEOUT` when the variable is set, and SHALL let
`--timeout SEC` override both. It SHALL document `--timeout SEC` and `--interval SEC` in `--help`.
The budget is a ceiling, not a target: the requirement fixes the number and the knob, and the
splitting guidance lives in the skill.

#### Scenario: The default is 1800 s and comes from the environment

- PROOF: `grep -c 'ROBOTINA_OPENCODE_DELEGATE_TIMEOUT' robotina/bin/opencode-delegate` (must be ≥ 1)
  together with `grep -c ':-1800' robotina/bin/opencode-delegate` (must be ≥ 1) and
  `grep -c '^TIMEOUT=900' robotina/bin/opencode-delegate` (must be 0 — the old constant form is
  gone, so this cannot pass with the defect present)

#### Scenario: The two time flags are documented

- PROOF: `sh robotina/bin/opencode-delegate --help 2>&1 | grep -c 'presupuesto global del turno'`
  (must be ≥ 1) together with the same for the `--interval` entry (must be ≥ 1)
- NOTE: the `uso:` line already listed `<--timeout SEC>` before this change, so a plain grep for the
  flag name would be vacuous; the assertion names the **description** the requirement asks for.

#### Scenario: The environment value bounds the turn

- GIVEN the stack is up
- WHEN a delegation whose turn keeps running is issued with the environment value and no `--timeout`
- THEN the helper exits `4` and names that budget
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -c 'ROBOTINA_OPENCODE_DELEGATE_TIMEOUT=3 sh -s -- "Run the shell command sleep 40 and then reply with exactly DONE"' < robotina/bin/opencode-delegate`
  (must exit `4`; stderr must carry `timeout global de 3s`; a non-zero-but-not-4 exit, or a
  completion, is a FAILURE)
- NOTE: the helper is baked into the image, so this uses the stale-image recipe of the verification
  model; after a rebuild and `--force-recreate` the same proof runs against
  `/opt/robotina/bin/opencode-delegate`.

### Requirement: OD12 — A budget exhaustion names the session and a retry path

When `opencode-delegate` ends a turn because the global budget ran out (exit `4`), it SHALL print, on
stderr and without changing the exit code, (a) a retry template that re-issues work on that same
session (`--session SID`) carrying the effective agent, provider, model and timeout, (b) the fact that
the identical prompt is deduped (A3), so resuming means sending a **follow-up** task, and (c) a
bounded progress snapshot of what the turn had reached: the `git status` of the session's canonical
`directory`, the agent's own todo list when it has one, and a truncated last assistant text. It SHALL
emit a **one-shot** advisory when the elapsed time reaches 80% of the budget. The advisory is
time-gated, not exit-4-gated: a turn that crosses 80% and later closes with `finish=stop` keeps the
advisory on stderr and still exits `0`. stdout SHALL stay empty on exit `4`, and every snapshot read
SHALL be best-effort: an unreadable source MUST NOT change the exit code, the abort, or the
already-printed timeout line.

Measured origin (#79): a 12-skill delegation was aborted at the global timeout **after** pushing its
branch — a productive turn, not a stalled one — and the caller got a single line with no session id
and no `--session` hint, so the pushed work had to be rediscovered by hand. The same measurement
showed that the endpoint that looks like the natural source for "what did it change",
`GET /session/{id}/diff`, returns `[]` even after the agent writes a file, so the snapshot reads
`git status` of the session directory instead.

#### Scenario: The exit-4 message carries the session and a retry template

- GIVEN the stack is up and a delegation whose turn keeps running
- WHEN the global budget expires
- THEN the helper exits `4` and stderr carries the retry template with the session id and the
  follow-up operand
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -c 'ROBOTINA_OPENCODE_DELEGATE_TIMEOUT=3 sh -s -- "Run the shell command sleep 40 and then reply with exactly DONE"' < robotina/bin/opencode-delegate`
  (must exit `4`; stderr must carry `para retomar: opencode-delegate --session ses_`, a
  `"<seguimiento>"` operand, and the dedupe note; a missing hint or a non-4 exit is a FAILURE)

#### Scenario: The 80% advisory fires exactly once

- GIVEN the same budget-expiring delegation
- WHEN the elapsed time crosses 80% of the budget
- THEN stderr carries one advisory naming elapsed and total seconds
- PROOF: the run above, with its stderr captured to a file: `grep -c 'presupuesto al 80%'` (must be
  exactly `1`; `0` is a FAILURE and a count `> 1` proves the advisory is not one-shot)

#### Scenario: The snapshot reports the session tree, and stdout stays clean

- GIVEN a throwaway git repository with a modified tracked file, used as the session directory
- WHEN the budget expires
- THEN stderr lists the `git status` entries and stdout is empty
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -c 'd=$(mktemp -d /tmp/od12.XXXXXX); cd "$d"; git init -q; git config user.email od12@robotina.local; git config user.name od12; printf "a\n" > f.txt; git add f.txt; git commit -qm init; printf "a\nb\n" > f.txt; ROBOTINA_OPENCODE_DELEGATE_TIMEOUT=3 sh -s -- --directory "$d" "Run the shell command sleep 40 and then reply with exactly DONE"; rc=$?; rm -rf "$d"; exit $rc' < robotina/bin/opencode-delegate`
  (must exit `4`; stderr must carry `git (` and ` M f.txt`; stdout must be 0 bytes; a non-empty
  stdout is a FAILURE)
- NOTE: this scenario needs no model edit to be non-vacuous (the dirty file exists before the
  delegation) and leaves nothing behind: the repository is `mktemp -d` and removed before the outer
  shell exits, preserving the helper's exit code.

#### Scenario: A turn that closes before 80% prints neither the advisory nor the snapshot

- GIVEN a delegation that closes well inside its budget
- WHEN the helper exits `0`
- THEN stderr carries neither the advisory nor the snapshot block, and stdout is exactly the answer
- PROOF: `MSYS_NO_PATHCONV=1 docker compose exec -T -u hermes robotina sh -c 'sh -s -- --timeout 180 "Reply with exactly OK"' < robotina/bin/opencode-delegate`
  (must exit `0`; stdout must be exactly `OK`; stderr MUST NOT match `presupuesto al 80%` or
  `snapshot del progreso`)
- NOTE: the advisory is time-gated, so this control is non-vacuous only while the turn closes before
  80% of its budget — a turn that crosses 80% keeps the advisory on stderr even when it later closes
  with `finish=stop` and exits `0`. The snapshot block, by contrast, exists **only** on the exit-4
  path.

#### Scenario: The snapshot degrades instead of failing

- GIVEN a session whose `directory` is not a git work tree
- WHEN the budget expires
- THEN the helper still exits `4` with the timeout line and the resume command, and omits only the
  `git` line
- PROOF: the exit-4 proof above run with no `--directory` (the server's own `/workspace` cwd, which
  is not a git work tree): stderr must still carry `para retomar: opencode-delegate --session ses_`
  and MUST NOT carry a `git (` line; a non-4 exit is a FAILURE
