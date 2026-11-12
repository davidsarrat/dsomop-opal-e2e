# Helpers of scenario G (scenario_G.R, scenario_G_old.R, combo_old_server.R): verdicts, exact answer fingerprints,
# sessions, the server calls exactly as dsOMOPClient builds them, Rock and database helpers and the probe set.
# Source after common.R and library(dsOMOPClient) (any version from 2.10.2 on).
`%||%` <- function(a, b) if (is.null(a)) b else a
RES <- "omop_data.gibleed"
ROCK <- Sys.getenv("ROCK", paste0(Sys.getenv("STACK", "e2e"), "-rock"))
CDM_DB_NAME <- Sys.getenv("CDM_DB", "omop")
CELECOXIB <- 1118084L
DICLOFENAC <- 1124300L

# --- verdicts -------------------------------------------------------------------------------------------------------
# PASS, FAIL (a product failure, with its evidence), INFO, ERROR (the harness section stopped).
VERDICTS <- list()
VERDICT_PREFIX <- "G"
squash <- function(x, n = 600) {
  x <- gsub("[\r\n\t ]+", " ", paste(x, collapse = " "))
  if (nchar(x) > n) paste0(substr(x, 1, n), "...") else x
}
verdict <- function(id, status, title, evidence = "") {
  evidence <- squash(evidence, 3000)
  VERDICTS[[length(VERDICTS) + 1L]] <<- data.frame(id = id, status = status, title = title, evidence = evidence,
                                                   stringsAsFactors = FALSE)
  summary_line("[", E2E_PATH, "] ", VERDICT_PREFIX, " ", id, " ", status, ": ", title,
               if (nzchar(evidence)) paste0(" | ", squash(evidence, 900)) else "")
}
section <- function(id, title, fn) {
  say("")
  say("======== ", id, ": ", title)
  t0 <- Sys.time()
  err <- tryCatch({ fn(); NULL }, error = function(e) conditionMessage(e))
  if (!is.null(err)) verdict(id, "ERROR", paste0(title, " (the harness section stopped)"), err)
  say("-------- ", id, " done in ", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), " s")
}
write_verdicts <- function(file_tag) {
  tab <- if (length(VERDICTS)) do.call(rbind, VERDICTS) else
    data.frame(id = character(0), status = character(0), title = character(0), evidence = character(0))
  utils::write.csv(tab, out_file(paste0(file_tag, "-verdicts.csv")), row.names = FALSE)
  tab
}
ERRS <- character(0)   # every error text the analyst received (scenario G's leak check)
capture_ds <- function(label, expr) {
  r <- capture(label, expr)
  if (!r$ok) {
    e <- tryCatch(DSI::datashield.errors(), error = function(e) NULL)
    if (length(e)) {
      r$error <- paste0(r$error, " || ", paste(names(e), unlist(e), sep = ": ", collapse = " | "))
      say("  [datashield.errors] ", squash(unlist(e), 3000))
    }
    ERRS <<- c(ERRS, r$error)
  }
  r
}
# An internal R error reaching the analyst is a crash, not a plain refusal.
CRASH_RE <- paste0("subscript out of bounds|argument is of length zero|\\$ operator is invalid|could not find function|",
                   "missing value where TRUE/FALSE needed|non-numeric argument|unused argument|attempt to apply ",
                   "non-function|object of type 'closure'|cannot coerce|replacement has|arguments imply differing|",
                   "Internal Server Error|\\(500\\)")
plain_error <- function(msg) is.character(msg) && length(msg) == 1L && nzchar(msg) && !grepl(CRASH_RE, msg)
last_server_error <- function(msg) squash(sub("^.* -> ", "", msg %||% ""), 300)

# --- exact answer fingerprints --------------------------------------------------------------------------------------
canon <- function(x) paste(deparse(x, control = c("keepNA", "keepInteger", "niceNames", "showAttributes", "digits17")),
                           collapse = "\n")
md5 <- function(txt) {
  f <- tempfile()
  on.exit(unlink(f))
  writeLines(txt, f, useBytes = TRUE)
  unname(tools::md5sum(f))
}
plain_columns <- function(x) lapply(as.list(x), function(v) {
  if (inherits(v, "integer64") || is.factor(v)) return(as.character(v))
  if (inherits(v, c("Date", "POSIXt"))) return(format(v))
  as.vector(v)
})
answer_of <- function(x) if (is.data.frame(x)) plain_columns(x) else x
hex64 <- function(txt) unique(unlist(regmatches(txt, gregexpr("[0-9a-f]{64}", txt))))
# Numeric cells of two frames that changed, aligned on their text columns (rows absent from one side count as changed).
cell_changes <- function(a, b) {
  if (!is.data.frame(a) || !is.data.frame(b)) return(c(cells = NA, changed = NA))
  key_cols <- intersect(names(a)[!vapply(a, is.numeric, logical(1))], names(b))
  num_cols <- intersect(names(a)[vapply(a, is.numeric, logical(1))], names(b)[vapply(b, is.numeric, logical(1))])
  ka <- if (length(key_cols)) do.call(paste, c(lapply(a[key_cols], as.character), sep = "\r")) else as.character(seq_len(nrow(a)))
  kb <- if (length(key_cols)) do.call(paste, c(lapply(b[key_cols], as.character), sep = "\r")) else as.character(seq_len(nrow(b)))
  m <- match(ka, kb)
  cells <- 0L
  changed <- 0L
  for (cn in num_cols) {
    va <- as.numeric(a[[cn]])
    vb <- as.numeric(b[[cn]])[m]
    nz <- (!is.na(va) & va != 0) | (!is.na(vb) & vb != 0)
    cells <- cells + sum(nz)
    changed <- changed + sum(nz & (is.na(va) | is.na(vb) | va != vb))
  }
  c(cells = cells, changed = changed)
}

# --- sessions -------------------------------------------------------------------------------------------------------
N_SESSIONS <- 0L
next_symbol <- function() {
  N_SESSIONS <<- N_SESSIONS + 1L
  paste0("omopG", N_SESSIONS)
}
open_session <- function(label, servers = "Ethiopia", users = rep("analyst", length(servers)), restore = NULL,
                         resource = RES, connect = TRUE) {
  lg <- capture(sprintf("%s: login (%s as %s%s)", label, paste(servers, collapse = "+"), paste(users, collapse = "+"),
                        if (is.null(restore)) "" else paste0(", restore '", restore, "'")),
                analyst_login(servers, users, restore))
  if (!lg$ok) return(list(ok = FALSE, error = lg$error, label = label, conns = NULL, symbol = NA_character_))
  s <- list(ok = TRUE, label = label, conns = lg$value, servers = servers, symbol = NA_character_, rs = NA_character_,
            login_secs = lg$secs, login_warnings = lg$warnings)
  if (connect) s <- connect_session(s, resource)
  s
}
connect_session <- function(s, resource = RES) {
  s$symbol <- next_symbol()
  con <- capture_ds(sprintf("%s: ds.omop.connect(%s, symbol = \"%s\")", s$label, squash(deparse(resource), 200), s$symbol),
                    ds.omop.connect(resource = resource, symbol = s$symbol, conns = s$conns))
  s$ok <- con$ok
  s$error <- con$error
  s$connect_warnings <- con$warnings
  s$connect_secs <- con$secs
  s$rs <- if (con$ok) dsOMOPClient:::.get_session(s$symbol)$res_symbol else NA_character_
  s
}
disconnect_session <- function(s) {
  if (isTRUE(s$ok) && !is.na(s$symbol)) {
    capture(paste0(s$label, ": ds.omop.disconnect(\"", s$symbol, "\")"),
            ds.omop.disconnect(symbol = s$symbol, conns = s$conns))
  }
  env <- dsOMOPClient:::.dsomop_client_env
  if (!is.na(s$symbol) && exists(s$symbol, envir = env, inherits = FALSE)) rm(list = s$symbol, envir = env)
  s$ok <- FALSE
  s
}
close_session <- function(s) {
  if (is.null(s) || is.null(s$conns)) return(invisible(NULL))
  disconnect_session(s)
  try(DSI::datashield.logout(s$conns), silent = TRUE)
  invisible(NULL)
}

# Server calls exactly as the client builds them, returned with every attribute (labels, signed components).
raw_run <- function(s, id, params = list(), cohort = NULL) {
  scope <- dsOMOPClient:::.analysis_scope_expr(cohort, NULL)
  DSI::datashield.aggregate(s$conns, dsOMOPClient:::.analysis_run_call("omopAnalysisRunDS", s$rs, id, params,
                                                                       scope, "union"))
}
raw_typed <- function(s, sym, spec) {
  DSI::datashield.aggregate(s$conns, call("omopDpReleaseDS", as.name(sym), dsOMOPClient:::.ds_encode(spec)))
}
raw_status <- function(s) DSI::datashield.aggregate(s$conns, quote(omopDpStatusDS()))
protection_of <- function(x) {
  if (is.data.frame(x)) attr(x, "dsomop_protection", exact = TRUE)$protection %||% "standard" else
    if (is.list(x)) x$protection %||% NA_character_ else NA_character_
}

# --- Rock, as the administrator sees it -------------------------------------------------------------------------------
STATE_CODE <- 'local({
  s <- tryCatch(dsOMOP:::.dsomopStateRoot(), error = function(e) paste("error:", conditionMessage(e)))
  f <- if (dir.exists(s)) list.files(s, recursive = TRUE, all.files = TRUE) else character(0)
  i <- file.info(file.path(s, f))
  list(user = Sys.info()[["user"]], home = Sys.getenv("HOME"), state_dir = s,
       state_files = if (length(f)) paste(f, i$size, format(i$mode), format(i$mtime, "%Y-%m-%dT%H:%M:%OS3"),
                                          sep = " | ") else character(0))
})'
state_files <- function() {
  st <- rock_eval(STATE_CODE)
  if (inherits(st, "rock_error")) stop("cannot list the dsOMOP state directory: ", st)
  st
}
root_line <- function(st) grep("^secrets/dp_noise_root \\|", st$state_files, value = TRUE)
rock_log <- function() {
  tryCatch(suppressWarnings(system2("docker", c("exec", ROCK, "cat", "/srv/logs/Rserve.log"), stdout = TRUE,
                                    stderr = FALSE)), error = function(e) character(0))
}
ROOT_CREATED_RE <- "created the DP noise root"
# One administrator R session on Rock with a resource assigned and a dsOMOP handle initialised (symbol "gres").
admin_handle_eval <- function(code, resource = RES) {
  o2 <- admin()
  on.exit(try(opal.logout(o2), silent = TRUE))
  tryCatch({
    opal.assign.resource(o2, "gres", resource)
    opal.execute(o2, 'invisible(dsOMOP::omopInitDS("gres"))')
    opal.execute(o2, code)
  }, error = function(e) structure(conditionMessage(e), class = "rock_error"))
}
HANDLE_CODE <- 'h <- if (exists(".dsomop_handle_gres", envir = globalenv())) get(".dsomop_handle_gres", envir = globalenv()) else dsOMOP:::.getHandle("gres")'
set_option <- function(name, value) {
  o2 <- admin()
  on.exit(try(opal.logout(o2), silent = TRUE))
  r <- capture(sprintf("dsadmin.set_option(o, \"%s\", %s)", name, value), dsadmin.set_option(o2, name, value))
  opts <- tryCatch(dsadmin.get_options(o2), error = function(e) NULL)
  if (is.data.frame(opts)) show(paste("profile option", name), opts[opts$name == name, , drop = FALSE])
  invisible(r)
}
rm_option <- function(name) {
  o2 <- admin()
  on.exit(try(opal.logout(o2), silent = TRUE))
  capture(sprintf("dsadmin.rm_option(o, \"%s\")", name), dsadmin.rm_option(o2, name))
  opts <- tryCatch(dsadmin.get_options(o2), error = function(e) NULL)
  if (is.data.frame(opts)) say("profile option ", name, " after removal: ", if (name %in% opts$name) "still present" else "absent")
}

# --- the OMOP database (container omopdb), as its owner ---------------------------------------------------------------
psql <- function(sql, db = CDM_DB_NAME, label = NULL) {
  out <- suppressWarnings(system2("docker", c("exec", "-i", "omopdb", "psql", "-v", "ON_ERROR_STOP=1", "-U", "omop",
                                              "-d", db, "-qAt"), input = sql, stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status") %||% 0L
  say("psql[", db, "] ", label %||% squash(sql, 160), ": ", if (identical(as.integer(st), 0L)) "ok" else paste("FAILED", st))
  if (!identical(as.integer(st), 0L)) stop("psql failed (", label %||% squash(sql, 80), "): ", paste(out, collapse = " "))
  out
}
psql_value <- function(sql, db = CDM_DB_NAME) {
  out <- psql(sql, db = db)
  out <- out[nzchar(out)]
  if (!length(out)) NA_character_ else out[[length(out)]]
}
sql_quote <- function(x) paste0("'", gsub("'", "''", x, fixed = TRUE), "'")

# --- the probe set ------------------------------------------------------------------------------------------------------
COHORT_SPECS <- list(
  T = list(spec = list(type = "drug", concept_set = CELECOXIB), id = 601L, name = "g_celecoxib"),
  C = list(spec = list(type = "drug", concept_set = DICLOFENAC), id = 602L, name = "g_diclofenac"))
AGES_RECIPE <- omop_recipe(variables = omop_variable_age(name = "age_at_2025", year = 2025),
                           outputs = omop_output(name = "ages", type = "wide"))
TAR365 <- list(tar_start_offset = "0", tar_end_offset = "365", tar_anchor_start = "start", tar_anchor_end = "start")
TAR730 <- list(tar_start_offset = "0", tar_end_offset = "730", tar_anchor_start = "start", tar_anchor_end = "start")
# Unscoped questions over public bases (fixed synopses keyed on the automatic generation).
FIXED_Q <- list(
  achilles_3 = list(id = "dsomop:achilles.3"),
  age_decade = list(id = "dsomop:person.age_distribution_decade", params = list(reference_year = "2020")),
  long_op = list(id = "dsomop:observation_period.long_period_count", params = list(min_days = "365")),
  condition_era = list(id = "dsomop:condition_era.length_stats"))
# Cohort-scoped questions (realised-contribution protection).
SCOPED_Q <- list(
  incidence = list(id = "dsomop:incidence.rate", cohort = "T", params = c(list(outcome_concept_id = "192671"), TAR365)),
  mdrr = list(id = "dsomop:cm.mdrr", cohort = c("T", "C"), params = c(list(outcome_concept_id = "192671"), TAR365)))
# Typed releases: a pinned loader table (fixed-synopsis capable) and a prepared table (realised).
TYPED_Q <- list(
  loader_count = list(table = "loader", spec = unclass(omop_privacy("count", population_id = "g_loader"))),
  loader_records = list(table = "loader", spec = unclass(omop_privacy("bounded_record_count", max_contributions = 10,
                                                                      population_id = "g_loader"))),
  prepared_count = list(table = "prepared", spec = unclass(omop_privacy("count", population_id = "g_ages"))),
  prepared_hist = list(table = "prepared", spec = unclass(omop_privacy("numeric_histogram", variable = "age_at_2025",
                                                                       breaks = seq(0, 120, by = 10), reducer = "mean",
                                                                       population_id = "g_ages"))))

make_objects <- function(s, prepared = "G_ages", loader = TRUE, cohorts = TRUE) {
  obj <- list(cohorts = list(), loader = NA_character_, prepared = NA_character_)
  if (cohorts) for (k in names(COHORT_SPECS)) {
    cs <- COHORT_SPECS[[k]]
    r <- capture_ds(sprintf("%s: cohort %s (%s %d, cohort_id %d)", s$label, k, cs$spec$type, cs$spec$concept_set, cs$id),
                    ds.omop.cohort.create(spec = cs$spec, cohort_id = cs$id, name = cs$name, mode = "temporary",
                                          symbol = s$symbol, conns = s$conns))
    if (r$ok) obj$cohorts[[k]] <- r$value
  }
  if (loader) {
    r <- capture_ds(sprintf("%s: pinned loader dsomop:condition_occurrence.load (assign)", s$label),
                    ds.omop.analysis.run("dsomop:condition_occurrence.load", type = "split", symbol = s$symbol,
                                         conns = s$conns))
    if (r$ok) obj$loader <- r$value$meta$assign_symbol
    obj$loader_error <- r$error
  }
  if (!is.null(prepared)) {
    r <- capture_ds(sprintf("%s: ds.omop.dp.prepare(ages at 2025 -> %s)", s$label, prepared),
                    ds.omop.dp.prepare(AGES_RECIPE, out = c(ages = prepared), symbol = s$symbol, conns = s$conns))
    if (r$ok) obj$prepared <- prepared
    obj$prepared_error <- r$error
  }
  obj
}

probe_one <- function(s, kind, q, obj) {
  if (identical(kind, "typed")) {
    sym <- obj[[q$table]]
    label <- sprintf("%s: typed %s on %s", s$label, q$spec$statistic, q$table)
    if (is.null(sym) || is.na(sym)) return(list(ok = FALSE, error = paste("no", q$table, "table in this session"), secs = 0))
    r <- capture_ds(label, raw_typed(s, sym, q$spec))
  } else {
    coh <- NULL
    if (!is.null(q$cohort)) {
      coh <- obj$cohorts[q$cohort]
      if (length(coh) != length(q$cohort) || any(vapply(coh, is.null, logical(1)))) {
        return(list(ok = FALSE, error = "cohort missing in this session", secs = 0))
      }
      coh <- if (length(coh) == 1L) coh[[1L]] else unname(coh)
    }
    label <- sprintf("%s: %s %s", s$label, q$id, if (length(q$params)) squash(jsonlite::toJSON(q$params, auto_unbox = TRUE), 160) else "")
    r <- capture_ds(label, raw_run(s, q$id, q$params %||% list(), coh))
  }
  if (!r$ok) return(list(ok = FALSE, error = r$error, secs = r$secs))
  per <- lapply(r$value, function(x) {
    list(answer = md5(canon(answer_of(x))), full = md5(canon(x)), protection = paste(protection_of(x), collapse = "/"),
         rows = if (is.data.frame(x)) nrow(x) else NA_integer_)
  })
  list(ok = TRUE, secs = r$secs, per = per, value = r$value)
}
# Order: scoped questions first (they warm the catalogue registry and the DP runtime), then the fixed ones (the first
# derives the session's data generation), then the typed releases. keys = a subset of probe names.
run_probes <- function(s, obj, sets = c("scoped", "fixed", "typed"), keys = NULL) {
  out <- list()
  pick <- function(qs) if (is.null(keys)) names(qs) else intersect(names(qs), keys)
  if ("scoped" %in% sets) for (k in pick(SCOPED_Q)) out[[k]] <- probe_one(s, "catalog", SCOPED_Q[[k]], obj)
  if ("fixed" %in% sets) for (k in pick(FIXED_Q)) out[[k]] <- probe_one(s, "catalog", FIXED_Q[[k]], obj)
  if ("typed" %in% sets) for (k in pick(TYPED_Q)) out[[k]] <- probe_one(s, "typed", TYPED_Q[[k]], obj)
  out
}
probe_table <- function(p) {
  if (!length(p)) return(data.frame())
  do.call(rbind, lapply(names(p), function(k) {
    x <- p[[k]]
    data.frame(probe = k, ok = isTRUE(x$ok), secs = x$secs %||% NA,
               protection = if (isTRUE(x$ok)) paste(unique(vapply(x$per, `[[`, "", "protection")), collapse = "/") else "",
               answer = if (isTRUE(x$ok)) paste(substr(vapply(x$per, `[[`, "", "answer"), 1, 10), collapse = " ") else "",
               error = if (isTRUE(x$ok)) "" else squash(x$error, 200), stringsAsFactors = FALSE)
  }))
}
compare_probes <- function(ref, other, level = "answer", keys = intersect(names(ref), names(other))) {
  if (!length(keys)) return(data.frame(probe = character(0), ref_ok = logical(0), other_ok = logical(0),
                                       equal = logical(0), protection = character(0), detail = character(0)))
  do.call(rbind, lapply(keys, function(k) {
    a <- ref[[k]]
    b <- other[[k]]
    va <- if (isTRUE(a$ok)) vapply(a$per, `[[`, "", level) else character(0)
    vb <- if (isTRUE(b$ok)) vapply(b$per, `[[`, "", level) else character(0)
    eq <- isTRUE(a$ok) && isTRUE(b$ok) && length(unique(c(va, vb))) == 1L
    data.frame(probe = k, ref_ok = isTRUE(a$ok), other_ok = isTRUE(b$ok), equal = eq,
               protection = if (isTRUE(a$ok)) paste(unique(vapply(a$per, `[[`, "", "protection")), collapse = "/") else "",
               detail = if (!isTRUE(a$ok)) paste("reference failed:", squash(a$error, 300)) else
                 if (!isTRUE(b$ok)) paste("failed:", squash(b$error, 300)) else
                   if (!eq) paste("answers differ:", paste(substr(c(va, vb), 1, 10), collapse = " ")) else "",
               stringsAsFactors = FALSE)
  }))
}
equality_verdict <- function(id, title, tab, full = NULL) {
  if (nrow(tab)) show(paste(id, title), tab[, c("probe", "ref_ok", "other_ok", "equal", "protection", "detail")])
  bad <- tab[!tab$equal, , drop = FALSE]
  extra <- if (!is.null(full) && nrow(full)) {
    paste0("; with labels and signed components: ", sum(full$equal), "/", nrow(full), " identical",
           if (any(!full$equal)) paste0(" (differ: ", paste(full$probe[!full$equal], collapse = ", "), ")") else "")
  } else ""
  verdict(id, if (nrow(tab) > 0L && nrow(bad) == 0L) "PASS" else "FAIL", title,
          if (nrow(bad)) paste0(paste(paste0(bad$probe, ": ", bad$detail), collapse = "; "), extra) else
            if (!nrow(tab)) "no probe to compare" else
              paste0(nrow(tab), " answers identical (", paste(unique(tab$protection), collapse = ", "), ")", extra))
}
first_fixed_secs <- function(p) {
  k <- intersect(names(FIXED_Q), names(p))
  if (length(k) && isTRUE(p[[k[1]]]$ok)) p[[k[1]]]$secs else NA_real_
}
# Warnings and messages of a capture, for "explicit upgrade warning" checks.
UPGRADE_RE <- "upgrade|older|unpatched|security release|2\\.10\\.[0-2]\\b|not protected|legacy"
said <- function(...) paste(unlist(lapply(list(...), function(r) c(r$warnings, r$messages))), collapse = " | ")
