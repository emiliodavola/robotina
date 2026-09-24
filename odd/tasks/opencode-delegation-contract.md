# Feature: opencode-delegation-contract

## Goal

Make a task that Hermes delegates to OpenCode actually run and finish.

The reported symptom was "Hermes funciona, pero cuando manda una tarea a OpenCode
este no la ejecuta". The diagnosis below shows OpenCode *did* start and did read
the repository, but the turn never converged, and Hermes reported a result it
never got.

## Diagnosis (measured against the running stack, 2026-09-24)

Sources: `${HOST_DATA_DIR}/hermes/logs/agent.log`, `state.db` (the real Hermes
conversation), `/opt/data/.local/share/opencode/log/opencode.log`, and
`GET /config/providers`.

Chain of events for the delegated code review of `cv-emilio-davola`:

1. **Hermes drives the HTTP API by hand, not the CLI.** `POST /session` →
   `ses_f33eec0fcffeENJvbDmyy2Wq0t`, then `POST /session/{id}/message`.
2. **The task landed on `gentle-orchestrator`.** Its own prompt: *"You are a
   COORDINATOR, not an executor. … delegate ALL real work to sub-agents"*. It is
   the `default_agent` of the merged `opencode.json`, contributed by
   `/opt/gentle-ai-stage/.config/opencode/opencode.json` — the repo overlay does
   not set it. This is the root cause.
3. **The turn never closed.** 23 tool calls, then the last event for that session
   is `02:23:36.525 stream providerID=opencode modelID=big-pickle`, followed by 32
   minutes of silence until the explicit `cancel`. `info.finish` stayed `None`.
4. **Hermes used the blocking endpoint**, so it waited:
   `sequential tool terminal timed out after 420.0s`.
5. **Hermes then hand-picked a provider that does not carry that model.**
   `providerID: "opencode"` (8 models, default `big-pickle`) with
   `modelID: "deepseek-v4.1-flash"` →
   `ProviderModelNotFoundError: Model not found: opencode/deepseek-v4.1-flash`
   (ref `err_8a98b137`). The valid provider for the Go key is `opencode-go`
   (32 models, `deepseek-v4.1-flash` included).
6. **Hermes started a second, unsupervised server** (`opencode serve --port 4097`,
   background, not an s6 service). When that process died, the in-flight session
   died with it, and Hermes kept telling the user "está corriendo en segundo
   plano, te aviso al terminar".

Proof that the delegate itself is healthy:

```
opencode run --agent build -m opencode-go/deepseek-v4-flash \
  "Fix the bug in calc.py so add() adds, and say DONE"
```

→ read the file, edited `return a - b` to `return a + b`, ran its own check, and
printed `DONE.` (exit 0).

## Why Hermes did not know better

Commit `6ec5fad` (*"fix(hermes): drop the redundant opencode skill and key the
local CLI"*) deleted `hermes/skills/opencode-server/SKILL.md` as redundant with
the vendor's builtin `opencode` skill. The vendor skill is generic (npm install,
`opencode auth login`, TUI, `--model openrouter/...`); the deleted skill held the
stack-specific verified facts that were missing here: `/message` blocks, use
`/prompt_async` plus polling for long jobs, pick a `modelID` that
`GET /config/providers` actually lists, and the loopback auth recipe. After the
deletion `hermes/skills/` mounted only `github-private-repos`, and
`logs/errors.log` records two `Skill 'opencode-server' not found`.

## Shape (decided by the user)

The delegation target must be an agent that executes.

1. `robotina/overlay.json` gains `"default_agent": "build"`. The overlay is merged
   last and repo keys win, so this overrides the gentle-ai stage for every entry
   point (CLI, HTTP API, TUI). `gentle-orchestrator` stays reachable with
   `--agent gentle-orchestrator`.
2. A repo-owned stack skill restores the verified delegation contract, this time
   accurate for the two-key layout (`opencode-go`, not `opencode`). It lives at the
   flat repo path `hermes/skills/opencode-delegation/SKILL.md`, which lands at
   `/opt/data/skills/stack/opencode-delegation`.
3. `hermes/context/.hermes.md` carries the short always-on rule, so the contract
   is in every prompt without depending on the model choosing to open a skill.
4. `openspec/specs/opencode-delegation/spec.md` makes the contract durable and
   testable, following this repo's verification model.

Trade-off accepted: an interactive TUI session now opens on `build` instead of
`gentle-orchestrator`. The orchestrator remains one `--agent` flag away.

The user re-confirmed this after the PR was open, against the earlier recorded choice
in `odd/tasks/opencode-config-port.md` ("identical to the host, `default_agent:
gentle-orchestrator` with all 23 agents"). That earlier answer was about porting the
host configuration, not about delegation, and it never entered a living spec —
`openspec/specs/` did not mention `default_agent` before this change. The reasoning
that settled it: `default_agent` is the safety net, so with `build` a caller that
forgets `--agent` still gets the work done, while with `gentle-orchestrator` forgetting
it reproduces this incident. And the incident went through the HTTP API, where only
`default_agent` or an explicit `"agent": "build"` in the body decides — a CLI wrapper
could not have helped.

## Tasks

- [x] T1 — Feature document (this file).
- [x] T2 — Reproduce and bound the failure from logs, `state.db` and
      `opencode.log`; confirm the delegate works via `opencode run --agent build`.
- [x] T3 — Resolve the design decision with the user (overlay + skill +
      `.hermes.md`, option 1 of 3).
- [x] T4 — `robotina/overlay.json`: `default_agent: build`.
- [x] T5 — `hermes/skills/opencode-delegation/SKILL.md` (flat: the whole
      `hermes/skills/` directory is mounted at `/opt/data/skills/stack`, so a
      `stack/` level in the repo path would double that segment).
- [x] T6 — `hermes/context/.hermes.md`: always-on delegation rule.
- [x] T7 — `openspec/specs/opencode-delegation/spec.md`.
- [x] T8 — Doc alignment: `openspec/project.md`, `README.md`, `README.en.md`,
      `SECURITY.md`.
- [x] T9 — Verify: build, `--force-recreate`, merged config, CLI end-to-end,
      skill visible on the read-only mount, `docker compose config -q`.
- [x] T10 — Commit, push, PR against `main`, assigned to `emiliodavola` →
      [#20](https://github.com/emiliodavola/robotina/pull/20).

## Evidence

Rebuilt (`docker compose build robotina` → `Image robotina:local Built`) and
force-recreated (`docker compose up -d --force-recreate`; both `robotina` and
`egress-proxy` `healthy`). Every proof in the new spec was then run as written.

| Proof | Observed |
| --- | --- |
| OD1 — merged `default_agent` | `build` (was `gentle-orchestrator` before the rebuild) |
| OD1 — overlay is the source | `grep -c` → `1` |
| OD2 — `gentle-orchestrator` still exposed | `1` |
| OD2 — its description still says it does not execute | `1` (`never does work inline`) |
| OD3 — `opencode run --agent build` edits a throwaway repo | `2:    return a + b`, exit 0 |
| OD3 — same, **with no `--agent`**, so the default decides | `2:    return a * b`, exit 0; banner `> build · deepseek-v4-flash` |
| OD3 — non-vacuous control | `control: unfixed content does not match` |
| OD4 — `opencode-go` in the catalogue | `1` |
| OD4 — chosen `modelID` in the same response | `1` |
| OD5 — exactly one `opencode serve` | `1` |
| OD5 — it is the supervised service | `up (pid 221 pgid 221)` |
| OD5 — no listener on 4097 / control on 4096 | `0` / `1` |
| Skill on the read-only mount | `/opt/data/skills/stack/opencode-delegation/SKILL.md` present |
| Compose validity | `docker compose config -q` → exit 0 |

Two defects were found in the authored spec during this verification and fixed
before committing:

1. **OD5's supervised-service proof used `s6-svstat` bare.** It is not on `PATH`
   (`/command/s6-svstat` is). The proof now uses the absolute path with
   `MSYS_NO_PATHCONV=1`, the pattern already recorded in this repo (`D-s12-5` in the
   archived change). Measured: without the prefix Git Bash rewrites the argument and
   the probe dies with `sh: 1: C:/Program: not found`.
2. **OD3's proof ran as `root`.** `docker compose exec` defaults to root, whose
   `HOME` is `/root`, so OpenCode loads `/root/.config/opencode` instead of the merged
   stack config and the delegation fails with a bare
   `{"name":"UnknownError",…,"ref":"err_…"}`. The proof now runs as `-u hermes`,
   where `HOME=/opt/data`. It also writes its run log inside the throwaway directory:
   a `/tmp` path created by the earlier root probe is root-owned, and the next
   `hermes`-user run then fails on the redirect instead of on the delegation.

One correction to the wording, made after measuring `/config/providers`:
`OPENCODE_API_KEY` is **unset** in this container while `OPENCODE_GO_API_KEY` is set;
`opencode-go` resolves a key and lists 32 models, `opencode` resolves none and lists
only its 8-model free tier. The docs therefore say `opencode-go` *resolves
credentials here* rather than asserting which variable it reads — the mechanism was
not established, only the observable result.

## Gotchas carried from this repo

- `overlay.json` is baked at image build (`install -m 0644` in
  `robotina/Dockerfile`), so it needs a rebuild **and** `--force-recreate`:
  `docker compose up -d` compares declared config, not image contents.
- `hermes/skills/` and `hermes/context/.hermes.md` are bind mounts: no rebuild
  needed, but the container must be recreated to pick up a mount change.
- `docker compose config` bare prints resolved `.env` secrets — always `-q`.
- Every proof recipe must assert it matched something; empty output is a FAILURE.
