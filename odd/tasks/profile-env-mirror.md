# Feature: profile-env-mirror

## Goal

Make the stack survive a container recreate without locking its own owner out and without losing
the model credential. Two symptoms were measured on 2026-09-28, both caused by one hidden change in
the vendor's gateway: it now runs in **multiplex** mode, and under multiplex the runtime reads the
credentials and gates it needs from the **profile secret scope** (`~/.hermes/.env`), never from the
container environment.

Branch: `fix/profile-env-mirror`, off `main`. Owner: `emiliodavola`.

## Diagnosis (measured, not inferred)

The gateway was recreated and, with it, re-read `config.yaml`, where
`gateway.multiplex_profiles: true` (the vendor persists that default, `auto_multiplex_migration`
writes it, and an explicit `false` is **retired as an opt-out** — it resolves exactly like an unset
key). The long-running process had been grandfathered into standalone mode
(`served_profiles: []`, reason *"only one profile exists (nothing to multiplex)"*); the new one came
up multiplexed (`served_profiles: ["default"]`).

Under multiplex, `gateway/platforms/_shared.py::platform_gate_env` and `agent/secret_scope.py::
get_secret` read the **profile scope**, and on a miss they return the default instead of falling
through to `os.environ`, on purpose: falling through would leak another profile's value
(`#72348`). The scope is built by `build_profile_secret_scope()` from each profile's `.env`. The
default profile's `.env` (`/opt/data/.env`) had **neither** of the two keys the stack injects
through compose:

| Symptom | Key | Evidence |
| --- | --- | --- |
| The bot ignored its own owner | `TELEGRAM_ALLOWED_USERS` | `[Telegram] Blocked unauthorized user …` on every message, while the gateway **process** demonstrably had the variable in its environment |
| *"I couldn't connect to the AI model service"* | `OPENCODE_GO_API_KEY` | `gateway.run: Model resolution failed … No usable credentials found for provider 'opencode-go'. Set OPENCODE_GO_API_KEY.` |

Two details that make this hard to diagnose by hand, and that belong in the record:

- `hermes doctor` reports **"OpenCode Go (key configured)"** because it inspects the process
  environment. The credential is there; it is simply not where the runtime now looks.
- `TELEGRAM_BOT_TOKEN` keeps working without being in the profile `.env`, because the adapter reads
  it straight from `os.environ`. So the failure is not "all container env is ignored" — it is
  precisely "everything the runtime reads through the fail-closed scoped path".

## Non-goals

- **Not reverting multiplex.** `multiplex_profiles: false` is retired upstream; adopting the mode is
  the only stable direction.
- Not mirroring the whole container environment into the profile `.env`. Only what the runtime reads
  through the scoped path, and each addition has to name the read site that needs it.
- Not touching `TELEGRAM_BOT_TOKEN` (measured: read from `os.environ`, so mirroring it would only
  widen the secret's surface).

## Shape

One cont-init, `50-robotina-profile-env`, in the same family as `30-robotina-model` (which already
writes `config.yaml` from the container environment on every boot):

1. For each key in an explicit, overridable list, take the value from the container environment.
2. Skip when the profile `.env` already carries that value (idempotent: no mtime churn per boot).
3. Otherwise write it with the vendor's own `save_env_value()` — the same writer the dashboard uses,
   which updates the existing line instead of appending a duplicate — running as the app uid.
4. Never fatal, never prints a value, and says in the log which key changed.

The list is a variable (`ROBOTINA_PROFILE_ENV_KEYS`) so adding the next scoped key is a one-line
change with its own evidence.

## Tasks

- [x] T1 — Branch and this tracker.
- [x] T2 — `50-robotina-profile-env` with the explicit list, the idempotency guard, the vendor
      writer, and non-fatal error handling.
- [x] T3 — Spec: CR7 in `agent-credentials` — the profile `.env` is part of the credential contract,
      and it is refreshed at boot.
- [x] T4 — Verify: syntax with the container's own `dash`, the idempotency path against the live
      file, and the write path against a throwaway file.
- [ ] T5 — Commits per work unit, push, PR against `main` assigned to the owner, and the issue that
      documents the defect class.

## Note on the live state

Both keys were written to the profile `.env` by hand (with the vendor's writer) to restore the bot
before this change existed; backup at `/opt/data/.env.bak-20260927-225028`. This cont-init is what
makes that survive the next recreate instead of depending on someone noticing in time.
