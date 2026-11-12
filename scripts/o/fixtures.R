O_SOURCE_ROOT <- Sys.getenv("DSOMOP_O_SOURCE", "/tmp/o-server-source")
O_HARNESS_ROOT <- Sys.getenv("DSOMOP_O_HARNESS", "/tmp/o-harness")
# Runs only in the disposable Rock administrator session. No analyst endpoint is added.
o_fixture_env <- function() {
  e <- new.env(parent = asNamespace("dsOMOP"))
  for (f in c("create_reach_db.R", "extend_reach_db.R", "load_reach_pg.R"))
    sys.source(file.path(file.path(O_SOURCE_ROOT, "tests/fixtures"), f), envir = e)
  e
}
o_load_fixtures <- function() {
  e <- o_fixture_env()
  db <- DBI::dbConnect(RPostgres::Postgres(), host = "omopdb", dbname = "omop", user = "omop",
                        password = Sys.getenv("O_DB_PASSWORD"), sslmode = "disable")
  on.exit(DBI::dbDisconnect(db))
  h <- e$build_extended_reach_handle(100L)
  on.exit(DBI::dbDisconnect(h$conn), add = TRUE)
  for (schema in c("o_reach", "o_small")) e$load_reach_fixture_pg(db, schema, handle = h)
  stopifnot(identical(e$reach_fixture_signature(db, "o_reach"), e$reach_fixture_signature(h$conn)))
  # Fixed public cohort selector 909: four persons at the small site, ten elsewhere.
  # k=5; every other fixture row is unchanged, so a second root can still pass.
  for (schema in c("o_reach", "o_small")) {
    n <- if (schema == "o_small") 4L else 10L
    DBI::dbExecute(db, paste0("INSERT INTO ",schema,".cohort SELECT 909, subject_id, cohort_start_date, cohort_end_date FROM ",
                              schema,".cohort WHERE cohort_definition_id=1 AND subject_id <= ",n))
  }
  big <- e$build_reach_handle(10000L)
  on.exit(DBI::dbDisconnect(big$conn), add = TRUE)
  e$load_reach_fixture_pg(db, "o_big", handle = big)
  invisible(TRUE)
}
