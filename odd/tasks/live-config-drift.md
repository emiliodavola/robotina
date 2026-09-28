# Feature: live-config-drift

## Goal

Turn a read-only survey of the **live** `robotina` stack (2026-09-27, container up since
2026-09-25T02:07Z) into a tracked issue set, plus the two owner-authorized documents that come out
of it: the `squid/allowlist.txt` commit and a credential-rotation runbook.

The survey answered one question: does the running stack still match what the repository
declares? Mostly yes, and the exceptions are the point of this feature.

Branch: `docs/live-config-drift`, off `main`. Owner: `emiliodavola`.

## Non-goals

- **No container recreate in this feature.** The owner decided the reconcile window opens after
  phases 1 and 2 of the roadmap, never before, because a recreate drops `/var/tmp` (the uv Python
  tree) and returns `engram` to the pinned 1.20.0 over the same SQLite.
- **No narrowing of `squid/allowlist.txt`.** Owner decision, 2026-09-27: the added entries
  (`.kaggle.com`, `.googleapis.com`) MUST be preserved. The breadth of `.googleapis.com` is
  documented as an accepted risk, not "fixed" by removing it.
- No fix for issue #40 here; this feature only opens its sibling contract issue (#51).
- No change to `compose.yml`, the Dockerfile or the s6 tree. Those are phases 1–2 work.

## Decisions (owner, 2026-09-27)

- **D-MODEL**: for Hermes the default model MUST be the cheapest one available in the provider
  catalog at the moment. Today that is `muse-spark-1.3-contributor`. The delegation knob
  (`ROBOTINA_OPENCODE_DELEGATE_MODEL`) is separate and stays `deepseek-v4.1-flash`.
- **D-ALLOWLIST**: the `.kaggle.com` and `.googleapis.com` entries in `squid/allowlist.txt` are
  preserved. Their breadth is documented as an accepted residual risk; removal is never proposed.
- **D-ISSUES**: one issue per finding, `status:approved`, assigned to the owner.
- **D-RECREATE**: the reconcile window opens after roadmap phases 1–2, never before.
- **D-DELIVERY**: feature branch, then push and a PR against `main` assigned to the owner.

## Method

Read-only against the live stack: `docker inspect` with narrow `--format` filters, `docker exec`
file reads, sha256 comparisons, one `docker compose up -d --dry-run` (plans only), and egress
probes from inside the agent container. Nothing was written, restarted or recreated.

## What is healthy (measured, so the findings below stay in proportion)

- All 10 repo artifacts inside the image are **byte-identical** (sha256): `opencode-init.sh`,
  `opencode-ready.sh`, `healthcheck.sh`, `overlay.json`, `bin/{opencode,opencode-delegate,pre-commit-repair}`,
  `cont-init.d/{10,20,30}-robotina-*`.
- The live Squid allowlist hash equals the repo working copy (`6f74be58fced6482…`), and the proxy
  was restarted after the edit (2026-09-27T04:26Z), so the new entries are **active**:
  `https://www.kaggle.com` → 200, `https://example.com` → 403.
- All five container credentials match the repo `.env` (compared by hash, never printed).
- No gateway crash loop: 35 starts between 2026-09-22 and 2026-09-25T02:07Z, the last one being
  the current container boot; nothing since.
- `GET http://127.0.0.1:4096/global/health` returns 401 without the credential → the password is
  set and enforced.

## Findings

| Id | Finding | Evidence | Class |
| --- | --- | --- | --- |
| D1 | The live container no longer matches the declared config | `com.docker.compose.config-hash` = `672c99a4…` vs current render `0f595f1d…`; `egress-proxy` matches. `--dry-run` → `Recreate`. Verified equal: 23 env names + the 5 secrets (hash), 9 mounts with `ro` flags, caps, tmpfs, limits, healthcheck, logging, `stop_grace_period`, network. Label `com.docker.compose.image` (`ef80d1c4…`) ≠ `.Image` (`d33e0181…` = current `robotina:local`). **Changed input not identified** | drift |
| D2 | The running `engram` is not the pinned one | Dockerfile pins 1.20.0; `s6-rc.d/engram/run` execs `engram serve` without an absolute path; `PATH` resolves `/opt/data/.local/bin/engram` = **2.1.0** (bind-mounted HOME, 2026-09-24). `healthcheck.sh` only runs `pgrep "[e]ngram serve"` | bug |
| D3 | State outside both bind and volume | `/var/tmp/opencode/uv-python/` holds cpython 3.10.20, 3.13.13, 3.14.4, and `~/.local/bin/python3.10` / `python3.14` symlink into it. Declared `UV_PYTHON_INSTALL_DIR=/opt/uv/python` | bug |
| D4 | Runtime provisioning, undeclared, one tool unreachable | `/opt/data/bin/kaggle` → `/opt/data/cache/uv-tools/kaggle` (CLI 2.2.4) with a `UV_TOOL_DIR` other than the declared `/opt/uv/tools`, which does not exist; `/opt/data/bin` is **not** on `PATH`, so `command -v kaggle` fails. Also `~/.local/bin/rtk` 0.49.0 and `/opt/data/bin/tirith` | bug |
| D5 | `rtk` is load-bearing and invisible to the repo | `rtk` 0.49.0 = "CLI proxy designed to filter and summarize system outputs before they reach your LLM context". Absent from `.hermes.md`, the `opencode-delegation` skill, `opencode.json` and `AGENTS.md`. It is also the unreproduced symptom of #40: `rtk`-prefixed commands finish, bare `git -C /workspace/sofer status --short` stayed `running` forever | bug |
| D6 | New credential, not inventoried, inside the host bind | `/opt/data/.kaggle/access_token` (37 bytes, 2026-09-27) = `${HOST_DATA_DIR}/hermes/.kaggle/`. `SECURITY.md` documents no Kaggle credential | docs |
| D7 | The allowlist change is **uncommitted** and broader than its comment says | `git status` dirty only for `squid/allowlist.txt`; the comment says "competencia gemma-4-developer-agent" but the entries are `.kaggle.com` **and** `.googleapis.com` (all Google APIs). Live and applied. Owner: **preserve** | security/docs |
| D8 | The deployed Hermes model is not the declared default | `.env` → `ROBOTINA_HERMES_MODEL=muse-spark-1.3-contributor`; `compose.yml`/`.env.example` default = `deepseek-v4.1-flash`; live `config.yaml` matches `.env`. The real decision lives only in a gitignored file | docs |
| D9 | Undocumented second config plane | `/opt/data/.env` (26 KB, agent HOME) with `API_SERVER_KEY`, `BROWSERBASE_*`, `TELEGRAM_HOME_CHANNEL`, `TERMINAL_*` | docs |
| D10 | Missing git identity; broad trust setting | `git config --global --list` = one line: `safe.directory=*`. No `user.name`, no `user.email`, against docs that claim git identity lives in the bind | verify |
| D11 | SDD/ODD state out of sync | Change `single-robotina-container` **archived**, yet `project.md`/`config.yaml` say "Active SDD change" and `current_branch: feat/single-robotina-container` while HEAD is `main`; tracker T8/T9/T10 unchecked; `.git/REBASE_HEAD` left from 2026-09-24 | docs |
| D12 | Unwatched resilience signal | 8 Telegram reconnects on 2026-09-27 (11:05, 11:59, 12:42, 14:21, 16:48…) with `httpx.ConnectError:` carrying **no message**. The agent's only human channel drops for minutes | observability |

Underlying pattern: `PATH` puts `/opt/data/.local/bin` **before** `/usr/local/bin`, so anything the
agent installs into its bind-mounted HOME silently shadows what the Dockerfile pinned. D2–D5 are
that one defect seen four ways.

## Shape

1. `squid/allowlist.txt` is committed **as-is** (both entries preserved) and its breadth documented
   as an accepted residual risk in `SECURITY.md`.
2. Each finding becomes one GitHub issue with the evidence above, so the roadmap is executable from
   the tracker instead of from a chat transcript.
3. The rotation runbook lands in `SECURITY.md` (no secret values, no incident narrative).

## Deferred: the container reconcile window

`docker compose up -d` will recreate `robotina` (see D1). It MUST NOT run before roadmap phases 1–2
are decided, because the recreate:

1. drops `/var/tmp/opencode/uv-python` (the three cpythons of D3) and leaves the
   `~/.local/bin/python3.10` / `python3.14` symlinks dangling, and
2. returns `engram` to the Dockerfile's pinned 1.20.0 (D2) over the same WAL `engram.db` that the
   live 2.1.0 has been writing.

Gate: decide D2 (which engram version is the target) and D3 (where the uv Pythons live) first.
Until then, `--dry-run` is the only reconcile command that runs.

## Tasks

- [x] T1 — Branch `docs/live-config-drift` and this tracker.
- [x] T2 — Open the 10 issue candidates (D1–D10) plus the #40 sibling plus Dependabot:
      #41 (D1 config drift), #42 (D2 engram pin), #43 (D3 uv Pythons in `/var/tmp`),
      #44 (D4 runtime provisioning), #45 (D5 `rtk`), #46 (D6 Kaggle credential),
      #47 (D7 allowlist), #48 (D8 model default), #49 (D9 second config plane),
      #50 (D10 git identity), #51 (#40 sibling contract), #52 (Dependabot). All read back from
      the target host: title, body, labels and assignee confirmed.
- [x] T3 — Commit the allowlist change as-is (both entries preserved) and record its breadth as an
      accepted risk in `SECURITY.md`.
- [x] T4 — Credential-rotation runbook plus the D6/D8/D9 facts in `SECURITY.md`, written by one
      bounded writer and reviewed here (two corrections applied: the value-hash recipe now tolerates
      CRLF, and the second config plane no longer claims to be measured).
- [x] T5 — Align the Hermes model default with D-MODEL on five of the six surfaces
      (`compose.yml`, `30-robotina-model`, `README.md`, `README.en.md`, `SECURITY.md`), with the
      "cheapest model of the catalogue" policy written down.
- [x] T6 — Record the deferred recreate and its gate (see § Deferred above).
- [x] T7 — Push the branch and open the PR against `main`, assigned to `emiliodavola`: **PR #53**
      (4 commits: tracker, allowlist, model default, security docs). Static validation
      (`docker compose config -q`) green before the push. Merge stays the owner's decision.
- [x] T8 — `.env.example` line 30 now carries the new default, and the assignment block at the foot
      keeps bare `KEY=` lines. The repo-local safety guard refuses every `.env*` path to the editor
      tools (the writer refused to route around it and so did the parent), so the owner applied the
      two lines by hand; this branch commits them (`chore/env-example-model-default`).
      **Measured rationale for keeping the keys bare:** Docker Compose reads an inline comment as
      *part of the value*, so a comment on a real key does not document it, it corrupts it.

## Route declaration

- Classification: **substantial and authorized** (issue set + two documents).
- Delegation: the issue set was published by the parent (it holds the evidence and the
  publication contract). The `SECURITY.md` / model-default file edits went to one bounded writer
  with the six allowed surfaces, because they are a single reviewable writing unit and the parent
  keeps the branch, the commits and the PR.
- Branch policy: feature branch, then **push and a PR against `main`**, assigned to the owner
  (`emiliodavola`) — owner instruction, 2026-09-27. Merge stays the owner's decision.

## Evidence

Survey session, 2026-09-27. Commands worth keeping:

```bash
docker inspect robotina --format '{{index .Config.Labels "com.docker.compose.config-hash"}}'
docker compose config --hash='*'                     # robotina 0f595f1d… vs label 672c99a4…
docker compose up -d --dry-run                       # plans a recreate; writes nothing
docker inspect robotina --format '{{json .Mounts}}' --format '{{json .HostConfig}}'
docker exec -u hermes robotina sh -lc 'which -a engram; /usr/local/bin/engram --version; /opt/data/.local/bin/engram --version'
docker exec -u hermes robotina sh -lc 'command -v kaggle || echo "kaggle NOT on PATH"'
docker exec -u hermes robotina sh -lc 'rtk --help | head -3; rtk --version'
docker exec robotina sha256sum -u /opt/robotina/bin/opencode-delegate   # + local sha256sum
docker exec -u hermes robotina sh -c 'curl -sS -o /dev/null -m 15 -w "%{http_code}" https://www.kaggle.com'
```

Trap that cost time: Git Bash rewrites absolute in-container paths, so every `docker exec …
/some/path` needs `MSYS_NO_PATHCONV=1` or the shell reads a Windows path
(`sha256sum: 'C:/Program Files/Git/etc/squid/allowlist.txt': No such file or directory`).
