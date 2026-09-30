# agent-credentials Specification

## Purpose

Define the observable properties of the credential model after the merge: two independent
API-key inputs in the gitignored `.env`, each process configured with only its own key under
the vendor-expected variable name, `GITHUB_TOKEN` present in the merged container, the
"Hermes has no GitHub credential" invariant formally retired, and the honest statement that
per-process key isolation is **not enforceable** at equal uid.

This domain is **new**: `openspec/specs/` was empty before this change, so this file is a
full domain spec and is copied verbatim into `openspec/specs/agent-credentials/spec.md` at
archive time.

Artifact language: English (proposal §16).

## Verification model

There is no test runner in this repository (`openspec/config.yaml` → `testing.runner: none`).
Every scenario names the exact shell-level observation that proves it.

- Static recipes MUST use `docker compose config -q`; the bare form prints resolved `.env`
  secrets (proposal §9 risk 8, §9 risk 9) and is forbidden anywhere in this change.
- **Secret safety**: no recipe may print a secret value. Key-distinctness is asserted with
  `sha256sum` over the `NAME=value` line only.
- **No vacuous passes.** A `pgrep`/`grep` probe that matches nothing is a FAILURE.
- `pgrep`/`pkill` patterns MUST use a character-class form (`[h]ermes gateway`,
  `[o]pencode serve`) so the probe shell's own command line cannot match itself, and a recipe
  that substitutes a single pid MUST take `head -1` and assert the pid is non-empty and is not
  `$$`.
- Host-side reference hashes read `.env` and strip CRLF (`tr -d "\r"`), because `.env` may
  have Windows line endings; without that, a correct implementation would fail spuriously.

Named recipes used below:

`KEY-PROBE` (in-container, prints nothing secret; each loop MUST print at least one line — an
empty loop is a FAILURE, and the character-class patterns keep the probe shell's own command
line from matching itself):

```sh
docker compose exec robotina sh -c '
  for p in $(pgrep -f "[o]pencode serve"); do echo "opencode: $(tr "\0" "\n" < /proc/$p/environ | grep "^OPENCODE_GO_API_KEY=" | sha256sum)"; done
  for p in $(pgrep -f "[h]ermes gateway"); do echo "hermes:   $(tr "\0" "\n" < /proc/$p/environ | grep "^OPENCODE_GO_API_KEY=" | sha256sum)"; done'
```

`KEY-REFERENCE` (host-side hashes of the two `.env` inputs, prints nothing secret):

```sh
grep -m1 "^HERMES_OPENCODE_GO_API_KEY=" .env | tr -d "\r" | sed "s/^HERMES_//" | sha256sum   # must equal the hermes hash
grep -m1 "^OPENCODE_GO_API_KEY="        .env | tr -d "\r" | sha256sum                        # must equal the opencode hash
```

`CLI-KEY-PROBE` (in-container; prints only sha256 hashes; rewrites the wrapper's `exec` target to a stub so the real CLI is never launched and no model call is made, and clears `ROBOTINA_OPENCODE_GO_API_KEY` for the last line only):

```sh
docker compose exec -T robotina sh -c '
  stub=/tmp/cli-key-stub; wrap=/tmp/cli-key-wrap
  printf "%s\n" "#!/bin/sh" "printf %s \"\$OPENCODE_GO_API_KEY\" | sha256sum" > "$stub"
  chmod 0755 "$stub"
  sed "s#^exec /usr/local/bin/opencode#exec $stub#" /opt/robotina/bin/opencode > "$wrap"
  chmod 0755 "$wrap"
  echo "via-wrapper:    $("$wrap")"
  echo "opencode-input: $(printf %s "$ROBOTINA_OPENCODE_GO_API_KEY" | sha256sum)"
  echo "hermes-input:   $(printf %s "$OPENCODE_GO_API_KEY" | sha256sum)"
  echo "passthrough:    $(env -u ROBOTINA_OPENCODE_GO_API_KEY "$wrap")"'
```

## Requirements

### Requirement: CR1 — Two independent API-key inputs

`.env` SHALL keep two independently settable inputs, `HERMES_OPENCODE_GO_API_KEY` (Hermes)
and `OPENCODE_GO_API_KEY` (OpenCode). `.env.example` SHALL document both names and no value.

#### Scenario: Both names exist and are independently settable

- GIVEN the merged compose file and the example env file
- WHEN both files are searched for the two names
- THEN both names are present in each file as distinct inputs
- PROOF: `git grep -n "HERMES_OPENCODE_GO_API_KEY\|OPENCODE_GO_API_KEY" -- .env.example compose.yml`
  (both names appear; no literal value appears)

#### Scenario: No secret value is committed

- GIVEN the change set
- WHEN tracked files are searched for a populated secret assignment
- THEN nothing is found
- PROOF: `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'`
  (no output, exit non-zero)

#### Scenario: Documented names survive a real rendering

- GIVEN a `.env` with distinct values for both inputs
- WHEN compose validates the merged file
- THEN validation succeeds without printing any value
- PROOF: `docker compose config -q` (exit 0; the bare form is forbidden)

### Requirement: CR2 — Hermes' process is configured with the Hermes key only

The Hermes main program SHALL see `OPENCODE_GO_API_KEY` set to the **Hermes** input, under
that vendor-expected name.

#### Scenario: The Hermes process environment hash equals the Hermes input hash

- GIVEN the stack is up with distinct values in `.env`
- WHEN the Hermes process environment is hashed and compared with the host-side reference
- THEN both hashes are equal
- PROOF: `KEY-PROBE` then `KEY-REFERENCE` — the `hermes:` line MUST equal the first reference hash
- NOTE: the `[h]ermes gateway` loop matching nothing is a FAILURE (no vacuous pass), and the
  character-class form is required so the probe shell's own command line cannot match itself.
  If the merged runtime execs Hermes through a shim, confirm the real command line once inside
  the container with `pgrep -af "[h]ermes"` (the character-class form of design §19.2's
  `pgrep -af hermes` confirmation), then name the corrected pattern and update this recipe and
  `KEY-PROBE` in the same commit.

#### Scenario: Hermes does not see the OpenCode input

- GIVEN the stack is up with two different values
- WHEN the Hermes process's vendor-named value is compared with the OpenCode process's
- THEN the two hashes differ
- PROOF: `KEY-PROBE` (the `hermes:` and `opencode:` lines MUST differ)

### Requirement: CR3 — The OpenCode process is configured with the OpenCode key only, process-scoped

The OpenCode server process SHALL see `OPENCODE_GO_API_KEY` set to the **OpenCode** input.
The assignment SHALL be scoped to that process launch (not made container-wide by patching a
vendor file), and the process SHALL NOT receive the Hermes value under that name.

#### Scenario: The OpenCode process environment hash equals the OpenCode input hash

- GIVEN the stack is up with distinct values in `.env`
- WHEN the OpenCode process environment is hashed and compared with the host-side reference
- THEN both hashes are equal
- PROOF: `KEY-PROBE` then `KEY-REFERENCE` — the `opencode:` line MUST equal the second reference hash

#### Scenario: The two processes demonstrably carry different values

- GIVEN the stack is up with distinct values in `.env`
- WHEN both process environments are hashed in one command
- THEN two different hashes are printed and no secret value is printed
- PROOF: `KEY-PROBE` (two non-identical hashes; output contains only hashes)

#### Scenario: Overriding the vendor name happens in the process launch, not in a vendor file

- GIVEN the merged change
- WHEN the change set is inspected for writes into the vendor application tree
- THEN no vendor file under `/opt/hermes` is patched by the Dockerfile or the s6 scripts
- PROOF: `git grep -nE '(sed|cat|tee|cp)[^\n]*([/]opt/hermes/(bin|\.venv|docker))' -- robotina/ compose.yml`
  (no output, exit non-zero)

### Requirement: CR4 — No secret is echoed, logged, or written to a tracked file

No secret value SHALL be echoed, logged, or written into a tracked file by any script,
document, or verification recipe. Verification recipes SHALL use `docker compose config -q`.

#### Scenario: No tracked file carries a real secret value

- GIVEN the change set
- WHEN tracked files are searched for populated secret assignments
- THEN nothing is found
- PROOF: `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'`
  (no output, exit non-zero)

#### Scenario: The container log stream carries no secret

- GIVEN the stack is up and has served at least one delegation
- WHEN the container logs are searched for secret-shaped assignments
- THEN nothing is found
- PROOF: `docker compose logs robotina 2>&1 | grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN|OPENCODE_SERVER_PASSWORD)='`
  (no output, exit non-zero)

#### Scenario: No recipe written by this change uses the secret-printing static-validation form

- GIVEN the merged change
- WHEN the recipes written by this change are inspected
- THEN every occurrence of the static-validation command in a recipe-bearing file carries `-q`
  (or `--services`/`--format`) on the same line
- PROOF: `git grep -n "docker compose config" -- README.md README.en.md SECURITY.md scripts/ openspec/changes/single-robotina-container/design.md | grep -vE "config (-q|--services|--format)"` (no output, exit non-zero) — the rule being enforced is that the static-validation command appears as `config -q` (or `--services`/`--format`) on the same line
- SCOPE: the pathspec is deliberately limited to recipe-bearing files — the two READMEs,
  `SECURITY.md`, `scripts/`, and this change's own `design.md` (`tasks.md` is appended once it
  exists). The frozen explainer artifacts `openspec/changes/single-robotina-container/proposal.md`
  and `explore.md` are excluded on purpose: they are frozen inputs whose risk rows describe the
  dangerous form as prose, they carry no executable recipe, and a line-scoped grep would report
  them even though nothing is wrong. Frozen prose cannot be reworded, so scoping is the only form
  of this proof that can pass.
- NOTE: the spec files under `openspec/changes/single-robotina-container/specs/` are covered by
  the same authoring rule and were audited against it line by line. They are kept out of the
  pathspec because the negative filter below quotes the static-validation command, so the proof
  line would report itself.
- AUTHORING RULE (adopted by design §19.3 and binding on this change): in every artifact this
  change writes, any mention of the static-validation command carries `-q` (or
  `--services`/`--format`) on the same line, and the dangerous bare form is referred to by
  description rather than written literally.

### Requirement: CR5 — `GITHUB_TOKEN` is present and the retired invariant is stated

`GITHUB_TOKEN` SHALL remain available inside `robotina` (frozen: D3), and the "Hermes has no
GitHub credential" invariant SHALL be formally retired in `SECURITY.md`. The token's scope
SHALL NOT be narrowed by this change (frozen: proposal §17 answer 1).

#### Scenario: The token is present in the merged container

- GIVEN `GITHUB_TOKEN` is set in the gitignored `.env` and the stack is up
- WHEN the container environment is probed without printing the value
- THEN the variable is non-empty
- PROOF: `docker compose exec robotina sh -c 'test -n "$GITHUB_TOKEN" && echo present'`

#### Scenario: No document or skill still claims Hermes has no GitHub credential

- GIVEN the merged change
- WHEN the always-loaded context, the Hermes skills and the docs are searched for the retired claim
- THEN nothing is found
- PROOF: `grep -rniE "sin credencial|no github credential|no tiene token|delegate to opencode|delegar a opencode|does not run inside this container|no esta instalado|no rewrite" hermes/ SECURITY.md`
  (no output, exit non-zero)

#### Scenario: SECURITY.md states the retained GitHub reach and the kept PAT

- GIVEN the merged change
- WHEN `SECURITY.md` is read for the credential entry
- THEN it states that every process in the container — including the Telegram-facing agent —
  can reach GitHub with the PAT, and that the PAT is kept as-is
- PROOF: `grep -niE "GITHUB_TOKEN" SECURITY.md` (non-empty) plus the human check in CR7

### Requirement: CR6 — The non-isolation of per-process keys is stated honestly

`SECURITY.md` SHALL state explicitly that per-process API-key isolation is **not enforceable**
in a single container at equal uid. The acceptance criterion SHALL be expressed as "each
process is configured with only its own key" and SHALL NEVER be expressed as "neither process
can read the other's key" (proposal §6.2 R2).

#### Scenario: The limitation is documented

- GIVEN the merged change
- WHEN `SECURITY.md` is read for the isolation entry
- THEN a statement of non-enforceability at equal uid is present
- PROOF: `grep -niE "mismo uid|equal uid|no se puede aislar|not enforceable|misma identidad" SECURITY.md`
  (non-empty)

#### Scenario: No document claims an isolation guarantee

- GIVEN the merged change
- WHEN the docs are searched for an affirmative isolation claim about the keys
- THEN nothing is found
- PROOF: `grep -rniE "claves? (estan |están )?aislad|keys? are isolated|aisladas por proceso|isolated per process|no puede leer la clave del otro|cannot read the other" README.md README.en.md SECURITY.md hermes/`
  (no output, exit non-zero)

### Requirement: CR7 — The accepted credential regressions are signed off

The user SHALL have confirmed understanding of the accepted credential regressions
(proposal §6.2 R1 and R2, §13 items 1, 2 and 7). This is a **human check**, not a shell recipe.

#### Scenario: Human check — the credential regressions are understood

- GIVEN the change is ready for verification
- WHEN the reviewer reads the R1/R2 entries in `SECURITY.md`
- THEN the reviewer confirms that (a) prompt injection into the Telegram bot can reach GitHub
  with the kept PAT and (b) the two keys are not isolated from each other at equal uid
- PROOF: human check (no shell command). The shell-verifiable prerequisites are CR5's
  `grep -niE "GITHUB_TOKEN" SECURITY.md` and CR6's non-enforceability grep.

### Requirement: CR8 — A locally invoked `opencode` CLI resolves OpenCode's own key

The `opencode` CLI invoked from the agent's shell SHALL authenticate with the **OpenCode** input
(`ROBOTINA_OPENCODE_GO_API_KEY`), never with the Hermes input that the container-level
`OPENCODE_GO_API_KEY` carries. The CLI has **no credential store** of its own, so the assignment
SHALL be provided by the `PATH` wrapper `/opt/robotina/bin/opencode`, which re-exports
`OPENCODE_GO_API_KEY` from `ROBOTINA_OPENCODE_GO_API_KEY` before executing the real binary. When
`ROBOTINA_OPENCODE_GO_API_KEY` is unset the wrapper SHALL exec the real binary unchanged
(pass-through) rather than fail, and it SHALL print no credential value at any time.

#### Scenario: The wrapper hands the CLI the OpenCode key

- GIVEN the stack is up with distinct values for both inputs and the wrapper is installed at
  `/opt/robotina/bin/opencode`
- WHEN the wrapper is run against a stub that hashes `OPENCODE_GO_API_KEY`, with
  `ROBOTINA_OPENCODE_GO_API_KEY` set
- THEN the printed hash equals the hash of `ROBOTINA_OPENCODE_GO_API_KEY` and differs from the
  hash of the container's `OPENCODE_GO_API_KEY`
- PROOF: `CLI-KEY-PROBE` — the `via-wrapper:` line MUST equal the `opencode-input:` line and MUST
  differ from the `hermes-input:` line

#### Scenario: The wrapper degrades to a pass-through when its input is unset

- GIVEN the wrapper is installed and `ROBOTINA_OPENCODE_GO_API_KEY` is not exported to it
- WHEN the same stub is run without that variable
- THEN the stub sees the untouched container value
- PROOF: `CLI-KEY-PROBE` — the `passthrough:` line MUST equal the `hermes-input:` line

#### Scenario: The wrapper wins on `PATH` and prints no credential

- GIVEN the merged image
- WHEN the CLI is resolved from `PATH` and run
- THEN it resolves to the wrapper under the root-owned `/opt/robotina/bin` (ahead of
  `/usr/local/bin/opencode` and of the agent-writable `/opt/data/.local/bin`), and neither the
  resolution nor the wrapper emits a credential value
- PROOF: `docker compose exec -T robotina sh -c 'command -v opencode'` (prints
  `/opt/robotina/bin/opencode`) and `docker compose exec -T robotina sh -c 'opencode --version'`
  (prints the version only: no key, no extra wrapper output).

### Requirement: CR9 — A locally invoked `opencode` CLI resolves the stack's own identity

The `PATH` wrapper `/opt/robotina/bin/opencode` SHALL pin `HOME=/opt/data` and the four `XDG_*`
variables (`XDG_CONFIG_HOME=/opt/data/.config`, `XDG_DATA_HOME=/opt/data/.local/share`,
`XDG_STATE_HOME=/opt/data/.local/state`, `XDG_CACHE_HOME=/opt/data/.cache`) for the process it
executes, so that a CLI invoked from an environment whose `HOME` differs still loads the merged
stack configuration. The pin SHALL be scoped to the executed process and SHALL NOT modify the
container environment.

The Hermes terminal snapshot exports `HOME="/opt/data/home"`
(`/opt/data/cache/scratch/hermes-snap-*.sh`). Without the pin the CLI resolves its config and
state under that directory instead: measured, `opencode debug paths` reports
`config /opt/data/home/.config/opencode` and `data /opt/data/home/.local/share/opencode`, and
`opencode debug config` reports `mcp: null` with no `permission` block. A server launched that way
therefore has no MCP servers and no permission policy, and a tool call reaching outside its own
cwd hits the default `external_directory: ask` and never returns — no human sits at that prompt,
so `info.finish` stays `null` and the turn never completes.

#### Scenario: The wrapper pins the identity when `HOME` differs

- GIVEN the stack is up and the wrapper is installed at `/opt/robotina/bin/opencode`
- WHEN the CLI is resolved from `PATH` with `HOME` set to the Hermes snapshot value
- THEN `opencode debug paths` reports the config and data paths under `/opt/data`
- PROOF: `docker compose exec -T -u hermes robotina sh -c 'HOME=/opt/data/home; export HOME; opencode debug paths'`
  (the `config` and `data` lines MUST begin with `/opt/data/` and MUST NOT contain `/opt/data/home/`;
  a `/opt/data/home` path or an error is a FAILURE)

#### Scenario: The pinned identity loads the merged configuration

- GIVEN the same `HOME` override
- WHEN the resolved configuration is printed
- THEN the MCP servers and the permission policy from the merged config are present
- PROOF: `docker compose exec -T -u hermes robotina sh -c 'export HOME=/opt/data/home; opencode debug config > /tmp/cr9-config.json; python3 -c "import json; d=json.load(open(\"/tmp/cr9-config.json\")); mcp=d.get(\"mcp\") or {}; assert \"codegraph\" in mcp and \"engram\" in mcp, mcp; assert d.get(\"permission\"), \"no permission\"; print(\"mcp:\", sorted(mcp)); print(\"permission: present\")"'`
  (must print the `mcp:` line listing `codegraph` and `engram` and the `permission: present` line; an
  assertion error or a non-zero exit is a FAILURE)
- NOTE: the output MUST be redirected to a file before it is parsed. `opencode debug config` caps its
  stdout at exactly 65536 bytes when stdout is a pipe, and the merged configuration is ~165 kB, so a
  piped read is truncated mid-string and the `mcp` block — which sits near the end — never arrives.
  Measured: piped, exactly 65536 bytes and `json.load` raises `Unterminated string`; redirected to a
  file, 345638 bytes of valid JSON. The cap applies to any future proof built on this command.

#### Scenario: A delegation under the hostile `HOME` completes

- GIVEN the same `HOME` override
- WHEN a bounded task is delegated against a throwaway git repository under `/tmp`
- THEN the file is mutated, which a run with a stub config cannot achieve
- PROOF: `docker compose exec -T -u hermes robotina sh -c 'set -e; export HOME=/opt/data/home; d=$(mktemp -d /tmp/cr9.XXXXXX); cd "$d"; git init -q; git config user.email cr9@robotina.local; git config user.name cr9; printf "def add(a, b):\n    return a - b\n" > calc.py; git add calc.py; git commit -qm init; opencode run --agent build -m opencode-go/deepseek-v4-flash "Fix the bug in calc.py so add() adds. Do not change anything else." >run.log 2>&1; grep -n "return a + b" calc.py'`
  (must print the corrected line; empty output or a non-zero exit is a FAILURE. The log goes to the
  throwaway directory, never to `/tmp`: a `/tmp` path left by an earlier root-run probe is root-owned
  and the next `hermes`-user run then fails on the redirect instead of on the delegation)

#### Scenario: The merged `engram` MCP entry points at the pinned binary

- GIVEN the change is applied
- WHEN the source overlay and the merged configuration are read
- THEN the overlay declares `mcp.engram.command[0] = /usr/local/bin/engram`, and the merged config
  resolves the same absolute path
- PROOF: `grep -c '"/usr/local/bin/engram"' robotina/overlay.json` (must be ≥ 1) together with
  `docker compose exec -T robotina python3 -c "import json;print(json.load(open('/opt/data/.config/opencode/opencode.json'))['mcp']['engram']['command'][0])"`
  (must print `/usr/local/bin/engram`; a value under `/opt/data` is a FAILURE — that is the shadow AC11
  quarantines, not the binary the image pins)
- NOTE: measured origin (#77): the server reported the `engram` MCP as `failed` with
  `ENOENT posix_spawn '/opt/data/.local/bin/engram'`. The merged config is produced by `opencode-init`
  at container start, so the overlay-authored value becomes the served one only after a rebuild plus
  `--force-recreate`; until then the overlay's key-wins semantics are proved without touching the
  running stack with
  `docker run --rm --entrypoint sh robotina:local -c 'cat /opt/gentle-ai-stage/.config/opencode/opencode.json' | jq -s '.[0] as $b | .[1] as $o | ($b * $o) | .mcp = (($b.mcp // {}) * ($o.mcp // {})) | .mcp.engram.command[0]' - robotina/overlay.json`
  (must print `/usr/local/bin/engram` — the overlay's value, not the stage's)

### Requirement: CR10 — The keys the runtime reads through the profile scope live in the profile's `.env`

Keys that the gateway reads through the **profile secret scope** — rather than from the container
environment — SHALL be present in the default profile's `.env` (`/opt/data/.env`), and a boot step
SHALL keep them in sync with the container environment, because those values are what the stack
declares. The mirrored set SHALL be explicit, and a key is added to it only together with the read
site that needs it. Keys the adapter reads straight from `os.environ` SHALL NOT be mirrored: the
point is to satisfy the fail-closed scoped read, not to duplicate the whole environment.

Measured origin (2026-09-28). Under `gateway.multiplex_profiles: true` — the vendor's persisted
default, whose explicit `false` is retired as an opt-out — `platform_gate_env()` and `get_secret()`
return the default on a scope miss instead of falling through to `os.environ`, to avoid leaking
another profile's value (#72348). The scope is built by `build_profile_secret_scope()` from each
profile's `.env`. With that file carrying neither key, one recreate produced two silent failures:

- the Telegram allowlist went empty → `Blocked unauthorized user` for the owner's own id, while the
gateway process demonstrably had the variable in its environment;
- the model credential went missing → `Model resolution failed … No usable credentials found for
provider 'opencode-go'. Set OPENCODE_GO_API_KEY.`

`hermes doctor` catches neither, because it inspects the process environment: it reported the
OpenCode Go key as configured while the runtime could not find it.

#### Scenario: Every mirrored key is present in the profile's `.env`

- GIVEN the container is up
- WHEN the profile's env file is inspected for each key of the mirrored set
- THEN each key appears exactly once
- PROOF:
  `docker compose exec -T robotina sh -c 'for k in OPENCODE_GO_API_KEY TELEGRAM_ALLOWED_USERS; do printf "%s: " "$k"; grep -c "^$k=" /opt/data/.env; done'`
  (each count must be exactly `1`; `0` is a FAILURE)

#### Scenario: The profile's value equals the container's, compared without printing it

- GIVEN the same keys
- WHEN the two values are compared
- THEN they are identical
- PROOF:
  `docker compose exec -T robotina sh -c 'a=$(printf "%s" "$OPENCODE_GO_API_KEY" | tr -d "\r\n" | sha256sum); b=$(grep -m1 "^OPENCODE_GO_API_KEY=" /opt/data/.env | cut -d= -f2- | tr -d "\r\n" | sha256sum); [ "$a" = "$b" ] && echo MATCH || echo MISMATCH'`
  (must print `MATCH`; a `docker inspect`-based comparison is forbidden because it prints the value)

#### Scenario: The boot step is idempotent, non-fatal, and scoped by home

- GIVEN the keys are already mirrored
- WHEN the boot step runs again
- THEN it reports no change, does not rewrite the file, and exits `0`
- GIVEN a key that is absent from the environment
- WHEN the step runs
- THEN it warns and still exits `0`
- PROOF:
  `docker compose exec -T robotina sh -s < robotina/s6/cont-init.d/50-robotina-profile-env` twice
  (both exits `0`; the second prints `ya esta espejada` for each mirrored key) and
  `docker compose exec -T -e ROBOTINA_PROFILE_ENV_KEYS=NO_EXISTE_ESTA_KEY robotina sh -s < robotina/s6/cont-init.d/50-robotina-profile-env`
  (must exit `0`)
- NOTE: `ROBOTINA_PROFILE_ENV_HOME` redirects both the comparison and the write, so the write path
  can be exercised against a throwaway home (`ROBOTINA_PROFILE_ENV_HOME=/tmp/probehome`) instead of
  the agent's file. Measured: it writes the key there and is idempotent on the second run.

#### Scenario: A key read from `os.environ` is not part of the mirrored set

- GIVEN `TELEGRAM_BOT_TOKEN` is read straight from the process environment and works without the
  mirror
- WHEN the mirrored set is read
- THEN the token is not in it
- PROOF:
  `grep -E '^KEYS=' robotina/s6/cont-init.d/50-robotina-profile-env | grep -c 'TELEGRAM_BOT_TOKEN'`
  (must be `0`; the header prose mentions the token deliberately, so the assertion names the set,
  not the file)

### Requirement: CR11 — The Hugging Face token reaches the container under the name the client reads

`.env` SHALL accept an optional `ROBOTINA_HF_TOKEN` with an empty default, and the `robotina` service
SHALL publish it to the container as `HF_TOKEN` — the name `huggingface_hub` reads, so neither `hf auth
login` nor a credentials file is involved. The host-facing name carries the `ROBOTINA_` prefix, the rule
every host-facing key here follows (CR1). The default SHALL be written with the `:-` form, because that is
what keeps the credential optional: an unset token leaves the CLI anonymous and the Hub answers 401/403 at
the moment of use, which is a read failure the agent reports, not a boot failure. `ROBOTINA_HF_TOKEN` SHALL
be documented in `.env.example` with no value, next to the GitHub PAT.

The credential exists for the capability, not for a present gate. Measured anonymously on 2026-09-30,
`https://huggingface.co/api/models/google/gemma-4-31B-it-qat-w4a16-ct` answers `"gated": false` and
`"private": false`, so the repository is public today and its weights are readable without a token; there
is no acceptance step to perform on huggingface.co while the gate is off. The credential SHALL still be
required for the capability it grants — the repository owner can activate a gate at any time and the licence
terms still apply — so this requirement asserts the credential and its honest status, not an acceptance
step. The documentation SHALL record that status where the credential is described, and the repository SHALL
NOT be documented as gated while the API reports otherwise.

#### Scenario: Both names exist and are independently settable

- GIVEN the change is applied
- WHEN the two files are searched for the two names
- THEN `ROBOTINA_HF_TOKEN` appears in `.env.example` and `HF_TOKEN` appears in `compose.yml`, with no
  literal value in either
- PROOF: `git grep -n "ROBOTINA_HF_TOKEN\|HF_TOKEN" -- .env.example compose.yml`
  (both names present in the expected files, no value after either)
- NOTE: the `.env.example` half of this recipe is PENDING on a hand edit the repository owner is making on
  this same branch — measured before that edit, `compose.yml:166` carries
  `HF_TOKEN: ${ROBOTINA_HF_TOKEN:-}` while `.env.example` still has no `ROBOTINA_HF_TOKEN=` line. The
  recipe is written for the merged state and is not runnable until the edit lands.

#### Scenario: The empty default is what keeps the start unconditional

- GIVEN the `robotina` service's environment
- WHEN the published token's default is read
- THEN it is the `:-` empty default
- PROOF: `git grep -n "ROBOTINA_HF_TOKEN:-" -- compose.yml`
  (non-empty)
- NOTE: a `${ROBOTINA_HF_TOKEN:?…}` form would be a FAILURE: `:?` makes compose refuse to start without
  the variable, turning an optional credential into a mandatory one. The recipe names the `:-` substring
  rather than the whole `HF_TOKEN: ${ROBOTINA_HF_TOKEN:-}` line because the braces of the full form are an
  escaping trap in the BRE that `git grep` uses.

#### Scenario: The container sees the vendor name with the token's value

- GIVEN the stack was recreated with `ROBOTINA_HF_TOKEN` set
- WHEN the container's environment is probed for the vendor name
- THEN `HF_TOKEN` is non-empty, and the probe prints a word instead of the value
- PROOF: `docker compose exec robotina sh -c 'test -n "$HF_TOKEN" && echo present'`
  (must print `present`; short-circuiting on `test -n` is what keeps the value out of the terminal and out
  of any log)
- NOTE: this needs the stack recreated with the token set, so it is not runnable before a rebuild plus
  `--force-recreate`. The recipe never prints the value on purpose: the token is readable with a bounded
  `docker inspect`, and echoing it would put a live credential in the transcript.

#### Scenario: No secret value is committed by this change

- GIVEN the change's commits
- WHEN the added lines are searched for a credential written with a value
- THEN no line assigns a token-like value
- PROOF:
  `git diff main...HEAD | grep -nE '^\+.*(HF_TOKEN|GITHUB_TOKEN|TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY)=[A-Za-z0-9_-]{8,}'`
  (no output, exit non-zero)
- NOTE: this recipe is deliberately **change-set scoped**. CR4's repo-wide
  `…(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+` matches value-less documentation
  placeholders such as `ROBOTINA_GITHUB_TOKEN=      # comment`, so it reports 34 hits on `main` today
  (measured, of which 7 are that value-less placeholder subclass); that over-broad class is already
  recorded at
  `odd/tasks/single-robotina-container.md:501-506`. CR4 is NOT changed by this requirement — this recipe
  exists so that a change can prove its own cleanliness without waiting on that repair.

#### Scenario: The repo's gating status is reported as measured

- GIVEN the change is applied
- WHEN the three documents are searched for the measured status and the two READMEs for the documented
  access probe
- THEN all three record the measured `"gated": false` status where the credential is described, and both
  READMEs document the ranged `-L` probe
- PROOF: `test "$(grep -c '"gated": false' README.md README.en.md SECURITY.md | grep -c ':0$')" -eq 0`
  (exits `0` only when all three documents report at least one `"gated": false`; a single `0` in any file
  fails it) together with
  `test "$(grep -c 'curl -fsSL' README.md README.en.md | grep -c ':0$')" -eq 0`
  (exits `0` only when both READMEs document the ranged `-L` probe; a single `0` fails it)
- NOTE: the recipes assert exactly two properties — the measured status is recorded in all three documents
  and the documented access probe is the ranged `curl -fsSL` — and nothing more. The previous version named
  the model id as a substring, which matched inside the probe URL and degenerated to "the string appears
  somewhere", and searched the status with `grep -rn` over only `README.md` and `SECURITY.md`, so a bilingual
  desync in `README.en.md` passed; these recipes close both gaps.

#### Scenario: The access probe fails loudly when there is no access

- GIVEN the image is rebuilt and the container is recreated with `ROBOTINA_HF_TOKEN` set
- WHEN the probe reads a bounded byte range of the weights through the proxy, first through Hugging Face and
  then, following the redirect, through the download CDN
- THEN the ranged read returns bytes from the CDN host (measured 2026-09-30: `206`, 101 bytes, proxy tunnel
  to `us.aws.cdn.hf.co`) and a 4xx or 5xx turns into a non-zero exit status
- PROOF:
  `docker compose exec robotina sh -c 'curl -fsSL -m 30 -o /dev/null -r 0-100 -H "Authorization: Bearer $HF_TOKEN" https://huggingface.co/google/gemma-4-31B-it-qat-w4a16-ct/resolve/main/model.safetensors && echo "acceso ok"'`
  (prints `acceso ok` on success; a 4xx or 5xx — a gate that blocks or a missing path — exits non-zero, and
  the same shape against `resolve/main/no-existe.json` measured exit `22`)
- NOTE: `-L` is what makes the probe touch the CDN: measured without it, curl stops at the `302` and downloads
  the redirect body instead of the weights, so a probe without `-L` is a false green. `hf download <repo>
  --dry-run` is NOT this probe either: measured with and without a token it exits `0` in both cases because it
  only lists the repo's public file inventory. A bare `curl` also exits `0` on a 4xx, which is the trap `-f`
  closes. The probe tests that the bytes are reachable, **not** credential validity: while the API reports the
  repository as public, measured, a bogus bearer also receives `206`, so an expired or scope-less token is not
  detected — what it does catch is a 4xx/5xx and, with `-L`, a CDN host missing from the allowlist. The ranged
  read needs no weight download (`-r 0-100` reads 100 bytes, never GBs); the download host measured on
  2026-09-30 is `us.aws.cdn.hf.co`, which falls under the same `.hf.co` family.

### Requirement: CR12 — The Google AI Studio key reaches the container under the name AI Studio documents

`.env` SHALL accept an optional `ROBOTINA_GEMINI_API_KEY` with an empty default, and the `robotina` service
SHALL publish it to the container as `GEMINI_API_KEY` — the vendor name AI Studio documents for the Gemini
Developer API path — written with the `:-` form so that an unset key never changes container start
behaviour. `ROBOTINA_GEMINI_API_KEY` SHALL be documented in `.env.example` with no value.

Exactly **one** alias SHALL be published. Google's own page for the Gemini API key
(https://ai.google.dev/gemini-api/docs/api-key) says to "Set the environment variable `GEMINI_API_KEY` or
`GOOGLE_API_KEY`", that the client libraries "automatically detect and use these variables", and that "If
both are set, `GOOGLE_API_KEY` takes precedence". The SDK implements that precedence literally —
`google/genai/_api_client.py` reads `GOOGLE_API_KEY` first and warns when both are present — and the same
page recommends setting only one. A second alias of the same value would hand the SDK a name the stack
never chose, and that name would silently win. A tool that expects `GOOGLE_API_KEY` SHALL alias it itself.

The key's egress is already covered: the generation API falls under the existing `.googleapis.com` entry in
`squid/allowlist.txt`, so a subdomain SHALL NOT be re-listed per endpoint.

Measured (2026-09-30): `compose.yml` publishes `GEMINI_API_KEY: ${ROBOTINA_GEMINI_API_KEY:-}` on the
`robotina` service, while `.env.example` does not carry the host-facing name yet — the repository owner is
adding it by hand on this branch, so the scenarios that name `.env.example` below are written for that
merged state.

#### Scenario: Both names exist and are documented, with no value

- GIVEN the change is applied
- WHEN the two files are searched for the two names
- THEN `ROBOTINA_GEMINI_API_KEY` appears in `.env.example` and `GEMINI_API_KEY` appears in `compose.yml`,
  with no literal value in either
- PROOF: `git grep -n "ROBOTINA_GEMINI_API_KEY\|GEMINI_API_KEY" -- .env.example compose.yml`
  (both names present in the expected files, no value after either)
- NOTE: the `.env.example` half is PENDING on the same hand edit — measured before it, `compose.yml:175`
  carries `GEMINI_API_KEY: ${ROBOTINA_GEMINI_API_KEY:-}` while `.env.example` still has no
  `ROBOTINA_GEMINI_API_KEY=` line. The other hit the recipe returns today, `compose.yml:169`, is the
  explanatory comment and not a published name — the mapping form is what the next scenario asserts.
  Written for the merged state; not runnable until the edit lands.

#### Scenario: The empty default keeps the start unconditional

- GIVEN the `robotina` service's environment
- WHEN the published key's default is read
- THEN it is the `:-` empty default
- PROOF: `git grep -n "ROBOTINA_GEMINI_API_KEY:-" -- compose.yml`
  (non-empty)
- NOTE: as in CR11, a `${ROBOTINA_GEMINI_API_KEY:?…}` form would be a FAILURE: `:?` makes compose refuse
  to start without the variable and turns an optional credential into a mandatory one.

#### Scenario: Exactly one alias is published, so Google's precedence rule cannot bite

- GIVEN the change is applied
- WHEN the environment mappings are searched for the second alias
- THEN `GOOGLE_API_KEY` is published nowhere
- PROOF: `git grep -nE '^[[:space:]]*GOOGLE_API_KEY:' -- compose.yml robotina/`
  (no output, exit non-zero — no mapping publishes it)
- NOTE: the pattern names the **mapping form**, not the word, deliberately: `compose.yml:169` mentions
  `GOOGLE_API_KEY` in the comment that explains this very rule, so the bare
  `git grep -n "GOOGLE_API_KEY" -- compose.yml robotina/` returns that comment — measured. A proof that
  matches the prose is not a proof, the same convention AC12's last scenario and CR9's last scenario
  record. Publishing both aliases would give the SDK a second name for the same value and that name would
  win, with a warning.

#### Scenario: The container sees the vendor name with the key's value

- GIVEN the stack was recreated with `ROBOTINA_GEMINI_API_KEY` set
- WHEN the container's environment is probed for the vendor name
- THEN `GEMINI_API_KEY` is non-empty, and the probe prints a word instead of the value
- PROOF: `docker compose exec robotina sh -c 'test -n "$GEMINI_API_KEY" && echo present'`
  (must print `present`; short-circuiting on `test -n` keeps the key out of the terminal and out of any log)
- NOTE: needs the stack recreated with the key set, so it is not runnable before a rebuild plus
  `--force-recreate`.

#### Scenario: No secret value is committed by this change

- GIVEN the change's commits
- WHEN the added lines are searched for a credential written with a value
- THEN no line assigns a token- or key-like value
- PROOF:
  `git diff main...HEAD | grep -nE '^\+.*(GEMINI_API_KEY|HF_TOKEN|GITHUB_TOKEN|TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY)=[A-Za-z0-9_-]{8,}'`
  (no output, exit non-zero)
- NOTE: the same change-set-scoped recipe as CR11's, extended with `GEMINI_API_KEY`. The same caveat about
  CR4's over-broad repo-wide form applies, and CR4 is not changed by this requirement.
