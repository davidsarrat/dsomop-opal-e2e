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
  if (identical(Sys.getenv("DSOMOP_O_READ_ONLY"), "1")) {
    probe <- file.path(root, "tests/testthat/.pre7-write-probe")
    created <- suppressWarnings(file.create(probe))
    if (created) unlink(probe)
    stopifnot(!created)
    cat("PASS: fixture source directory refuses writes in this process\n")
  }
  only <- Sys.getenv("DSOMOP_O_ONLY")
  if (!nzchar(only)) {
    before <- tools::md5sum(list.files(file.path(root, "tests"), recursive = TRUE, full.names = TRUE))
    stopifnot(o_installed_tests(c("test-publication.R", "test-assignment-policy.R",
      "test-queries.R", "test-ohdsi-results.R", "test-analysis-catalog.R")))
    after <- tools::md5sum(list.files(file.path(root, "tests"), recursive = TRUE, full.names = TRUE))
    stopifnot(identical(before, after))
    cat("PASS: installed publication/aggregate checks preserve the source tree\n")
  }

  original_compare <- o_compare
  o_compare <- function(run, oracle, handle) {
    tryCatch(original_compare(run, oracle, handle), error = function(error) {
      for (component in names(oracle$outputs)) {
        spec <- oracle$outputs[[component]]; actual <- run$frames[[component]]
        expected <- spec$rows
        expected$person_id <- o_ns(".pseudonymizeIdentifiers")(data.frame(person_id = expected$person_id),
          o_ns(".personKey")(handle), attr(actual, "dsomop_pseudonymization"))$person_id
        cols <- unique(c("person_id", spec$comparison_columns))
        cat("Oracle mismatch:", component, "\n")
        print(all.equal(o_rows(actual[cols]), o_rows(expected[cols]), check.attributes = FALSE))
      }
      stop(error)
    })
  }
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
  birth <- omop_recipe(variables = list(
    omop_variable(name = "year_of_birth", table = "person", column = "year_of_birth"),
    omop_variable(name = "month_of_birth", table = "person", column = "month_of_birth"),
    omop_variable(name = "birth_datetime", table = "person", column = "birth_datetime"),
    age = omop_age(year = 2020), age_group = omop_age(year = 2020, bands = TRUE, age_breaks = c(0,18,19,65))),
    outputs = omop_output("birth", format = "wide", grain = "person"))
  checks <- if (nzchar(only)) strsplit(only, ",", fixed = TRUE)[[1L]] else c("acceptance1", "acceptance2", "staged", "matching", "aggregate_policy")
  for (name in checks) {
    # Separate invoking environments reproduce Opal resource/handle scoping.
    session <- new.env(parent = environment()); session$ores <- resource()
    plan <- switch(name, acceptance1 = recipe_to_plan(study),
                   aggregate_policy = recipe_to_plan(birth), NULL)
    original_births <- DBI::dbGetQuery(db, paste0("SELECT person_id, year_of_birth FROM ", schema, ".person ORDER BY person_id"))
    stopifnot(evalq(o_server_check(name, plan_override = plan), session))
    stopifnot(identical(original_births, DBI::dbGetQuery(db, paste0(
      "SELECT person_id, year_of_birth FROM ", schema, ".person ORDER BY person_id"))))
    cat("PASS: installed administrator check", name, "\n")
  }

  # Failure-inject the fixture callback itself to verify database restoration.
  fixture_handle <- new.env(); fixture_handle$conn <- db; fixture_handle$cdm_schema <- schema
  before_births <- DBI::dbGetQuery(db, paste0("SELECT person_id, year_of_birth FROM ", schema, ".person ORDER BY person_id"))
  o_error(o_with_birth_fixture(fixture_handle, function() stop("injected fixture failure")), "injected fixture failure")
  stopifnot(identical(before_births, DBI::dbGetQuery(db, paste0(
    "SELECT person_id, year_of_birth FROM ", schema, ".person ORDER BY person_id"))))
  cat("PASS: committed birth fixture writes are restored after assertion failure\n")
  if (!nzchar(only)) {
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
  }
})
