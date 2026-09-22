# agent-identity Specification

## Purpose

Define the observable properties of the agent's identity after the merge: the agent answers
to the name `robotina` through (1) a repo-authored read-only Hermes skin carrying
`branding.agent_name`, (2) an explicit identity statement in the always-loaded context file,
and (3) a documented BotFather **display-name** step outside the repository (frozen:
proposal §7, §17 answer 3).

This domain is **new**: `openspec/specs/` was empty before this change, so this file is a
full domain spec and is copied verbatim into `openspec/specs/agent-identity/spec.md` at
archive time.

Artifact language: English (proposal §16). `README.md` stays Spanish, `README.en.md` English.

## Verification model

There is no test runner in this repository (`openspec/config.yaml` → `testing.runner: none`).
Every scenario names the exact shell-level observation that proves it; two observations in
this domain are **human checks** and are labelled as such.

- Static recipes MUST use `docker compose config -q`; the bare form prints resolved `.env`
  secrets and is forbidden.
- **No vacuous passes**: a `grep`/`ls` probe whose pipeline can succeed on empty output MUST
  assert non-empty output.

## Requirements

### Requirement: ID1 — A repo-authored read-only skin names the agent `robotina`

The repository SHALL ship a Hermes skin defining the agent's displayed name as `robotina`
(top-level `name: robotina` plus `branding.agent_name: robotina`) and SHALL mount it
**read-only** into the Hermes home skins directory, so the agent cannot rewrite its own
identity file.

#### Scenario: The skin file exists and carries the name

- GIVEN the merged change
- WHEN the skin file is read
- THEN it is tracked by git and declares both `name: robotina` and `agent_name: robotina`
- PROOF: `git ls-files hermes/skins/robotina.yaml` (non-empty) and
  `grep -nE "^(name: robotina| +agent_name: robotina)$" hermes/skins/robotina.yaml` (two matches)

#### Scenario: The skin reaches the container's skin directory

- GIVEN the stack is up
- WHEN the skin directory inside the container is listed
- THEN the skin file is present
- PROOF: `docker compose exec robotina sh -c 'ls -l /opt/data/skins/robotina.yaml'`

#### Scenario: The agent cannot rewrite its identity file

- GIVEN the stack is up
- WHEN a write inside the mounted skin path is attempted from inside the container
- THEN the write fails with a read-only filesystem error
- PROOF: `docker compose exec robotina sh -c 'touch /opt/data/skins/robotina.yaml'` (non-zero exit,
  message reports a read-only file system) and, as a secondary observation,
  `docker compose exec robotina sh -c 'grep " /opt/data/skins" /proc/self/mountinfo'` (mount
  options field reports `ro`)

#### Scenario: The repo skin is authoritative over host state

- GIVEN both the repository skin and a `${HOST_DATA_DIR}/hermes/skins` directory exist
- WHEN the skin path is inspected inside the container
- THEN the read-only repository mount shadows the host-state copy at that path
- PROOF: `docker compose exec robotina sh -c 'grep " /opt/data/skins" /proc/self/mountinfo'`
  (the mount source is the repository path, and the mount is read-only)

### Requirement: ID2 — The skin is selected at startup without interaction

Container startup SHALL select the skin non-interactively, so that a freshly created
`${HOST_DATA_DIR}/hermes` also gets it, and the selection SHALL be persisted in the Hermes
state so it survives restarts.

#### Scenario: The effective configuration selects the skin

- GIVEN the stack is up
- WHEN the Hermes state configuration is read for the skin key
- THEN the selected skin is `robotina`
- PROOF: `docker compose exec robotina sh -c 'grep -niE "skin" /opt/data/config.yaml'`
  (non-empty, `robotina`)

#### Scenario: A fresh state directory also gets the selection

- GIVEN an empty host state directory and an isolated compose project name
- WHEN the merged service starts against that directory
- THEN the skin selection exists afterwards, with no interactive step
- PROOF:
  `docker compose -p robotina-fresh config -q` (static sanity, still `-q`) then
  `docker compose -p robotina-fresh up -d robotina` then
  `docker compose -p robotina-fresh exec robotina sh -c 'grep -niE "skin" /opt/data/config.yaml'`
- CAUTION: an isolated project name is required so the fresh-state run does not collide with
  the running `robotina` container name.

#### Scenario: The selection survives a recreation

- GIVEN the stack is up with the skin selected
- WHEN the stack is recreated
- THEN the selection is still present
- PROOF: `docker compose down && docker compose up -d && docker compose exec robotina sh -c 'grep -niE "skin" /opt/data/config.yaml'`

### Requirement: ID3 — The always-loaded context states the identity and the merged topology

The always-loaded context file (`hermes/context/.hermes.md`, mounted at
`/workspace/.hermes.md`) SHALL contain an explicit identity statement that the agent is
`robotina`, and SHALL be rewritten for the merged topology: one agent container, no sibling
`opencode` container, and the loopback endpoint `http://127.0.0.1:4096`.

#### Scenario: The identity statement is present

- GIVEN the merged change
- WHEN the context file is searched for the identity statement
- THEN a statement that the agent is `robotina` is present
- PROOF: `grep -niE "robotina" hermes/context/.hermes.md` (non-empty)

#### Scenario: The context file reaches the container as the always-loaded file

- GIVEN the stack is up
- WHEN the mounted context file is read inside the container
- THEN the identity statement from the repository file is visible at `/workspace/.hermes.md`
- PROOF: `docker compose exec robotina sh -c 'grep -c "robotina" /workspace/.hermes.md'` (non-zero)

#### Scenario: The topology claims match the merged reality

- GIVEN the merged change
- WHEN the context file is searched for the retired topology
- THEN nothing is found and the loopback endpoint is named instead
- PROOF (both):
  `grep -rniE "sibling container|contenedor hermano|http://opencode:4096|own container|propio contenedor" hermes/context/.hermes.md` (no output, exit non-zero)
  `grep -n "http://127.0.0.1:4096" hermes/context/.hermes.md` (non-empty)

### Requirement: ID4 — The BotFather step is display-name only and documented in both READMEs

The setup sections of `README.md` (Spanish) and `README.en.md` (English) SHALL document the
Telegram-side step as exactly: rename the bot's public **display name** to `robotina`. The
change SHALL NOT require, request or verify a `@username` change (frozen: proposal §17
answer 3).

#### Scenario: Both READMEs document the BotFather step

- GIVEN the merged change
- WHEN both READMEs are searched for the step
- THEN each README contains a BotFather instruction
- PROOF: `grep -ci "botfather" README.md README.en.md` (both counts non-zero)

#### Scenario: The documented step does not ask for a username change

- GIVEN the merged change
- WHEN the BotFather instructions are read in context in both READMEs
- THEN they mention the display name and do not ask for a `@username` rename
- PROOF: `grep -rniA6 "botfather" README.md README.en.md | grep -iE "username"` (no output, exit non-zero)

#### Scenario: Human check — the bot is displayed as `robotina`

- GIVEN the BotFather step has been performed by the user and the stack is running
- WHEN the user opens the bot's Telegram profile
- THEN the displayed name is `robotina` (the `@username` handle MAY remain different)
- PROOF: human check (no shell command). Recorded in the change's verification evidence.

### Requirement: ID5 — The container answers to the name as an egress peer

The agent's container name `robotina` SHALL replace the retired names in the proxy-bypass
configuration, so the loopback and intra-container hops never traverse Squid (this is the
identity half of the egress invariant INV3, specified in `egress-boundary`).

#### Scenario: `NO_PROXY` names `robotina` and not the retired names

- GIVEN the stack is up
- WHEN the container's proxy-bypass variable is read
- THEN it contains `robotina` and contains neither `hermes` nor `opencode` as entries
- PROOF: `docker compose exec robotina sh -c 'printenv NO_PROXY'` (must contain `robotina`;
  must not contain `hermes` or `opencode`)
