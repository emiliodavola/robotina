---
name: github-private-repos
description: "Private GitHub repositories and everything needing GitHub credentials (clone private, push, gh) from this container: gh is installed and GITHUB_TOKEN is wired as git's credential helper. A 404 is a token-permissions problem. Never ask the user for a token."
version: 2.0.0
author: robotina stack
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [GitHub, Credentials, Private-Repos, Security]
    related_skills: [opencode-server]
---

# GitHub: private repositories and credentials

This container holds the credentials itself. The old split — one container with the
credentials and another without — is retired: there is a single agent container now, and
it can clone, fetch and push to private repositories directly.

| Capability | This container |
| --- | --- |
| `git` | yes (2.47) |
| `gh` | yes (2.97) |
| GitHub credential | yes — a fine-grained PAT in `GITHUB_TOKEN`, wired as git's credential helper |
| Shared state | `/workspace` |

## Rules

1. **Never ask the user for a GitHub token.** The stack already holds one, right here.
   Asking for one is a regression: it happens when nothing says where the credential
   lives.
2. **Never write a token into a prompt, a file, a commit, or a session transcript.**
   Do not print it either.
3. **Public repositories: clone them over `https://` URLs.** `git` works through the
   egress proxy without credentials. `git ls-remote https://github.com/<owner>/<repo>`
   is a cheap check. `git@github.com:` does not work from here: `ssh` cannot reach the
   Internet through the proxy, which allows `CONNECT` to port 443 only.
4. **Private repositories and pushes work directly from here** — `git` finds the helper
   and `gh` finds `GITHUB_TOKEN` in the environment.
5. **A `404` on a private repo is a token-permissions problem.** GitHub answers `404`
   for private repositories the token does not cover, exactly as it does for
   repositories that do not exist. Read it as "the token does not include this repo (or
   it expired)", fix the token's repository scope on the host, and retry — never as a
   request for a new token in the chat.

## Recipes

Clone a private repository:

```sh
git clone https://github.com/<owner>/<repo> /workspace/<repo>
```

Check what the token actually covers before blaming the network:

```sh
gh auth status
gh repo view <owner>/<repo> --json nameWithOwner
```

If the clone returns `404`, run `gh repo view` for the same repo: a `404` there confirms
a token-scope gap, while a `403` (`Write access to repository not granted.`) is GitHub
refusing the write specifically.

## Troubleshooting

| Symptom | Meaning |
| --- | --- |
| `404` on a private repo | The PAT does not include that repo, or it expired. Report it as a token-permissions problem, with the exact repo. |
| `403` with an HTML body | The host is not in the proxy allowlist. See the egress notes in the `opencode-server` skill. |
| `403` with a git body (`Write access to repository not granted.`) | GitHub itself: the token does not cover that repository. A permissions problem, not an allowlist problem. |
| `Permission denied` writing in `/workspace` | Ownership problem on the shared mount, not a credential problem. Report it; the host has `scripts/fix-permissions.ps1`. |
