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
- A container `ENV` is immutable at runtime, so the value only takes effect after
  `up -d --force-recreate`. This work verified the guard by injecting the exact value into a
  probe process and never restarted the container (explicit user constraint); the owner
  recreated it afterwards, and the live proofs below were then run against the running
  container.

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
- [x] T7 — Live verification after the owner's `up -d --force-recreate`, against the running
      container instead of an injected probe.

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

### Live verification after the owner's recreate (2026-09-24)

The owner recreated the container (`docker inspect` → `running`, `healthy`). Every AC10 proof
was then run against the container itself, with no injected environment.

| Probe | Observed |
| --- | --- |
| `docker compose exec -T robotina printenv HERMES_WRITE_SAFE_ROOT` | `/opt/data/:/workspace/` |
| `docker compose exec -T robotina printenv HERMES_HOME` | `/opt/data` |
| AC10 s2 — workspace allowed, outside every root denied | `True True` |
| AC10 s3 — `HERMES_HOME` still writable | `True` |
| AC10 s4 — credential denylist intact | `True True` |
| AC10 s5 — roots normalized | `['/opt/data', '/workspace']` |
| Real write as `hermes` in `/workspace/sofer` | probe file written, read back and removed (`uid=10000(hermes)`) |
| Real write as `hermes` in `/opt/data` | probe file written, read back and removed |

The two real writes are the end-to-end check the original request asked for; both probe files
were removed after reading them back, so no project file was touched.

### Finding: `/opt/data/.ssh/id_rsa` is not a stable credential probe

The natural-looking probe `d("/opt/data/.ssh/id_rsa")` returns **allowed** under `docker exec`,
because the guard builds its home set from the *process* `HOME`, which is `/root` for a root
`exec` (`_guard_homes()` starts from `os.path.expanduser("~")`). The credential denylist only
covers homes it knows about. AC10's proof therefore uses `/etc/passwd` and `/opt/data/.env`,
both of which classify as `credential` independently of the process home.
