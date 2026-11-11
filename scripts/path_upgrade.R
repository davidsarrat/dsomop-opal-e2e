# UPGRADE path (APHRC's server): dsOMOP <old_ref> installed and published first, then upgraded through the same
# Opal install call. Opal only auto-publishes packages that were not installed before, so the profile keeps the
# old methods until someone publishes the package again (scenario A); scenario B publishes and retries.
source("scripts/common.R")
start_log("path")
o <- admin()
old <- Sys.getenv("OLD_REF", "6a22d259db95a3bfd264d029b653587f935e32db")
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
if (!a$ok) {
  # APHRC's session got past the resource assignment, so the dsOMOP namespace (2.x code, whose resolver reads
  # omop.dbi.db) was already loaded there. Calling any still-published 1.x method loads it the same way.
  say("== A4: a published 1.x method first (loads the installed dsOMOP namespace in the session), then connect again")
  l <- capture("DSI::datashield.aggregate(conns, quote(checkConnectionDS()))", DSI::datashield.aggregate(conns, quote(checkConnectionDS())))
  if (!l$ok) ds_errors()
  a4 <- analyst_script(conns, res)
  summary_line("[upgrade] A4: same session after a 1.x call: ", if (a4$ok && isTRUE(a4$tables_ok)) "OK" else paste0("FAIL: ", a4$error))
  e4 <- tryCatch(DSI::datashield.errors(), error = function(e) NULL)
  if (length(e4)) summary_line("[upgrade] A4 datashield.errors(): ", paste(names(e4), unlist(e4), sep = ": ", collapse = " | "))
}
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
