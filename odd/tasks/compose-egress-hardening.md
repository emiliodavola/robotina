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
- [x] T9 — Pull both vendor images and diagnose the Telegram transport from
      their contents instead of guessing.
- [x] T10 — Run both services under the hardened config and fix what breaks.
- [x] T11 — Re-run with the proxy up and read the real egress requests.
- [x] T12 — Document the findings in `SECURITY.md` and adjust `compose.yml`,
      `squid/squid.conf` and `squid/allowlist.txt`.

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

## Image compatibility (T9–T12, verified by running the images)

- **Hermes is s6-overlay and must be PID 1.** `init: true` made it degrade with
  `[hermes] WARNING: container entrypoint is not PID 1; skipping s6-overlay
  /init`. Removed from `hermes`; kept on `opencode` (single binary).
- **Hermes needs five capabilities.** With `cap_drop: [ALL]` startup died with
  `s6-applyuidgid: fatal: unable to set supplementary group list: Operation not
  permitted`. Applied `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETUID, SETGID]`
  to `hermes` only; s6 then boots the full tree (preinit → `s6-rc` →
  `cont-init` → stage2-hook) and syncs its 58 bundled skills.
- **`user:` is rejected by Hermes** (`--user <arbitrary uid> ... not
  supported`); the supported knob is `HERMES_UID`/`HERMES_GID` while starting
  as root. The earlier "just set user: 1000:1000" advice was wrong and is gone.
- **Opencode is clean under `cap_drop: [ALL]` + `init: true`**: prints
  `1.18.31`.

## Telegram transport (the earlier open question)

The image ships `python-telegram-bot 22.8` (**Bot API over HTTPS**, not
MTProto). Its `HTTPXRequest` passes `proxy=None` to `httpx.AsyncClient`, and
httpx defaults to `trust_env=True`, so `HTTPS_PROXY` is honored. Confirmed live:
the proxy logged `domain=raw.githubusercontent.com ... TCP_TUNNEL http=200` for
the Hermes run container. Step 2 of the report is therefore closed by evidence,
not by reasoning.

With the proxy up, Hermes requested exactly four domains at startup:
`raw.githubusercontent.com` (allowed), and `openrouter.ai`,
`hermes-agent.nousresearch.com`, `portal.nousresearch.com` (denied with 403).
The denials are non-fatal: bootstrap completes and the skills sync reports
`Done: 0 new, 0 updated, 58 unchanged`. They are documented as deliberately
denied in `squid/allowlist.txt`.

The model host TODO is resolved: the image code (`agent/anthropic_endpoints.py`,
`agent/model_metadata.py`: `"opencode.ai": "opencode-go"`) shows the relay is
`opencode.ai`, now allowlisted. Not verified end to end: a real model call needs
a funded key.

## Audit improvement found while diagnosing

`squid.conf` originally logged neither URL nor domain, so a denied request could
not be identified. `%>rd` was validated with `squid -k parse` and added: the log
now carries the **domain** but still no URL — the bot token lives in the path,
never in the domain.

## Residual risks (documented, not fixed)

- Env vars are visible in `docker inspect` / `/proc/1/environ`.
- External DNS is already unavailable from `agents` in this environment, which
  closes the DNS-exfiltration channel. Observed property, not a configured
  guarantee: re-measure if the daemon or host resolver changes.
- `hermes` holds CHOWN/DAC_OVERRIDE/FOWNER/SETUID/SETGID because its s6
  bootstrap needs them; `opencode` and `egress-proxy` hold none.
- Hermes' seeded `/opt/data/config.yaml` predates its own config version 12 and
  cannot be auto-migrated; `hermes setup` is suggested by the image.
