---
name: opencode-server
description: "Delegate coding work to a remote OpenCode server over HTTP. There is no opencode binary in this container."
version: 1.0.0
author: robotina stack
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Coding-Agent, OpenCode, Delegation, HTTP]
    related_skills: [opencode, claude-code, codex]
---

# OpenCode server (remote coding delegate)

OpenCode does **not** run inside this container. There is no `opencode` binary here,
so `which -a opencode` fails and the bundled `opencode` skill — which assumes the
CLI is local — does not apply. A sibling container runs `opencode serve` and is
reachable at `http://opencode:4096`. Both containers mount the same `/workspace`,
so anything it writes is visible here immediately, and vice versa.

## When to use

- The user asks for OpenCode by name, or wants a second coding agent on the same files.
- A coding task is worth running as its own agent, with its own model and its own cost.

## Do not

- Do not try to install or run the OpenCode CLI in this container. Use the HTTP API.
- Do not hardcode `OPENCODE_SERVER_PASSWORD` anywhere, and never print it in output.
- Do not assume new outbound hosts will work: this container has **no direct Internet**.
  Everything external goes through `egress-proxy` with a domain allowlist. A task that
  needs a new host means editing `squid/allowlist.txt` on the host and restarting the
  proxy — report that to the user instead of working around it.

## API (verified against OpenCode 1.18.31)

Full OpenAPI spec: `GET http://opencode:4096/doc`. Liveness: `GET /global/health`.

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

Request body of `POST /session/{id}/message`:

```json
{
  "parts": [{"type": "text", "text": "<the task>"}],
  "model": {"providerID": "opencode", "modelID": "mimo-v2.5-free"}
}
```

The response is `{"info": {...}, "parts": [...]}` — the answer is the `text` in
`parts`. `info.finish` should be `"stop"`; `info.tokens` reports usage.

The reply also comes as event stream on `GET /event` (SSE) if you need progress.

## Authentication

The server enforces HTTP Basic **only if** it was started with
`OPENCODE_SERVER_PASSWORD`. Credentials are username `opencode` and that password as
the password. Without the env var the endpoint is open (the server logs a warning).

Always build the credentials from the environment, optionally:

```sh
AUTH=""
[ -n "$OPENCODE_SERVER_PASSWORD" ] && AUTH="-u opencode:$OPENCODE_SERVER_PASSWORD"
curl -s $AUTH http://opencode:4096/global/health
```

## Recipe

Send one task and read the answer:

```sh
AUTH=""
[ -n "$OPENCODE_SERVER_PASSWORD" ] && AUTH="-u opencode:$OPENCODE_SERVER_PASSWORD"

SID=$(curl -s $AUTH -X POST http://opencode:4096/session \
        -H 'Content-Type: application/json' \
        -d '{"title":"task from Hermes"}' \
      | sed -n 's/.*"id":"\(ses_[^"]*\)".*/\1/p')

curl -s $AUTH -X POST "http://opencode:4096/session/$SID/message" \
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
the `opencode/*` free tier is authenticated (`opencode/mimo-v2.5-free`,
`opencode/nemotron-3-ultra-free`, `opencode/muse-spark-1.3-contributor-free`, …).
It is a sibling agent on the same workspace: it can read and write the same files
you can, and it cannot reach the Internet except through the same allowlisted proxy.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Connection refused` | The opencode container is stopped or still starting. |
| `401` | A password is set on the server; your request did not send the Basic credentials. |
| `403` with an HTML body mentioning Squid | The URL host is not in `NO_PROXY`, so the call went through the proxy and the allowlist denied it. Use the `opencode` service name. |
| `Model ... is not supported` | Pick a `modelID` that `GET /config/providers` actually lists. |
