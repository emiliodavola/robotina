# Feature: gated-claim-and-aistudiocdn

## Goal

Close #87: fix two measured defects that the merged PR #86 (#85) left behind.

1. **A false claim in the docs and in the contract.** `google/gemma-4-31B-it-qat-w4a16-ct` is
   **not** a gated repository, and #85's premise ("repo gated") was inherited into `README.md`,
   `README.en.md`, `SECURITY.md`, `hermes/context/.hermes.md` and the **CR11** requirement.
2. **A check that cannot fail.** The documented probe (`hf download … --dry-run`) proves nothing
   about access, because the metadata is public. It has to be replaced by a probe whose 4xx becomes
   a non-zero exit code.
3. **A wrong CDN host in the docs and in the allowlist comment**, and `aistudiocdn.com` left
   disabled although the owner asked for it in the same breath.

Branch: `fix/issue-87-gated-claim-and-aistudiocdn`, off `main`. Owner: `emiliodavola`.

## Diagnosis (measured, read-only, 2026-09-30, no credential involved)

1. **`"gated": false`.** `curl https://huggingface.co/api/models/google/gemma-4-31B-it-qat-w4a16-ct`
   returns `"private":false` and `"gated":false`. An anonymous request with `Range: 0-100` to
   `resolve/main/model.safetensors` answers `302` to
   `https://us.aws.cdn.hf.co/xet-bridge-us/…?user_id=public&X-Xet-Cas-Uid=public…`, and following it
   returns **`206`** — a real byte of the weights, with no token at all.
2. **Every "gate" probe is blind for the same reason.**
   | probe | anonymous | with token |
   | --- | --- | --- |
   | `GET /api/models/<repo>/tree/main` | `200` | `200` |
   | `GET resolve/main/config.json` | `307` | `307` |
   | `GET resolve/main/config.json` `-L` | `200` | `200` |
   | `hf download <repo> --dry-run` | exit `0` | exit `0` |
   | `GET resolve/main/model.safetensors` `-r 0-100` | `302` -> `206` | `302` -> `206` |
   `hf auth whoami` does distinguish *identity* (`Not logged in` vs `user: emiliodavola`), but it
   says nothing about a licence.
3. **`--dry-run` cannot fail by construction**: it lists the repo's file inventory
   (`.gitattributes`, `README.md`, `config.json`, `model.safetensors`, …), which the Hub serves
   publicly. A green `--dry-run` is not evidence of access.
4. **The measured CDN host is `us.aws.cdn.hf.co`**, not `cas-bridge.xethub.hf.co` (the name the
   issue mentioned and the comment repeated). Both fall under the `.hf.co` entry, so the ACL was
   correct and only the prose was wrong.
5. **`aistudiocdn.com` is denied today**: `domain=aistudiocdn.com method=CONNECT squid=TCP_DENIED
   http=403` and the response carries `Server: squid`. It is the CDN that serves the apps AI Studio
   generates (the `importmap` of their `index.html`); the owner asked for it in this same follow-up.

## Shape

1. Docs correction, affirmative to conditional: the repo is public **today** (measured), the token
   stays wired and is still worth setting (HF gates can be turned on, and the licence terms still
   apply), and a `401/403` means "a gate appeared or the token is spent", never "the allowlist".
2. The probe that **can** fail, in the docs and as a CR11 scenario: a ranged read of one byte,
   `curl -fsS -r 0-100`, because `-f` turns `401/403/404` into a non-zero exit status while a bare
   `curl` exits `0` on 4xx. It also exercises the redirect to the CDN, which is the egress proof for
   `.hf.co`.
3. `squid/allowlist.txt`: uncomment `aistudiocdn.com` with the reason written next to it, and name
   the measured CDN host in the Hugging Face comment.
4. CR11 rewritten to assert what is measured, with the useless probe documented as useless (a NOTE),
   so nobody reintroduces it as a gate check.

## Tasks

- [ ] T1 — Branch, issue #87 and this tracker.
- [ ] T2 — `squid/allowlist.txt`: enable `aistudiocdn.com`, fix the CDN host comment. Recreate the
      proxy and verify the tunnel.
- [ ] T3 — Docs: `README.md`, `README.en.md`, `SECURITY.md`, `hermes/context/.hermes.md`.
- [ ] T4 — Contract: `openspec/specs/agent-credentials/spec.md` CR11.
- [ ] T5 — Verification: the recipes of both axes, plus an independent read-only verifier.
- [ ] T6 — Push and PR against `main` (`Closes #87`), assigned to `emiliodavola`.

## Verification

| Fact | Recipe |
| --- | --- |
| The gate claim is what the API says | `docker compose exec robotina sh -c 'curl -sS -m 25 https://huggingface.co/api/models/google/gemma-4-31B-it-qat-w4a16-ct \| tr "," "\n" \| grep -E "\"gated\"\|\"private\""'` |
| The new probe can fail (and passes today) | `docker compose exec robotina sh -c 'curl -fsS -m 30 -o /dev/null -r 0-100 -H "Authorization: Bearer $HF_TOKEN" https://huggingface.co/google/gemma-4-31B-it-qat-w4a16-ct/resolve/main/model.safetensors && echo acceso-ok'` (exit 0; a 4xx makes it exit 22) |
| The new probe really fails on a 4xx | same command pointed at a nonexistent path: `curl -fsS -o /dev/null -r 0-100 https://huggingface.co/google/gemma-4-31B-it-qat-w4a16-ct/resolve/main/no-existe.json` (exit non-zero) |
| `aistudiocdn.com` is admitted now | `docker compose exec robotina sh -c 'curl -m 15 -sS -o /dev/null -D - https://aistudiocdn.com/ \| head -2'` (no `Server: squid`; the origin answers) and `docker logs egress-proxy 2>&1 \| grep aistudiocdn \| tail -2` (`TCP_TUNNEL`) |
| The allowlist still parses | `MSYS_NO_PATHCONV=1 docker compose run --rm --no-deps --entrypoint /usr/sbin/squid egress-proxy -f /etc/squid/squid.conf -k parse` (exit 0) |
| Compose still validates | `docker compose config -q` (exit 0) |
| The false claim is gone | `grep -rniE "gated" README.md README.en.md SECURITY.md hermes/context/.hermes.md` — every remaining mention must be conditional and anchored in the measurement |

## Route declaration

- Classification: **small but precision-heavy** (five documentation files plus one contract
  requirement, all stating measured facts, plus one allowlist line and a proxy recreate).
- Delegation: the parent owns the issue, the tracker, the allowlist, the recreate and the
  verification; the five documentation/contract files go to one writer with the measured evidence
  handed over. Independent read-only verification goes to `gentle-ai-verify`.
