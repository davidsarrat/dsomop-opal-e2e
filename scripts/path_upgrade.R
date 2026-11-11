# UPGRADE path (APHRC's server): dsOMOP <old_ref> installed and published first, then upgraded through the same
# Opal install call. Opal only auto-publishes packages that were not installed before, so the profile keeps the
# old methods until someone publishes the package again (scenario A); scenario B publishes and retries.
source("scripts/common.R")
start_log("path")
o <- admin()
old <- Sys.getenv("OLD_REF", "1.1.1")
target <- server_target()
res <- if (identical(MODE, "candidate")) "omop_data.gibleed" else "omop_data.gibleed_tls_disable"

say("== A1: install dsOMOP ", old, " (a new package: Opal publishes it)")
install_server(o, old)
show_dsomop_methods(o, paste("after installing", old))

say("== A2: upgrade to ", target, " through the same Opal install call")
install_server(o, target)
check_publication(o, paste("after upgrading to", target, "(no publish)"))

conns <- analyst_login()
introspect(conns, "after the upgrade, before publishing")
versions(conns, "after the upgrade, before publishing")
ensure_driver(o, conns, res)
say("== A3: the analyst's script (", res, ") right after the upgrade")
a <- analyst_script(conns, res)
summary_line("[upgrade] A: after upgrading ", old, " -> ", target, " without publishing: ",
             if (a$ok && isTRUE(a$tables_ok)) "OK" else paste0("FAIL: ", a$error))
DSI::datashield.logout(conns)

say("== B1: publish dsOMOP's settings (Opal > DataSHIELD > Packages > dsOMOP > Publish)")
capture("dsadmin.publish_package(o, \"dsOMOP\")", dsadmin.publish_package(o, "dsOMOP"))
check_publication(o, "after publishing")

conns <- analyst_login()
introspect(conns, "after publishing")
versions(conns, "after publishing")
say("== B2: the analyst's script on omop_data.gibleed (TLS mode left empty)")
b <- analyst_script(conns, "omop_data.gibleed")
summary_line("[upgrade] B: after publishing, gibleed (TLS mode empty): ",
             if (b$ok && isTRUE(b$tables_ok)) "OK" else paste0("FAIL: ", b$error))
if (!identical(MODE, "candidate")) {
  say("== B3: the analyst's script on omop_data.gibleed_tls_disable")
  c3 <- analyst_script(conns, "omop_data.gibleed_tls_disable")
  summary_line("[upgrade] B: after publishing, gibleed_tls_disable: ",
               if (c3$ok && isTRUE(c3$tables_ok)) "OK" else paste0("FAIL: ", c3$error))
}
DSI::datashield.logout(conns)
opal.logout(o)
