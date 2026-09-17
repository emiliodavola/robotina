# Feature: compose-egress-hardening

## Goal

Turn `compose.yml` into a fail-closed deployment for two autonomous agents
(Hermes gateway + OpenCode) sharing a workspace volume.

Decisions taken with the user:

1. **Egress**: mediated by an allowlisting forward proxy. Agents lose any
   direct route to the Internet; the proxy is the only container with a
   default gateway.
2. **Secrets**: kept as environment variables sourced from an external
   `.env` (never versioned). Accepted residual risk: `docker inspect`
   exposes them.
3. **Container hardening**: strong but compatible — `cap_drop: [ALL]`,
   `no-new-privileges`, resource/pid limits, bounded logs, tmpfs for temp
   paths, writable rootfs for the two vendor agent images.

## Non-goals

- Rebuilding or wrapping the vendor images (`nousresearch/hermes-agent`,
  `ghcr.io/anomalyco/opencode`).
- Docker daemon level hardening (rootless, `userns-remap`); recommended in
  `SECURITY.md`, not applied here.
- Published ports: none existed and none are added.

## Tasks

- [x] T1 — Write the feature task document (this file).
- [x] T2 — Add the `egress-proxy` service (Squid) with `squid/squid.conf` and
      `squid/allowlist.txt`: fail-closed policy, no cache, no URLs in logs,
      private/metadata destination ranges denied.
- [x] T3 — Move both agents onto the internal `agents` network only; drop
      their direct-Internet membership; inject `HTTP(S)_PROXY`/`NO_PROXY`.
- [x] T4 — Container hardening on all three services: `cap_drop: [ALL]`,
      `no-new-privileges`, `pids_limit`, `mem_limit`, `cpus`, `ulimits.core: 0`,
      bounded json-file logs, tmpfs `/tmp`, `init: true`.
- [x] T5 — Secret hygiene: required-variable interpolation (`:?`) so compose
      aborts instead of starting with empty keys; `.env` gitignored; required
      variables documented in `SECURITY.md`.
      `.env.example` stays empty on purpose: the harness safety policy refuses
      writes to `.env*` paths even after explicit user authorization, and the
      guard was not bypassed. The user pastes that content if they want it.
- [x] T6 — Verify: `docker compose config` parses; `squid -k parse` is clean;
      live checks of allowed / denied / metadata / direct egress.
- [x] T7 — Work-unit commits on branch `security/egress-hardening`.
- [x] T8 — `SECURITY.md`: guarantees table, allowlist workflow, verification
      commands, attention points, out-of-scope next steps.

## Evidence

`docker compose config` → OK. Merge anchors resolved, `mem_limit`/`cpus`/
`pids_limit`/`tmpfs`/`healthcheck` accepted, agents hold no `egress`
membership, and `${VAR:?}` interpolation aborts with
`required variable ... is missing a value` when the `.env` values are absent.

`squid -k parse` → exit 0, no warnings (31 processed directives). Two issues
found and fixed during verification: a redundant subdomain in the allowlist,
and `via off` triggering `WARNING: HTTP requires the use of Via` (replaced by
`httpd_suppress_version_string on`, which hides the version without breaking
the header).

Live run (ephemeral `curlimages/curl` on the `agents` network):

| Check | Result |
| --- | --- |
| `curl https://example.com/` direct | `curl: (6) Could not resolve host` |
| same for `github.com`, `pypi.org` | fail (external resolution unavailable) |
| `curl -x proxy https://api.telegram.org/` | `302` — allowed |
| `curl -x proxy https://example.com/` | `CONNECT tunnel failed, response 403` |
| `curl -x proxy http://169.254.169.254/` | `403` — metadata denied |
| `http://egress-proxy:3128/` from `agents` | reachable (`400`), internal DNS works |

Proxy isolation:

```console

docker exec egress-proxy id                      → uid=13(proxy)
docker inspect egress-proxy --format 'ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}} ...'
  → ReadonlyRootfs=true CapDrop=[ALL] SecurityOpt=[no-new-privileges:true] User=13:13
docker exec egress-proxy touch /usr/sbin/evil    → Read-only file system
docker logs egress-proxy | grep client=          → client/method/status only, no URLs
```

After verification the test stack was torn down; no project containers or
networks remain, and no project volumes existed beforehand.

## Follow-ups discovered

- External DNS is unavailable from `agents`: the harness profile (or the host
  resolver path) already closes the DNS-exfiltration channel, so it did not
  need a `dns:` override. Noted as an observed property, not a configured
  guarantee: re-check if the Docker daemon or host resolver changes.
- Any client that ignores `HTTP(S)_PROXY` and opens its own socket (MTProto /
  Telethon, Node's `fetch`) will fail rather than bypass. First thing to check
  if the Hermes Telegram gateway does not start.
- `squid/allowlist.txt` still has a `TODO` for the OpenCode Go model host.
