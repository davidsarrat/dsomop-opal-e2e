# dsOMOP on a real Opal, end to end

Private harness. Three manual workflows; results come back as `results/<run>-<path>-<mode>` (e2e),
`results/<run>-vendor-candidate` (vendor), and
`results/<run>-<attempt>-opal-<version>-<path>-candidate` (Opal contract) branches.

**`e2e.yml` (`dsomop-opal-e2e`)** brings up an easy-opal stack (Opal, Rock, MongoDB, nginx) on a GitHub runner, a
PostgreSQL OMOP CDM (OHDSI Eunomia GiBleed, CDM 5.3) on the stack's network, and runs:

- **fresh**: a clean Opal; dsOMOP installed through Opal's DataSHIELD package install; publication check against the
  installed DESCRIPTION; the analyst's script.
- **upgrade**: dsOMOP `old_ref` installed first, then upgraded through the same install call. With a 1.x `old_ref`,
  scenario A reproduces "No such DataSHIELD 'ASSIGN' method with name: omopInitDS"; with a 2.x `old_ref` (2.10.2) the
  old server's noise root is created and the new client is run against that real old server
  (`scripts/combo_old_server.R`, V checks) before the upgrade. Scenario B publishes and retries.
- **C** (both paths): resources created with dsOMOP 1.x's form (`omop.cdm.db`). **D** (fresh): the method audit, every
  method of the installed DESCRIPTION. **E** (fresh): recipes. **F** (fresh, last): the RPostgreSQL fallback.
- **G** (both paths): the 2.10.3 checks that need a real Opal/Rock (`scripts/scenario_G.R`; each check states its
  expected result; verdicts in `<path>-G-verdicts.csv`), then the released 2.10.2 client against this server
  (`scripts/scenario_G_old.R`). On the fresh path G16 also builds a synthetic CDM of `big_persons` persons.

`mode=candidate` installs dsOMOP and dsOMOPClient from `pkgs/`.

**`vendor.yml` (`dsomop-vendor-db`)** runs dsOMOP's vendor database CI (PostgreSQL 16, MySQL 8.4, MariaDB 11.4, the
same pinned images and test call as dsOMOP's `vendor-db-integration.yaml`) on `pkgs/dsOMOP`, plus the protected
release routes (`test-vendor-release-routes.R`) on the same servers.

Rerun on a new candidate head:

```sh
REF=<branch or commit> scripts/vendor.sh /workspace/dsomop     # git archive of each committed branch into pkgs/
git add pkgs && git commit -m "Vendor ..." -- pkgs && git push
gh workflow run e2e.yml -f mode=candidate -f old_ref=2.10.2 -f scenarios="C D E F G"
gh workflow run vendor.yml
```

## Native-language contract matrix (WS-10)

`opal-contract.yml` is a separate, manually dispatched release check. It uses
`compose/opal-matrix.yml` with **Opal 6.1.3 and 5.7.6**, each on fresh and
2.10.1→candidate upgrade paths; Rock is `2.3.0-R4.6.1`. The 5.x pin is the current
published 5.x image, rather than an assertion about an upstream LTS designation.
Pins were checked against [OBiBa's Opal image tags](https://hub.docker.com/r/obiba/opal/tags)
and [Rock image tags](https://hub.docker.com/r/obiba/rock/tags) on 12 November 2026.
The compose wiring follows the [official Opal example](https://github.com/obiba/docker-opal/blob/master/docker-compose.yml).
Actual image digests, Opal response, R, SQLite, PostgreSQL and R driver versions
are written to artifacts. Database TLS is not required.

Vendor the **integrated, coordinated** packages first, using the existing
`vendor.sh` workflow. The native/publication changes were integrated into
2.10.3; a prospective 2.10.4 label is not a capability. Both DESCRIPTION
versions must match and be at least 2.10.3; the preflight also requires native
normalizer/label sources. Runtime O1 still checks language operations and publication;
the source archive must include tests/fixtures and the frozen acceptance corpus.
The coordinator commits/pushes the candidate and dispatches
`opal-contract.yml`. WS-10 never pushes. The workflow has repository contents
write permission and publishes a separate results branch for every matrix job
and rerun attempt, including jobs that fail during startup or installation.
Evidence includes step outcomes in `workflow-status.json`, command output,
container logs, image digests and the last HTTP readiness responses. The status
snapshot precedes publication and stack removal; it is not the final GitHub job
conclusion. Per-run passwords and tokens are redacted before publishing or
uploading. Artifact upload is an independent fallback if branch publication fails.

Bootstrap waits for an exact plain-text Opal version and a running server in the
default R cluster. Each endpoint gets up to 90 attempts with five-second pauses;
each HTTP request has a five-second connection timeout and a 15-second total
timeout. Startup transport errors, non-200 statuses and malformed bodies retry;
a well-formed different version fails immediately. No stack environment is
exported on readiness failure. The pins and scenario assertions are unchanged.

Targeted harness checks: `python3 scripts/tests/o-stack.py` (local HTTP server,
real curl, Docker stand-in), `python3 scripts/tests/o-results.py` (requires
PyYAML; workflow failure paths with Docker/R/git stand-ins), and
`python3 scripts/tests/o-candidate.py`. These checks never start containers or
push branches and do not certify O1–O12 on real Opal.

`scripts/tests/o-installed.R` exercises the administrator helpers against the
installed candidate and a disposable PostgreSQL/SQLite reach fixture on the
R test pod. It requires `DSOMOP_O_SOURCE` (candidate source with tests and
acceptance fixtures) and `DSOMOP_O_HARNESS` (`scripts/o`), plus installed matching
server/client packages. It checks the simple-layer oracle, survival, staging,
matching and selected installed publisher/aggregate tests. Fixture sources are
read in place; no write access to the Docker-copied source tree is required.
Oracle comparisons resolve keys through the installed provider without storing
raw keys on production handles. Administrator failures return concise error
messages so a serialized plan cannot hide the assertion in Opal's error wrapper.
The old-client workflow step still runs after scenario failures if setup passed.

| Scenario | Executed assertions |
|---|---|
| O1 | Actual installed/published version, language 2, required operations, dialect fields. |
| O2 | Acceptance-1 variables via `omop_study`, ds.dim/summary/table/levels/glm; complete frozen schema and per-person value multiset compared inside Rock. |
| O3 | Acceptance 2, inventory-named ITT/on-treatment TARs, time summaries and independent event/switch-censoring oracle. |
| O4 | Strict/non-strict × error/skip, in memory and staged mode, at two logical sites with distinct CDM schemas; k=5 and exactly k−1 in the small root; whole-federation symbol/file rollback, skip NULL, partial warning, constant text and only `insufficient_support`. |
| O5 | Recipes 7/9 staged, actual server-side descriptor reader, forged uncommitted/revoked descriptors, files removed by revocation; installed publisher failure-injection tests for precommit/manifest cleanup. |
| O6 | Actual 2.10.1 server accepts a numeric v1 request; the new client refuses a native request before output assignment (`install.R`, upgrade jobs); isolated 2.10.1 client runs a safe v1 recipe on the candidate (`old_client.R`, every job). |
| O7 | Frozen matching oracle, same seed on PostgreSQL and SQLite, both reloaded in reversed physical order; alternate seed checked against committed independent expected sets, including weights and set IDs. Both Opal versions compare to the same oracle. |
| O8 | Public person-local native DP prepare/release, matched descendant refusal; independently unsealed external and persistent-cohort scope refusals; actual native execution with injected sealing failure leaves no publication. |
| O9 | Native recipes 1/7 on 10k persons within unchanged memory caps; identical v1 baseline/panel workloads on 2.10.1 and the candidate, median of three, fixed 25% timing tolerance (with a one-second noise floor). |
| O10 | Real installation over 2.10.1, methods and Options republished and checked, O1–O3 rerun on the upgraded server. |
| O11 | GiBleed wide/baseline birth/age assignments and ds.summary, public class-1 refusal, profiling/value-count/crosstab refusals; frozen column corpus, query-library/external/OHDSI admission, Achilles deciles and one-person off-grid `18-18` assigned band. |
| O12 | Both non-strict small-site policies; trace of the real authenticated status read before execution-symbol removal, passing-family inventory, partial warning, whole-site skip. |

`run.R` writes a verdict after each scenario and exits nonzero on any failure.
Missing compilers, absent test dependencies and failed assertions cannot become
passing skips. O6's compatibility assertions are separate failing workflow
steps; its verdict row alone does not certify both directions. All four jobs
and their old-client steps must pass. The harness uses only disposable public
synthetic fixtures. Administrator assertions inspect rows inside Rock and return
booleans; no helper endpoint or generic aggregate constructor is published.
The observer traces the real client status transport without replacing it.

The reach fixture is exported using the frozen loader, with its signature
compared to SQLite. A separate cohort 909 gives ten persons in `o_reach` and
four in `o_small`; unrelated roots still qualify. The 10k fixture uses the same
public deterministic generator. O11 temporarily changes public synthetic
GiBleed births with committed fixture writes, then restores the original births
on both success and assertion failure. Fixture writes finish before the public
executor opens its own read snapshot; O7 similarly commits its row reorder first. Test options and
failure injection are harness-only; this is not a production deployment recipe.

`matching_oracle.R` is the WS-0 SQL/base-R reference sampler with only its seed
parameterized (source SHA-256 recorded in the file). The alternate oracle is
committed in `matching-seed-20261112.json`. `validate.R` checks both seeds against
independent expected rows, v1 performance-plan preflight, syntax and targeted
installed aggregate-policy tests on the R test pod. It can also parse YAML and
vignettes copied into `yaml/` and `vignettes/` beside it. This static/contract
validation is **not an Opal pass**. The two-version run, native compiler output,
actual DSOpal integration, timing, upgrade and downstream dsBase behavior can
only be certified after the integrated packages are vendored.

## Numeric CDM (scenario N, 2.10.4+)

The second resource, `omop_data.numeric_cdm`, is the pinned Apache-2.0
[Eunomia Synthea27Nj CDM 5.4](https://github.com/OHDSI/EunomiaDatasets/tree/3d349dcdd79cc346b8e36eb837e49feffe7f7497/datasets/Synthea27Nj).
Despite its name it contains 28 people, with 10,040 measurements: 9,107 numeric
values (90.707%) and 8,403 numeric values with mapped units (83.695%). The
3,351,707-byte archive is SHA-256 checked by `scripts/numeric/load.R`, the same
loader as `dsOMOP/tests/fixtures/numeric/load.R`. It preserves all original
rows and types, and loads PostgreSQL schema `numeric_cdm`; the reusable loader
also writes DuckDB when `NUMERIC_DUCKDB` is not `0`.

The regular database setup now loads both CDMs and registers both resources.
Select `N` in the e2e workflow's scenarios with matching 2.10.4+ candidates.
N executes a hemoglobin recipe, verifies `ds.mean` and `ds.quantileMean`
against independent pinned CSV expectations, and assigns a staged result.
N exits nonzero on any failed assertion; its verdict is in `*-summary.txt`.
It runs before F removes RPostgres. `scripts/tests/numeric-installed.R` runs
that same scenario on DSLite with installed packages and asserts actual
Parquet staging; this is not evidence of a real Opal pass.

Standalone reuse (DBI, RPostgres, openssl, jsonlite; DuckDB also needs duckdb):

```sh
PGHOST=omopdb PGDATABASE=omop PGUSER=omop PGPASSWORD=omop \
  Rscript scripts/numeric/load.R /root/rt/numeric-data
```

The loader writes `manifest.json` with source revision, checksum, row counts,
license and numeric/unit coverage. `scripts/numeric/load.sh` configures the
same loader for this harness's Docker database and archives the manifest.
