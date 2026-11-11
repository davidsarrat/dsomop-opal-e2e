# Scenario F: the legacy RPostgreSQL fallback. The stock Rock image carries RPostgres in Rock's own library, so the
# administrator removes it first (through Opal's R session); dsOMOP must then connect through RPostgreSQL and still
# verify a UTC session (.ensurePostgresUtc stops the connection otherwise).
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
conns <- analyst_login()
for (res in c("omop_data.gibleed", "omop_data.gibleed_tls_disable", "omop_data.gibleed_v1")) {
  say("== ", res, " through RPostgreSQL")
  r <- capture(paste0("ds.omop.connect(\"", res, "\")"), ds.omop.connect(resource = res, symbol = "omop", conns = conns))
  if (!r$ok) {
    ds_errors()
    summary_line("[", E2E_PATH, "] F (RPostgreSQL fallback) ", res, ": FAIL: ", r$error)
    next
  }
  t <- capture("ds.omop.tables", ds.omop.tables(symbol = "omop", conns = conns)[[1]])
  dc <- capture("ds.omop.date.counts(\"condition_occurrence\")",
                ds.omop.date.counts("condition_occurrence", symbol = "omop", conns = conns))
  if (dc$ok) show("date counts (first rows)", utils::head(dc$value$per_site[[1]], 5))
  capture("ds.omop.disconnect", ds.omop.disconnect(symbol = "omop", conns = conns))
  summary_line("[", E2E_PATH, "] F (RPostgreSQL fallback; RPostgres ", after[["RPostgres"]], ") ", res,
               ": connect OK (UTC session verified), tables ", if (t$ok) "OK" else paste("FAIL", t$error),
               ", date counts ", if (dc$ok) "OK" else paste("FAIL", dc$error))
}
DSI::datashield.logout(conns)
