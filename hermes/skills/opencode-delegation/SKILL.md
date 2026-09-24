---
name: opencode-delegation
description: "Delegate work to OpenCode from inside this container: the local `opencode` CLI (`--agent build`, model from `GET /config/providers`) plus the supervised loopback server on http://127.0.0.1:4096. Covers the executor-agent rule, the provider/model rule, the non-blocking endpoint, and why you must never start a second server. For private GitHub repos and credentials, see the github-private-repos skill."
version: 1.0.0
author: robotina stack
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Coding-Agent, OpenCode, Delegation, CLI, HTTP, Local]
    related_skills: [github-private-repos, opencode]
---

# OpenCode delegation (in-container coding executor)

OpenCode runs **inside this same container**. The `opencode` CLI is at
`/opt/robotina/bin/opencode` — a wrapper that re-exports OpenCode's own key
(`ROBOTINA_OPENCODE_GO_API_KEY` → `OPENCODE_GO_API_KEY`) for the CLI process only, then
execs `/usr/local/bin/opencode`; `/opt/robotina/bin` precedes it on `PATH`. The server
runs too: `opencode serve` is the s6 service `opencode`, listening on
`http://127.0.0.1:4096`. Both share this filesystem, so anything OpenCode writes is
visible to you immediately, and vice versa. There is no second agent: the endpoint is
local, not a peer host.

## Prefer the CLI

The CLI is genuinely local, so `opencode run` is the normal path — lead with it. It must
be told **which agent and which model**; do not rely on configuration defaults:

```sh
opencode run --agent build -m opencode-go/<model> "<task>"
```

Verified end to end on this stack:

```sh
opencode run --agent build -m opencode-go/deepseek-v4-flash \
  "Fix the bug in calc.py so add() adds, and say DONE"
```

→ it read the file, edited `return a - b` to `return a + b`, ran its own check, and
printed `DONE.` (exit 0). Reach for the HTTP endpoint only when a program needs one.

## The agent rule (most important)

`gentle-orchestrator` is the Gentle AI SDD orchestrator. Its own prompt says it
coordinates sub-agents and **never does work inline**, so a task delegated to it does not
get executed. Never delegate a task that must be *done* to `gentle-orchestrator`.

- `build` is the executor (native, "The default agent. Executes tools based on configured
  permissions."). This is what you want.
- `plan` is read-only.
- The repo overlay sets `default_agent: build`, so the CLI, the HTTP API and the TUI all
  land on `build` unless overridden — but pass `--agent build` explicitly anyway, so the
  choice does not depend on configuration drift.

## The model rule

**Never substitute a model.** Read the configured value *before* delegating — the ids
change over time, so none of them is a constant here.

| Side | Today | Where it is configured |
| --- | --- | --- |
| Hermes / robotina | `muse-spark-1.3-contributor` (on promo) | `ROBOTINA_HERMES_MODEL` → `config.yaml` `model.default` |
| Delegation to OpenCode | `deepseek-v4.1-flash` | `ROBOTINA_OPENCODE_DELEGATE_MODEL` (the `opencode-delegate` default) |

`GET /config/providers` only **confirms** that the configured pair resolves; it does not
choose.

- `opencode-go` is the provider that resolves credentials in this container, and its
  catalogue holds this stack's models (32 of them).
- `opencode` resolves no key here: it exposes only its free tier (8 models).

A wrong pair fails with `ProviderModelNotFoundError`, and the HTTP layer surfaces it only
as `{"name":"UnknownError",...,"ref":"err_…"}` — the real message lives in the server log,
not in the response. Do not paste the `/config/providers` body into a log, transcript or
issue: that endpoint serializes provider credentials in plain text (see `SECURITY.md`).

## The endpoint rule

`POST /session/{id}/message` is **blocking**: it waits for the whole turn. For anything
longer than a short task, use `POST /session/{id}/prompt_async` (it returns immediately)
and poll `GET /session/{id}/message` until the last assistant message has
`info.finish == "stop"`. Do not hold a synchronous call open across a long agent loop —
that is what turns a slow turn into a transport timeout.

## The one-server rule

The supervised server is the s6 service `opencode` on `127.0.0.1:4096`, started with
`--hostname 127.0.0.1 --port 4096`. **Never start a second `opencode serve` on another
port**: it is unsupervised, it dies without notice, and any session in it dies with it. If
the endpoint refuses connections, check the supervised service instead of starting your
own.

## Do not

- Do not hardcode `OPENCODE_SERVER_PASSWORD` anywhere, and never print it in output.
- Do not assume new outbound hosts will work: this container has **no direct Internet**.
  Everything external goes through `egress-proxy` with a domain allowlist. A task that
  needs a new host means editing `squid/allowlist.txt` on the host and restarting the
  proxy — report that to the user instead of working around it.
- Do not point at a peer host name: the endpoint is loopback only and is not published to
  any other container or to the host.

## API (verified against OpenCode 1.18.32)

Full OpenAPI spec: `GET http://127.0.0.1:4096/doc`. Liveness: `GET /global/health`.

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/session` | Create a session. Returns `{"id": "ses_..."}` |
| POST | `/session/{id}/message` | **Blocking**: send a prompt and wait for the answer |
| POST | `/session/{id}/prompt_async` | Same, but returns immediately (for long jobs) |
| GET | `/session/{id}/message` | List messages of a session |
| GET | `/session/{id}/diff` | Working-tree diff of what it changed |
| GET | `/session/{id}/todo` | Task list it is tracking |
| POST | `/session/{id}/abort` | Stop it |
| GET | `/agent` | Agents it exposes (and their descriptions) |
| GET | `/config/providers` | Providers and models actually available |
| GET | `/session` | List existing sessions |
| GET | `/mcp` | Status of its MCP servers |

Request body of `POST /session/{id}/message` (or `/prompt_async`):

```json
{
  "parts": [{"type": "text", "text": "<the task>"}],
  "model": {"providerID": "opencode-go", "modelID": "deepseek-v4-flash"}
}
```

The reply to `/message` is `{"info": {...}, "parts": [...]}` — the answer is the `text`
in `parts`. `info.finish` should be `"stop"`; `info.tokens` reports usage. With
`/prompt_async` you get `204` and then poll `GET /session/{id}/message`.

The reply also comes as an event stream on `GET /event` (SSE) if you need progress.

## Authentication (the server password)

The server enforces HTTP Basic **only if** it was started with
`OPENCODE_SERVER_PASSWORD`. Credentials are username `opencode` and that password as the
password. Without the env var the endpoint is open (the server logs
`server is unsecured`).

Build the credentials as **positional parameters**, so the password survives any
character it contains:

```sh
set --
[ -n "$OPENCODE_SERVER_PASSWORD" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"
curl -s "$@" http://127.0.0.1:4096/global/health
```

Do **not** do `AUTH="-u opencode:$OPENCODE_SERVER_PASSWORD"` and then `curl $AUTH`: the
unquoted expansion splits a password with spaces or special characters into several
arguments, curl receives garbage, and the API answers `401` as if the credential were
wrong. That failure costs an hour if you don't know it.

## Recipe

Send one short task and read the answer:

```sh
set --
[ -n "$OPENCODE_SERVER_PASSWORD" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"

SID=$(curl -s "$@" -X POST http://127.0.0.1:4096/session \
        -H 'Content-Type: application/json' \
        -d '{"title":"task from robotina"}' \
      | sed -n 's/.*"id":"\(ses_[^"]*\)".*/\1/p')

curl -s "$@" -X POST "http://127.0.0.1:4096/session/$SID/message" \
  -H 'Content-Type: application/json' \
  -d '{"model":{"providerID":"opencode-go","modelID":"deepseek-v4-flash"},
       "parts":[{"type":"text","text":"Add retry logic to the HTTP client and run the tests"}]}' \
  --max-time 900
```

Then report the outcome, and show `GET /session/$SID/diff` so the user sees exactly what
changed. **Prefer `git status`/`git diff` in `/workspace` as the source of truth for the
user, not the model's summary.**

Note on long tasks: `/message` blocks until the agent finishes. Give it a generous
timeout, and if the task is expected to run for many minutes use `/prompt_async` plus
polling `GET /session/{id}/message` until the last message has an assistant part with
`info.finish == "stop"`, so a transport timeout does not look like a failure.

## Models

`GET /config/providers` lists what the server can actually use, and it only confirms the
pair you already read from the config — never pick from memory. As configured today,
`opencode-go` is the provider that resolves credentials here (32 models) and the
delegation model is `deepseek-v4.1-flash`; `opencode` resolves no key, exposes only its
free tier (8 models, default `big-pickle`), and does not contain `deepseek-v4.1-flash`.
OpenCode reads and writes the same files you can, and it cannot reach the Internet except
through the same allowlisted proxy.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Connection refused` | The server is stopped or still starting. Check the supervised service with `/command/s6-svstat /run/service/opencode` — `s6-svstat` is not on `PATH`. |
| `401` | A password is set on the server and the request did not send it — or it sent it with an unquoted `$AUTH` expansion. Use the `set --` pattern above. |
| `403` with an HTML body mentioning Squid | The URL host is not in `NO_PROXY`, so the call went through the proxy and the allowlist denied it. Use `127.0.0.1`. |
| `ProviderModelNotFoundError` (the HTTP layer shows only `{"name":"UnknownError",...,"ref":"err_…"}`) | The provider/model pair is wrong. Read `GET /config/providers` and pick a listed pair; the Go key's provider is `opencode-go`, not `opencode`. The real error text is in the server log. |
| The blocking call times out (`sequential tool terminal timed out after 420.0s`) | You held `POST /session/{id}/message` open across a long agent loop. Switch to `POST /session/{id}/prompt_async` plus polling `GET /session/{id}/message` until `info.finish == "stop"`. |
| A session stalls: its last part is a `reasoning` part and `info.finish` stays `null` | The turn never converged. Inspect it and abort (`POST /session/{id}/abort`); do **not** report a result you never got. |
| `MCP error -32000: Connection closed` on an MCP server | That server's process died at startup. For local ones, run its command by hand inside the container to see the real error. |
