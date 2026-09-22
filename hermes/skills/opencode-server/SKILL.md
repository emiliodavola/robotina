---
name: opencode-server
description: "Drive the OpenCode server that runs inside this same container (loopback http://127.0.0.1:4096): verified API, server-password auth, model routing, troubleshooting. For private GitHub repos and credentials, see the github-private-repos skill."
version: 2.0.0
author: robotina stack
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Coding-Agent, OpenCode, Delegation, HTTP, Local]
    related_skills: [github-private-repos, opencode]
---

# OpenCode server (in-container coding delegate)

The OpenCode server runs **inside this same container**. `opencode serve` listens on
`http://127.0.0.1:4096`, the `opencode` CLI is installed here too, and both share this
filesystem — anything the server writes is visible to you immediately, and vice versa.
There is no second agent: the endpoint is local, not a peer host.

## When to use

- The user asks for OpenCode by name, or wants a second coding agent on the same files.
- A coding task is worth running as its own agent, with its own model and its own cost.
- Any task that needs a long-running agent loop you do not want to block your own turn on.

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
| POST | `/session/{id}/prompt_async` | Same, but returns immediately (for very long jobs) |
| GET | `/session/{id}/message` | List messages of a session |
| GET | `/session/{id}/diff` | Working-tree diff of what it changed |
| GET | `/session/{id}/todo` | Task list it is tracking |
| POST | `/session/{id}/abort` | Stop it |
| GET | `/config/providers` | Providers and models actually available |
| GET | `/session` | List existing sessions |
| GET | `/mcp` | Status of its MCP servers |

Request body of `POST /session/{id}/message`:

```json
{
  "parts": [{"type": "text", "text": "<the task>"}],
  "model": {"providerID": "opencode", "modelID": "mimo-v2.5-free"}
}
```

The response is `{"info": {...}, "parts": [...]}` — the answer is the `text` in
`parts`. `info.finish` should be `"stop"`; `info.tokens` reports usage.

The reply also comes as an event stream on `GET /event` (SSE) if you need progress.

## Authentication (the server password)

The server enforces HTTP Basic **only if** it was started with
`OPENCODE_SERVER_PASSWORD`. Credentials are username `opencode` and that password as
the password. Without the env var the endpoint is open (the server logs
`server is unsecured`).

Build the credentials as **positional parameters**, so the password survives any
character it contains:

```sh
set --
[ -n "$OPENCODE_SERVER_PASSWORD" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"
curl -s "$@" http://127.0.0.1:4096/global/health
```

Do **not** do `AUTH="-u opencode:$OPENCODE_SERVER_PASSWORD"` and then `curl $AUTH`:
the unquoted expansion splits a password with spaces or special characters into
several arguments, curl receives garbage, and the API answers `401` as if the
credential were wrong. That failure costs an hour if you don't know it.

## Recipe

Send one task and read the answer:

```sh
set --
[ -n "$OPENCODE_SERVER_PASSWORD" ] && set -- -u "opencode:$OPENCODE_SERVER_PASSWORD"

SID=$(curl -s "$@" -X POST http://127.0.0.1:4096/session \
        -H 'Content-Type: application/json' \
        -d '{"title":"task from robotina"}' \
      | sed -n 's/.*"id":"\(ses_[^"]*\)".*/\1/p')

curl -s "$@" -X POST "http://127.0.0.1:4096/session/$SID/message" \
  -H 'Content-Type: application/json' \
  -d '{"model":{"providerID":"opencode","modelID":"mimo-v2.5-free"},
       "parts":[{"type":"text","text":"Add retry logic to the HTTP client and run the tests"}]}' \
  --max-time 900
```

Then report the outcome, and show `GET /session/$SID/diff` so the user sees exactly
what changed. Prefer `git status`/`git diff` in `/workspace` as the source of truth
for the user, not the model's summary.

Note on long tasks: `/message` blocks until the agent finishes. Give it a generous
timeout, and if the task is expected to run for many minutes use `/prompt_async`
plus polling `GET /session/{id}/message` until the last message has an assistant
part, so a transport timeout does not look like a failure.

## Models

`GET /config/providers` lists what the server can actually use. As configured, only
the `opencode/*` free tier is authenticated inside OpenCode (`opencode/mimo-v2.5-free`,
`opencode/nemotron-3-ultra-free`, `opencode/muse-spark-1.3-contributor-free`, …).
It can read and write the same files you can, and it cannot reach the Internet
except through the same allowlisted proxy.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Connection refused` | The server is stopped or still starting. Check `s6-svstat /run/service/opencode`. |
| `401` | A password is set on the server and the request did not send it — or it sent it with an unquoted `$AUTH` expansion. Use the `set --` pattern above. |
| `403` with an HTML body mentioning Squid | The URL host is not in `NO_PROXY`, so the call went through the proxy and the allowlist denied it. Use `127.0.0.1`. |
| `Model ... is not supported` | Pick a `modelID` that `GET /config/providers` actually lists. |
| `MCP error -32000: Connection closed` on an MCP server | That server's process died at startup. For local ones, run its command by hand inside the container to see the real error. |
