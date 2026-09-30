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

- [x] T1 — Branch, issue #87 and this tracker. Commit `a1c9931`.
- [x] T2 — `squid/allowlist.txt`: `aistudiocdn.com` enabled, CDN host comment fixed, proxy recreated
      and verified. Commit `25480ac`.
- [x] T3 — Docs: `README.md`, `README.en.md`, `SECURITY.md`, `hermes/context/.hermes.md` (including the
      `hf auth whoami` identity hint it gained), the stale `aistudiocdn.com` prose, the `compose.yml`
      comment and the `#85` tracker annotation. Commit `25cb815` plus the verifier follow-up.
- [x] T4 — Contract: `openspec/specs/agent-credentials/spec.md` CR11. Same commits.
- [x] T5 — Verification: the recipes of both axes, plus `gentle-ai-verify` over `main..HEAD`. Done; its
      findings are recorded below and fixed in the follow-up commit.
- [x] T6 — Push and PR against `main` (`Closes #87`), assigned to `emiliodavola`: **PR #88**.

## What the independent verifier found (and what was done about it)

It attacked ten claims and could not falsify nine. The tenth was real and severe, and its MEDIUM/LOW
findings were all accepted:

- **HIGH — the probe did not follow the redirect.** `curl` without `-L` stops at Hugging Face's `302` and
  downloads the *redirect body* (measured: `code=302 bytes=1124`, and the proxy log shows only
  `domain=huggingface.co`). So the three sentences claiming the probe "exercises the redirect to the CDN"
  were false, and the probe was a **false green** for the `.hf.co` allowlist entry: deleting that entry
  would not have made it fail. Fixed by adding `-L`, which was then measured: `code=206 bytes=101`, real
  weight bytes, with `domain=us.aws.cdn.hf.co … squid=TCP_TUNNEL http=200` in the log. The negative
  control still cuts (`no-existe.json` -> exit `22`).
- **MEDIUM — an over-claim about the credential.** The branch said a non-zero exit means "an expired token".
  Measured: with a public repo, a bogus bearer also receives `206`. The claim is gone from the READMEs,
  `SECURITY.md` and CR11; what remains is what the probe actually catches (a 4xx/5xx, and with `-L` a CDN
  host missing from the allowlist) plus the explicit statement that it does **not** test credential validity.
- **MEDIUM — a PROOF recipe that could not fail.** The `aistudiocdn.com` recipe ended in `| head -2`, which
  makes `curl` die with EPIPE (exit 23) and never shows the origin's block. Replaced by a status-only form,
  below.
- **MEDIUM — CR11's recipes proved less than their NOTE claimed.** The model-id grep matched the id inside
  the probe URL, and the status grep skipped `README.en.md`, so a bilingual desync would have passed. Both
  replaced by fail-closed forms (`test "$(grep -c … | grep -c ':0$')" -eq 0`) and the NOTE now claims only
  what they prove.
- **LOW** — the bold lead still read "a gated repo" (now the measurement leads); "26 hits" (now 27, see the
  table); `compose.yml` said "HOY" with no measurement date (now dated); the new Spanish prose had lost its
  diacritics (restored); and the log recipe was order-sensitive (now one grep per host).

## Verification

Every row was run. This branch needs no rebuild: the image is the one #85 left, and the
`hermes/context/.hermes.md` it touches is a live read-only bind.

| Fact | Recipe | Result |
| --- | --- | --- |
| The gate claim is what the API says | `docker compose exec robotina sh -c 'curl -sS -m 25 https://huggingface.co/api/models/google/gemma-4-31B-it-qat-w4a16-ct \| tr "," "\n" \| grep -E "\"gated\"\|\"private\""'` | `"private":false`, `"gated":false`, anonymously |
| The redirect host is the measured one | anonymous ranged read with `-L` | `302` -> `us.aws.cdn.hf.co/xet-bridge-us/…?user_id=public…` -> `206` |
| The probe passes today | `docker compose exec robotina sh -c 'curl -fsSL -m 30 -o /dev/null -r 0-100 -H "Authorization: Bearer $HF_TOKEN" <resolve url> && echo acceso-ok'` | `acceso ok`, exit 0 (`206`, 101 bytes) |
| The probe touches the CDN | `docker logs egress-proxy \| grep -c "domain=us.aws.cdn.hf.co.*TCP_TUNNEL"` | non-zero, and only with `-L`; without `-L` the log shows `huggingface.co` alone |
| The probe can fail | the same shape against `resolve/main/no-existe.json`, with `-L` | exit **22** |
| …and it does NOT test the credential | the same shape with `-H "Authorization: Bearer token-basura-000"` | `206` — recorded as a limit, not as a check |
| `--dry-run` is not a probe | `hf download <repo> --dry-run`, with and without a token | exit 0 in both cases |
| `aistudiocdn.com` is admitted | `docker compose exec robotina sh -c 'curl -m 15 -sS -o /dev/null -w "%{http_code}\n" https://aistudiocdn.com/'` | `200`, exit 0 |
| …and the proxy logged it | `docker logs egress-proxy \| grep -c "domain=aistudiocdn.com.*TCP_TUNNEL"` | `9` |
| Fail-closed is intact | the same status form against a non-allowlisted host | `000` with `curl: (56) CONNECT tunnel failed, response 403`; `docker logs egress-proxy \| grep -c "domain=example.com.*TCP_DENIED"` -> `3` |
| The allowlist still parses | `MSYS_NO_PATHCONV=1 docker compose run --rm --no-deps --entrypoint /usr/sbin/squid egress-proxy -f /etc/squid/squid.conf -k parse` | exit 0 |
| Compose still validates | `docker compose config -q` | exit 0 |
| The false claim is gone | `grep -rniE "gated\|licencia\|licence"` over the five files | 27 hits, every one conditional, measured, or about the CLI's capability; none asserts the gate as a present fact |
| The measured status is in all three documents | `grep -c '"gated": false' README.md README.en.md SECURITY.md` | `2` / `2` / `1` — non-zero in each, which is the fail-closed form CR11 now asserts |
| The wrong CDN host is gone | `grep -rn cas-bridge README.md README.en.md SECURITY.md hermes/context/.hermes.md` | empty; `us.aws.cdn.hf.co` present in both READMEs |

## Out-of-band finding (pre-existing, NOT from this change)

`robotina` reports `unhealthy`: the healthcheck's check #4 fails because `/opt/data/.local/bin/gentle-ai`
(hermes-owned, dated 2026-09-29) precedes `/usr/local/bin` on the `PATH` and shadows the baked binary.
This is exactly the failure mode `#42`/`#74` built that check for, it predates this branch (the container
was already unhealthy before any change here), and the healthcheck prints the remedy it wants:
quarantine the shadowing copy with `mv` (never `rm`). It is state in the bind, not repository content, so
this branch does not touch it — reported to the owner instead.

## Route declaration

- Classification: **small but precision-heavy** (five documentation files plus one contract
  requirement, all stating measured facts, plus one allowlist line and a proxy recreate).
- Delegation: the parent owns the issue, the tracker, the allowlist, the recreate and the
  verification; the five documentation/contract files go to one writer with the measured evidence
  handed over. Independent read-only verification goes to `gentle-ai-verify`.
