# e2e4-pre7 — real-Opal harness repairs

13 November 2026. All changes are committed locally in the supplied harness checkout. No push, PR, tag, CI dispatch, Claude CLI, full suite, or delegated agent was used. Product worktrees remain on `feat/2.10.3` and unchanged: server `83761ba`, client `9ee5197`, both version 2.10.3 (the integrated 2.10.4 candidate).

## Commits

- `18a94db`: current key resolution, read-only installed fixture runner, concise remote administrator errors, independent old-client workflow step, and installed-package regression probes.
- `cb90333`: exact analytic key comparison, corrected testthat selection, fixture transactions separated from public read snapshots, restoration on failure, and documentation.
- `d784164`: complete aggregate probe with the optional birth datetime column present in GiBleed, and clearer refusal diagnostics.
- The evidence/report commit following these contains this report, the audit, targeted logs and the temporary pod driver. The requested report path is an exact copy of this committed file; `/workspace/dsomop/design/astra-dev` is not a Git repository.

## Input diagnosis

The supplied original `43472800948-failed.log` records the four startup failures: the plain-text version endpoint was parsed as JSON amid connection resets and HTTP 400s. The checkout already contained `8fa067a`, `13de084`, and `5fe355a`, fixing readiness and failed-job publication. I reviewed and retained them. Readiness checks the exact pinned plain-text version, then valid JSON containing a running default Rock server, with bounded requests/retries and separate HTTP status, body and diagnostics. It rejects incomplete bodies, wrong versions, redirects, and stale partial responses. The workflow always collects/redacts evidence and publishes a unique per-run/attempt/version/path branch, with artifact fallback and stack cleanup. Publication remains conditioned on successful redaction; a failed scenario does not prevent it.

This is supported by actual downloaded results, not just mocks: **all four** `res/43506711667-1-opal-*` branches identify harness `e5322cb`, show `stack: success`, and contain failed scenario verdicts. They fail O2, O3, O5, O7 and O11, plus consequential O10 failures on upgrade. O1, O4, O6's current-client half, O8, O9 and O12 pass. The analyst O2 factor/table/levels/GLM calls now finish before the administrator oracle fails. The earlier categorical/Arrow product fixes therefore remain in place.

The companion `43506719427` e2e results have no failing verdicts: fresh G has 88 PASS/12 INFO, upgrade G 88 PASS/16 INFO, each old-client file 10 PASS, and upgrade V 3 PASS/2 INFO. INFO rows are not counted as passes. `input-audit.json` records every supplied log's size/hash and immutable result-ref commits/verdicts. Empty downloaded failed logs are recorded as empty, not as proof of success.

## Findings, repairs and tests

| Finding | Fix | Evidence |
| --- | --- | --- |
| O2/O3/O7 oracle reads `handle$person_key`, although production handles store only resource identity | Resolve through `.personKey(handle)`. Remove the obsolete raw key from the auxiliary SQLite fixture before copying the production key contract | Actual installed production handles have no raw key field; acceptance 1/2 and matching compare against frozen oracles. A deliberately incorrect person ID still fails |
| O5/O11 write a selected test file into the Docker-copied source directory | Run original files in place with testthat's exact-description selector and only the three intended helpers; missing, failed or skipped checks remain failures | Installed test probes run with the source directory mode 0555 and Linux DAC override capabilities removed. An actual attempted write fails; selected tests pass; source hashes remain unchanged |
| Matching publishes a decimal-string BIGINT `set_id`, while JSON stores numeric IDs | Compare this analytic key as exact decimal text; numeric analytic values remain numeric | Fixed and alternate seeds, PostgreSQL/SQLite, original/reversed row order; negative checks for changed set IDs and weights, including preservation of a key above double precision |
| O7 holds its fixture write transaction open while invoking a public executor that owns its read snapshot | Commit the atomic row reorder before calling the executor | Full installed matching check passes; product snapshot guard unchanged |
| O11 has the same nested-transaction problem | Save original births in a temporary table, commit synthetic fixture writes, execute, then restore births and remove the backup on success or assertion failure. Qualify the resource's actual schema | Complete administrator aggregate check; database equality before/after; injected callback failure also restores original values |
| Long serialized O2 plans obscure the remote error in Opal's wrapper | Catch administrator assertion errors on Rock and return a short failure message | Actual helper's remote-call wrapper tested with success and injected error; verdict remains a failure |
| Old-client check is skipped when O scenarios fail | Run it whenever fixture setup succeeded, preserving its independent failing gate | Workflow regression checks prerequisite and failure-independent condition; failed-job publication tests still pass |

No additional product defect was established. The remaining failures were in administrator fixture orchestration and comparison. All 2,078 tracked server files and 1,331 tracked client files match the vendored candidate byte-for-byte (`vendor-comparison.json`). No product changes, version changes, NEWS changes, frozen-interface changes, privacy-rule changes or acceptance-oracle edits were needed.

## Targeted validation

Final harness code: `d784164`; installed product: server `83761ba`, client `9ee5197`. R tests ran on the pod through `/workspace/dsomop/tools/rtest.sh`, filter **`^e2e4-pre7-harness$`**, using the temporary driver saved as `pod-driver.R`. The first run installed both exact product worktrees with `RTEST_WITH`; subsequent runs reused those unchanged installed packages in the task-owned `/root/e2e4-pre7/lib`. The driver was removed from the product worktree afterward.

- `scripts/tests/o-stack.py`: **11 tests passed**, using a real local HTTP server/curl and Docker stand-in.
- `scripts/tests/o-results.py`: **7 tests passed**, including all four failed-startup paths, credential redaction, failure before initialization, reruns, push failure, and old-client scheduling. Git is intercepted: no real push occurred.
- `scripts/tests/o-candidate.py`: **2 tests passed**.
- `scripts/tests/o-contract.R`: **8 named probes passed**, including exact key comparison and concise remote errors.
- `scripts/tests/o-installed.R`: **all five administrator paths passed**, with driver result **0 failures, 0 errors, 0 skips** in `pod-final.log`. It runs real installed-package administrator checks for acceptance1, acceptance2, staged, matching and aggregate_policy, plus negative oracle and fixture-restoration checks.
- Exact product test files invoked by the installed runner: all of `test-publication.R` (12 cases/93 assertions); selected cases in `test-assignment-policy.R` (3/152), `test-queries.R` (1/2), `test-ohdsi-results.R` (1/1) and `test-analysis-catalog.R` (1/10). These are **258 unique assertions**; publication and aggregate selections are repeated inside their actual scenario paths, for **516 executed assertions** in the final combined probe. No product full suite ran.
- Shell/Python syntax and source whitespace checks pass. Original R evidence logs are preserved verbatim, including their trailing spaces.

Development evidence is retained: `pod-initial.log` and `pod-round2.log` exposed my incorrect assumptions about testthat's `desc` argument (exact single/nested paths, not regexes or a union); `pod-round3.log` and `pod-matching-diagnostic.log` exposed the BIGINT representation mismatch; `pod-round4.log` exposed the nested snapshot; `pod-round5.log` and `pod-aggregate-diagnostic.log` reached an omitted optional column in the minimal test fixture. The probe adds `birth_datetime` only to its disposable schema, matching the existing CI GiBleed resource; the frozen fixture and production recipe are unchanged. `pod-aggregate-final.log` records the isolated aggregate fix passing. These earlier failures are not presented as passing runs.

## Integration and cleanup

The new probes exercise real PostgreSQL and SQLite, the installed public executor, actual CSV staging and the current key provider. Arrow is absent on this pod run; the unchanged Parquet code retains the pre6 validation evidence. They do **not** certify the Opal/DSOpal transport, both Docker image versions or upgrade installation. No Docker executable was available locally, and the task prohibits pushing. The coordinator must run the four fresh/upgrade contract jobs from the committed harness and inspect the old-client step independently. The earlier startup/result-publication fix is already demonstrated by all four latest downloaded result branches. Full package suites remain the integration/release job's responsibility.

Task-owned scratch paths and allocated sizes are recorded in `cleanup-local.json` and `cleanup-pod.tsv`; saved logs precede deletion. The temporary product driver, task Python dependency, pod scripts/private package library and task package mirrors are removed. No unrelated worktree, shared dependency library, session data, or cache is removed. The pod probe drops its uniquely named PostgreSQL schema and temporary state on exit and verifies birth restoration before dropping it. Workspace free space was approximately 9.6 GB; no large local copies or full test runs were performed.
