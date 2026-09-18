# Feature: readme-and-doc-alignment

## Goal

Give the repository a front door and make its documentation honest.

Two gaps, both measured on the current tree:

- **There is no `README.md`.** The only entry point to the repo is `SECURITY.md`
  (534 lines), which is a threat model, not an introduction. Someone landing on the
  repo has no stated purpose, architecture, requirements or setup path.
- **The docs have drifted from the tree.** Every `.md` here makes verifiable claims
  (versions, paths, flags, counts, behaviours) and several were written mid-build,
  before the stack was frozen. Nothing reconciles them against `compose.yml`,
  `opencode/Dockerfile`, `squid/` and `scripts/`.

Decisions taken with the user:

- Drift scope: **fix factual drift in place** (same tone and structure, no
  rewriting), and report every finding. Not "report only".
- `README.md` in **Spanish** plus `README.en.md` in English. Spanish is the repo's
  existing convention (`SECURITY.md`, the skills, the code comments); English is the
  GitHub-facing convention. The user chose to carry both.
- **No GitHub Actions.** See "Open risks" for why, and for the cost of reversing it.
- The user **pushes and opens the PR** (this document is the tracking artifact; the
  PR body and the branch are part of the deliverable).

## Shape

- `README.md` (Spanish, primary) and `README.en.md` (English, mirror) written from a
  verified inventory of the tree, not from memory or from the existing prose.
- Factual corrections applied to the existing `.md`: wrong versions, wrong paths,
  wrong flags, claims about behaviour that is no longer true.
- Repo metadata set on GitHub: description + topics.
- One PR against `main`, which currently holds only `LICENSE`.

## Non-goals

- Rewriting the prose of `SECURITY.md`. It is the threat model; its structure is
  deliberate and the user asked for alignment, not editorial work.
- Touching `compose.yml`, `squid/`, `opencode/` or `scripts/`. This feature changes
  documentation and repo metadata only. Any reality that does not match a doc is,
  by default, a doc bug — if it turns out to be a real defect, it becomes its own
  task instead of being silently "fixed" by editing prose.
- Turning this into a public-facing marketing README. It describes a private,
  self-hosted, security-sensitive stack.
- Adding CI.

## Open risks to verify

- **Does any doc claim a security control that is not actually enforced?** That is
  the one class of finding severe enough to justify editing beyond facts: a threat
  model that overstates its own controls is worse than no threat model. Every such
  finding gets promoted and reported explicitly, not folded into a silent edit.
- **The version numbers are the most likely drift.** `opencode/Dockerfile` pins
  `ENGRAM_VERSION`, `GENTLE_AI_VERSION`, `MARKSMAN_RELEASE` and npm packages via
  `ARG`/`RUN`, and the daemon versions live in the images, so a doc copying them by
  hand goes stale on the next rebuild.
- **`main` vs `security/egress-hardening`.** The remote default branch is `main` and
  its tree contains only `LICENSE`; the entire stack lives on
  `security/egress-hardening`. A README that assumes the reader already has the
  stack is wrong for anyone who clones the default branch, and the PR is
  consequently one large diff rather than an incremental review.
- **`.atl/` is gitignored** (`.gitignore:2`) but `hermes/context/.hermes.md` is
  tracked. Any inventory has to separate "the tree" from "what git actually holds".
- **Reversing the Actions decision later has a security cost, not just a workflow
  cost.** The agent container holds a PAT with `push` on this repository. A workflow
  file is executable configuration: whoever can push it can run code with the repo's
  GitHub-side identity. With no secrets in the repo today the payoff is small; the
  moment a secret exists, a workflow is the shortest path to it. Recorded here so
  the decision is a decision, not an omission.

## Tasks

- [x] T1 — Feature document (this file).
- [x] T2 — Reality inventory + drift report: every trackable claim in the `.md`
      files checked against `compose.yml`, `opencode/Dockerfile`,
      `opencode/entrypoint.sh`, `opencode/overlay.json`, `squid/`, `scripts/` and
      `.env.example`.
- [x] T3 — `README.md` (Spanish) and `README.en.md` (English), from that inventory.
- [x] T4 — Apply the factual corrections to the existing `.md`.
- [x] T5 — GitHub description and topics.
- [x] T6 — Independent verification: every factual claim in the new and edited docs
      re-checked against the real system by a second reader.
- [x] T7 — Work-unit commits, push, PR against `main` → PR #1.

## Evidence

### Measurement, not memory

The scout session had no shell (`read`/`grep`/`find` only), so it marked every
runtime claim `UNVERIFIABLE` instead of guessing — which is why the numbers below
were measured separately from the host, against the running stack.

Verified live: 4 mandatory env vars (`${VAR:?…}`: `HOST_DATA_DIR`,
`TELEGRAM_BOT_TOKEN`, `HERMES_OPENCODE_GO_API_KEY`, `OPENCODE_GO_API_KEY`) and 3
optional (`${VAR:-}`); three services, none with a published port; `agents` is
`internal: true` and only `egress-proxy` also sits on `egress`; git 2.54.0, gh
2.97.0, go 1.26.8, uv 0.11.19, CPython 3.13.13, node 24.18.1, jq 1.8.2, rg
15.1.0, opencode 1.18.31, engram 1.20.0, gentle-ai 3.1.0, squid 6.13; the six
Hermes databases at format bytes 18/19 = `1 1` (rollback) while
`opencode.db`/`engram.db` = `2 2` (WAL); `models.opencode.ai` present in the
proxy log as `TCP_TUNNEL http=200`; `docker compose config -q` exits 0.

### Corrected (all in the tree now)

| Where | Said | Actually |
| --- | --- | --- |
| `SECURITY.md` §Variables | 3 variables, "if one is missing compose aborts" | 7 variables; 4 mandatory, 3 optional with an empty default |
| `SECURITY.md` model call | "not verified yet" | verified later: `domain=models.opencode.ai method=CONNECT squid=TCP_TUNNEL http=200` |
| `SECURITY.md` interop | `hermes` .3 / `opencode` .2, "the only shared volume is /workspace" | .2 / .4 (ephemeral, they had already drifted); `/workspace` is a bind, and `hermes` also gets two ro mounts |
| `SECURITY.md` interop | ro skill mount ⇒ "the agent cannot rewrite its own instructions" | only `/opt/data/skills/stack` is ro; the agent's own tree lives on the writable `/opt/data` bind and it does write there |
| `SECURITY.md` DB recipe | "bytes 18-19" (ambiguous, read as 1-based gives `0 1`) | the version bytes are 0-based offsets 18 and 19; disambiguated |
| `SECURITY.md` versions | listed as facts | same values, but none is pinned: they describe the measured image, not a guarantee |
| `SECURITY.md` Python | "outbound ports used: pypi.org, files.pythonhosted.org" | those are hosts; the ports are 80/443, and 443 only for `CONNECT` |
| `SECURITY.md` uid step | "the mounted folders and both volumes" | names the five subdirs and two volumes the script actually touches, and that `hermes` is deliberately excluded |
| `SECURITY.md` guarantees | allowlist presented as the exfiltration control | added the caveat that it bounds destination, not payload, plus a “Puntos de atención” entry |
| `.hermes.md`, `github-private-repos` | `git@github.com:` is rewritten to HTTPS "automatically" | false in `hermes` (no `/etc/gitconfig`, no `insteadOf`; it also has an `ssh` that cannot resolve anything). The rewrite exists only in the opencode image |
| `github-private-repos` troubleshooting | any `403` ⇒ allowlist | added the GitHub-own `403` (`Write access to repository not granted.`) vs Squid's HTML-page `403` |

### Reported, deliberately not rewritten

`odd/tasks/*.md` are the historical record of each stage: they say `init: true` on
all three services, `opencode_data` as the volume name, "5 LSPs plus R and Julia"
against its own "six LSPs", and a `workspace` volume instead of a bind. A task
document is evidence of what was true then; editing it destroys the trail. They
are listed here and left alone, except where a reader would act on them today.

The drift the scout found in them (11 items) and the 11 internal contradictions
between docs are in this feature's session report, not in the tree.

### Verification

A second reader with shell access tried to falsify every claim in both READMEs,
the corrected `SECURITY.md` and the two Hermes files: 39 claims checked, 38 PASS,
1 FAIL. The FAIL was real and is fixed — the READMEs claimed the Dockerfile
checksum-verifies "the binaries" (engram, gentle-ai, marksman and the npm
packages) when only engram and gentle-ai are checksum-verified; marksman is pinned
by a movable release tag with no integrity check.

## Gotchas found

- **Two writers landed on the branch mid-feature.** Two commits from the human
  editor arrived while this work was in flight; one of them rewrote this README's
  checksum sentence back to the exact claim the verifier had just falsified, and
  dropped the Git Bash path-mangling note, while the English mirror kept both. The
  bilingual pair desynchronized on a **fact** — the failure mode a two-language
  doc invites by construction. Either every measured claim lives in one document
  and the other links to it, or the two files are edited together, always.
- **`git ls-remote` never fetches objects.** It returns refs over HTTP. Reading it
  as proof of a clone sends you looking for files that were never downloaded —
  exactly the confusion that opened this feature.
- **Two different `403`s.** A fine-grained PAT that authenticates but does not
  include the repository gets `404` from the API and
  `remote: Write access to repository not granted.` from git — from GitHub, with no
  HTML body. Squid's denial is proxy-originated and carries an HTML page. Blaming
  the allowlist for a permissions problem costs a session.
- **`docker compose config` prints resolved `.env` values.** Verification leaked
  live secrets that way. `-q` validates without printing them.
- **Git Bash/MSYS rewrites absolute paths**, so `docker compose run --entrypoint
  /usr/sbin/squid` fails on Windows with a `C:/Program Files/Git/...` path unless
  `MSYS_NO_PATHCONV=1` is set. Documented in both READMEs.
- **The `agents` IPs are ephemeral** and had already drifted out from under
  `SECURITY.md`. A doc that quotes container IPs is a doc that will lie; the
  stable handle is the service name.
