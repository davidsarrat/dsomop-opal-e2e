# Scenario F: the legacy RPostgreSQL fallback. The stock Rock image carries RPostgres in Rock's own library, so the
# administrator removes it first (through Opal's R session); dsOMOP must then connect through RPostgreSQL, verify a
# UTC session (.ensurePostgresUtc stops the connection otherwise), run the analyst's work and clean up on disconnect.
source("scripts/common.R")
suppressPackageStartupMessages(library(dsOMOPClient))
start_log("scenario-F")
before <- c(RPostgres = rock_pkg_version("RPostgres"), RPostgreSQL = rock_pkg_version("RPostgreSQL"))
removed <- rock_eval(paste0('tryCatch({ p <- system.file(package = "RPostgres"); if (!nzchar(p)) "not installed" else ',
                            '{ utils::remove.packages("RPostgres", lib = dirname(p)); paste("removed from", dirname(p)) } }, ',
                            'error = function(e) paste("error:", conditionMessage(e)))'))
after <- c(RPostgres = rock_pkg_version("RPostgres"), RPostgreSQL = rock_pkg_version("RPostgreSQL"))
say("drivers before: ", paste(names(before), before, collapse = ", "), "; ", paste(removed, collapse = " "),
    "; after: ", paste(names(after), after, collapse = ", "))
summary_line("[", E2E_PATH, "] F: Rock drivers for this scenario: RPostgres ", after[["RPostgres"]], ", RPostgreSQL ", after[["RPostgreSQL"]])
conns <- analyst_login()
note <- function(res, step, r) {
  summary_line("[", E2E_PATH, "] F ", res, " ", step, ": ", if (r$ok) "OK" else paste0("FAIL: ", r$error))
  if (!r$ok) {
    e <- tryCatch(DSI::datashield.errors(), error = function(e) NULL)
    if (length(e)) summary_line("     datashield.errors(): ", paste(names(e), unlist(e), sep = ": ", collapse = " | "))
  }
}
k <- 0L
for (res in c("omop_data.gibleed", "omop_data.gibleed_v1", "omop_data.gibleed_noschema")) {
  k <- k + 1L  # recipe outputs persist in the session after disconnect: fresh names per resource
  say("== ", res, " through RPostgreSQL")
  r <- capture(paste0("ds.omop.connect(\"", res, "\")"), ds.omop.connect(resource = res, symbol = "omop", conns = conns))
  note(res, "connect (verified UTC session)", r)
  if (!r$ok) { ds_errors(); next }
  t <- capture("ds.omop.tables", ds.omop.tables(symbol = "omop", conns = conns)[[1]])
  if (t$ok) show("tabs[CDM]", t$value[t$value$schema_category == "CDM", c("table_name", "has_person_id")])
  note(res, "ds.omop.tables (analyst script)", t)
  dc <- capture("ds.omop.date.counts(\"condition_occurrence\")",
                ds.omop.date.counts("condition_occurrence", symbol = "omop", conns = conns))
  note(res, "ds.omop.date.counts", dc)
  r1 <- capture("recipe: demographics", recipe_execute(omop_recipe(
    variables = list(omop_variable_age(), omop_variable_sex()),
    outputs = omop_output(name = "demo", type = "wide")), out = c(demo = paste0("F1_", k)), symbol = "omop", conns = conns))
  note(res, "recipe demographics (wide)", r1)
  r2 <- capture("recipe: GI bleed index, drug events in the 2 years before (long)", recipe_execute(omop_recipe(
    populations = omop_population(id = "base", index_event = omop_index_event(192671, "condition_occurrence",
                                                                              primary_limit = "first", include_descendants = TRUE)),
    variables = list(omop_variable_age(reference = "index"), omop_variable_sex()),
    outputs = omop_output(name = "gib", type = "wide")), out = c(gib = paste0("F2_", k)), symbol = "omop", conns = conns))
  note(res, "recipe GI bleed index (wide)", r2)
  d <- capture("ds.omop.disconnect (cleanup)", ds.omop.disconnect(symbol = "omop", conns = conns))
  note(res, "ds.omop.disconnect (cleanup)", d)
}
DSI::datashield.logout(conns)
