# Feature: hf-cli-and-token

## Goal

Close #85: make the `hf` CLI available inside `robotina`, wired to a Hugging Face token, so the
gated scored model `google/gemma-4-31B-it-qat-w4a16-ct` can be downloaded from the stack through
the egress proxy.

Three deliverables, one per axis:

1. **Tool**: `hf` baked into `robotina/Dockerfile`, pinned by `ARG` like every other baked tool
   (AGENTS.md: the `ARG` is the single source of truth for the version, and `hf --version` is how
   the question "which version runs" is answered from the image).
2. **Credential**: `ROBOTINA_HF_TOKEN` in `.env.example`, published to the container as `HF_TOKEN`
   (the name `huggingface_hub` reads), same prefix and default-empty criteria as the rest.
3. **Egress + documentation**: `.huggingface.co` and `.hf.co` in `squid/allowlist.txt` (the second
   one covers the download redirects to `cas-bridge.xethub.hf.co`), and the gated-repo caveat
   (the licence has to be accepted on huggingface.co with the token's account) written down.

Branch: `feat/issue-85-hf-cli-and-token`, off `main`. Owner: `emiliodavola`. Closes #85.

## Non-goals

- **Downloading the weights.** They are ~GBs and go to the off-Kaggle flow; the container only gets
  the client, the token and the egress path.
- **No published pin / healthcheck entry.** `hf` joins the majority of baked tools (`gh`, `taplo`,
  `marksman`, `codegraph`, `opencode-ai`): pinned by `ARG`, no `ROBOTINA_*_VERSION` published and no
  healthcheck arm. AC13 ("the published-pin scope is exactly engram and gentle-ai today") therefore
  stays true verbatim. Extending the healthcheck to the third tool is a follow-up, not this change.
- **No rebuild of the running stack as part of the change** (see Tasks T7).

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
   `/opt/hf/bin/hf`, and `hf --version` prints `2.0.0\n` on stdout (plus a `hf-cli` skill hint on
   stderr). `huggingface-cli` is gone in 2.0.0 — `hf` is the only entry point.
   Contrast measured on `huggingface_hub==1.33.0`: `hf --version` prints only updater and skill
   hints, no version line — unusable as a pin assertion.
5. **Therefore the pin is `huggingface_hub==2.0.0`, not the `hf` distribution.** One pin covers the
   library and the CLI (they are versioned together), and it is the version `uv` can actually
   install.
6. **The `hf` CLI honours the proxy environment.** `httpx2` (the HTTP client of
   `huggingface_hub==2.0.0`) reads `HTTPS_PROXY`/`https_proxy`, which compose already exports to the
   container through the `x-egress-env` anchor. `hf download --help` confirms `--dry-run` exists,
   so the issue's read-only probe is available.
7. **`uv tool install <cli>` cannot be used at build time here.** `UV_TOOL_DIR` /
   `UV_TOOL_BIN_DIR` point inside the `/opt/data` bind (`/opt/data/.local/share/uv-tools`,
   `/opt/data/.local/bin`), which at runtime is a host bind: anything `uv tool install` bakes under
   those paths is shadowed by the mount and lost. The CLI is installed into a dedicated image-path
   venv (`/opt/hf`) with a symlink in `/usr/local/bin` instead.
8. **`/opt/uv/python` is a named volume** (`robotina_uv_python`), not an image path, at runtime.
   Docker seeds a new named volume from the image content at that path, so the venv's interpreter
   link stays valid; this is the same mechanism the image already relies on for `uv`.
9. **There is a working-tree change to `squid/allowlist.txt` that must not be lost**: it adds
   `.huggingface.co` and `.hf.co` (exactly what this issue needs) plus three unrelated pending
   entries (`.arxiv.org`, `api.semanticscholar.org`, `.archive.org`). The user instructed that the
   whole modification be incorporated into this branch, so it is committed here as its own work unit
   and the unrelated entries are stated as such, not smuggled in.

## Shape

1. `robotina/Dockerfile`: new `ARG HUGGINGFACE_HUB_VERSION=2.0.0` in the pinned-versions block, a
   new numbered section that creates the `/opt/hf` venv, installs the pinned package, links
   `/usr/local/bin/hf` and asserts `hf --version | grep -F "${HUGGINGFACE_HUB_VERSION}"`, plus `hf`
   in the final inventory assertions. Counts that said "seis" become "siete".
2. `scripts/bump-tools.sh`: new `pypi` source kind (PyPI JSON `info.version`) and the
   `huggingface-hub` catalog row, so the new `ARG` has the supported update path AGENTS.md requires
   (`--check`/`--write`). An `AVISO` records the `hf`-distribution trap from the diagnosis.
3. `compose.yml`: `HF_TOKEN: ${ROBOTINA_HF_TOKEN:-}` on the `robotina` service, next to
   `GITHUB_TOKEN`.
4. `.env.example`: `ROBOTINA_HF_TOKEN=` with the comment that it is published as `HF_TOKEN`.
5. Docs, both languages where the claim is measured: `README.md` / `README.en.md` (versions table,
   the baked-tools update list, the `.env` block, a short gated-repo + allowlist note),
   `SECURITY.md` (credential inventory, `.env` block, rotation order, and the `uv`/Python section
   where the "fix a tool by baking it" rule already lives), `hermes/context/.hermes.md` (agent-facing
   fact + the never-ask-for-a-token rule), `openspec/project.md` (toolchain line).
6. Contract: `openspec/specs/agent-credentials/spec.md` gains CR10 (the `HF_TOKEN` input and its
   gated-repo documentation); `openspec/specs/agent-container/spec.md` gains AC14 (the `hf` CLI is
   baked from a pinned PyPI `ARG` and resolves from the image).

## Tasks

- [x] T1 — Branch and this tracker.
- [ ] T2 — Commit the pre-existing `squid/allowlist.txt` modification, verbatim.
- [ ] T3 — Dockerfile `hf` pin + install + assertions; `bump-tools.sh` `pypi` kind + catalog row;
      `dependabot.yml` count. Commit.
- [ ] T4 — `compose.yml` + `.env.example` credential wiring. Commit.
- [ ] T5 — Docs (`README.md`, `README.en.md`, `SECURITY.md`, `hermes/context/.hermes.md`,
      `openspec/project.md`). Commit.
- [ ] T6 — Contract specs (`agent-credentials` CR10, `agent-container` AC14). Commit.
- [ ] T7 — Verification: `docker compose build robotina`, then the `hf`/`HF_TOKEN` recipes against
      the built image without touching the running stack; plus an independent read-only verifier.
- [ ] T8 — Push and PR against `main`, assigned to `emiliodavola`.

## Verification (recipes)

| Fact | Recipe |
| --- | --- |
| The pin is registered in the update path | `scripts/bump-tools.sh --check` (must report `huggingface-hub` and not `sin ARG`) |
| The image resolves the baked CLI | `docker run --rm --entrypoint /bin/sh robotina:local -c 'command -v hf'` → `/usr/local/bin/hf` |
| The baked CLI matches the pin | `docker run --rm --entrypoint /bin/sh robotina:local -c 'hf --version'` → `2.0.0` |
| The credential reaches the container under the vendor name | `docker compose run --rm --no-deps --entrypoint /bin/sh robotina -c 'test -n "$HF_TOKEN" && echo present'` (never the bare `env`: it prints every secret) |
| Compose still validates without printing secrets | `docker compose config -q` |
| No secret is committed | `git grep -nE '(HF_TOKEN|GITHUB_TOKEN|TELEGRAM_BOT_TOKEN|OPENCODE_GO_API_KEY)=.+' -- ':!*.example'` (no output) |
| The egress allowlist admits HF | `grep -nE '^\.(huggingface\.co\|hf\.co)$' squid/allowlist.txt` |

## Pending after this PR

- The running stack keeps the old image until a rebuild + `--force-recreate robotina`. The
  end-to-end probe (`hf download google/gemma-4-31B-it-qat-w4a16-ct --dry-run`) needs both that
  recreate and a token whose account has accepted the licence.
- Extending the healthcheck shadow check to `hf` (option B in the non-goals).
- The licence acceptance itself is a human step on huggingface.co, not something this repo can do.

## Route declaration

- Classification: **substantial but bounded** (one tool pin, one credential, one egress pair, and
  the documentation that states each), with a measured deviation from the issue text that is part
  of the change's value.
- Delegation: the parent owns exploration, the tracker and the commits; the implementation slices
  go to **one** `gentle-ai-worker` at a time (toolchain, then wiring+docs+specs), and one
  independent read-only **`gentle-ai-verify`** pass checks the result before the PR is opened.
