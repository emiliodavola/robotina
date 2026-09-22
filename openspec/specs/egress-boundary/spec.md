# egress-boundary Specification

## Purpose

Restate the frozen invariants INV1–INV5 (proposal §5.D) as regression guards for the merged
stack, so the single-container merge cannot quietly weaken the egress boundary that
`egress-proxy` exists to enforce. Nothing in this domain is modified by the change: these are
assertions that MUST keep holding.

This domain is **new**: `openspec/specs/` was empty before this change, so this file is a
full domain spec and is copied verbatim into `openspec/specs/egress-boundary/spec.md` at
archive time.

Artifact language: English (proposal §16). `SECURITY.md` and `README.md` stay Spanish,
`README.en.md` English.

## Verification model

There is no test runner in this repository (`openspec/config.yaml` → `testing.runner: none`).
Every scenario names the exact shell-level observation that proves it.

- Static recipes MUST use `docker compose config -q`; the bare form prints resolved `.env`
  secrets (proposal §9 risk 8) and is forbidden.
- **No vacuous passes**: a probe whose pipeline can succeed on empty output MUST assert
  non-empty output.
- A "denied" egress result MUST be distinguished from a DNS or proxy-configuration artifact:
  the control for every denial is a request that succeeds under the same conditions.

## Requirements

### Requirement: EG1 — INV1: no published port, no Docker socket, secrets only from `.env`

No service SHALL publish a port. No Docker socket SHALL be mounted. Secrets SHALL come only
from the gitignored `.env`.

#### Scenario: Nothing is published

- GIVEN the stack is up
- WHEN the published ports are listed
- THEN neither container reports a host port mapping
- PROOF: `docker compose ps --format 'table {{.Name}}\t{{.Ports}}'`

#### Scenario: No `ports:` key exists in the compose file

- GIVEN the merged compose file
- WHEN the source is searched for a port mapping
- THEN nothing is found
- PROOF: `git grep -nE '^[[:space:]]+ports:' -- compose.yml` (no output, exit non-zero)

#### Scenario: No Docker socket is mounted

- GIVEN the merged compose file
- WHEN the source is searched for the Docker socket
- THEN nothing is found
- PROOF: `git grep -n "docker.sock" -- compose.yml` (no output, exit non-zero)

#### Scenario: `.env` is the only secret source and it is gitignored

- GIVEN the repository
- WHEN the ignore status of `.env` is queried and tracked files are listed
- THEN `.env` is ignored and is not tracked
- PROOF: `git check-ignore -v .env` (non-empty) and `git ls-files .env` (no output, exit non-zero)

#### Scenario: No tracked file carries a real secret value

- GIVEN the change set
- WHEN tracked files are searched for populated secret assignments
- THEN nothing is found
- PROOF: `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'`
  (no output, exit non-zero)

### Requirement: EG2 — INV2: `robotina` has no direct Internet route; all egress goes through `egress-proxy`

`robotina` SHALL have no direct Internet route. Every outbound connection SHALL traverse
`egress-proxy`, which admits only the allowlist in `squid/allowlist.txt`.

#### Scenario: A direct connection that bypasses the proxy fails

- GIVEN the stack is up
- WHEN a request is issued from inside `robotina` with the proxy explicitly disabled
- THEN the request fails (this is the decisive "no direct route" observation; the proxied
  variant below would also fail if the proxy denied the domain, which is a different fact)
- PROOF: `docker compose exec robotina sh -c 'curl -m 5 -sS --noproxy "*" -o /dev/null https://example.com'`
  (non-zero exit)

#### Scenario: The container has no default route

- GIVEN the stack is up
- WHEN the container's routing table is read
- THEN no default route (`0.0.0.0`) is present
- PROOF: `docker compose exec robotina sh -c 'awk "NR>1 && \$2==\"00000000\" {print}" /proc/net/route'`
  (no output, exit non-zero)

#### Scenario: The proxy is reachable from inside the container

- GIVEN the stack is up
- WHEN the proxy port is probed without asserting an HTTP status
- THEN the TCP connection is established (a code is returned rather than a connection failure)
- PROOF: `docker compose exec robotina sh -c 'curl -m 5 -sS -o /dev/null -w "%{http_code}\n" http://egress-proxy:3128'`
  (a numeric code is printed; empty output or a connection error FAILS)

#### Scenario: A non-allowlisted destination is denied through the proxy

- GIVEN the stack is up
- WHEN a domain outside the allowlist is requested through the proxy
- THEN the request fails
- PROOF: `docker compose exec robotina sh -c 'curl -m 5 -sS -o /dev/null https://example.com'`
  (non-zero exit)

#### Scenario: An allowlisted destination succeeds through the proxy

- GIVEN the stack is up and `.github.com` is present in `squid/allowlist.txt`
- WHEN an allowlisted destination is requested from inside `robotina`
- THEN the request succeeds
- PROOF: `docker compose exec robotina sh -c 'curl -m 10 -sS -o /dev/null https://github.com'`
  (exit 0 — control proving the denial above is an allowlist decision, not a broken network)

### Requirement: EG3 — INV3: `NO_PROXY` names `robotina` and keeps loopback

`NO_PROXY` (and its lowercase alias) SHALL reference `robotina`, SHALL keep `127.0.0.1`, and
SHALL NOT reference the retired names `hermes` or `opencode`, so the loopback hop never
touches Squid.

#### Scenario: The bypass list is correct

- GIVEN the stack is up
- WHEN the proxy-bypass variables are read
- THEN both contain `robotina`, `127.0.0.1` and `egress-proxy`, and neither contains `hermes`
  or `opencode` as an entry
- PROOF: `docker compose exec robotina sh -c 'printenv NO_PROXY; printenv no_proxy'`

#### Scenario: Squid never sees the loopback hop

- GIVEN the stack is up and the endpoint has been exercised over loopback
- WHEN the proxy logs are searched for the loopback endpoint
- THEN nothing is found
- PROOF: `docker compose logs egress-proxy 2>&1 | grep -n "127.0.0.1:4096"` (no output, exit non-zero)

### Requirement: EG4 — INV4: `squid/` is byte-identical after this change

`squid/squid.conf` and `squid/allowlist.txt` SHALL be byte-identical to the base branch.

#### Scenario: The egress configuration is untouched

- GIVEN the change set
- WHEN the working tree is diffed against the base branch for `squid/`
- THEN there is no difference
- PROOF: `git diff --exit-code $(git merge-base HEAD main)...HEAD -- squid/` (exit 0) and
  `git status --porcelain -- squid/` (no output)

### Requirement: EG5 — INV5: the stack refuses to start without `HOST_DATA_DIR`

The stack SHALL refuse to start when `HOST_DATA_DIR` is not defined, so state can never end up
hidden inside the repository.

#### Scenario: The mandatory interpolation guard exists

- GIVEN the merged compose file
- WHEN the mount sources are searched for the mandatory-with-message interpolation form
- THEN the guard is present
- PROOF: `git grep -n 'HOST_DATA_DIR:?' -- compose.yml` (non-empty)

#### Scenario: Rendering without the variable fails

- GIVEN an environment without `HOST_DATA_DIR` and an empty interpolation file
- WHEN compose validates the file
- THEN it exits non-zero
- PROOF: `env -u HOST_DATA_DIR docker compose --env-file /dev/null config -q` (non-zero exit)
- NOTE: if the installed Compose version still reads the project `.env`, run the same check
  from a copy of `compose.yml` in an otherwise empty directory, and record which form was used.

## Non-regression checklist (proposal §6.3)

Every asserted non-regression is owned by exactly one requirement and has a named recipe.

| Non-regression | Owner | Recipe |
| --- | --- | --- |
| No published ports | EG1 | `docker compose ps --format 'table {{.Name}}\t{{.Ports}}'` |
| No direct Internet for `robotina` | EG2 | `curl --noproxy "*" https://example.com` inside the container (must fail) |
| Egress only via `egress-proxy` | EG2 | proxy reachability probe + allowlisted-destination control |
| Squid config and allowlist untouched | EG4 | `git diff --exit-code … -- squid/` |
| No Docker socket | EG1 | `git grep -n "docker.sock" -- compose.yml` |
| `no-new-privileges:true` | agent-container AC4 | `grep -i NoNewPrivs /proc/self/status` → `1` |
| `cap_drop: [ALL]` + minimal `cap_add` | agent-container AC4 | `grep -E "Cap(Bnd\|Eff)" /proc/1/status` |
| Core dumps off | agent-container AC4 | `ulimit -c` → `0` |
| Bounded logs | agent-container AC4 | `docker inspect --format '{{.HostConfig.LogConfig.Config}}' robotina` |
| Secrets only via the gitignored `.env` | EG1 / agent-credentials CR4 | `git check-ignore -v .env` + secret greps |
| WAL SQLite on native volumes | state-layout SL2 | `mount \| grep -E "\.engram\|\.local/share/opencode"` |
| Single agent container | agent-container AC1 | `docker compose config --services` |
