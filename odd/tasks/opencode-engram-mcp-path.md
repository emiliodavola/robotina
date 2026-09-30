# Feature: opencode-engram-mcp-path

## Goal

Close #77: the merged OpenCode config's `mcp.engram` entry MUST point at the binary the image pins
(`/usr/local/bin/engram`), and the repository MUST own that value, so a reprovision cannot reintroduce
the measured failure: the OpenCode server reported the `engram` MCP as `failed` with
`ENOENT posix_spawn '/opt/data/.local/bin/engram'` while the image's binary lives at
`/usr/local/bin/engram`.

Branch: `fix/issue-77-engram-mcp-path`, off `main`. Owner: `emiliodavola`. Closes #77.

## Non-goals

- **No symlink in the bind** (`/opt/data/.local/bin/engram -> /usr/local/bin/engram`): AC11 treats a
  copy in the agent's HOME as the shadow to quarantine. A managed symlink would mask the shadow
  instead of the invariant, so the MCP entry is fixed at its source of truth instead.
- **No change to the MCP tool surface** (`mcp --tools=agent`) nor to the s6 `engram` service.
- **No image rebuild or container recreate in this change.**

## Diagnosis (measured, read-only against the live stack, 2026-09-29)

1. The running image already stages `mcp.engram.command[0] = /usr/local/bin/engram` in
   `/opt/gentle-ai-stage/.config/opencode/opencode.json` — proved with a throwaway container from the
   image (`docker run --rm --entrypoint sh robotina:local -c 'jq …'`), which never touches the running
   stack. `opencode-init` copies the stage over the user config and then merges
   `robotina/overlay.json`, so a fresh reprovision from this image does **not** reproduce the reported
   `/opt/data/.local/bin/engram`.
2. The repository does **not** own the key: the entry comes from gentle-ai's generated config, and
   `robotina/overlay.json` declares only `codegraph` and `gh_grep` under `mcp`.
3. The reported wrong path was therefore **stale state** (an older image and/or an older merged
   config), not a value the current sources produce. The durable gap is ownership, not the current
   string.

## Shape

1. `robotina/overlay.json`: declare `mcp.engram` with the absolute image path, `enabled: true` and
   `type: local`. The overlay is merged by key and **its keys win**, so the repository becomes the
   owner of the value and a regenerated gentle-ai stage cannot silently retarget it.
2. Spec `agent-credentials` **CR9** gains a scenario: the source overlay carries
   `mcp.engram.command[0] = /usr/local/bin/engram`, and the merged config uses the same path.
3. Issue evidence: the current image already stages the correct path; the overlay pin makes it
   regression-proof and gives the repo the last word.

## Tasks

- [x] T1 — Branch and this tracker.
- [x] T2 — `robotina/overlay.json`: `mcp.engram` pinned to `/usr/local/bin/engram`.
- [x] T3 — Spec `agent-credentials` CR9: the overlay owns the path and the merged config uses it.
- [x] T4 — Verification: overlay grep, overlay-wins merge simulation against the image's stage, the
      live merged config, and `docker compose config -q` — all measured. The change is a trivial
      config value plus one spec scenario, so the proofs above are the verification (see the route
      declaration).
- [x] T5 — Commit per work unit, push, PR against `main` assigned to the owner: **PR #83**.

## Pending after this PR

- A rebuild plus `--force-recreate` is what makes the overlay-authored value the one the running
  container serves; until then the proofs use the merge simulation and the merged-config probe.

## Route declaration

- Classification: **trivial and authorized** (one config value + one spec scenario).
- Delegation: none. A separate verifier is disproportionate for a constant pinned in a config file;
  the verification is the measured proofs of T4 (JSON validity, overlay-wins merge simulation against
  the image's stage, live merged-config probe, `docker compose config -q`).
