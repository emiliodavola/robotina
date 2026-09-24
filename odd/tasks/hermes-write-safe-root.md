# Feature: hermes-write-safe-root

## Goal

Let Hermes' file tools write anywhere inside the shared workspace (`/workspace`), without
disabling its write guard. Today every write outside `/opt/data` is refused, so the agent cannot
touch the code it is asked to change.

Branch: `fix/hermes-write-safe-root`, off `main`. Issue:
[#22](https://github.com/emiliodavola/robotina/issues/22) (`status:approved`, assigned to
`emiliodavola`).

## Decision (owner, 2026-09-24)

The safe root is the **whole shared workspace** (`/workspace/`), not a single project. The
earlier `/workspace/sofer` scoping was the agent's first attempt; the owner overrode it because
the workspace is the agent's work area and pinning one project would force a compose edit per
project. The guard is defense-in-depth, not a security boundary, and `/workspace` is already the
agent's `cwd` on an `rw` bind; the credential denylist keeps applying on top.

Recorded in `openspec/specs/agent-container/spec.md` AC10, which no longer claims the added
prefix is "one project, not the whole workspace".

## Diagnosis (measured against the running stack, 2026-09-24)

`HERMES_WRITE_SAFE_ROOT=/opt/data` is **not** a compose or `.env` value. It is an `ENV` baked
into the vendor image:

- `nousresearch/hermes-agent:latest` declares `ENV HERMES_WRITE_SAFE_ROOT=/opt/data`
  (`/opt/hermes/Dockerfile:429`). `robotina/Dockerfile` derives `FROM` that base and never
  overrides the variable.
- Confirmed on the live container: `docker inspect robotina --format '{{json .Config.Env}}'`
  lists the value, while `Select-String` over `compose.yml` finds nothing.
- `/opt/data` is also `HERMES_HOME`, so the vendor default is correct for agent state — it
  simply does not cover the workspace.

The guard (`/opt/hermes/agent/file_safety.py`) reads the variable as an `os.pathsep`-separated
**list**:

```python
def get_safe_write_roots() -> set[str]:
    roots: set[str] = set()
    for path in filter(None, os.getenv("HERMES_WRITE_SAFE_ROOT", "").split(os.pathsep)):
        with suppress(OSError, ValueError):
            roots.add(os.path.realpath(os.path.expanduser(path)))
    return roots
```

```python
safe_roots = get_safe_write_roots()
if safe_roots and not any(_is_under(resolved, root) for root in safe_roots):
    return "safe_root"
```

So the fix is to **widen** the list, never to replace it. Note that `get_safe_write_roots()`
runs every entry through `os.path.realpath()`, so a trailing slash is notation only: it is
stripped before the prefix comparison.

Reproduced on the live container with the running value:

```
$ docker exec -e HERMES_WRITE_SAFE_ROOT=/opt/data robotina \
    /opt/hermes/.venv/bin/python -c 'import sys; sys.path.insert(0, "/opt/hermes"); \
    from agent.file_safety import get_write_denied_error as d; \
    print(d("/workspace/sofer/tests/conftest.py"))'
Write denied: '/workspace/sofer/tests/conftest.py' is outside HERMES_WRITE_SAFE_ROOT (/opt/data). ...
```

## Shape

Set the variable from `compose.yml` — the compose `environment` block overrides the image
`ENV`, is declarative, needs no rebuild, and never touches `/opt/hermes/**`:

```yaml
HERMES_WRITE_SAFE_ROOT: ${ROBOTINA_HERMES_WRITE_SAFE_ROOT:-/opt/data/:/workspace/}
```

`/opt/data/` stays first (`HERMES_HOME` unchanged) and `/workspace/` joins as the work root.
Both entries are directories, so both carry a trailing slash.

Deliberately **not** in scope:

- `chmod`/ownership changes. `/workspace` is already `rw` and its contents are already
  writable; the block is the guard, not the filesystem.
- Narrowing the safe root to one project. The decision above is the whole workspace.
- Touching `HERMES_HOME`.

## Residual risk

- The guard no longer separates projects inside the workspace: any project mounted under
  `/workspace` is writable. The credential denylist (`/etc/passwd`, `<HERMES_HOME>/.env`, the
  home-dir prefixes) still applies regardless of the safe root, and that is what AC10's
  credential scenario pins down.
- `.env` overrides the default on this host; it now carries the canonical
  `/opt/data/:/workspace/` form. `os.path.realpath()` normalizes the trailing slashes, so the
  literal and the effective roots agree.
- `_is_under` uses a string-prefix test, so a root directory itself is not "under" itself;
  writes target files inside the roots, which is the normal case.
- A container `ENV` is immutable at runtime, so the running container keeps `/opt/data` until
  the next `up -d --force-recreate`. The fix was verified by injecting the exact value into a
  probe process; the running container was **not** restarted (explicit user constraint).

## Tasks

- [x] T1 — Feature document (this file).
- [x] T2 — `compose.yml`: set `HERMES_WRITE_SAFE_ROOT` to the widened list.
- [x] T3 — `.env.example`: document the optional override key (pasted manually by the user; the
      harness blocks `.env*` edits).
- [x] T4 — `openspec/specs/agent-container/spec.md`: AC10 with runnable proofs.
- [x] T5 — Verify: `docker compose config -q`, the resolved value, and the guard with both the
      running and the widened value.
- [x] T6 — Commit, push, PR against `main`, assigned to `emiliodavola`, linked to #22 →
      [#23](https://github.com/emiliodavola/robotina/pull/23).

## Route declaration

T2 and T4 are one delegated unit (multi-file write trigger): one bounded `gentle-ai-worker`
over `compose.yml` and `openspec/specs/agent-container/spec.md`. The worker was blocked by the
harness safety policy on `.env.example` (a `.env*` path), so T3 is a parent-side manual paste by
the user. T1, T5 and T6 stay inline as parent bookkeeping and verification.

## Evidence

| Probe | Observed |
| --- | --- |
| Guard with the running `/opt/data` | `/workspace/sofer/tests/conftest.py` → `Write denied: ... outside HERMES_WRITE_SAFE_ROOT (/opt/data)` |
| Guard with `/opt/data/:/workspace/` | roots `['/opt/data', '/workspace']`; `/workspace/sofer/tests/conftest.py` ALLOWED; `/tmp/x.py` DENIED (`safe_root`); `/opt/data/state.txt` ALLOWED; `/etc/passwd` DENIED (`credential`); `/opt/data/.env` DENIED (`credential`) |
| `docker compose config -q` | exit 0 |
| `ROBOTINA_HERMES_WRITE_SAFE_ROOT= docker compose config --format json \| grep -o '"HERMES_WRITE_SAFE_ROOT": *"[^"]*"'` | `"HERMES_WRITE_SAFE_ROOT": "/opt/data/:/workspace/"` (the compose default, with any `.env` override shadowed) |
| `docker compose config --format json \| grep -o '"HERMES_WRITE_SAFE_ROOT": *"[^"]*"'` | `"HERMES_WRITE_SAFE_ROOT": "/opt/data/:/workspace/"` (this host, the `.env` override, now in the canonical form) |

### Finding: `/opt/data/.ssh/id_rsa` is not a stable credential probe

The natural-looking probe `d("/opt/data/.ssh/id_rsa")` returns **allowed** under `docker exec`,
because the guard builds its home set from the *process* `HOME`, which is `/root` for a root
`exec` (`_guard_homes()` starts from `os.path.expanduser("~")`). The credential denylist only
covers homes it knows about. AC10's proof therefore uses `/etc/passwd` and `/opt/data/.env`,
both of which classify as `credential` independently of the process home.
