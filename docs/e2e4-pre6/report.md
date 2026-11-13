# e2e4-pre6 — integrated real-Opal gate repairs

13 November 2026. Work was confined to `wt/int/{dsOMOP,dsOMOPClient}` on `feat/2.10.3`, the supplied harness checkout, and this report. No push, tag, PR, CI dispatch or claude CLI invocation. Package versions remain coordinated at 2.10.3, the source candidate for integrated 2.10.4.

## Commits

- Server `83761ba`: categorical publication, private staged factor domains, Arrow row-group size, v1 age-band staging parity, and lineage-key performance repair; regression matrix and NEWS.
- Client `dc2260f`: reconcile non-concept categories independently of concept-label opt-out; three-site DSLite regression and transport-only publication fixture correction.
- Harness `0801cdd`: administrator session scope/cleanup and O8/O11 refusal assertions.
- Harness `020c86b`: real-Rock categorical class/level/value comparison between memory and staging.
- Harness `10eae58`: vendor the exact integrated product changes.
- Client `9ee5197`: restrict three transport-only fixtures to raw baseline columns; harness `240251a` vendors that test correction.
- The final evidence commit contains this report itself.

## Input evidence and readiness/publication

`input-audit.json` records SHA-256/size for every supplied `*-failed.log` (including the coordinator note and empty logs), immutable result-branch commits, verdicts and timing evidence. The original `43472800948` startup failure was caused by treating the plain-text version response as JSON while Opal/Rock were still starting. At entry, the checkout already included fixes `8fa067a` (readiness), `13de084` (failed-job branches), and `5fe355a` (stalled curl handling). I reviewed and retained them rather than undoing the later repairs.

The stack now accepts only the exact pinned plain-text version, then a valid JSON default R cluster with a running server. It separates curl exit, HTTP status, diagnostics and response body; rejects stale/partial/non-JSON bodies; retries 400/reset/not-running responses and subprocess timeouts within bounded attempts; and fails immediately on a different valid version. Eleven readiness tests pass.

The workflow always collects/redacts evidence, records each step's outcome, publishes a unique result branch for every matrix/run/attempt after failures, uploads an artifact fallback, and removes the stack. Six result-publication tests pass; their git operations are mocked and did not push. The four newer `res/43493229424-1-opal-*` branches independently demonstrate that startup passed and failed jobs actually published evidence. Those branches expose the next defects; the original startup error is not the current root cause.

## Findings mapped to fixes and checks

| Failure / finding | Repair | Targeted verification |
| --- | --- | --- |
| O2: derived `sex_mf` was character, so `ds.levels` failed on every real-Opal configuration | Publish an unordered factor with fixed public F/M levels, including locally unused levels; preserve private evaluation types | Server categorical matrix; three-site client memory/staged probe; `ds.levels`, `ds.table`, Gaussian `ds.glm` versus pooled reference; O2 class assertion |
| Other categorical holes found by audit: native legacy-age bands and birth-year bands; person-period age/month/year categories; v1 baseline age groups and binned dates | Attach private category domains and present at the final boundary; ordered domains use existing controlled date metadata, public levels and deterministic numeric ordering | Native output/path matrix; v1 baseline/features; empty legacy date frames; disjoint numeric bands ordered 2 before 10; concept-opt-out client probe |
| O5: real Rock log shows `writer$WriteTable(table)` missing required `chunk_size` | Supply a positive row-group size in both presentation rewrite paths | Actual Arrow/Parquet private rewrite, empty and populated streams; staged reconciliation and federation tests |
| CSV/Parquet ordinary factors lose unused levels or order | Store ordinary factor domains in private manifest-bound descriptor metadata and restore on read; controlled concept/date columns use their current reconciled capsule | Both physical formats, unused levels, orderedness and values; existing concept federation regressions |
| v1 staged baseline rejects public age breaks 0/18/65 even though memory assignment permits them | Stop applying the aggregate age grid to assignment; retain integer/increasing/starts-at-zero validation | v1 memory/staged, translation on/off probe; existing staging-contract tests |
| O3/O7 administrator `ores` not found | Initialize/get/close the handle in the invoking Opal session; run revocation/rollback before closing it | Actual helper evaluated with session-sensitive stand-ins, including injected failure cleanup |
| O8 pools two sessions on the same Rock privacy node | Assert duplicate-noise-domain refusal, then release on one connection; preserve non-person-local matching refusal | Actual O8 expression executed with stand-ins; product privacy guard unchanged |
| O11 falsely reports relaxed aggregate admission | Recognize explicit refusal warnings in a `dsomop_result` only if no per-site or pooled values were returned; still recognize explicit errors | Positive and negative refusal probes, including results that contain data |
| O9 upgrade timing exceeds 25% | Vectorize exact integer lineage-key formatting and format other numeric values once per distinct value | Scalar-byte equivalence tests including fractions, large/nonfinite values; same targeted panel profile fell from 8.48 to 5.92 sampled seconds |
| O10 | Consequence of O1–O3 failure, not a separate product defect | Retained the upgrade gate; no assertion weakened |

The O9 measurements are local diagnostic profiles, not proof of the real-Opal timing gate. The 25% gate remains unchanged.

## Systematic categorical coverage

The native matrix covers wide, long, survival date covariates, joined, temporal panels, person-period, sparse, membership and dictionary outputs. It checks memory, forced CSV and actual Parquet, asserting factor class, orderedness, levels and labels after private file reads and eligible staged reconciliation. Tiny fixture components that fail the distinct-person level gate are asserted to refuse reconciliation; their private file round-trip is still audited. The test does not lower production disclosure rules.

Kinds include concept labels and ID fallback, explicit recodes and unused declared labels; sex; age and birth-year bands; age-at bands; month/weekday/season; year/quarter/month, ISO/CDC/epi weeks, fiscal year/quarter. Separate v1 baseline/features checks cover their compatibility paths and concept translation opt-out. Existing concept/date tests cover generated names, ID fallback resolution and custom calendar range/order contracts.

Concept-derived column **names** remain strings, and the numeric measures they name remain numeric. Sparse/panel concept identifiers are factors in the reference component, not their analytic measure columns. Membership cohort IDs, row keys, counts and numeric date representations remain numeric. Native survival has date covariate slots; ordinary non-date covariates use the wide/joined path. These are applicability distinctions, not untested categorical exemptions.

Across three DSLite servers, the client verifies identical factor levels and ordering with a sex and birth-year band absent locally, an unused declared concept label, memory and staged output, and concept translation/factor opt-out. Real dsBase calls operate on the published protected table. The real-Opal harness now checks sex with `ds.class` and administrator-side factor class/order/domain/value parity for memory and staged output. That added real-Opal check is committed but has not been live-run here.

## Validation and scope

All product R tests used `/workspace/dsomop/tools/rtest.sh` on the pod (R 4.6.2); no full suites. The client runs installed the matching server using `RTEST_WITH`. Actual Arrow was installed in task-owned `/root/rt/pre6-deps`; existing dsBase dependencies were supplied from `/root/rt/labels-deps`. No public API documentation or frozen schemas were changed; NEWS classifies the corrected output behavior and tells callers to recreate outputs and use labels rather than integer factor codes.

Evidence logs retain intermediate failures transparently: invalid initial test fixture parameters, a stale controlled-factor domain introduced during development and then corrected, an inherited DSLite `datashield.env`, and transport-only mocks that accidentally requested derived categorical columns. None is hidden as a passing run. Final targeted results and precise source attribution follow below.

| Evidence | Exact test files / checks | Source and result |
| --- | --- | --- |
| `server-final.log` | `test-e2e4-categories.R` | Server `83761ba`: **1,155 passed, 0 failures/errors/skips** |
| `server-dependencies-final.log` | `test-assignment-policy.R`, `test-compile-reduce.R`, `test-concept-label-presentation.R`, `test-publication.R`, `test-date-system-outputs.R`, `test-extraction.R`, `test-publication-compiled.R`, `test-staging-contract.R`, `test-staging-csv.R` | Server `83761ba`: **1,990 passed, 0 failures/errors/skips** |
| `client-final.log` | `test-e2e4-categories.R`, `test-publication-status.R` | Exact tree committed as `dc2260f`, matching server `83761ba`: **313 passed, 0 failures/errors/skips** |
| `client-ergonomics-final.log` | `test-phase-e-ergonomics.R` | Client `9ee5197`, server `83761ba`: **102 passed, 0 failures/errors/skips**; final fixture SHA-256 checked against pod |
| `client-protocol-round1.log` | `test-v2-execution.R`, `test-v2-plan.R`, `test-v2-review.R`, `test-phase-e-ergonomics.R` | Client `dc2260f`, server `83761ba`: three v2 files passed; combined run 320 assertions passed / 3 ergonomics errors. Those three fixture errors are corrected and covered by the clean final ergonomics run above |
| `client-round3.log` | `test-concept-label-analysis.R`, `test-concept-label-federation.R`, `test-date-range.R`, `test-date-review-fixes.R`, `test-e2e4-categories.R` | Working tree based on client `30a9794` / server `1c2803f`, including controlled-factor domain correction: four existing files passed; combined 433 assertions passed / 1 new-probe setup error. Final isolated fixture sets its DSLite environment and passes above |
| `stack.log`, `results.log`, `candidate-final.log` | `scripts/tests/o-stack.py`, `o-results.py`, `o-candidate.py` | Retained readiness/publication implementation and harness through `240251a`: **11 + 6 + 2 tests passed** |
| `harness-contract.log` | `scripts/tests/o-contract.R` | Harness `0801cdd`/`020c86b`: **7 named probes passed** on pod, exercising actual helper/scenario expressions with stand-ins |

Earlier development evidence remains in `server-initial.log`, `server-round2.log`, `server-round3.log`, `server-round4.log`, `client-categories.log`, `client-round2.log` and `client-round4.log`. These ran the same changed files and direct dependencies listed here, on working trees based on server `1c2803f` and client `30a9794` before the final commits. Server dependencies were `test-assignment-policy.R`, `test-compile-reduce.R`, `test-concept-label-presentation.R`, `test-publication.R`, `test-date-system-outputs.R`, `test-extraction.R`, `test-publication-compiled.R`, `test-staging-contract.R` and `test-staging-csv.R`. The temporary O9 profile used the targeted `test-e2e4-profile.R` path; the tracked original was restored exactly, and the probe is saved separately as `panel-profile.R` with `profile-before.log` and the post-optimization profile in `server-initial.log`.

`vendor-manifest.json` hashes each changed vendored file and records integrated commit IDs. `vendor-comparison.json` compares **every tracked file**: 2,078 server and 1,331 client files, zero mismatches. The candidate guard passes with matching source versions. Source/report whitespace checks pass. Raw test logs are preserved byte-for-byte, including testthat trailing spaces, so a whitespace check over those evidence logs reports those original spaces.

## Remaining integration validation and cleanup

No live Docker/Opal stack was available in this task environment, and I did not push or dispatch CI. The coordinator should run all four real-Opal fresh/upgrade jobs from the committed harness. In particular, the actual Arrow 26.0.1 pod tests and existing downloaded Rock error establish the row-group fix, but do not substitute for that matrix. O9's real-Opal performance threshold and the new administrator categorical parity check remain to be observed there. The full product suites remain the integration/release job's responsibility under the targeted-test-only rule.

No schema, frozen acceptance input, privacy threshold, duplicate-node guard or aggregate admission rule was relaxed. Changes are corrected behavior documented in NEWS; no new wire fields or change request were needed. Older protocol code remains unchanged. The test pod's pre-existing `/root/rt/labels-deps` is preserved.

Local task scratch deletion paths and allocated sizes are recorded in `cleanup-local.json`; evidence copies were saved first. This includes the 3,289,088-byte temporary PyYAML dependency, temporary profile/log copies (4,096–20,480 bytes each) and the 12,288-byte Python bytecode cache. Workspace free space was checked (9.6 GB); no large local package copies or full suites were run. No unrelated worktrees, session data, or dependency libraries were cleaned.

After saving evidence I removed these task-owned pod copies/libraries (`cleanup-pod.tsv`, allocated bytes):

- `/root/rt/pre6-deps`: 139,001,856 bytes.
- `/root/e2e4-pre6`: 122,880 bytes.
- `/root/rt/lib/wt_int_dsOMOP`: 0 bytes.
- `/root/rt/lib/wt_int_dsOMOPClient`: 15,716,352 bytes.
- `/root/rt/wt/int/dsOMOP`: 30,208,000 bytes.
- `/root/rt/wt/int/dsOMOPClient`: 17,084,416 bytes.

The package mirrors and private libraries are regenerated by `rtest.sh`; the pre-existing labels dependency library and all saved evidence logs remain. The requested report is an exact copy of this committed report at `/workspace/dsomop/design/astra-dev/e2e4-pre6.report.md` (that directory is not itself a Git repository).
