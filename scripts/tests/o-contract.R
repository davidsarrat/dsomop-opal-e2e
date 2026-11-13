# Targeted harness probes. Extract production helpers; stub only remote APIs.
get_fn <- function(path, name, env) {
  forms <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("<-")) &&
    identical(x[[2]], as.name(name)), as.list(parse(path)))
  stopifnot(length(forms) == 1L)
  remote_stubs <- function(x) {
    if (!is.call(x)) return(x)
    if (identical(x[[1]], as.name("::")) &&
        as.character(x[[2]]) %in% c("DSI", "dsOMOP")) return(x[[3]])
    as.call(lapply(as.list(x), remote_stubs))
  }
  eval(remote_stubs(forms[[1]]), env)
  get(name, env)
}
local({
  events <- character(); active <- FALSE; logged <- FALSE
  fail <- "none"
  analyst_login <- function(servers) {
    logged <<- TRUE
    setNames(as.list(servers), servers)
  }
  ds.omop.connect <- function(...) {
    stopifnot(logged, !active)
    if (fail == "connect") stop("connect failed")
    active <<- TRUE
  }
  ds.omop.disconnect <- function(...) {
    stopifnot(logged, active)
    events <<- c(events, "disconnect")
    active <<- FALSE
    if (fail == "disconnect") stop("disconnect failed")
  }
  datashield.logout <- function(...) {
    events <<- c(events, "logout"); logged <<- FALSE
  }
  with_sites <- get_fn("scripts/o/run.R", "with_sites", environment())
  for (i in 1:3) {
    with_sites(function(conns) stopifnot(active, logged))
    stopifnot(!active, !logged)
  }
  stopifnot(identical(events, rep(c("disconnect", "logout"), 3)))
  events <- character()
  msg <- tryCatch(with_sites(function(conns) stop("scenario failed")), error = conditionMessage)
  stopifnot(msg == "scenario failed", identical(events, c("disconnect", "logout")))
  for (phase in c("disconnect", "connect")) {
    fail <- phase; events <- character()
    msg <- tryCatch(with_sites(function(conns) NULL), error = conditionMessage)
    stopifnot(msg == paste(phase, "failed"), !logged)
    stopifnot(identical(tail(events, 1), "logout"))
  }
})
cat("PASS: OMOP cleanup precedes logout, repeats, and exposes cleanup errors\n")
local({
  ready <- FALSE; assigned <- FALSE
  admin <- function() "session"
  opal.logout <- function(o) NULL
  opal.execute <- function(o, code) {
    if (grepl('loadNamespace("dsOMOP")', code, fixed = TRUE)) ready <<- TRUE
    else stopifnot(ready, assigned)
    if (grepl('tryCatch(list(ok = o_server_check(', code, fixed = TRUE))
      return(list(ok = TRUE))
    TRUE
  }
  `%||%` <- function(a, b) if (is.null(a)) b else a
  opal.assign.resource <- function(...) {
    stopifnot(ready); assigned <<- TRUE
  }
  check <- function(ok, message) if (!isTRUE(ok)) stop(message)
  admin_check <- get_fn("scripts/o/run.R", "admin_check", environment())
  admin_check("fixture")
  stopifnot(ready, assigned)
  opal.execute <- function(o, code) {
    if (grepl('loadNamespace', code, fixed = TRUE)) return(TRUE)
    list(ok = FALSE, error = "specific fixture failure")
  }
  msg <- tryCatch(admin_check("fixture", plan = list(version = 2)), error = conditionMessage)
  stopifnot(grepl("specific fixture failure", msg, fixed = TRUE), nchar(msg) < 200L)
  # Every O administrator assignment must load the namespace first in that session.
  for (path in c("scripts/o/run.R", "scripts/o/install.R", "scripts/o/setup.R")) {
    lines <- readLines(path)
    assignments <- grep("opal.assign.resource(o,", lines, fixed = TRUE)
    stopifnot(length(assignments) > 0,
      all(grepl('loadNamespace("dsOMOP")', lines[assignments - 1L], fixed = TRUE)))
  }
})
cat("PASS: administrator resolver registration before assignment\n")
local({
  active <- FALSE; executed <- 0L; revoked <- 0L
  omopInitDS <- function(symbol) {
    stopifnot(exists(symbol, parent.frame(), inherits = FALSE), !active)
    active <<- TRUE
  }
  omopCleanupDS <- function(symbol, close) {
    stopifnot(exists(symbol, parent.frame(), inherits = FALSE), active, close)
    active <<- FALSE
  }
  omopPlanExecuteDS <- function(symbol, p, out) {
    stopifnot(active); executed <<- executed + 1L
    TRUE
  }
  omopPlanStatusDS <- function(symbol) {
    stopifnot(exists(symbol, parent.frame(), inherits = FALSE))
    list(status = "ok")
  }
  omopStagedRevokeDS <- function(symbol) { revoked <<- revoked + 1L }
  packageVersion <- function(...) numeric_version("2.10.3")
  o_performance_plans <- get_fn("scripts/o/performance.R", "o_performance_plans", environment())
  o_performance <- get_fn("scripts/o/performance.R", "o_performance", environment())
  session <- new.env(parent = environment()); session$ores <- "resource"
  result <- evalq(o_performance("ores", "candidate"), session)
  stopifnot(!active, executed == 6L, revoked == 6L,
            identical(names(result$seconds), c("baseline", "panel")))
  evalq(o_performance("ores", "baseline"), session)
  stopifnot(!active, executed == 12L, revoked == 6L)
  omopPlanExecuteDS <- function(...) stop("timing failed")
  msg <- tryCatch(evalq(o_performance("ores", "candidate"), session), error = conditionMessage)
  stopifnot(msg == "timing failed", !active)
})
cat("PASS: timing initialization and cleanup use the resource's session\n")
local({
  script <- paste(readLines("scripts/o/install.R"), collapse = "\n")
  stopifnot(grepl('ds.omop.connect("omop_data.gibleed_legacy",', script, fixed = TRUE),
    grepl('opal.logout(o)\n  o <- admin()\n}\ninstall_server', script, fixed = TRUE))
  # Evaluate the actual resource definitions without contacting Opal.
  env <- new.env(parent = baseenv())
  env$v2_url <- function(host, port, database, ...) database
  env$v1_url <- function(...) "v1"
  env$db <- "omop"
  forms <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("<-")) &&
    identical(x[[2]], as.name("resources")), as.list(parse("scripts/admin_setup.R")))
  eval(forms[[1]], env)
  stopifnot(env$resources$gibleed_legacy$url == "omop53",
            env$resources$gibleed$url == "omop",
            env$resources$gibleed_asshipped$url == "omop")
})
cat("PASS: old-server fixture selection and fresh namespace for upgrade\n")
local({
  o_aggregate_refused <- get_fn("scripts/o/run.R", "o_aggregate_refused", environment())
  result <- function(per_site = list(), pooled = NULL, warnings = "Server: blocked sensitive column")
    structure(list(per_site = per_site, pooled = pooled, meta = list(warnings = warnings)), class = "dsomop_result")
  stopifnot(o_aggregate_refused(list(ok = FALSE, error = "blocked column"), list()),
    o_aggregate_refused(list(ok = TRUE, value = result()), list()),
    !o_aggregate_refused(list(ok = TRUE, value = result(warnings = "network failure")), list()),
    !o_aggregate_refused(list(ok = TRUE, value = result(per_site = list(site = data.frame(n = 1)))), list()),
    !o_aggregate_refused(list(ok = TRUE, value = result(pooled = data.frame(n = 1))), list()),
    !o_aggregate_refused(list(ok = TRUE, value = list()), list()))
})
cat("PASS: aggregate refusals require explicit evidence and no returned values\n")
local({
  active <- FALSE; closed <- FALSE
  omopInitDS <- function(symbol) {
    stopifnot(exists(symbol, parent.frame(), inherits = FALSE), !active)
    assign(paste0(".dsomop_handle_", symbol), "fixture-handle", parent.frame())
    active <<- TRUE
  }
  omopCleanupDS <- function(symbol, close) {
    stopifnot(active, close); closed <<- TRUE; active <<- FALSE
  }
  .getHandle <- function(symbol) get(paste0(".dsomop_handle_", symbol), parent.frame(), inherits = FALSE)
  o_ns <- function(name) get(name)
  # This check follows the exact init/getHandle path, then deliberately fails.
  # Rewrite ::: only for this test's stand-in, just as :: in get_fn().
  forms <- parse("scripts/o/server.R")
  selected <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("<-")) &&
    identical(x[[2]], as.name("o_server_check")), as.list(forms))
  rewrite <- function(x) {
    if (!is.call(x)) return(x)
    if ((identical(x[[1]], as.name("::")) || identical(x[[1]], as.name(":::"))) && identical(x[[2]], as.name("dsOMOP"))) return(x[[3]])
    as.call(lapply(as.list(x), rewrite))
  }
  eval(rewrite(selected[[1L]]))
  session <- new.env(parent = environment()); session$ores <- "resource"
  msg <- tryCatch(evalq(o_server_check("injected_unknown"), session), error = conditionMessage)
  stopifnot(grepl("unknown administrator check", msg), closed, !active)
})
cat("PASS: fixture initialization and failure cleanup use the invoking Opal session\n")
local({
  calls <- integer(); checked <- FALSE
  with_sites <- function(fn) fn(list(good = 1L, other = 2L))
  omop_study <- function(...) "recipe"; omop_event <- omop_age <- function(...) NULL
  omop_privacy <- function(...) NULL; recipe <- function(...) "matching"
  ds.omop.dp.prepare <- function(rec, ...) { if (identical(rec, "matching")) stop("not_person_local") }
  ds.omop.dp.release <- function(..., datasources) {
    calls <<- c(calls, length(datasources))
    if (length(datasources) == 2L) stop("Selected servers share a DP noise domain")
    list(count = 10)
  }
  capture <- function(label, expr) tryCatch(list(ok = TRUE, value = force(expr)), error = function(e) list(ok = FALSE, error = conditionMessage(e)))
  check <- function(ok, ...) stopifnot(ok)
  admin_check <- function(name) { stopifnot(name == "dp"); checked <<- TRUE }
  scenario <- function(id, fn) { stopifnot(id == "O8"); fn() }
  forms <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("scenario")) && identical(x[[2]], "O8"), as.list(parse("scripts/o/run.R")))
  eval(forms[[1L]])
  stopifnot(identical(calls, c(2L, 1L)), checked)
})
cat("PASS: duplicate DP node is refused and a single-node release succeeds\n")

local({
  o_rows <- get_fn("scripts/o/server.R", "o_rows", environment())
  numeric <- data.frame(person_id = c("b", "a"), set_id = c(2L, 1L), w = c(1, 0.5))
  text <- transform(numeric, set_id = as.character(set_id))
  stopifnot(identical(o_rows(numeric), o_rows(text)),
    !identical(o_rows(numeric), o_rows(transform(text, set_id = c("3", "1")))),
    !identical(o_rows(numeric), o_rows(transform(text, w = c(1, 0.6)))),
    identical(o_rows(data.frame(set_id = "9007199254740993"))$set_id, "9007199254740993"))
})
cat("PASS: analytic key comparisons preserve exact identity and numeric measures\n")
