# e2e4-pre4 — contract readiness and failure evidence

13 November 2026. Harness repairs are committed locally; nothing was pushed. All four supplied contract failures happen before product installation. No new product defect is established. Eighteen targeted harness tests passed; the real four-job Opal matrix remains unverified.

## Commits and scope

Harness: `/tmp/claude-1000/-workspace-app/a9e21344-5d10-4451-a8b6-63b53826c6ca/scratchpad/dsomop-e2e`, branch `main`, starting HEAD **27478a5**.

- **8fa067a** — wait for valid pinned Opal and running default Rock before exporting stack configuration; real local HTTP/curl regression tests.
- **13de084** — retain redacted results on separate branches after failures; workflow status and command logs; failure-path tests and README.
- The documentation commit containing this report is discoverable with `git log -1 --format='%H %s' -- docs/e2e4-pre4/report.md`.

Existing **29901ea** had already fixed the original plain-text-version JSON parsing mistake. That repair was retained and strengthened, not claimed as new work. No WIP commits required action in the relevant history.

Product worktrees remain clean and unchanged on `feat/2.10.3`:

- `/workspace/dsomop/wt/int/dsOMOP`: **22c7ef57fc8e17b3109af611883b8782cd5c1d6b**.
- `/workspace/dsomop/wt/int/dsOMOPClient`: **30a9794b4fe30c7b04f30390686157bf67ff4a63**.

Both versions remain 2.10.3, the integrated candidate for the prospective 2.10.4 gate. Comparing DESCRIPTION, NAMESPACE, R/, inst/, src/ and tests/ with the vendored sources found no differences: 663 server files and 198 client files. No product modification, NEWS entry, version bump, re-vendoring or frozen-interface change request was warranted.

## Findings mapped to repairs and tests

| Finding | Fix | Targeted test |
|---|---|---|
| Four jobs decode dotted plain-text versions as JSON; startup also returns resets and HTTP 400s. | Retain exact plain-text version matching. Separate HTTP status, body and curl diagnostics. Accept only HTTP 200 with valid content. Retry transport errors, other statuses and malformed content; fail immediately on a well-formed different version. | `scripts/tests/o-stack.py`: both pins, resets, 400/503, redirects, truncated bodies, HTML/empty/wrapped bodies and exact-version refusal. |
| Version readiness does not establish Rock readiness. | Independently wait for `/ws/service/r/clusters`; defensively parse JSON and require a running server in the default cluster. Export environment only after readiness, nonempty Docker network and successful image inspection. | Same file: malformed JSON/shapes, absent/stopped/non-default servers, strict boolean handling, exhaustion at either endpoint, Docker failures and missing network. |
| Contract jobs have no results branch when artifact/log services fail. | Contents-write permission; collect with `always()`; publish before artifact fallback. Branch format is `results/<run>-<attempt>-opal-<version>-<path>-candidate`, distinct for all jobs and reruns, without force push. | `scripts/tests/o-results.py`: four failed bootstrap jobs reach a mocked push, with four distinct branches; reruns get another branch. |
| Early failures may leave OUT/passwords unset and failure output uncaptured. | Create OUT before preflight and during collection; tee commands under Bash pipefail. Save available container/status logs and workflow-status.json with source SHA, run/attempt, matrix identity, job status and named step outcomes. | Same file: failure before output/password setup, missing containers, nonzero bootstrap and R-install pipelines, retained failure logs/status. |
| Both publication routes need consistent redaction and independent recovery. | Literal nonempty password/token byte replacement, including raw response bytes. Require successful collection/redaction for publishing/uploading. Artifact fallback runs after push failure; cleanup remains unconditional. | Same file: punctuation-bearing secrets, binary response bytes, empty/unset passwords, token removal, push failure and finalizer conditions. |

Each readiness endpoint allows 90 attempts, five-second pauses, a five-second connection timeout and a 15-second request timeout. Exhaustion fails explicitly and retains last response/status/diagnostics. Scenario assertions and image pins are unchanged.

The cluster parser matches the pinned upstream protobuf definitions for [Opal 5.7.6](https://raw.githubusercontent.com/obiba/opal/5.7.6/opal-web-model/src/main/protobuf/OpalR.proto) and [Opal 6.1.3](https://raw.githubusercontent.com/obiba/opal/6.1.3/opal-web-model/src/main/protobuf/OpalR.proto): cluster name/servers and a required boolean running field. The saved e2e output has that shape too.

## Input evidence and product assessment

`43472800948-failed.log`: 599,595 bytes, SHA-256 `064ac8886073c6f792e752bcf2d31f67919217622099e87bbb507cd321ae3019`. JSONDecodeError locations: 5.7.6 upgrade line 857; 6.1.3 upgrade line 1887; 5.7.6 fresh line 2958; 6.1.3 fresh line 4002. All are in **Pinned Opal and Rock**, before package installation. O1–O12 were not exercised. The original log is already committed under `docs/e2e4-fix3/`.

`43472806671-failed.log` is empty. Directly rechecked result refs contain:

| Result ref | Immutable commit | Verdicts |
|---|---|---|
| `res/43472806671-fresh-candidate` | `075e49cf874f3dc0390657468be5dc11bda0b925` | G: 88 PASS, 12 INFO; old client: 10 PASS |
| `res/43472806671-upgrade-candidate` | `24e8704e61ed0574c35cfdb36c455c9ae537c3d5` | G: 90 PASS, 15 INFO; old client: 10 PASS; V: 3 PASS, 2 INFO |

Zero FAIL/ERROR rows occur in these verdict files. The earlier comprehensive classification remains in `docs/e2e4-fix3/`. No new product defect is established; these results do not certify the blocked O scenarios or an unavailable GitHub workflow conclusion. `docs/e2e4-pre4/input-audit.json` records hashes, refs, counts and product comparisons.

## Validation

- **10 tests PASS:** `python3 scripts/tests/o-stack.py -v`, against the exact working-tree source subsequently committed as **8fa067a**, unchanged at **13de084**. Real curl/local HTTP server, Docker stand-in.
- **6 tests PASS:** `PYTHONPATH=/tmp/dsomop-e2e4-pre4-python python3 scripts/tests/o-results.py -v`, against source subsequently committed as **13de084**; only README changed after the test. PyYAML 6.0.3 reads the actual workflow. Docker, Rscript and every git operation are stand-ins. No real push occurred.
- **2 tests PASS:** `python3 scripts/tests/o-candidate.py -v` on **13de084**; output in `docs/e2e4-pre4/o-candidate.log`.
- Candidate preflight passes on **13de084**: matching integrated 2.10.3 sources and frozen inputs.
- Changed Python AST, Bash syntax, workflow YAML, every embedded workflow shell command and `git diff --check 27478a5..13de084` pass.

`docs/e2e4-pre4/validation.json` records commands, source commits and boundaries. No R test files were run because no R/product code changed. No full suites were run, following the user and COMMON.md targeted-test rules.

## Handoff, limitations and housekeeping

The coordinator can push the local harness commits and dispatch the four-job matrix. CI will then publish its own results branches. workflow-status.json is captured before publication/cleanup and is not a final GitHub job conclusion. A collection/redaction failure intentionally prevents unsanitized publication. Checkout failure or runner loss can also prevent finalizers.

Docker is not installed locally. No real stack or GitHub workflow was run, and no O1–O12 success is claimed. This is the remaining validation limitation.

The requested report location is outside git; an identical committed copy lives at `docs/e2e4-pre4/report.md`. Disk free space was 9.6 GiB; CLEANUP.md was read. No large package copies or R libraries were created. The only removed scratch directory was this job's temporary PyYAML installation, `/tmp/dsomop-e2e4-pre4-python` (3,180,367 bytes). A bundled write/cleanup command was rejected before execution because it used `rm -rf`; cleanup was retried safely with Python on that exact job-owned directory.

No other worktrees, primary checkouts, frozen interfaces, thresholds or pins changed. No push, PR, tag, stash, sub-agent or Claude CLI was used.
