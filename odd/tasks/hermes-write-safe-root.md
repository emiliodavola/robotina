# Feature: hermes-write-safe-root

## Goal

Let Hermes' file tools write inside the workspace project (`/workspace/sofer`) without
disabling its write guard and without opening `/workspace` as a whole. Today every write
outside `/opt/data` is refused, so the agent cannot touch the code it is asked to change.

Branch: `fix/hermes-write-safe-root`, off `main`. Issue:
[#22](https://github.com/emiliodavola/robotina/issues/22) (`status:approved`, assigned to
`emiliodavola`).

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

So the fix is to **widen** the list, never to replace it.

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
HERMES_WRITE_SAFE_ROOT: ${ROBOTINA_HERMES_WRITE_SAFE_ROOT:-/opt/data:/workspace/sofer}
```

`/opt/data` stays first (`HERMES_HOME` unchanged) and `/workspace/sofer` is added as one
bounded prefix.

Deliberately **not** in scope:

- `chmod`/ownership changes. `/workspace` is already `rw` and `/workspace/sofer` is already
  writable; the block is the guard, not the filesystem.
- Widening the guard to `/workspace`. The added prefix is exactly the project directory.
- Touching `HERMES_HOME`.

## Residual risk

- The default names one project (`/workspace/sofer`). A different project needs
  `ROBOTINA_HERMES_WRITE_SAFE_ROOT` in `.env`; the guard deliberately does not become "any
  workspace project".
- A container `ENV` is immutable at runtime, so the running container keeps `/opt/data` until
  the next `up -d --force-recreate`. The fix was verified by injecting the exact value into a
  probe process; the running container was **not** restarted (explicit user constraint).

## Tasks

- [x] T1 — Feature document (this file).
- [x] T2 — `compose.yml`: set `HERMES_WRITE_SAFE_ROOT` to the widened list.
- [ ] T3 — `.env.example`: document the optional override key.
- [x] T4 — `openspec/specs/agent-container/spec.md`: AC10 with runnable proofs.
- [x] T5 — Verify: `docker compose config -q`, the resolved value, and the guard with both the
      running and the widened value.
- [ ] T6 — Commit, push, PR against `main`, assigned to `emiliodavola`, linked to #22.

## Route declaration

T2 and T4 are one delegated unit (multi-file write trigger): one bounded `gentle-ai-worker`
over `compose.yml` and `openspec/specs/agent-container/spec.md`. The worker was blocked by the
harness safety policy on `.env.example` (a `.env*` path), so T3 is a parent-side manual paste
by the user. T1, T5 and T6 stay inline as parent bookkeeping and verification.

## Evidence

| Probe | Observed |
| --- | --- |
| Guard with the running `/opt/data` | `/workspace/sofer/tests/conftest.py` → `Write denied: ... outside HERMES_WRITE_SAFE_ROOT (/opt/data)` |
| Guard with `/opt/data:/workspace/sofer` | roots `['/opt/data', '/workspace/sofer']`; `/workspace/sofer/tests/conftest.py` ALLOWED; `/workspace/other/x.py` DENIED; `/opt/data/state.txt` ALLOWED; `/etc/passwd` DENIED |
| `docker compose config -q` | exit 0 |
| `docker compose config --format json \| grep -o '"HERMES_WRITE_SAFE_ROOT": *"[^"]*"'` | `"HERMES_WRITE_SAFE_ROOT": "/opt/data:/workspace/sofer"` |
