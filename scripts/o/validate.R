# Run on the test pod against the matching installed package, without Opal.
args <- commandArgs(TRUE)
package <- normalizePath(args[[1]])
harness <- normalizePath(args[[2]])
for (f in list.files(harness, pattern = "[.]R$", full.names = TRUE)) parse(f)
source(file.path(harness, "performance.R"))
source(file.path(harness, "matching_oracle.R"))
e <- new.env(parent = asNamespace("dsOMOP"))
for (f in c("create_reach_db.R", "extend_reach_db.R")) sys.source(file.path(package,"tests/fixtures",f), e)
h <- e$build_extended_reach_handle(100L)
for (p in o_performance_plans()) dsOMOP:::.irPrepare(p, h)
expected <- jsonlite::fromJSON(file.path(package,"inst/plans/acceptance/10-matching/expected.json"))
a <- o_matching_oracle(h$conn, 20261111L)
b <- o_matching_oracle(h$conn, 20261112L)
stopifnot(isTRUE(all.equal(a$outputs$cc_table$rows, expected$outputs$cc_table$rows, check.attributes = FALSE)),
          !identical(a$outputs$cc_table$rows, b$outputs$cc_table$rows))
if (identical(Sys.getenv("O_RECORD_ORACLE"), "1"))
  jsonlite::write_json(b, file.path(harness, "matching-seed-20261112.json"), auto_unbox = TRUE,
                      pretty = TRUE, digits = 16, na = "null", null = "null")
if (file.exists(file.path(harness, "matching-seed-20261112.json"))) {
  frozen <- jsonlite::read_json(file.path(harness, "matching-seed-20261112.json"), simplifyVector = TRUE)
  stopifnot(isTRUE(all.equal(b$outputs$cc_table$rows, frozen$outputs$cc_table$rows, check.attributes = FALSE)))
}
DBI::dbDisconnect(h$conn)
for (f in list.files(file.path(harness, "yaml"), full.names = TRUE)) yaml::read_yaml(f)
# Vignette code is deliberately unevaluated, but all chunks must parse.
for (f in list.files(file.path(harness,"vignettes"), pattern = "Rmd$", full.names = TRUE)) {
  code <- readLines(f); inside <- FALSE; chunks <- character()
  for (line in code) {
    if (grepl("^```\\{r", line)) {inside <- TRUE; next}
    if (grepl("^```", line)) {inside <- FALSE; next}
    if (inside) chunks <- c(chunks, line)
  }
  parse(text = chunks)
  stopifnot(any(grepl("opts_chunk.*eval = FALSE",code)))
}
cat("PASS: R syntax, YAML, v1 performance preflight, both matching reference seeds, vignette chunks\n")

Sys.setenv(DSOMOP_O_SOURCE = package, DSOMOP_O_HARNESS = harness)
source(file.path(harness, "server.R"))
stopifnot(o_installed_tests(c("test-assignment-policy.R", "test-queries.R", "test-ohdsi-results.R", "test-analysis-catalog.R")))
cat("PASS: installed aggregate-policy probes, including external birth-column admission
")
