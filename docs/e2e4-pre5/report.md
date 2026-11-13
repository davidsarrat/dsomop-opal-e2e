# e2e4-pre5 — real-Opal gate repairs

13 November 2026. Changes are committed locally; nothing was pushed or dispatched. The original startup/parser and failed-job publication fixes were already present and are confirmed by the newer result branches. This job repaired the failures exposed after startup, plus one product defect. Targeted checks pass after correcting a new regression test's fault injection. The real Opal matrix still needs another CI run.

## Commits

Product, `/workspace/dsomop/wt/int/dsOMOP`, branch `feat/2.10.3`:

- **1c2803f15bcfb87bd5d0ace345b0f529e31eb873** — explain unavailable protected Poisson rate ratios; NEWS and targeted regression.

Harness, `/tmp/claude-1000/-workspace-app/a9e21344-5d10-4451-a8b6-63b53826c6ca/scratchpad/dsomop-e2e`, branch `main`:

- **5fe355a** — retry stalled curl processes; repair scenario cleanup, old-server fixture selection, administrator resolver initialization, and timing-session initialization/cleanup; targeted probes.
- **2710b8f** — vendor the product repair, NEWS and regression test.
- The documentation commit is discoverable with `git log -1 --format='%H %s' -- docs/e2e4-pre5/report.md`.

Client remains unchanged at **30a9794b4fe30c7b04f30390686157bf67ff4a63** on `feat/2.10.3`. Both packages remain 2.10.3, the integrated candidate for the prospective 2.10.4 gate. Comparison of DESCRIPTION, NAMESPACE, NEWS, R/, inst/, src/ and tests/ found no drift between integration and vendored sources: 665 server files and 199 client files. See `product-comparison.json`.

## Evidence and findings mapped to fixes/tests

| Finding | Repair or retained behavior | Targeted verification |
|---|---|---|
| Original run 43472800948: four jobs parse plain-text dotted Opal versions as JSON after resets/HTTP 400. | Retain existing **29901ea / 8fa067a**: separate HTTP status/body/diagnostics; exact plain-text version pin; retry invalid responses; independently require valid JSON with a running default Rock; explicitly fail on exhaustion. Additionally retry a Python subprocess timeout instead of abandoning startup after one stalled curl. | `scripts/tests/o-stack.py`: 11 tests, both pins, transient errors, malformed JSON/shapes, wrong pins, exhaustion, Docker errors, and stalled-process recovery/exhaustion. |
| Failed jobs must retain evidence outside artifact services. | Retain **13de084**: `always()` evidence collection, redaction, per-job/per-attempt results branch, then artifact fallback and unconditional cleanup. No workflow weakening was needed. | `scripts/tests/o-results.py`: six tests including four failed matrix jobs, distinct result branches, early failure, secret redaction and push failure. Every git operation is stubbed. Four real result branches from run 43483690265 also prove this path ran after failures. |
| Fresh O1 passes, then O2–O8/O11/O12 say `omopO` is already active. | `with_sites()` had registered logout before disconnect, with FIFO exit handlers, then silently swallowed the disconnect error. Register disconnect before logout with `after = FALSE`; expose cleanup failures. Keep logout registered for failed connections and failed scenarios. | `scripts/tests/o-contract.R`: repeated calls, scenario failure, connect failure and disconnect failure; requires live connections during cleanup and always logs out. Product session retention on unproved cleanup is intentional and unchanged. |
| Fresh O9 cannot resolve the OMOP resource. | Load dsOMOP in each administrator R session before assigning its resources. Apply consistently to O9, administrator fixture checks, setup and old-server baseline. | `o-contract.R`: resolver-order simulation and inspection of every O administrator assignment. |
| Both upgrade jobs fail O6 before installing the candidate: old 2.10.1 rejects GiBleed's `v5.3.1`. | Add `gibleed_legacy`, pointing to the existing omop53 fixture with version `5.3`; use only for the old-server probe. Keep current-server GiBleed and as-shipped resources unchanged. | `o-contract.R`: evaluates actual resource definitions and checks old-server selection. Read 2.10.1's local `.loadCdmSpec` implementation to confirm this is an old-version limitation. |
| Old-server timing loads 2.10.1 in the administrator session that would otherwise survive upgrade. | Log out of the old timing session and open a fresh administrator session before candidate installation. | `o-contract.R`: checks upgrade session boundary; existing `g-contract.R` retains exact-archive installation checks. |
| Timing probe calls `omopInitDS()` inside a helper that does not own the resource variable; the initializer deliberately uses its immediate caller. | Evaluate initialization in the invoking Opal session, parent timing execution environments to that session, and close the handle there on both success and failure. | `o-contract.R`: immediate-caller resource lookup, six timings per phase, candidate status/revoke path and cleanup after timing failure. |
| Fresh G10 Poisson returns two NA estimates without an explanation, despite a stable protected result. | Product adds `unavailable_reason` only when the protected Poisson estimate is nonfinite. It is generic post-processing of protected components and flows through the existing standard-mode protected block. NEWS classifies this as corrected; re-run to receive the label. | `test-e2e4-poisson.R`: forced protected zero person-time and insufficient outcomes, auto and standard routes, stable replay, serialization, and finite results without a spurious reason. Existing MDRR, Cox/survival, sweep and effect tests also pass. |

No privacy thresholds, noise draws, numeric answers, release mechanisms, product session semantics, TLS requirements, frozen interfaces or image pins changed. No change request was needed.

## Newer result evidence

The user-described startup failure is from the earlier run. The newer run used harness **262780f**, which already includes the pre4 repairs. All four saved `workflow-status.json` files show `stack` succeeded, followed by later failures:

- `res/43483690265-1-opal-5.7.6-fresh-candidate` at `518c423`: O1/O10 PASS; ten FAIL.
- `res/43483690265-1-opal-6.1.3-fresh-candidate` at `38c8ec0`: same verdicts.
- Upgrade 5.7.6 at `98e0b5f` and 6.1.3 at `be60cfd`: fail in install/old-server negotiation; scenarios not reached.
- `res/43483695412-fresh-candidate` at `40ac8ea`: G 85 PASS, 13 INFO, one FAIL (G10 Poisson); old client ten PASS.
- `res/43483695412-upgrade-candidate` at `f34e378`: G 90 PASS, 15 INFO; old client ten PASS; V three PASS, two INFO.

`input-audit.json` records full immutable result commits, workflow metadata, verdict counts/failures and hashes of all supplied failed logs. These are observations of existing local refs, not claims that this job ran CI or that all contract scenarios now pass.

## Targeted validation and source attribution

- `python3 scripts/tests/o-stack.py -v`: **11 tests PASS**, source committed as **5fe355a**.
- `PYTHONPATH=/tmp/dsomop-e2e4-pre5-python python3 scripts/tests/o-results.py -v`: **6 tests PASS**, unchanged publication code from **262780f**, retained in **5fe355a**. Used temporary PyYAML; no real push.
- `python3 scripts/tests/o-candidate.py -v`: **2 tests PASS**; candidate preflight also PASS on **2710b8f**.
- On the R 4.6.2 pod: `Rscript scripts/tests/o-contract.R` and `Rscript scripts/tests/g-contract.R`: **PASS**, on the exact harness source committed as **5fe355a**. Remote APIs are stand-ins; this is not a real Opal run.
- Product through `tools/rtest.sh`, with matching client installed first: filter `e2e4-(poisson|mdrr)|tools-release-(survival|sweeps)|analysis-ports-cm-effect`, timeout 1200. Exact files: `test-analysis-ports-cm-effect.R`, `test-e2e4-mdrr.R`, `test-e2e4-poisson.R`, `test-tools-release-survival.R`, `test-tools-release-sweeps.R`. Production code equals **1c2803f**. The four existing files passed; the initial new Poisson probe had one failed assertion and one subsequent error (434 assertions passed overall), because it injected family `S` rather than the actual `status` event coordinate.
- Corrected only that new probe, then ran `tools/rtest.sh /workspace/dsomop/wt/int/dsOMOP '^e2e4-poisson$' 300`: **33 passed, zero failures/errors/skips**, exact final source **1c2803f**. Time and status fault cases, both routes and finite controls all passed. See `poisson-pod-full.log` and the retained initial result summary.
- Bash syntax for stack/publication scripts, Python AST parsing, R parsing in the harness probes, workflow conditions/YAML in results tests, and `git diff --check` pass. Source comparison confirms the vendored repair.

No full server or client suites were run, following the user's targeted-only instruction. No client test files were run because the client was not changed. The standalone harness R probes ran directly over SSH on the pod rather than through `rtest.sh`, which expects an R package; product tests used the required wrapper. An initial probe upload omitted files needed by `g-contract.R`; adding those source files made the complete probe pass without changing production code.

## Handoff and limitations

The coordinator can push the local harness commits and dispatch the fresh/upgrade matrix on both pins. Failed jobs will publish redacted results branches through the existing workflow. No Docker executable is available locally, so no live stack, O1–O12 rerun or GitHub workflow dispatch was performed. The newly reachable scenarios may reveal further defects; targeted stand-ins cannot certify Opal/Rock transport or performance thresholds.

The requested report path is outside a git repository. An identical committed copy is `docs/e2e4-pre5/report.md` in the harness. Evidence logs and JSON are committed beside it. Integration server and client worktrees are clean after the product commit.

Disk free space was 9.6 GiB; CLEANUP.md was read. No large source copies or full suites were made. Removed only this job's temporary PyYAML directory `/tmp/dsomop-e2e4-pre5-python` (3,151,695 bytes), generated harness `scripts/o/__pycache__` (5,669 bytes), and pod probe copy `/root/e2e4-pre5` (295,376 bytes); see `cleanup.json`. The pod has no Python, so its cleanup used R's `unlink`. Evidence was preserved before cleanup.

No push, PR, tag, stash, sub-agent or Claude CLI was used. No other worktrees or primary package checkouts were edited.
