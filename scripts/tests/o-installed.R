# Targeted administrator probes against installed dsOMOP; no Opal API mocks.
# Run via rtest.sh's temporary test driver on the test pod. Source/harness paths
# are explicit so this can also run inside the disposable Rock image.
local({
  root <- normalizePath(Sys.getenv("DSOMOP_O_SOURCE"), mustWork = TRUE)
  harness <- normalizePath(Sys.getenv("DSOMOP_O_HARNESS"), mustWork = TRUE)
  scratch <- tempfile("o-installed-"); dir.create(scratch, mode = "0700")
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  Sys.setenv(DSOMOP_STATE_DIR = file.path(scratch, "state"),
             DSOMOP_TEST_ALLOW_EPHEMERAL_STATE = "1",
             DSOMOP_ALLOW_LEGACY_GLOBAL_PSEUDONYMS = "false")
  library(dsOMOP)
  options(dsstaging.base_dir = file.path(scratch, "staging"))
  source(file.path(harness, "server.R"), local = TRUE)
  before <- tools::md5sum(list.files(file.path(root, "tests"), recursive = TRUE, full.names = TRUE))
  stopifnot(o_installed_tests(c("test-publication.R", "test-assignment-policy.R",
    "test-queries.R", "test-ohdsi-results.R", "test-analysis-catalog.R")))
  after <- tools::md5sum(list.files(file.path(root, "tests"), recursive = TRUE, full.names = TRUE))
  stopifnot(identical(before, after))
  cat("PASS: installed publication/aggregate checks preserve the source tree\n")

  e <- o_fixture_env()
  sqlite <- e$build_extended_reach_handle(100L)
  on.exit(DBI::dbDisconnect(sqlite$conn), add = TRUE)
  db <- DBI::dbConnect(RPostgres::Postgres(), host = "omopdb", dbname = "omop",
                       user = "omop", password = "omop", sslmode = "disable")
  on.exit(DBI::dbDisconnect(db), add = TRUE)
  schema <- paste0("o_pre7_", Sys.getpid())
  e$load_reach_fixture_pg(db, schema, handle = sqlite)
  on.exit(DBI::dbExecute(db, paste("DROP SCHEMA", schema, "CASCADE")), add = TRUE, after = FALSE)
  resource <- function() resourcer::newResourceClient(resourcer::newResource(
    name = "pre7", url = paste0("omop+dbi:postgresql://omopdb:5432/omop?cdm_schema=", schema,
      "&vocabulary_schema=", schema, "&results_schema=", schema),
    identity = "omop", secret = "omop", format = "omop.dbi.db"))

  # O2 uses the simple-layer lowering, with its baseline output name.
  library(dsOMOPClient)
  rec_env <- new.env(parent = environment())
  dirs <- list.dirs(file.path(root, "inst/plans/acceptance"), recursive = FALSE)
  source(file.path(dirs[startsWith(basename(dirs), "01-")], "recipe.R"), local = rec_env)
  study <- omop_study(index = omop_population("c1", index = omop_index(list(cohort_definition_id = 1),
    select = "all", end = omop_end("event_end"))), baseline = rec_env$rec$variables,
    outputs = "baseline", name = "c1")
  for (name in c("acceptance1", "acceptance2", "staged", "matching")) {
    # Separate invoking environments reproduce Opal resource/handle scoping.
    session <- new.env(parent = environment()); session$ores <- resource()
    plan <- if (name == "acceptance1") recipe_to_plan(study) else NULL
    stopifnot(evalq(o_server_check(name, plan_override = plan), session))
    cat("PASS: installed administrator check", name, "\n")
  }

  # A production handle contains an identity, never cached raw key bytes.
  # The oracle comparison must still fail on a real row mismatch.
  session <- new.env(parent = environment()); session$ores <- resource()
  evalq(dsOMOP::omopInitDS("ores"), session)
  on.exit(evalq(dsOMOP::omopCleanupDS("ores", close = TRUE), session), add = TRUE, after = FALSE)
  h <- evalq(dsOMOP:::.getHandle("ores"), session)
  stopifnot(is.null(h$person_key), nzchar(h$person_key_identity))
  a <- o_plan(1); run <- o_execute(a$plan, h)
  on.exit(o_revoke(run), add = TRUE, after = FALSE)
  stopifnot(o_compare(run, a$expected, h))
  a$expected$outputs[[1]]$rows$person_id[[1]] <- 999999L
  o_error(o_compare(run, a$expected, h), "isTRUE.*not TRUE")
  stopifnot(is.null(h$person_key))
  cat("PASS: key resolution is lazy and oracle still rejects wrong rows\n")
})
