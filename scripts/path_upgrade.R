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
old_version <- rock_pkg_version("dsOMOP")

# A1b: a 2.x server with the DP service creates its noise root at the first DP call. The upgrade must keep using it
# (scenario G compares the root's public key id and the state files after the upgrade and the publish).
if (grepl("^2\\.", old_version) && utils::compareVersion(old_version, "2.6.0") >= 0) {
  say("== A1b: the analyst's first DP call under dsOMOP ", old_version, " creates the noise root")
  c0 <- analyst_login()
  k <- capture("ds.omop.connect", dsOMOPClient::ds.omop.connect(resource = res, symbol = "omop", conns = c0))
  st <- if (k$ok) capture("DSI::datashield.aggregate(omopDpStatusDS())", DSI::datashield.aggregate(c0, quote(omopDpStatusDS()))) else k
  key <- if (st$ok && is.list(st$value[[1]])) as.character(st$value[[1]]$noise_key_id %||% NA) else NA_character_
  if (k$ok) capture("ds.omop.disconnect", dsOMOPClient::ds.omop.disconnect(symbol = "omop", conns = c0))
  DSI::datashield.logout(c0)
  files <- rock_eval('local({ s <- file.path(Sys.getenv("HOME"), ".dsomop"); f <- list.files(s, recursive = TRUE, all.files = TRUE); i <- file.info(file.path(s, f)); paste(f, i$size, format(i$mtime, "%Y-%m-%dT%H:%M:%OS3"), sep = " | ") })')
  writeLines(c(paste0("version=", old_version), paste0("noise_key_id=", key), paste0("file=", files)),
             out_file("dp-root-before-upgrade.txt"))
  show("state files under the old version", files)
  summary_line("[upgrade] A1b: DP status under dsOMOP ", old_version, ": ",
               if (st$ok) paste0("noise root key id ", key) else paste0("FAIL: ", st$error))
}
# A1c: the new client against the real old server, before the upgrade (scenario G adds these V verdicts).
if (grepl("^2\\.", old_version) && utils::compareVersion(old_version, "2.10.3") < 0 &&
    grepl("G", Sys.getenv("SCENARIOS", "G"))) {
  say("== A1c: the new client against the real dsOMOP ", old_version, " server")
  tryCatch(source("scripts/combo_old_server.R", local = new.env()),
           error = function(e) summary_line("[upgrade] A1c: combo_old_server.R stopped: ", conditionMessage(e)))
}

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
