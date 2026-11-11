# FRESH path: a clean Opal; the administrator installs dsOMOP the way the Opal UI does it (DataSHIELD > Packages >
# Install > GitHub isglobal-brge/dsOMOP @ ref, or the candidate source); a new package is auto-published.
source("scripts/common.R")
start_log("path")
o <- admin()
target <- server_target()
say("== FRESH install of dsOMOP (", target, ") on a clean Opal")
say("dsOMOP on Rock before: ", rock_pkg_version("dsOMOP"))
show_dsomop_methods(o, "before install")
r <- install_server(o, target)
pub <- check_publication(o, "after install (auto-publish of a new package)")

conns <- analyst_login()
introspect(conns, "fresh install")
versions(conns, "after a fresh install")
# The driver the resource needs; note whether the stock Rock image already has it.
first <- if (identical(MODE, "candidate")) "omop_data.gibleed" else "omop_data.gibleed_tls_disable"
ensure_driver(o, conns, first)

say("== the analyst's script on omop_data.gibleed (resource form with TLS mode left empty)")
a <- analyst_script(conns, "omop_data.gibleed")
summary_line("[fresh] analyst script on gibleed (TLS mode empty): ",
             if (a$ok && isTRUE(a$tables_ok)) "OK" else paste0("FAIL: ", a$error))
say("== the analyst's script on omop_data.gibleed_noschema (2.x resource without a CDM schema; GiBleed is in cdm)")
n <- analyst_script(conns, "omop_data.gibleed_noschema")
summary_line("[fresh] analyst script on gibleed_noschema (no cdm_schema, TLS mode empty): ",
             if (n$ok && isTRUE(n$tables_ok)) "OK" else paste0("FAIL: ", n$error))
if (!identical(MODE, "candidate")) {
  say("== the analyst's script on omop_data.gibleed_tls_disable (sslmode=disable)")
  b <- analyst_script(conns, "omop_data.gibleed_tls_disable")
  summary_line("[fresh] analyst script on gibleed_tls_disable: ",
               if (b$ok && isTRUE(b$tables_ok)) "OK" else paste0("FAIL: ", b$error))
}
DSI::datashield.logout(conns)
opal.logout(o)
