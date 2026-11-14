# N: second, numeric CDM. Requires matching dsOMOP/Client >= 2.10.4.
source("scripts/common.R")
source("scripts/numeric/scenario.R")
start_log("scenario-N")
result <- capture("N numeric hemoglobin values, units, dates and staged assignment", {
  o <- admin()
  if (identical(rock_pkg_version("dsBase"), "not installed")) dsadmin.install_package(o, "dsBase")
  opal.logout(o)
  conns <- analyst_login()
  tryCatch(run_numeric_scenario(conns), finally = DSI::datashield.logout(conns))
})
summary_line("[", E2E_PATH, "] N: ", if (result$ok) "PASS" else paste("FAIL", result$error))
if (!result$ok) { ds_errors(); quit(save = "no", status = 1L) }
show("Numeric aggregate results", result$value)
