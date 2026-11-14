# e2e4-pre8 — real-Opal gate verification

14 November 2026. The latest supplied real-Opal evidence is green: run **43515122503**, harness **17e5df4**, passes O1–O12 in all four Opal/version/path combinations, and all four separate old-client steps pass. The reported startup failure belongs to the older run **43472800948**. Its repairs were already committed in the supplied checkout. I reviewed and retained them, reran their targeted regression tests, and committed an offline evidence audit. No further harness runtime or product correction was warranted by the supplied evidence.

## Commits and scope

- New commit **f841d48**: reproducible offline audit, immutable result-ref IDs, log hashes, source hashes, product/vendor comparison, and fresh targeted test logs in `docs/e2e4-pre8/`.
- The following documentation commit, titled **Record pre-eighth-run resolution and exact candidate validation limits**, contains this report. The requested `/workspace/dsomop/design/astra-dev/e2e4-pre8.report.md` is an identical copy; that directory is not a Git repository.
- Retained harness fixes: **8fa067a** (readiness), **13de084** (failed-job publication), **5fe355a** (scenario lifecycle), **0801cdd** (administrator fixtures), **020c86b** (categorical transport checks), **18a94db**, **cb90333**, and **d784164** (installed oracle, read-only fixtures, exact keys and transaction boundaries).
- Product worktrees remain clean on `feat/2.10.3`: server **27383ea**, client **b099df5**, both version **2.10.4**. No product commit was created in this job.

No push, PR, tag, CI dispatch, Claude CLI, delegated agent, full suite, or unrelated worktree edit occurred. The workflow's push implementation was inspected and tested with intercepted Git commands only.

## Findings mapped to fixes and tests

| Finding | Retained fix | Verification in this job |
| --- | --- | --- |
| The original stack parsed the plain-text version response as JSON, producing `Extra data` at column 4 | `8fa067a`: compare `/ws/system/version` as plain text against the exact pin; parse JSON only for the cluster endpoint | `o-stack.py`: both supported pins, malformed bodies, wrong version, redirects, HTTP 400, connection reset and truncated responses |
| Opal may answer before its default Rock server is running | Bounded curl connect/request/process timeouts and retry count; require a running server in the default cluster; export stack variables only after readiness succeeds | `o-stack.py`: default cluster shape/running state, timeout retries, exhaustion, stale/partial response rejection; latest actual matrix has stack success in all four jobs |
| Failed contract jobs need durable results | `13de084`: `always()` evidence collection and publication after successful credential redaction, with run/attempt/version/path-specific branches and artifact fallback | `o-results.py`: four startup failures, failed R dependency install, failure before setup, rerun isolation, push failure; all four earlier `43506711667` failed scenario jobs have result branches and failure metadata |
| Prior O2 categorical outputs failed DataSHIELD factor requirements | Existing server `83761ba`, vendored by `10eae58`, plus transport coverage `020c86b` | Latest actual O2/O5 and all other contract scenarios pass on both versions and paths; no new product regression established |
| Later administrator assertions failed after startup had been repaired | `18a94db`, `cb90333`, `d784164`: current key lookup, source files executed without writes, decimal analytic keys, committed fixture mutations before executor snapshots, restoration on failure | Latest actual O2/O3/O5/O7/O11 all pass; old-client step independently succeeds |
| Empty downloaded failed logs do not prove success | New offline audit checks concrete result metadata, exact 12 distinct scenario IDs, all verdicts, independent old-client evidence, and source commit | `docs/e2e4-pre8/audit.py`; all assertions pass; `input-audit.json` preserves evidence |

The readiness code keeps HTTP status, body and curl diagnostics separate. It clears the body before each request, accepts only successful HTTP 200 responses with valid expected content, and retains final body/status diagnostics on failure. Result publication remains conditional on successful collection/redaction, not product success; this prevents sending unsanitized evidence if redaction fails.

## Downloaded real-Opal results

All four refs below are under `refs/remotes/res/43515122503-1-opal-<version>-<path>-candidate`. Each records source `17e5df40f4718bdece091f68d3003c764f061854`, `JOB_STATUS=success`, every recorded step successful, **12 PASS / 0 FAIL**, and a separate O6 old-client PASS.

| Opal | Path | Result commit | Version readiness attempt |
| --- | --- | --- | --- |
| 5.7.6 | fresh | `e8978543ed5f9d9dfd3c9b5d87a74381f1aedae4` | 5 |
| 5.7.6 | upgrade | `854ac0e1af399b8524fa14ab64ae06b59b938fbe` | 9 |
| 6.1.3 | fresh | `8bbe513c0678fbf7d74aa204a7642a23e98c7a23` | 5 |
| 6.1.3 | upgrade | `f6b24cabdd4c170dfc42792b02b3287593870f4c` | 5 |

The companion **43515127555** results contain no failing verdicts: fresh G **88 PASS / 12 INFO**, upgrade G **90 PASS / 15 INFO**, old-client **10 PASS** on each path, and upgrade V **3 PASS / 2 INFO**. INFO is not counted as PASS. The fresh method audit separately contains 68 PASS, 4 NOT-EXERCISED and 1 REFUSED. No claim is made that those five entries passed. Contract workflow status was captured before publication and cleanup; the existence of the downloaded branches demonstrates publication, but that status does not certify later cleanup.

## Targeted validation performed now

All runtime and test sources match **17e5df4** byte-for-byte; `tested-sources.json` records SHA-256 hashes. Tests ran locally with Python 3.11 and task-local PyYAML 6.0.3:

- `scripts/tests/o-stack.py`: **11 tests passed**. Actual local HTTP server and curl; Docker stand-in.
- `scripts/tests/o-results.py`: **7 tests passed**. Executes workflow shell snippets with Docker/R/Git stand-ins; no real push.
- `scripts/tests/o-candidate.py`: **2 tests passed**.
- `docs/e2e4-pre8/audit.py`: all evidence assertions pass, including complete four-job success and four earlier failure-publication records.
- Shell syntax for `scripts/o/stack.sh` and `scripts/o/publish-results.sh`, workflow shell syntax within the results tests, and Git whitespace checks pass.

Exact outputs are in `stack.log`, `results.log`, `candidate.log`, and `audit.log`. No R test file ran in this job: no R implementation or fixture was changed, and the supplied actual CI results already exercise the retained repairs. Earlier targeted pod evidence remains in `docs/e2e4-pre7/`. No full suite was run, following the explicit user instruction and COMMON.md test-economy rule.

## Candidate limits and handoff

The green real-Opal run installed the integrated candidate still labelled **2.10.3** (server `83761ba`, client `9ee5197`), not the exact current **2.10.4** release trees. The current server differs in 11 tracked files; the client differs in 919, largely generated documentation. `vendor-comparison.json` enumerates them. All R sources match after removal of comment-only lines, and both NAMESPACE files match exactly. The only changed R source is the client's roxygen comment escaping in `R/dates.R`; metadata, documentation and regression fixtures also changed. Thus the green run establishes the requested runtime repairs, but is not an exact-current-release build certification.

Deviation from a new repair implementation: the requested fixes already existed and now have passing real-Opal evidence. Replacing them or altering the product without a remaining defect would add unneeded risk. Vendored packages were left intact so the passing evidence remains traceable. The coordinator/release job should vendor the exact coordinated 2.10.4 pair and run its release gates when certifying that artifact; full suites remain that job's responsibility.

No Docker executable is available locally. I did not launch another real stack or trigger GitHub workflows. Workspace free space was 11 GB; no large package copies were made. The task-local 3.2 MB PyYAML installation under `/tmp/e2e4-pre8-python` was removed after writing the evidence logs. No pod state or shared library was changed.
