# 2.10.5 real-Opal failure review, round 2

Both failed runs are **harness failures**. Their common cause was an unauthenticated GitHub API request made by Rock while installing the historical server. Opal returned apparent success to the R client after GitHub rejected the installation with HTTP 403. No product defect was found; neither product worktree needed changes.

## Commits and delivery

- `e0d7dd8` — Verify historical Rock installs from source archives before upgrade. Changes the shared historical installer, validates the old-server prerequisite, publishes that fixture, and adds orchestration regressions.
- `3d0af1c` — Exercise historical archive installs in a disposable R library. Adds the real-download/installation probe used on the pod.
- This report and its evidence are committed in the subsequent documentation commit; identify it with `git log -1 -- docs/r205-e2efix2/report.md`.
- Harness repository: `/tmp/claude-1000/-workspace-app/a9e21344-5d10-4451-a8b6-63b53826c6ca/scratchpad/dsomop-e2e`, local `main`.
- Server remains clean on `feat/2.10.5` at `259d65c5cb6739233efc549c4a58a74dc7c113d3`.
- Client remains clean on `feat/2.10.5` at `10baaef6711fdc7ef3f2d5865e1fc449757d8ca6`.
- Both products remain version 2.10.5. No empty product commits were made.
- Requested report: `/workspace/dsomop/design/astra-dev/r205-e2efix2.report.md`. That directory is outside Git; this committed report is an identical copy.

## Evidence inventory

All seven supplied result branches for these runs were inspected, including the contract retry. `source-manifest.json` records exact result commits, hashes and sizes of every saved artifact, verdict totals, workflow-status records, and the original failed-log hashes. `inventory.py` reproduces the inventory from the local refs without fetching or checking them out.

| Run / attempt / path | Saved result |
| --- | --- |
| 43656622522 / 1 / Opal 5.7.6 fresh | O1–O12: 12 PASS; saved job status success |
| 43656622522 / 1 / Opal 5.7.6 upgrade | Install step failed; probes, scenarios and old-client step skipped; no verdict CSV |
| 43656622522 / 1 / Opal 6.1.3 fresh | O1–O12: 12 PASS; saved job status success |
| 43656622522 / 1 / Opal 6.1.3 upgrade | O1–O12: 12 PASS; saved job status success |
| 43656622522 / 2 / Opal 5.7.6 upgrade | O1–O12: 12 PASS; saved job status success, unchanged harness/product source |
| 43656625337 / fresh | G: 88 PASS, 12 INFO; G-old: 10 PASS |
| 43656625337 / upgrade | G: 87 PASS, 1 FAIL (G1d), 12 INFO; G-old: 10 PASS |

The contract `43656622522-failed.log` is empty, but this time the saved attempt-1 branch contains an actual failing installation step and its cause. The absence of text in that supplied file does not mean the original run succeeded. The existing attempt-2 result establishes successful contract execution after the transient failure, not validation of this new fix. Saved workflow-status snapshots precede result publication and stack removal; they are not claims about those later steps.

Fresh D records 68 PASS, one expected REFUSED and four NOT-EXERCISED methods. Fresh C/E/F and upgrade C contain no captured errors. Upgrade D/E/F were not scheduled. Scenario N was not exercised, even though the numeric fixture was loaded. Fresh G16b did exercise 1,000,000 synthetic persons and passed: cold 18.5 s, warm 12.4 s, four concurrent cold releases 53.6 s.

## Failure classification, fix and test mapping

| Finding | Classification and evidence | Fix | Targeted verification |
| --- | --- | --- | --- |
| H1: contract 5.7.6 upgrade install failure | **Harness.** `upgrade-O-install.txt` reports the GitHub install call as OK, then `dsOMOP installed on Rock: not installed`. `upgrade-steps.log` ends at the assertion expecting 2.10.1. `opal.log:296` records HTTP 403, API rate limit remaining 0/60. The candidate was never reached. | Historical server installs now download the requested source from GitHub codeload, avoiding the API used by Rock's unauthenticated installer. Validate the archive's package and tag version, submit the local archive through Opal, install that exact archive in Rock's service library with captured subprocess status/log, and verify the installed version. A manager success, manager error or already-present matching version cannot bypass the actual installation. | `historical-install.R`: archive validation, failed download, manager no-op/error, same-version reinstall, copy error, subprocess error/malformed response/Rock error, wrong or absent installed version; generated wrapper preserves log/status and service-library argument. `historical-installed.R`: actual 2.10.1 download and install on pod. |
| H2a: e2e historical install failure and silently skipped A1b | **Harness.** `upgrade-path.txt:1–11` shows the same apparent success but no installed 2.10.4 and zero published methods, followed immediately by A2. `upgrade-opal.log:279` records HTTP 403, remaining 0/60. `old_version = "not installed"` made A1b's version condition false, so the previous protocol/baseline fix was never reached. | Shared H1 installer fixes acquisition. A1 independently refuses to proceed with an absent/unreadable historical version and explicitly publishes the verified historical fixture before analyst setup. Candidate publication behavior remains tested by A/B. | `historical-install.R` executes the actual A1/A1b entrypoint with transport stubs: valid 2.10.4 reaches the protocol-aware DP status and writes the baseline; absent server stops before publication/login/upgrade; invalid DP status stops with logout and no baseline. Actual 2.10.4 archive download and installation also pass on pod. |
| H2b: e2e A and A4 report FAIL; three captured path errors | **Harness consequence of H2a.** The candidate was effectively a fresh install into an empty DataSHIELD profile, not an upgrade from the requested old package. Calls to omopPingDS/checkConnectionDS failed because those methods were absent. B after publication and later product checks pass. | Stop on invalid old-server setup and publish the verified old fixture. Do not reinterpret these results as valid upgrade behavior or suppress missing-method errors. | Actual A1/A1b control-flow regression; existing candidate exact-archive/publication prerequisites in `g-contract.R`. |
| H2c: e2e G1d FAIL | **Harness consequence of H2a.** The missing-baseline check added in round 1 correctly failed: no old DP root had ever been created. This run did not test root persistence across an upgrade. | Repair the prerequisite; retain G1d's strict failure and all key/file/creation-count checks. | `g-upgrade-root.R`: valid preserved root passes; changed key/timestamp, missing root, duplicate creation, invalid or missing required baseline fail. The new A1/A1b replay covers the previously untested path leading into this check. |

The two original GitHub 403 messages are preserved in `root-causes.txt`; the failed contract setup and the e2e absent-old-install transcript are preserved separately. The runner's GITHUB_PAT was not available to Rock's GitHub installer. This fix avoids transmitting or persisting that credential in Rock.

## Other errors and coverage limits

`captured-errors.csv` enumerates all **54 captured ERROR lines** in the scenario/path/contract installation transcripts, with exact result ref, file, line, classification and disposition:

- **3 harness errors:** the upgrade A/A4 calls above.
- **51 expected product refusals or deliberate recovery probes, no defect:** two O6 native requests against old servers; D's absent physical result contract; four G-old protocol refusals; eight G6 duplicate-node/domain refusals; four G3d3 injected-generation refusals; two G10 empty-population support gates; ten G3a4/G3a6 DP-only route refusals; six G9 disabled-tool refusals; two G20c deliberately failed generation reads; and twelve G13b deliberately killed-connection requests. Their surrounding verdicts pass, including recovery checks.

D's separate cohort-definition REFUSED row explicitly uses an absent fixture. Four NOT-EXERCISED rows are coverage gaps, not product failures. No expected refusal was weakened or hidden.

`infrastructure-errors.csv` also inventories Opal's non-request ERROR records. Apart from the two installation failures, these are service startup/restart exceptions (profile initialization/concurrent modification, session/pool availability, resource-provider/package polling and sqldf initialization). Later resource, publication, connection and scenario checks recover. They are harness infrastructure events, not dsOMOP defects, and do not justify speculative product changes. Repeated Java stack traces and combined workflow/summary logs duplicate the original events.

## Targeted validation

All successful tests used the production change in `e0d7dd8`. The pod also ran the then-untracked `historical-installed.R`, subsequently committed unchanged as `3d0af1c`; the complete tested file hashes and final corresponding commit are in `tested-source.json`.

| Test file / check | Environment | Result |
| --- | --- | --- |
| `scripts/tests/historical-install.R` | Local R and pod R | PASS: source validation, installation status/version enforcement, generated service wrapper, actual A1/A1b entrypoint replay |
| `scripts/tests/g-upgrade-root.R` | Local R and pod R | PASS: protocol negotiation, baseline validity, actual G1d replay |
| `scripts/tests/g-contract.R` | Local R and pod R | PASS: shared installer direct dependents, candidate exact-source handling, existing scenario regressions |
| `scripts/tests/historical-installed.R` | Pod R, disposable library | PASS: real codeload downloads and real installations of 2.10.1 and 2.10.4, correct library/version, archive cleanup |
| Six changed/new R scripts parse; Python inventory syntax; shell validation script syntax; `git diff --check` | Local | PASS |

`harness-local.log`, `harness-pod.log` and `syntax.log` retain the results. Presentation-only trailing whitespace is normalized in text evidence; the source manifest hashes the original saved artifacts. `validate-pod.sh` reproduces the targeted pod run. The real archive sizes were 1,208,563 and 4,832,551 bytes; their digests are in the pod log. The first local regression development run failed because its mocked download function was not in the extracted helper's environment. Setting that test function's environment fixed the test setup; no product or installer behavior was changed for it.

No product test files were run: no product code changed. These harness scripts are not an R package, so they were copied in a small fixture to the existing test pod and run directly over SSH rather than through the package-oriented rtest.sh. This matches the previous harness fix's validation approach. No full suite or new real-Opal workflow was run, following the targeted-only instruction and COMMON.md's later Test economy rule.

## Handoff and deviations

Use these local harness commits in the next coordinated contract/e2e run. Both contract OLD_REF=2.10.1 and e2e OLD_REF=2.10.4 now use the shared verified source installer. The source-install probe proves the archive path and R installation work; it does not prove Opal transport, publication, or real pre/post-upgrade root persistence. A real-Opal rerun remains necessary for that final evidence.

Historical provisioning deliberately uses Opal's local-archive route plus Rock's service-session install, rather than the GitHub package-manager route that failed. It uses the same requested historical source and validates the tag version. The old server is explicitly published as a test prerequisite. This changes harness setup, not product semantics or analyst release gates.

The requested worktrees were inspected but left untouched. No push, PR, tag, stash, Claude CLI invocation, delegation, or changes to another job's worktree occurred. No product version changes are needed by another job.

Disk had 9.5 GiB free; no full suite or large copy was performed. Only small script/description fixtures were copied to the pod. The validation shell trap removed its uniquely named `/root/rt/r205-e2efix2.*` fixture, and the R probes removed their own temporary source directories, archives and disposable library after retaining logs. The local inventory syntax-check cache `docs/r205-e2efix2/__pycache__` was removed. No shared repositories, caches or other jobs' files were deleted.
