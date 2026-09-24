# Feature: opencode-cli-environment

## Goal

Make `opencode` invoked as a CLI resolve the **stack's** configuration, whatever `HOME` the
caller happens to have. Today it does not, and that is why a task Hermes delegates never
finishes.

Branch: `fix/opencode-cli-environment`, off `main` (PR #20 already merged).

## Diagnosis (measured against the running stack, 2026-09-24)

`HOME` for `opencode` decides where it looks for config and state. The Hermes terminal snapshot
exports `HOME="/opt/data/home"` — verified in `/opt/data/cache/scratch/hermes-snap-*.sh`:

```
declare -x HOME="/opt/data/home"
```

`sh -c`, `bash -c`, `bash -lc` and `bash -lic` all report `HOME=/opt/data`. Only Hermes'
snapshot changes it, and everything Hermes launches from its terminal inherits it.

Measured with that `HOME` (`docker compose exec -T -u hermes robotina sh -c 'HOME=/opt/data/home; export HOME; opencode debug paths'`):

| | `HOME=/opt/data` | `HOME=/opt/data/home` |
| --- | --- | --- |
| `config` | `/opt/data/.config/opencode` (merged stack config) | `/opt/data/home/.config/opencode` (a one-line stub) |
| `data` | `/opt/data/.local/share/opencode` | `/opt/data/home/.local/share/opencode` |
| `opencode debug config` → `mcp` | 4 servers | **`null`** |
| `opencode debug config` → `permission` | present | **absent** |

Consequences, measured on Hermes' own server (`opencode serve --port 4097`, since killed):

1. `GET /mcp` returned **`{}`** — no MCP servers at all.
2. Its sessions run with instance directory `/opt/data`, so `/workspace/...` counts as an
   **external directory**. With no `permission` policy loaded, `external_directory` falls back to
   opencode's default `ask`. The log shows the block verbatim:
   `evaluated permission=external_directory pattern=/workspace/awale/* action.action=ask` →
   `asking id=per_... permission=external_directory`.
3. No human sits at that prompt, so the tool part stays `state=running` forever, `info.finish`
   stays `None`, and tokens freeze. Reproduced side by side with an identical
   prompt/model/agent: the supervised **4096** server finished in **20 s** with `finish=stop`;
   the **4097** server was still frozen at `in=6532 out=45` after 120 s.

The s6 run script for the `opencode` service already pins `HOME`, the four `XDG_*` variables,
`GOPATH`, `GIT_CONFIG_GLOBAL` and `ENGRAM_DATA_DIR`. The CLI has no such guarantee. That is the
defect.

## Shape

Pin `HOME=/opt/data` and the four `XDG_*` variables inside `robotina/bin/opencode` — the wrapper
the repo already owns, which today only re-exports the credential (CR8). It is the narrowest
place: it wraps the `opencode` process and nothing else, it is root-owned and first on `PATH`,
and it is already installed with `sh -n` validation by the `Dockerfile`.

Deliberately **not** in scope:

- `default_agent`. Commit `3588eef` (the user's) pins `gentle-orchestrator`; the wrapper must not
  fight it, and this change does not touch it.
- Injecting `--agent build` into `run`. The merged skill already instructs the caller to name the
  executor; injecting arguments would make the wrapper more than an environment shim.
- Widening `permission` to silence `external_directory: ask` in general. Pinning the identity
  makes the stack's own policy load, which is the correct fix; a broader allow would weaken the
  policy. Residual risk recorded below.

## Residual risk

`external_directory` is not covered by the overlay's `permission` block, so a delegation whose
cwd is outside `/workspace` can still reach an `ask` and hang. With the identity pinned the
policy loads, and the contract steers delegations to `/workspace`; the case is recorded, not
silenced. Tracked as an open item below.

## Tasks

- [x] T1 — Feature document (this file).
- [x] T2 — `robotina/bin/opencode`: pin `HOME` and the four `XDG_*` variables (CR9).
- [x] T3 — `openspec/specs/agent-credentials/spec.md`: CR9 with three runnable proofs.
- [x] T4 — Verify: `sh -n`, `docker compose config -q`, rebuild, `--force-recreate`, the two
      `debug` probes under the hostile `HOME`, and a bounded end-to-end delegation under it.
- [x] T5 — Commit, push, PR against `main`, assigned to `emiliodavola` →
      [#21](https://github.com/emiliodavola/robotina/pull/21).
- [ ] T6 — Open item: decide whether `external_directory` needs an explicit policy.

## Route declaration

T2 and T3 are one delegated unit: the multi-file write trigger fires (the wrapper and the
`agent-credentials` spec are both non-trivial), and the long-session backstop has long since
fired. Route: **delegated direct**, one bounded `gentle-ai-worker`, surfaces
`robotina/bin/opencode` and `openspec/specs/agent-credentials/spec.md`. T1, T4's parent spot
check, T5 and T6 stay inline as parent bookkeeping and verification.

## Evidence

Rebuilt and force-recreated; both containers healthy. Every CR9 proof run as written, all under
the hostile `HOME=/opt/data/home` that the Hermes snapshot exports.

| Proof | Observed |
| --- | --- |
| CR9 s1 — `debug paths` | `config /opt/data/.config/opencode`, `data /opt/data/.local/share/opencode` |
| CR9 s2 — `debug config` | `mcp: ['codegraph', 'context7', 'engram', 'gh_grep']`, `permission: present` |
| CR9 s3 — bounded delegation mutates the file | `2:    return a + b`, exit 0 |
| `sh -n robotina/bin/opencode` | exit 0 |
| `docker compose config -q` | exit 0 |
| `docker compose build robotina` | `Image robotina:local Built`; the image's own assertions pass, including the `opencode --version` step that now resolves through the wrapper |
| `docker compose up -d --force-recreate` | healthy |

Before the pin, the same two probes with `HOME=/opt/data/home` reported
`config /opt/data/home/.config/opencode`, `data /opt/data/home/.local/share/opencode`,
`mcp: null` and no `permission` block.

### Finding: `opencode debug config` truncates its piped stdout

CR9's second proof was first written as a piped `opencode debug config | grep`. That cannot work:
opencode caps stdout at **exactly 65536 bytes** when stdout is a pipe, and the merged
configuration is ~165 kB, so the read is cut mid-string and the `mcp` block — which sits near the
end — never arrives. Measured: piped, 65536 bytes and `json.load` raises `Unterminated string`;
redirected to a file, 345638 bytes of valid JSON with all four MCP servers. The same result came
from the real binary `/usr/local/bin/opencode`, so the wrapper is not the cause. The proof now
redirects to a file before parsing, and the trap is recorded in a NOTE on the requirement.

### Route and process note

The writer surfaced that defect instead of silently working around it, and refused to edit spec
prose it had been told to write verbatim. The corrected proof was designed, **verified by hand**,
and only then written into the spec.

## Open item

`external_directory` is not covered by the overlay's `permission` block (`overlay.json` sets only
`bash` and `read`). With the identity pinned, the policy loads and delegations that run inside
`/workspace` are fine, which is what CR9 s3 proves. A delegation whose cwd is outside
`/workspace` and reaches back in could still hit `external_directory: ask` and hang the same way,
because nothing answers that prompt. Two candidate resolutions, neither taken here: state the cwd
rule in the delegation contract, or add an explicit `external_directory` decision to the overlay.
Widening the policy silently was rejected as the wrong trade.
