# Feature: hf-cli-and-token

## Goal

Close #85: make the `hf` CLI available inside `robotina`, wired to a Hugging Face token, so the
gated scored model `google/gemma-4-31B-it-qat-w4a16-ct` can be downloaded from the stack through
the egress proxy.

Four axes (the fourth one is an owner-requested extension of the same branch, not part of #85):

1. **Tool**: `hf` baked into `robotina/Dockerfile`, pinned by `ARG` like every other baked tool
   (AGENTS.md: the `ARG` is the single source of truth for the version, and `hf --version` is how
   "which version runs" is answered from the image).
2. **Credential**: `ROBOTINA_HF_TOKEN` in `.env.example`, published to the container as `HF_TOKEN`
   (the name `huggingface_hub` reads), same prefix and default-empty criteria as the rest.
3. **Egress + documentation**: `.huggingface.co` and `.hf.co` in `squid/allowlist.txt` (the second
   covers the download redirects to `cas-bridge.xethub.hf.co`), and the gated-repo caveat (the
   licence has to be accepted on huggingface.co with the token's account) written down.
4. **Extension, owner-requested in the same branch**: the Google AI Studio surface in the allowlist,
   and the AI Studio API key as a fourth credential (`ROBOTINA_GEMINI_API_KEY` ->
   `GEMINI_API_KEY`). #85 leaves the allowlist out of its scope on purpose ("se hace aparte
   editando `squid/allowlist.txt`"), so this axis is that "aparte" plus its credential.

Branch: `feat/issue-85-hf-cli-and-token`, off `main`. Owner: `emiliodavola`. Closes #85.

## Non-goals

- **Downloading the weights.** They are ~GBs and go to the off-Kaggle flow; the container only gets
  the client, the tokens and the egress path.
- **No published pin / healthcheck entry for `hf`.** It joins the majority of baked tools (`gh`,
  `taplo`, `marksman`, `codegraph`, `opencode-ai`): pinned by `ARG`, no `ROBOTINA_*_VERSION`
  published and no healthcheck arm. AC13 ("the published-pin scope is exactly engram and gentle-ai
  today") therefore stays true verbatim.
- **No Vertex AI variables and no ADC path** (`GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`,
  `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_APPLICATION_CREDENTIALS`): the request was AI Studio access,
  and ADC needs a credentials file inside the bind.
- **No rewrite of CR4.** Its repo-wide "no secret committed" recipe is over-broad (see Diagnosis 11);
  the new requirements use a change-set-scoped recipe instead of repairing it here.

## Diagnosis (measured, read-only, 2026-09-30)

Every claim below was measured before writing the change; the ones that contradict the issue text
are called out because they change the recipe.

1. **`huggingface_hub[cli]` no longer exists.** `provides_extra` for `huggingface_hub==2.0.0` is
   `oauth, torch, fastai, hf-xet, mcp, testing, gradio, typing, quality, all, dev` — there is no
   `cli` extra. The issue's suggested spec is stale.
2. **The CLI was extracted into its own PyPI project `hf`** (`hf 2.0.0`, "CLI extracted from the
   huggingface_hub library to interact with the Hugging Face Hub"), and `hf 2.0.0` depends on
   `huggingface_hub==2.0.0` exactly.
3. **But the `hf` distribution is not installable by `uv` at 1.32.0/1.33.0/2.0.0.** Its wheel
   declares `Dynamic: requires-dist` and `uv` refuses those versions:
   `Because there is no version of hf==2.0.0 and you require hf==2.0.0 ... unsatisfiable`.
   `hf==1.31.0` is the newest `hf` release `uv` resolves. Measured with
   `uv pip install --dry-run hf==<v>` for `1.31.0` (would install 16 packages), `1.32.0`, `1.33.0`,
   `2.0.0` (all three: no solution).
4. **`huggingface_hub` itself is installable at 2.0.0 and already ships the `hf` console script.**
   Measured: `uv venv --python 3.13 /opt/hf && uv pip install huggingface_hub==2.0.0` yields
   `/opt/hf/bin/hf`, and `hf --version` prints `2.0.0\n` on stdout. A `hf-cli` skill hint showed up on
   stderr in that first scratch container and did NOT reproduce in the built image (independently
   measured: stderr empty), so nothing depends on it. `huggingface-cli` is gone in 2.0.0 — `hf` is the
   only entry point.
   Contrast measured on `huggingface_hub==1.33.0`: `hf --version` prints only updater and skill
   hints, no version line — unusable as a pin assertion.
5. **Therefore the pin is `huggingface_hub==2.0.0`, not the `hf` distribution.** One pin covers the
   library and the CLI (they are versioned together), and it is the version `uv` can actually
   install.
6. **The `hf` CLI honours the proxy environment.** `httpx2` (the HTTP client of
   `huggingface_hub==2.0.0`) reads `HTTPS_PROXY`/`https_proxy`, which compose already exports through
   the `x-egress-env` anchor. `hf download --help` confirms `--dry-run` exists, so the issue's
   read-only probe is available.
7. **`uv tool install <cli>` cannot be used at build time here.** `UV_TOOL_DIR` / `UV_TOOL_BIN_DIR`
   point inside the `/opt/data` bind (`/opt/data/.local/share/uv-tools`, `/opt/data/.local/bin`),
   which at runtime is a host bind: anything baked under those paths is shadowed by the mount. The
   CLI is installed into a dedicated image-path venv (`/opt/hf`) with a symlink in `/usr/local/bin`.
8. **`/opt/uv/python` is a named volume** (`robotina_uv_python`) at runtime, seeded from the image on
   first use, so the venv's interpreter link stays valid; the image already relies on that mechanism.
9. **The working tree carried an uncommitted `squid/allowlist.txt` change** that must not be lost:
   `.huggingface.co` and `.hf.co` (exactly what this issue needs) plus three unrelated pending
   entries (`.arxiv.org`, `api.semanticscholar.org`, `.archive.org`). The owner instructed that the
   whole modification be incorporated, so it is committed here as its own work unit and the
   unrelated entries are stated as such, not smuggled in.
10. **Google's own tables say what the AI Studio surface needs, and the API part needs nothing new.**
    The Google Workspace host-name allowlist (support.google.com/a/answer/9012184, updated
    2026-09-24) puts `aistudio.google.com` in its "Generative AI" row and lists `accounts.google.com`
    plus `www.google.com` for authentication/accounts; the Gemini host list
    (knowledge.workspace.google.com -> firewall-and-proxy-settings) adds the gstatic and
    googleusercontent hosts as wildcards. The generation hosts (`generativelanguage.googleapis.com`,
    `oauth2.googleapis.com`, `cloudcode-pa.googleapis.com`, `cloudaicompanion.googleapis.com`,
    `serviceusage.googleapis.com`) all fall under the `.googleapis.com` that was already in the
    allowlist for Kaggle — verified by tunnel, not by reading: each answers
    `200 Connection established` through Squid (see Verification).
11. **Two recipes that look right are traps, and both are recorded in the specs' NOTEs.** (a) A bare
    `git grep -n "GOOGLE_API_KEY" -- compose.yml` matches the explanatory *comment* that names the
    variable, so the alias proof is asserted by mapping form
    (`^[[:space:]]*GOOGLE_API_KEY:`) — a proof that matches prose is not a proof. (b) On Windows Git
    Bash, `git grep -n '/opt/hf'` returns nothing with exit 1 because MSYS path-converts the leading
    slash: measured 0 matches bare versus 5 with `MSYS_NO_PATHCONV=1`, which is why the AC14 recipe
    carries the prefix and a NOTE.
12. **CR4's repo-wide secret recipe is over-broad and already red on `main`.** Measured:
    `git grep -nE '(TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY|GITHUB_TOKEN)=.+' -- ':!*.example'`
    matches value-less documentation placeholders such as
    `ROBOTINA_GITHUB_TOKEN=      # comment`: **34 hits on `main`**, of which 7 are that placeholder
    subclass, and the class is already recorded at
    `odd/tasks/single-robotina-container.md:501-506`. CR4 is not changed here; CR11 and CR12 prove their
    own cleanliness with a change-set-scoped recipe. The branch takes that count to 36 — the two extra
    hits are the spec's NOTE and this item literally quoting the over-broad pattern, which is the same
    "the proof line reports itself" effect CR4's own NOTE describes.
13. **The independent verifier found three real drifts, all fixed in this branch.** (a) *Medium*: AC13's
    prose still said "six" ARG-pinned tools and "the other four" uncovered — the new `ARG` makes it
    seven/five, so AC13's counts (and its PROOF's alternation) were amended while its invariant stayed
    untouched. (b) *Low*: the Dockerfile comment, AC14 and this tracker asserted an `hf-cli` hint on
    stderr that does not reproduce in the built image — the claim is gone and only the true part (the
    assertion reads stdout) remains. (c) *Low*: the "7 hits" figure quoted for CR4's recipe was the
    placeholder subclass, not the total (34) — corrected here and in CR11's NOTE. The verifier could not
    falsify any of the other seven claims it attacked.

## Shape

1. `robotina/Dockerfile`: `ARG HUGGINGFACE_HUB_VERSION=2.0.0` in the pinned-versions block, a new
   numbered section that creates the `/opt/hf` venv, installs the pinned package, links
   `/usr/local/bin/hf` and asserts `hf --version | grep -F "${HUGGINGFACE_HUB_VERSION}"`, `hf` in the
   final inventory assertions, and every "seis" count moved to "siete".
2. `scripts/bump-tools.sh`: a `pypi` source kind (PyPI JSON `info.version`) plus the
   `huggingface-hub` catalog row, so the new `ARG` has the supported update path AGENTS.md requires.
   An `AVISO` records the `hf`-distribution trap.
3. `compose.yml`: `HF_TOKEN: ${ROBOTINA_HF_TOKEN:-}` and `GEMINI_API_KEY: ${ROBOTINA_GEMINI_API_KEY:-}`
   on the `robotina` service, next to `GITHUB_TOKEN`.
4. `.env.example`: `ROBOTINA_HF_TOKEN=` and `ROBOTINA_GEMINI_API_KEY=`, with the comment that they
   are published as `HF_TOKEN` and `GEMINI_API_KEY`. **Owner-owned: the agent's write is blocked for
   this path by the host safety policy, and the owner chose to make the edit by hand (T4-bis).**
5. Docs: `README.md` / `README.en.md` (versions table, the bump-tools list, the healthcheck gap,
   the `.env` block, and one section per axis), `SECURITY.md` (credential inventory, `.env` block,
   rotation order, the `.googleapis.com` extension and the reachability note),
   `hermes/context/.hermes.md` (agent-facing facts and the never-ask rule), `openspec/project.md`
   (toolchain and credentials).
6. Contract: `agent-credentials` gains CR11 (the `HF_TOKEN` input) and CR12 (the AI Studio key and
   the single-alias rule); `agent-container` gains AC14 (the `hf` CLI is baked from a pinned PyPI
   `ARG` and resolves from the image, without publishing a pin).
7. Egress: `.huggingface.co` and `.hf.co`, plus the Google AI Studio section
   (`aistudio.google.com`, `ai.google.dev`, `accounts.google.com`, `www.google.com`, `.gstatic.com`,
   `.googleusercontent.com`) with `aistudiocdn.com` commented out and the reason written next to it.

## Tasks

- [x] T1 — Branch and this tracker.
- [x] T2 — Commit the pre-existing `squid/allowlist.txt` modification, verbatim.
- [x] T3 — Dockerfile `hf` pin + install + assertions; `bump-tools.sh` `pypi` kind + catalog row;
      `dependabot.yml` count. Commit `2242025`.
- [x] T4 — `compose.yml` `HF_TOKEN` wiring. Commit `366f4c7`.
- [ ] T4-bis — `.env.example`: `ROBOTINA_HF_TOKEN=` and `ROBOTINA_GEMINI_API_KEY=`. **Owner-owned and
      pending**: the agent cannot write that path (harness safety policy, `edit` and `read` both
      refused), and the owner chose to add the lines by hand.
- [x] T5 — Docs: `README.md`, `README.en.md`, `SECURITY.md`, `hermes/context/.hermes.md`,
      `openspec/project.md`. Commit `cf3fa33`.
- [x] T6 — Contract: `agent-credentials` CR11 + CR12, `agent-container` AC14. Commit `52795d5`.
- [x] T9 — Google AI Studio surface in `squid/allowlist.txt`, verified against a temporary Squid.
      Commit `326a5a0`.
- [x] T10 — Google AI Studio key: `compose.yml` wiring (commit `5ba0eda`) and docs (commit
      `e5b1e07`).
- [ ] T7 — Verification: `docker compose build robotina`, then the image recipes, plus an independent
      read-only verifier over `main..HEAD`.
- [ ] T8 — Push and PR against `main`, assigned to `emiliodavola`.

## Verification

Every row below was run. "Pending" rows are exactly the ones that need the rebuilt image, the
recreated container, or the owner's hand edit.

| Fact | Recipe | Result |
| --- | --- | --- |
| Compose still validates, without printing secrets | `docker compose config -q` | exit 0 after each `compose.yml` edit |
| The allowlist is well formed | `docker compose run --rm --no-deps --entrypoint /usr/sbin/squid egress-proxy -f /etc/squid/squid.conf -k parse` | exit 0 |
| The HF hosts are admitted | temporary Squid, same image/conf/allowlist, on `agents` + `egress` | `.huggingface.co`-family tunnels established; `example.com` -> `403 Forbidden` (control) |
| The Google AI Studio hosts are admitted | same temporary Squid | `aistudio.google.com` -> `200 Connection established` then 302; `accounts.google.com` -> 302; `ai.google.dev` -> 200; `www.google.com` -> 200; `fonts.gstatic.com` -> 404 from origin; `lh3.googleusercontent.com` -> 400 from origin; `aistudiocdn.com` -> `403 Forbidden` (deliberately off) |
| The generation API needs no new entry | same temporary Squid | `generativelanguage.googleapis.com`, `www.googleapis.com`, `cloudcode-pa.googleapis.com`, `oauth2.googleapis.com`, `storage.googleapis.com` all answer `200 Connection established` |
| The `hf` install recipe works | the new `RUN` replayed in a throwaway container on the then-current image | `/opt/hf` venv built, `huggingface_hub==2.0.0` installed, `hf --version` -> `2.0.0`, `command -v hf` -> `/usr/local/bin/hf` |
| The pin is in the update path | `scripts/bump-tools.sh --check \| grep huggingface-hub` | `huggingface-hub 2.0.0      al dia` (three other tools report ATRASADO — pre-existing, not this change) |
| The pin is single-sourced | `git grep -n '^ARG HUGGINGFACE_HUB_VERSION=' -- robotina/Dockerfile` | `robotina/Dockerfile:80` |
| No published pin was added | `git grep -n 'ROBOTINA_HF_VERSION' -- robotina/ compose.yml` | no output, exit non-zero |
| The venv is not a mount target | `MSYS_NO_PATHCONV=1 git grep -n '/opt/hf' -- robotina/Dockerfile` + `git grep -n 'target: /opt/hf' -- compose.yml` | 5 matches / no output |
| No secret value is committed | `git diff main...HEAD \| grep -nE '^\+.*(GEMINI_API_KEY\|HF_TOKEN\|GITHUB_TOKEN\|TELEGRAM_BOT_TOKEN\|OPENCODE_GO_API_KEY)=[A-Za-z0-9_-]{8,}'` | no output, exit non-zero |
| The gated caveat is documented | `grep -n "gemma-4-31B-it-qat-w4a16-ct" README.md README.en.md` (+ `SECURITY.md` as a bonus) | 2 hits each, plus `SECURITY.md:239` |
| The built image resolves the CLI and the version | `MSYS_NO_PATHCONV=1 docker run --rm --entrypoint /bin/sh robotina:local -c 'command -v hf'` and `... -c 'hf --version'` | `/usr/local/bin/hf` and `2.0.0` (image `sha256:39e9aa79…`, built from this branch; the verifier added the shadow check: `/opt/data/.local/bin` precedes `/usr/local/bin` on `PATH` and carries no `hf`, and `/opt/hf` is not a mount target) |
| The tokens reach the container under the vendor names | `ROBOTINA_HF_TOKEN=<fake> ROBOTINA_GEMINI_API_KEY=<fake> docker compose run --rm --no-deps --entrypoint /bin/sh robotina -c 'printf %s "$HF_TOKEN" \| sha256sum; printf %s "$GEMINI_API_KEY" \| sha256sum'` | both hashes identical to their host-side references, twice: once by the author and once independently by the verifier with its own fake values. The exact `docker compose exec` form still needs a recreate with real values |
| The `.env.example` names exist | `git grep -n "ROBOTINA_HF_TOKEN\|ROBOTINA_GEMINI_API_KEY" -- .env.example` | PENDING on T4-bis (owner's hand edit) |
| Independent read-only verification | `gentle-ai-verify` over `main..HEAD` | DONE: 10 claims attacked, 7 not falsified, 3 findings (1 Medium, 2 Low) fixed in this branch — Diagnosis 13 |

## Pending after this PR

- **The running stack keeps the old image** until a rebuild plus `--force-recreate robotina`, and the
  egress-proxy keeps the old allowlist until `docker compose up -d --force-recreate egress-proxy`.
  The end-to-end probe (`hf download google/gemma-4-31B-it-qat-w4a16-ct --dry-run`) needs both, plus
  a token whose account has accepted the licence.
- **T4-bis**: the two lines in `.env.example`.
- Extending the healthcheck shadow check to `hf` (the option-B alternative recorded in the
  non-goals).
- Repairing CR4's over-broad repo-wide recipe (Diagnosis 12).
- The licence acceptance itself is a human step on huggingface.co, not something this repo can do.

## Route declaration

- Classification: **substantial** (one tool pin with a measured deviation from the issue text, two
  credentials, egress policy on two axes, and the contract that states each), tracked here because
  progress had to survive interruption.
- Delegation: the parent owned exploration, the tracker, the commits and the inline one-file edits
  (`compose.yml`). Writing was delegated, one worker at a time: the toolchain slice, the docs slice,
  the specs slice and the second docs slice — each with `## Allowed edit surfaces` and each returning
  evidence. Independent read-only verification goes to `gentle-ai-verify`.
- Deviations recorded, not hidden: `huggingface_hub` instead of `huggingface_hub[cli]` (Diagnosis
  1-5); a change-set-scoped secret recipe instead of CR4's over-broad one (Diagnosis 12); the
  `.env.example` hunk is owner-owned because the harness blocks that path (T4-bis); the unrelated
  arXiv/Semantic-Scholar/Wayback allowlist entries ride along because the owner ordered the pending
  working-tree change preserved (Diagnosis 9).
