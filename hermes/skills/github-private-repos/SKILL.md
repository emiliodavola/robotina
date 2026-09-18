---
name: github-private-repos
description: "Private GitHub repositories, and anything needing GitHub credentials (clone private, push, gh). This container deliberately has NO credentials; OpenCode holds gh plus a fine-grained PAT. Delegate there, and never ask the user for a token."
version: 1.0.0
author: robotina stack
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [GitHub, Credentials, Private-Repos, Delegation, Security]
    related_skills: [opencode-server]
---

# GitHub: private repositories and credentials

Verified capability split between the two containers:

| | this container (`hermes`) | the `opencode` container |
| --- | --- | --- |
| `git` | yes (2.47) | yes (2.54) |
| `gh` | **no** | yes (2.97) |
| GitHub credential | **none** — no `GITHUB_TOKEN`, no credential helper, no `~/.config/gh` | yes — a fine-grained PAT in `GITHUB_TOKEN`, wired as git's credential helper |
| Shared state | `/workspace` | `/workspace` |

## Rules

1. **Never ask the user for a GitHub token.** The stack already holds one, in the
   container that needs it. Asking for one is a regression: it happens when nothing
   says where the credential lives.
2. **Never write a token into a prompt, a file, a commit, or a session transcript.**
   Do not ask OpenCode to print one either.
3. **Public repositories: clone them here.** `git` works through the egress proxy
   without credentials. `git ls-remote https://github.com/<owner>/<repo>` is a cheap
   check, and `git@github.com:` URLs are rewritten to HTTPS automatically.
4. **Private repositories, and anything that pushes: delegate to OpenCode.** It has
   the credentials, and it shares `/workspace`.
5. **A `404` on a private repo means "no credentials", not "no such repo".** GitHub
   answers 404 for private repositories to unauthenticated requests. The conclusion is
   "delegate", never "I need a new token".

## How to delegate a private clone

Ask OpenCode over its HTTP API — the mechanics, the auth flag and the pitfalls live in
the `opencode-server` skill — to do the clone in the shared workspace. A prompt that
works:

> With `git` (credentials are already configured there), clone `<owner>/<repo>` into
> `/workspace/<repo>` and tell me the HEAD commit. Do not touch anything else.

After that, `/workspace/<repo>` is a normal checkout for both containers: read it, edit
it, build it here, and ask OpenCode to push when the work is done. If the repo is
private and the clone comes back `404` **from OpenCode**, the PAT does not cover that
repository or expired: report that to the user, with the exact repo, as a permissions
problem — do not ask for a fresh token in the chat.

## Troubleshooting

| Symptom | Meaning |
| --- | --- |
| `404` on a private repo **from this container** | Expected: there are no credentials here. Delegate to OpenCode. |
| `404` on a private repo **from OpenCode** | The PAT does not include that repo, or it expired. Report it as a permissions problem. |
| `403` with an HTML body | The host is not in the proxy allowlist. See the egress notes in the `opencode-server` skill. |
| `Permission denied` writing in `/workspace` | Ownership problem on the shared mount, not a credential problem. Report it; the host has `scripts/fix-permissions.ps1`. |
