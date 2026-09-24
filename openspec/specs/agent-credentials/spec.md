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
