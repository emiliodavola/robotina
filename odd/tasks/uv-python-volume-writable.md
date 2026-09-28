# Feature: uv-python-volume-writable

## Goal

Close #70: the agent (uid 10000, `hermes`) MUST be able to write inside the image's managed
interpreter root, so `uv python install` and `uv sync` with `UV_PYTHON_PREFERENCE=only-managed`
stop failing with `permission denied writing /opt/uv/python/.temp`.

The interpreter root lives on the native volume `robotina_uv_python`, mounted at `/opt/uv/python`
(SL7, AC12). The phase-2 recreate window added the volume; it is `root:root` because the image baked
`/opt/uv/python` as root and nothing re-owns the mount at boot. The **location is correct and MUST
NOT move**: a path under `/opt/data` is shadowed by the bind at runtime (the baked interpreter would
be lost, and re-downloading it needs a host the egress allowlist does not carry). The defect is
**ownership**, not location.

Branch: `fix/issue-70-uv-python-volume-writable`, off `main`. Owner: `emiliodavola`.

## Non-goals

- No change to `UV_PYTHON_INSTALL_DIR`, `UV_TOOL_DIR` or `UV_TOOL_BIN_DIR`. Issue #70's first
  proposal (move the interpreter to `/opt/data/.local/share/uv/python`) is rejected here, with the
  reason recorded: the bind shadows it in runtime and the interpreter baked by the image is lost.
- No image rebuild or container recreate in this change. The fix lands on the next boot of a rebuilt
  and recreated container; proving it live belongs to the owner's phase-2 window.
- No `chown` in the Dockerfile. A build-time chown only reaches a **fresh** volume; an existing
  `robotina_uv_python` would stay root-owned. The boot-time re-own is idempotent and fixes both.

## Diagnosis (measured, read-only against the live stack, 2026-09-28)

1. `docker compose exec robotina stat -c '%U:%G %a %n' /opt/uv/python` →
   `root:root 755 /opt/uv/python`, and `/opt/uv/python/.temp` → `root:root 755` (created
   2026-09-24: a write that already failed once).
2. As the app uid: `s6-setuidgid hermes sh -c 'test -w /opt/uv/python'` → `NOT-WRITABLE`;
   `test -w /opt/uv/python/.temp` → `TEMP-NOT-WRITABLE`.
3. The image's `uv` is 0.11.6 and `UV_PYTHON_PREFERENCE=only-managed`, so any `uv sync` reaches
   `uv python install`, which writes `.temp` under the install dir.
4. Nothing re-owns the volume: `10-robotina-state` step 3 re-owns only the two SQLite volume roots
   (`/opt/data/.engram`, `/opt/data/.local/share/opencode`). The uv volume is not under `/opt/data`,
   so step 2's `find` never reaches it either.

## Shape

1. `10-robotina-state` step 3 re-owns the third volume root: `chown -R "$uid:$gid"` over
   `/opt/uv/python` too. Bounded and recursive, same treatment as the two databases.
2. The comments that describe the volume (Dockerfile §6 and the `compose.yml` volume block) say the
   boot re-own is what makes it writable.
3. Specs follow the state: `state-layout` SL7 gains the writability requirement and its proof;
   `agent-container` AC12 gains the writability assertion on the interpreter directory.
4. `SECURITY.md`'s interpreter/tooling row records that the volume is writable by the app uid.

## Tasks

- [x] T1 — Branch and this tracker.
- [x] T2 — `10-robotina-state`: re-own `/opt/uv/python` at boot (step 3: comment, chown and boot
      announcement line).
- [x] T3 — Align `robotina/Dockerfile` §6 and the `compose.yml` volume comment.
- [x] T4 — Specs: `state-layout` SL7 (writability scenario + proof) and `agent-container` AC12
      (the interpreter directory is writable by the app uid).
- [x] T5 — `SECURITY.md`: the interpreter row.
- [x] T6 — Static verification: `docker compose config -q`, `sh -n` and the container's own
      `dash -n` on the cont-init; independent read-only verifier over the diff and the spec
      assertions.
- [ ] T7 — Commit per work unit, push, PR against `main` assigned to the owner.

## Route declaration

- Classification: **substantial and authorized** (one s6 cont-init line + two specs + compose and
  Dockerfile comments + security doc).
- Delegation: one non-trivial code file (the cont-init); the rest is prose alignment. The parent
  owns the coupled slice, as `phase-2-recreate-window` did, and an independent read-only verifier
  checks the spec assertions.
- The container recreate is explicitly out of scope, exactly as in `phase-2-recreate-window`.
