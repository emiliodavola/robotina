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
