# opencode-endpoint Specification

## Purpose

Define the observable properties of the OpenCode HTTP server after the merge: it listens on
loopback inside `robotina` and is reachable from **nothing else** — not the host, not any
other container, not `egress-proxy`. Operator access becomes an in-container activity, and
the password variable's rationale is rewritten accordingly.

This domain is **new**: `openspec/specs/` was empty before this change, so this file is a
full domain spec and is copied verbatim into `openspec/specs/opencode-endpoint/spec.md` at
archive time.

Artifact language: English (proposal §16).

## Verification model

There is no test runner in this repository (`openspec/config.yaml` → `testing.runner: none`).
Every scenario names the exact shell-level observation that proves it.

- Static recipes MUST use `docker compose config -q`; the bare form prints resolved `.env`
  secrets (proposal §9 risk 8) and is forbidden.
- **No vacuous passes.** Probes built on `pgrep`/`grep` MUST assert they matched something;
  empty output is a FAILURE. `pgrep`/`pkill` patterns MUST use a character-class form
  (`[o]pencode serve`) so the probe shell's own command line cannot match itself, and a recipe
  that substitutes a single pid MUST take `head -1` and assert the pid is non-empty and is not
  `$$`.
- **Credential-awareness.** `OPENCODE_SERVER_PASSWORD` is kept (design §10.3), so every
  in-container health probe uses the positional-parameter form below, which survives any
  password character and never echoes the value:

  ```sh
  set --
  [ -n "$OPENCODE_SERVER_PASSWORD" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"
  curl -fsS "$@" http://127.0.0.1:4096/global/health
  ```
- A negative reachability result MUST be distinguished from a false positive: a refusal has
  to be a connect-level refusal, not a name-resolution failure and not a missing client tool.
  Each negative scenario therefore carries its own control step.
- `docker run --rm --network agents …` is the peer-probe recipe sanctioned by proposal §5.B3.

## Requirements

### Requirement: EP1 — The server listens on loopback `127.0.0.1:4096` only

`opencode serve` SHALL listen on `127.0.0.1:4096` inside `robotina` and SHALL NOT listen on
`0.0.0.0` or on any non-loopback address.

#### Scenario: The loopback health endpoint answers inside the container

- GIVEN the stack is up
- WHEN the health endpoint is requested over loopback from inside `robotina`
- THEN the request succeeds
- PROOF: `docker compose exec robotina sh -c 'set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 5 http://127.0.0.1:4096/global/health'`
- NOTE (apply obligation, design §19.4): record once whether `/global/health` is
  auth-protected — run the same probe with and without `-u` — and keep this recipe and EP4's
  loops correct for the observed case. The password is never echoed.

#### Scenario: The same port on the container's own network address refuses

- GIVEN the stack is up
- WHEN the health endpoint is requested from inside `robotina` at its own `agents`
  network address instead of loopback
- THEN the request fails (selecting any non-loopback interface is a necessary condition for
  listening on `0.0.0.0`)
- PROOF:
  `docker compose exec robotina sh -c 'ip=$(getent hosts robotina | awk "{print \$1}" | head -1); echo "addr=$ip"; set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; test -n "$ip" && curl -sS "$@" -m 5 "http://$ip:4096/global/health"'`
  (the `addr=` line MUST be non-empty and MUST NOT be `127.0.0.1`, otherwise the scenario
  FAILS as inconclusive; the curl MUST fail)
- NOTE: the probe is credential-aware so the failure measures **reachability**, not
  authentication, and `-f` is deliberately omitted here: a listening server answering `401`
  would still exit 0 and therefore register as a violation, which is the correct reading.

#### Scenario: The listener set, when the tooling exists, holds no wildcard bind

- GIVEN the stack is up and `ss` or `netstat` exists in the image
- WHEN the listening sockets are listed
- THEN `127.0.0.1:4096` is present and neither `0.0.0.0:4096` nor `[::]:4096` is
- PROOF: `docker compose exec robotina sh -c 'ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null'`
- NOTE: if neither tool exists, this scenario is skipped as inconclusive, never reported as passing.

### Requirement: EP2 — The server is unreachable from the host

No host-side path SHALL reach the OpenCode server: no published port, no host escape hatch
(frozen: proposal §17 answer 5).

#### Scenario: A host request to the loopback port fails

- GIVEN the stack is up
- WHEN a request to `127.0.0.1:4096` is issued from the host
- THEN the request fails
- PROOF: host-side `curl -m 5 -sS http://127.0.0.1:4096/global/health` (non-zero exit)

#### Scenario: The compose stack publishes nothing for the agent service

- GIVEN the stack is up
- WHEN published ports are listed
- THEN no host port mapping is reported for `robotina`
- PROOF: `docker compose ps --format 'table {{.Name}}\t{{.Ports}}'`

### Requirement: EP3 — The server is unreachable from every other container, including `egress-proxy`

No network peer SHALL reach the OpenCode server. In particular the previously documented
`egress-proxy` → opencode pivot path (proposal §6.1 I1) SHALL no longer exist.

#### Scenario: A throwaway peer container on the `agents` network is refused

- GIVEN the stack is up
- WHEN a throwaway container on the `agents` network probes `egress-proxy:3128`
  (control) and then `robotina:4096`
- THEN the control connection is established and the `robotina:4096` probe returns a
  connect-level refusal
- PROOF:
  `docker run --rm --network agents curlimages/curl -m 5 -sS -o /dev/null -w 'control=%{http_code}\n' http://egress-proxy:3128`
  (control: a non-zero HTTP code proves DNS + connectivity on that network) then
  `docker run --rm --network agents curlimages/curl -m 5 -sS http://robotina:4096/global/health`
  (must fail with a connection refusal and MUST NOT fail with a name-resolution error)

#### Scenario: `egress-proxy` itself cannot open the port

- GIVEN the stack is up and `egress-proxy` has a shell that supports `/dev/tcp`
- WHEN the proxy container opens a TCP connection to `robotina:4096`
- THEN the connection is refused
- PROOF:
  `docker compose exec egress-proxy bash -c 'echo bash-ok'` (control: the shell exists) then
  `docker compose exec egress-proxy bash -c 'exec 3<>/dev/tcp/robotina/4096'` (non-zero exit;
  the control step exists so a missing `bash` cannot masquerade as a refusal)

#### Scenario: The name resolves while the port is refused

- GIVEN the stack is up
- WHEN `robotina` is resolved from inside the agent container and the same name is probed
  from a peer container on the `agents` network
- THEN resolution succeeds on both sides while the peer's port probe is refused, so the
  refusal cannot be attributed to DNS
- PROOF: `docker compose exec robotina sh -c 'getent hosts robotina'` (non-empty) combined with
  the peer refusal probe above

### Requirement: EP4 — The server is ready before Hermes' first delegation

The OpenCode server SHALL be ready before Hermes' first delegation can reach it. A supervised
"s6 service started" state SHALL NOT be treated as evidence that the port is listening.

#### Scenario: An immediate post-start probe succeeds with bounded retry

- GIVEN the stack was just started with `docker compose up -d` and no manual wait
- WHEN the in-container health probe runs with a bounded retry
- THEN it succeeds without restarting any service by hand
- PROOF:
  `docker compose up -d && docker compose exec robotina sh -c 'i=0; while [ $i -lt 60 ]; do set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 2 http://127.0.0.1:4096/global/health >/dev/null && exit 0; i=$((i+1)); sleep 2; done; exit 1'`
- NOTE: credential-aware, per EP1's apply obligation; the password is never echoed.

#### Scenario: The readiness holds across repeated recreations

- GIVEN the migrated stack
- WHEN three consecutive `down`/`up` cycles are each followed immediately by the bounded probe
- THEN every cycle succeeds (a single success would not rule out a lucky race)
- PROOF:
  `for i in 1 2 3; do docker compose down && docker compose up -d && docker compose exec robotina sh -c 'j=0; while [ $j -lt 60 ]; do set --; [ -n "${OPENCODE_SERVER_PASSWORD:-}" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"; curl -fsS "$@" -m 2 http://127.0.0.1:4096/global/health >/dev/null && exit 0; j=$((j+1)); sleep 2; done; exit 1' || exit 1; done`

#### Scenario: No startup refusal reaches the container log

- GIVEN a fresh start
- WHEN the container log is searched for connection failures against the endpoint
- THEN no `Connection refused`/`ECONNREFUSED` entry for `127.0.0.1:4096` is present
- PROOF: `docker compose logs --since 10m robotina 2>&1 | grep -Ei '127\.0\.0\.1:4096.*(refused|econnrefused)'`
  (no output, exit non-zero)
- OPEN ITEM: the mechanism that provides readiness (`s6-notifyoncheck` against
  `GET /global/health`, `notification-fd`, or a bounded wait in `opencode-init`) is proposal
  §14 Q2, owned by `sdd-design`. This requirement constrains the outcome only.

### Requirement: EP5 — The server process runs as uid 10000

The OpenCode server process SHALL run as the application uid `10000` (gid `10000`), never as
root.

#### Scenario: The server process reports the application uid

- GIVEN the stack is up
- WHEN the server process's credentials are read
- THEN the real/effective uid and gid are `10000`
- PROOF: `docker compose exec robotina sh -c 'p=$(pgrep -f "[o]pencode serve" | head -1); test -n "$p" && test "$p" != "$$" && grep -E "^(Uid|Gid)" /proc/$p/status'`
  (expected `Uid: 10000 10000 10000 10000`; an empty match is a FAILURE, and the character-class
  pattern plus the `head -1`/`$$` assertions keep the probe from reading its own shell)

#### Scenario: No OpenCode process runs as root

- GIVEN the stack is up
- WHEN every matching OpenCode server process is enumerated
- THEN none of them reports uid 0
- PROOF: `docker compose exec robotina sh -c 'for p in $(pgrep -f "[o]pencode serve"); do echo "$p $(awk "/^Uid/{print \$2}" /proc/$p/status)"; done'`
  (non-empty output is required — an empty loop is a FAILURE — and no line may end in `0`)

### Requirement: EP6 — `OPENCODE_SERVER_PASSWORD` semantics are re-documented

After the merge, `OPENCODE_SERVER_PASSWORD` SHALL be documented as defense-in-depth only,
because no network peer can reach the port. The documentation SHALL NOT retain the retired
rationale ("a peer on the `agents` network could drive the server without a password").
Whether the variable is kept or removed SHALL NOT be decided here (proposal §14 Q5, owned by
`sdd-spec`/`sdd-design`); the requirement constrains the documented semantics either way.

#### Scenario: The password is still documented where it is used

- GIVEN the merged change
- WHEN the docs and the export helper are searched for the variable
- THEN the variable's post-merge semantics are documented
- PROOF: `grep -n OPENCODE_SERVER_PASSWORD SECURITY.md README.md README.en.md scripts/export-state.sh`
  (non-empty)

#### Scenario: The retired rationale is gone

- GIVEN the merged change
- WHEN the docs are searched for the old justification
- THEN no text claims a network peer can reach or drive the server
- PROOF: `grep -rniE "solo lo alcanza quien este en la red|puede manejar opencode|can drive opencode|reachable from the host|alcanzable desde el host" README.md README.en.md SECURITY.md`
  (no output, exit non-zero)

### Requirement: EP7 — In-container operator recipes are documented in both READMEs

Because the server is loopback-only, the inspection and export recipes that replace human
access SHALL be documented in `README.md` and `README.en.md` (frozen: proposal §17 answer 5,
§13 item 6). No published port and no host escape hatch may be added as a substitute.

#### Scenario: Both READMEs document the in-container path

- GIVEN the merged change
- WHEN both READMEs are searched for the operator commands
- THEN each README contains at least one `docker compose exec robotina` recipe
- PROOF: `grep -c "docker compose exec robotina" README.md README.en.md` (both counts non-zero)

#### Scenario: The export helper is invoked through the merged container name

- GIVEN the merged change
- WHEN the docs and the helper are searched for the old invocation prefix
- THEN no `docker compose exec opencode` reference remains
- PROOF: `grep -rn "docker compose exec opencode" README.md README.en.md SECURITY.md scripts/ hermes/`
  (no output, exit non-zero)
