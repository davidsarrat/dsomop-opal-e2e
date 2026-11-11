# Scenario C: resources created with dsOMOP 1.x's form (format omop.cdm.db) on the installed dsOMOP.
source("scripts/common.R")
start_log("scenario-C")
say("dsOMOP on Rock: ", rock_pkg_version("dsOMOP"), "; RPostgres: ", rock_pkg_version("RPostgres"))
conns <- analyst_login()
for (res in c("gibleed_v1", "gibleed_v1_vocab", "gibleed_v1_schemaonly", "gibleed_v1_plain")) {
  say("== ", res)
  r <- analyst_script(conns, paste0("omop_data.", res))
  summary_line("[", E2E_PATH, "] C: 1.x resource ", res, ": ",
               if (r$ok && isTRUE(r$tables_ok)) "OK" else paste0("FAIL: ", if (r$ok) "tables" else r$error))
}
DSI::datashield.logout(conns)
