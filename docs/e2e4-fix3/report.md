# e2e4-fix3 — round-three real-Opal failure classification

13 November 2026. **All four observed failures in contract run 43472800948 are the same harness startup defect, repaired in 29901ea. The saved e2e run 43472806671 contains no failed checks or execution halt. No new product defect is established.** The reported failed workflow conclusion for the e2e run cannot be reconciled from the available evidence; its failed job/step log was requested. Do not treat that unresolved workflow status as either a product failure or a verified workflow success.

## Commits and scope

All changes are local in the requested harness clone, on `main`; nothing was pushed:

- **29901ea** — read the pinned Opal version as plain text, require exact equality, and fail explicitly when startup readiness retries are exhausted; add bootstrap regression tests.
- **894c530** — retain the original contract failed-job log, e2e verdicts and summaries, complete error inventory, reproducible classification scripts and targeted validation logs.
- A subsequent documentation commit stores this report as `docs/e2e4-fix3/report.md`. Its commit can be located with `git log -1 --format='%H %s' -- docs/e2e4-fix3/report.md`.

Server `/workspace/dsomop/wt/int/dsOMOP` remains unchanged on `feat/2.10.3` at **22c7ef5** (product implementation 860c31f). Client `/workspace/dsomop/wt/int/dsOMOPClient` remains unchanged on `feat/2.10.3` at **30a9794**. Both are version **2.10.3**, the coordinated candidate for the prospective 2.10.4 work. The harness input is **128c504**, whose common tracked vendored files are byte-identical to these worktrees. No product change, NEWS change, version bump, frozen-interface change request or new vendoring is warranted by these results. No WIP commits occur in the relevant current repair history.

The requested report path is outside a git repository. The identical harness copy makes the report part of the committed deliverable.

## Contract run 43472800948: four harness failures

There are no `res/43472800948-*` refs in the supplied clone. The actual failed-job log was found at `/workspace/dsomop/design/astra-dev/contract-logs/43472800948-failed.log`, and its complete 4,003 lines are retained in the evidence commit. SHA-256: `064ac8886073c6f792e752bcf2d31f67919217622099e87bbb507cd321ae3019`.

| Job | Failure evidence in that log | Classification | Fix and test |
|---|---|---|---|
| Opal 5.7.6, upgrade | JSONDecodeError at line 857; exit 1 at 858 | Harness, H-version-text | 29901ea; `scripts/tests/o-stack.py` |
| Opal 6.1.3, upgrade | JSONDecodeError at line 1887; exit 1 at 1888 | Harness, H-version-text | Same |
| Opal 5.7.6, fresh | JSONDecodeError at line 2958; exit 1 at 2959 | Harness, H-version-text | Same |
| Opal 6.1.3, fresh | JSONDecodeError at line 4002; exit 1 at 4003 | Harness, H-version-text | Same |

Every failure occurs in **Pinned Opal and Rock**, before installing the candidate packages. `scripts/o/stack.sh` fetches `/ws/system/version`, then passes its plain-text dotted version to `json.load`. For a body such as `6.1.3`, the JSON decoder reads `6.1` and reports extra data at column 4, precisely the recorded exception. The existing working e2e bootstrap also reads this endpoint as plain text; its captured output is `Opal version: 6.2.1`.

The repair requests `text/plain`, retains the response as `opal-version.txt`, strips surrounding whitespace and compares it exactly with the selected reviewed pin. It does not accept a substring, a different release, a snapshot suffix, HTML or a JSON wrapper. It also adds bounded curl timeouts and an explicit error if all 90 HTTP readiness attempts fail. Transient startup curl connection resets, empty replies and one HTTP 400 in the log are harness lifecycle diagnostics; the terminal failure is the subsequent JSON parser, not those retries.

**O1 through O12 did not execute in any of the four jobs.** `contract-coverage.csv` records all 48 scenario/job combinations as NOT-EXERCISED. These are blocked checks, not 48 independent product failures, and the repair's local bootstrap tests do not establish their real-Opal outcome. The two pinned versions and all acceptance thresholds remain unchanged.

## E2E run 43472806671: no failure in the captured checks

Immutable result refs:

- `res/43472806671-fresh-candidate`: **075e49cf874f3dc0390657468be5dc11bda0b925**.
- `res/43472806671-upgrade-candidate`: **24e8704e61ed0574c35cfdb36c455c9ae537c3d5**.

| Evidence | Outcome and classification |
|---|---|
| Fresh G | 88 PASS / 0 FAIL / 12 INFO / 0 ERROR |
| Upgrade G, including copied V checks | 90 PASS / 0 FAIL / 15 INFO / 0 ERROR |
| Fresh and upgrade old-client checks | 10 PASS each, no failures/errors |
| Standalone upgrade V | 3 PASS / 2 INFO; no failures/errors |
| Fresh method audit D | 67 PASS / 1 expected REFUSED / 0 FAIL / 5 NOT-EXERCISED |
| C, E and F captured checks | No failed captured check; all 18 F resource/driver checks are OK |
| G10 MDRR, both paths | PASS, finite protected results; this run does not exercise the unavailable-MDRR reason branch repaired in the previous job |
| Fresh G16b million-person fixture | PASS: cold 18.6 s, warm 12.6 s, warm other 12.7 s, four concurrent cold 60.6 s; native hash acceleration TRUE; original 60/15/120 s limits preserved |

The complete extracted evidence comprises **62 files / 24,772,052 bytes**, including four archived server-log bundles. The error inventory contains **532 headings: 488 expected-refusal harness diagnostics and 44 harness stack-lifecycle diagnostics; zero unclassified headings and zero product-defect headings**. These counts include duplicated log wrappers and copies, not independent failure events.

- Missing cohort definition, absent physical OHDSI result tables and sensitive aggregate birth-column probes are intentional negative controls. They do not justify weakening the product's refusals. Server-side birth-column assignment probes pass.
- Duplicate-source pooling, analyst-injected reroll controls, all-null numeric support, DP-only and disabled routes, revoked reads, deliberately killed connections and old-client typed releases are also expected refusals. Their associated acceptance verdicts pass.
- The old-server `omopDpStatusDS` unused-argument error is the expected negotiation fallback; V checks pass.
- Authentication, R-resource/package discovery, interrupted package enumeration and connection-refusal errors occur during stack initialization or shutdown/restart. For example, fresh Opal's package enumeration is interrupted during shutdown at 17:29:44; upgrade Rock shuts R down at 17:31:31 immediately before the two RServerService connection refusals. Later publication, analysis and restart replay pass. These are harness lifecycle diagnostics, not product repairs.
- D's five uncovered methods remain coverage gaps: `omopPlanStatusDS`, `omopStagedRevokeDS`, `omopPlanExplainDS`, `omopAsFactorColumnsDS` and `omopMutateDS`. The unexecuted contract run does not fill those gaps.

An additional scan of every extracted text/log file for execution halts, tracebacks, GitHub error markers, fatal headings and segmentation faults found none. The raw old-server R error remains in the expected-refusal inventory. `all-errors.csv` retains each indexed file, line, category and evidence. `manifest.json`, `SHA256SUMS`, `extract.py`, `audit.py` and `classify.py` make the review reproducible without changing result refs.

**Workflow-status limitation:** the two result refs do not contain GitHub job conclusions or a failed post-capture step. `gh auth status` has no authenticated host, and unauthenticated GitHub API requests for this private run and its jobs return HTTP 404; the attempted URLs/results are retained. The user was asked for the failed job/step evidence. No unsupported harness or product repair was invented to explain the reported e2e failure.

## Targeted validation

- **Before repair:** `python3 scripts/tests/o-stack.py`, against the original 128c504 bootstrap, runs five test methods with **12 failing test/subtest cases**, including the two plain-text reviewed versions. The failure log is retained as `o-stack-before.log`.
- **After repair:** the same test file against the exact source committed as **29901ea** passes **all five methods**, including both pins, transient HTTP failures, 90 exhausted attempts, exact-version rejection controls and rejection of an unreviewed pin before provisioning. It executes the real Bash bootstrap and embedded Python with disposable Docker/curl/sleep stand-ins; it does not launch containers. Full log: `o-stack-after.log`.
- On **29901ea**, `python3 scripts/tests/o-candidate.py` passes **two tests**, and `python3 scripts/o/check_candidate.py` accepts the coordinated native-language candidate and frozen inputs. Log: `o-candidate.log`.
- `bash -n scripts/o/stack.sh` and source `git diff --check` pass. `audit.py` leaves no unclassified headings; `classify.py` verifies the four failed contract jobs and zero failed e2e verdicts.
- **No R test files were run:** no R/package code changed. No full suite was run. No real-Opal workflow was rerun; the bootstrap regression tests are not evidence of O1–O12 passing.

## Handoff and deviations

The coordinator should rerun the four-job contract matrix with 29901ea and inspect its actual O1–O12 results. Provide the allegedly failed e2e job/step log if further diagnosis of that workflow conclusion is required. Its captured product checks already pass, so repeating or altering them is not supported by the current evidence.

The deviation from the stated input locations is using the locally retained contract failed-job log because no contract result refs exist. The only unresolved classification scope is any e2e workflow failure absent from the supplied artifacts. All observed contract failures and captured e2e error headings are classified.

Disk free space was approximately 9.7 GiB; CLEANUP.md was read. No large package copies, full test runs or disposable R libraries were created. No files were deleted; the small extracted run files remain as reproducible evidence. No other worktree, primary package checkout, frozen contract, privacy behavior, persistent state, TLS policy, quota or owner configuration changed. No push, PR, tag, stash, sub-agent or Claude CLI was used.
