# Execute exactly the Opal numeric scenario using installed packages on DSLite.
# This validates the scenario and protected routes, not the real Opal transport.
suppressPackageStartupMessages({library(dsOMOPClient); library(DSLite); library(DSI)})
source(file.path(Sys.getenv("NUMERIC_HARNESS"), "scripts/numeric/scenario.R"))
base <- tempfile("numeric-harness-"); dir.create(base); Sys.chmod(base, "0700")
Sys.setenv(DSOMOP_STATE_DIR = base, DSOMOP_TEST_ALLOW_EPHEMERAL_STATE = "1",
  DSOMOP_PSEUDONYM_PROVIDER = "file", DSOMOP_PSEUDONYM_ROOT = "", DSOMOP_PSEUDONYM_REQUIRE_EXISTING = "false")
options(dsstaging.base_dir = base)
resource <- resourcer::newResource(name = "numeric", format = "omop.dbi.db",
  url = "omop+dbi:postgresql://omopdb:5432/omop?cdm_schema=numeric_cdm&sslmode=disable", identity = "omop", secret = "omop")
server <- DSLite::newDSLiteServer(resources = list(numeric = resource),
  config = DSLite::defaultDSConfiguration(include = c("dsOMOP", "dsBase")))
login <- DSI::newDSLoginBuilder()
login$append(server = "numeric", url = "server", driver = "DSLiteDriver")
conns <- DSI::datashield.login(login$build())
tryCatch({
  result <- run_numeric_scenario(conns, "numeric")
  print(result)
  staged <- DSLite::getDSLiteData(conns, "NumericLabsStaged")[[1L]]
  stopifnot(inherits(staged, "FlowerDatasetDescriptor"), staged$metadata$format == "parquet")
  chunks <- list()
  dsOMOP:::.publishReadChunks(staged, function(x) chunks[[length(chunks) + 1L]] <<- x)
  frame <- do.call(rbind, chunks)
  memory <- DSLite::getDSLiteData(conns, "NumericLabs")[[1L]]
  stopifnot(is.double(frame$mean_hgb), is.double(frame$index_hgb), inherits(frame$date, "Date"),
            identical(frame$mean_hgb, memory$mean_hgb), identical(frame$index_hgb, memory$index_hgb),
            identical(frame$date, memory$date))
  cat("NUMERIC HARNESS PASS\n")
}, finally = {
  try(dsOMOPClient::ds.omop.disconnect("numeric", conns = conns), silent = TRUE)
  DSI::datashield.logout(conns); unlink(base, recursive = TRUE)
})
