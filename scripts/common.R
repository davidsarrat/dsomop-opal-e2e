# Shared helpers: logins (administrator through opalr, the analyst through DSI/DSOpal), logging and captures.
suppressPackageStartupMessages({
  library(opalr)
  library(DSI)
  library(DSOpal)
})
OUT <- Sys.getenv("OUT", "out")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
OPAL_URL <- Sys.getenv("OPAL_URL", "https://localhost:8443")
E2E_PATH <- Sys.getenv("E2E_PATH", "fresh")
MODE <- Sys.getenv("MODE", "public")
SSL <- list(ssl_verifyhost = 0, ssl_verifypeer = 0)
options(width = 200, datashield.progress = FALSE)

out_file <- function(name) file.path(OUT, paste0(E2E_PATH, "-", name))
LOG <- NULL
start_log <- function(name) {
  LOG <<- out_file(paste0(name, ".txt"))
  cat("", file = LOG)
}
say <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n", sep = "")
  if (!is.null(LOG)) cat(msg, "\n", sep = "", file = LOG, append = TRUE)
}
show <- function(label, x) {
  say("--- ", label)
  for (l in capture.output(print(x))) say(l)
}
summary_line <- function(...) {
  cat(paste0(...), "\n", sep = "", file = out_file("summary.txt"), append = TRUE)
  say("SUMMARY ", ...)
}

admin <- function() opal.login(username = "administrator", password = Sys.getenv("OPAL_ADMIN_PW"),
                               url = OPAL_URL, opts = SSL)
# The analyst's DataSHIELD login. The server is named as APHRC's is, so error texts compare one to one. Several
# servers are several connections to this one Opal (scenario G: repeated logical-site connections, other users);
# users[i] logs in with the password in <USER>_PW (ANALYST_PW, ANALYST2_PW). restore = a saved workspace name.
analyst_login <- function(servers = "Ethiopia", users = rep("analyst", length(servers)), restore = NULL) {
  b <- DSI::newDSLoginBuilder()
  for (i in seq_along(servers)) {
    b$append(server = servers[[i]], url = OPAL_URL, user = users[[i]],
             password = Sys.getenv(paste0(toupper(users[[i]]), "_PW")),
             driver = "OpalDriver", options = "list(ssl_verifyhost = 0, ssl_verifypeer = 0)")
  }
  DSI::datashield.login(b$build(), restore = restore)
}

capture <- function(label, expr) {
  t0 <- Sys.time()
  warnings <- character(0)
  messages <- character(0)
  res <- tryCatch(
    list(ok = TRUE, value = withCallingHandlers(expr, warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    }, message = function(m) {
      messages <<- c(messages, trimws(conditionMessage(m)))
      say("  [message] ", trimws(conditionMessage(m))); invokeRestart("muffleMessage")
    })),
    error = function(e) list(ok = FALSE, error = conditionMessage(e)))
  res$warnings <- warnings
  res$messages <- messages
  res$secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  if (res$ok) say("OK    ", label, " (", res$secs, " s)") else say("ERROR ", label, " (", res$secs, " s): ", res$error)
  for (w in warnings) say("  [warning] ", w)
  res
}
ds_errors <- function() {
  e <- tryCatch(DSI::datashield.errors(), error = function(e) NULL)
  if (length(e)) show("DSI::datashield.errors()", e)
  invisible(e)
}
dsomop_methods <- function(o, type) {
  m <- dsadmin.get_methods(o, type = type)
  if (is.null(m) || !nrow(m)) return(m)
  m[!is.na(m$package) & m$package == "dsOMOP", , drop = FALSE]
}
show_dsomop_methods <- function(o, label) {
  agg <- dsomop_methods(o, "aggregate")
  asg <- dsomop_methods(o, "assign")
  na <- if (is.null(agg)) 0 else nrow(agg)
  ns <- if (is.null(asg)) 0 else nrow(asg)
  vers <- unique(c(if (na) agg$version, if (ns) asg$version))
  say(sprintf("dsOMOP methods published (%s): %d aggregate + %d assign; versions: %s; omopInitDS published: %s",
              label, na, ns, paste(vers, collapse = ", "), "omopInitDS" %in% asg$name))
  show(paste("assign methods", label), asg)
  show(paste("aggregate methods", label), agg)
  invisible(list(aggregate = agg, assign = asg))
}
# Rock as DataSHIELD sessions see it: through a fresh administrator R session in Opal (opal.execute), never
# `docker exec` (root's R in the Rock container does not use Rock's own library).
rock_eval <- function(code) {
  o2 <- admin()
  on.exit(try(opal.logout(o2), silent = TRUE))
  tryCatch(opal.execute(o2, code), error = function(e) structure(conditionMessage(e), class = "rock_error"))
}
rock_pkg_version <- function(pkg) {
  v <- rock_eval(sprintf('if (requireNamespace("%s", quietly = TRUE)) as.character(utils::packageVersion("%s")) else "not installed"', pkg, pkg))
  if (inherits(v, "rock_error")) paste("unknown:", v) else as.character(v)
}
installed_description <- function() {
  d <- rock_eval('as.list(as.data.frame(read.dcf(system.file("DESCRIPTION", package = "dsOMOP")), stringsAsFactors = FALSE))')
  if (inherits(d, "rock_error") || !is.list(d)) stop("cannot read dsOMOP's DESCRIPTION through Opal: ", paste(d, collapse = " "))
  d
}
split_field <- function(x) {
  x <- gsub("[\n\r\t ]", "", x)
  v <- strsplit(x, ",")[[1]]
  v[nzchar(v)]
}

# The analyst's script from APHRC's screenshot (lines 55-59).
analyst_script <- function(conns, resource = "omop_data.gibleed") {
  r <- capture(paste0("ds.omop.connect(resource = \"", resource, "\", symbol = \"omop\", conns = conns)"),
               dsOMOPClient::ds.omop.connect(resource = resource, symbol = "omop", conns = conns))
  if (!r$ok) {
    ds_errors()
    return(r)
  }
  t <- capture("tabs <- ds.omop.tables(symbol = \"omop\", conns = conns)[[1]]",
               dsOMOPClient::ds.omop.tables(symbol = "omop", conns = conns)[[1]])
  if (t$ok) {
    tabs <- t$value
    show("tabs[tabs$schema_category == \"CDM\", c(\"table_name\", \"has_person_id\")]",
         tabs[tabs$schema_category == "CDM", c("table_name", "has_person_id")])
  } else ds_errors()
  d <- capture("ds.omop.disconnect(symbol = \"omop\", conns = conns)",
               dsOMOPClient::ds.omop.disconnect(symbol = "omop", conns = conns))
  r$tables_ok <- t$ok
  r
}

# What an analyst (DataSHIELD "use" permission only) can read about the server's packages and methods.
introspect <- function(conns, label) {
  say("== analyst introspection (", label, ")")
  p <- capture("DSI::datashield.pkg_status(conns)", DSI::datashield.pkg_status(conns))
  if (p$ok) show("DSI::datashield.pkg_status(conns)", p$value)
  for (type in c("assign", "aggregate")) {
    m <- capture(sprintf("DSI::datashield.methods(conns, type = \"%s\")", type),
                 DSI::datashield.methods(conns, type = type))
    if (m$ok) {
      v <- m$value
      say("columns: ", paste(names(v), collapse = ", "), "; rows: ", nrow(v))
      rows <- v[grepl("^omop|OMOP", v$name), , drop = FALSE]
      say("dsOMOP rows: ", nrow(rows))
      show(sprintf("first dsOMOP %s rows", type), utils::head(rows, 4))
    }
  }
  ms <- capture("DSI::datashield.method_status(conns, type = \"assign\")",
                DSI::datashield.method_status(conns, type = "assign"))
  if (ms$ok) show("method_status (assign), omop rows", ms$value[grepl("^omop", ms$value$name), , drop = FALSE])
  pr <- capture("DSI::datashield.profiles(conns)", DSI::datashield.profiles(conns))
  if (pr$ok) show("DSI::datashield.profiles(conns)", pr$value)
  invisible(NULL)
}

# Candidate mode: the vendored dsOMOP source, built and installed through Opal (manager "local").
build_candidate <- function() {
  log <- system2("R", c("CMD", "build", "--no-build-vignettes", "--no-manual", "pkgs/dsOMOP"), stdout = TRUE, stderr = TRUE)
  say(paste(tail(log, 3), collapse = "\n"))
  expected <- unname(read.dcf("pkgs/dsOMOP/DESCRIPTION")[1, "Version"])
  archive <- paste0("dsOMOP_", expected, ".tar.gz")
  if (!is.null(attr(log, "status")) && attr(log, "status") != 0L)
    stop("Candidate build failed: ", paste(tail(log, 20), collapse = "\n"))
  normalizePath(archive, mustWork = TRUE)
}
install_candidate_deps <- function(o) {
  d <- read.dcf("pkgs/dsOMOP/DESCRIPTION")
  imports <- trimws(sub("\\(.*", "", strsplit(gsub("\n", " ", d[1, "Imports"]), ",")[[1]]))
  imports <- setdiff(imports[nzchar(imports)], c("stats", "utils", "methods", "tools", "grDevices", "graphics", "parallel"))
  for (p in imports) if (identical(rock_pkg_version(p), "not installed")) {
    r <- capture(paste0("dsadmin.install_package(o, \"", p, "\") [CRAN dependency of the candidate]"), dsadmin.install_package(o, p))
    if (!r$ok || identical(rock_pkg_version(p), "not installed"))
      stop("Candidate dependency did not install on Rock: ", p)
  }
}
install_server <- function(o, ref) {
  if (identical(ref, "candidate")) {
    install_candidate_deps(o)
    expected <- unname(read.dcf("pkgs/dsOMOP/DESCRIPTION")[1, "Version"])
    tb <- build_candidate()
    r <- capture(paste0("dsadmin.install_local_package(o, \"", basename(tb), "\")"), dsadmin.install_local_package(o, tb))
    {
      # A 201 response and even the expected version do not prove this archive
      # was installed (successive candidates share 2.10.3). Install this exact
      # archive from Rock's service R session and require R CMD INSTALL success.
      say("After Opal's local call dsOMOP is '", rock_pkg_version("dsOMOP"),
          "'; installing the exact candidate archive from Rock's R session")
      copied <- system2("docker", c("cp", shQuote(tb), shQuote(paste0(Sys.getenv("ROCK"), ":/tmp/"))))
      if (!identical(copied, 0L)) stop("Cannot copy the candidate archive to Rock")
      code <- sprintf('local({ log <- tempfile(); on.exit(unlink(log)); status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL", "-l", shQuote(.libPaths()[1]), shQuote("/tmp/%s")), stdout = log, stderr = log); list(status = status, library = .libPaths()[1], log = readLines(log, warn = FALSE)) })', basename(tb))
      installed <- rock_eval(code)
      show("Rock candidate installation (service R session and library)", installed)
      if (inherits(installed, "rock_error") || !is.list(installed) ||
          !identical(as.integer(installed$status), 0L)) stop("Rock candidate installation failed; see the captured install log")
    }
  } else {
    r <- capture(sprintf("dsadmin.install_github_package(o, \"dsOMOP\", username = \"isglobal-brge\", ref = \"%s\")", ref),
                 dsadmin.install_github_package(o, "dsOMOP", username = "isglobal-brge", ref = ref))
  }
  if (identical(ref, "candidate")) assert_candidate_server()
  say("dsOMOP installed on Rock: ", rock_pkg_version("dsOMOP"))
  r
}
server_target <- function() if (identical(MODE, "candidate")) "candidate" else Sys.getenv("SERVER_REF", "2.10.0")

# Published settings vs the installed DESCRIPTION: names, types, functions, versions, exports, options.
check_publication <- function(o, label) {
  m <- show_dsomop_methods(o, label)
  d <- installed_description()
  exp_agg <- split_field(d$AggregateMethods)
  exp_asg <- split_field(d$AssignMethods)
  agg <- if (is.null(m$aggregate)) data.frame(name = character(0), value = character(0), version = character(0)) else m$aggregate
  asg <- if (is.null(m$assign)) data.frame(name = character(0), value = character(0), version = character(0)) else m$assign
  bad_value <- c(agg$name[agg$value != paste0("dsOMOP::", agg$name)], asg$name[asg$value != paste0("dsOMOP::", asg$name)])
  stale <- unique(c(agg$version, asg$version))
  exports <- rock_eval('getNamespaceExports("dsOMOP")')
  opts <- tryCatch(dsadmin.get_options(o), error = function(e) NULL)
  exp_opts <- split_field(d$Options)
  exp_names <- sub("=.*", "", exp_opts)
  got <- if (is.null(opts)) character(0) else opts$name
  opt_vals <- if (is.null(opts)) NULL else stats::setNames(opts$value, opts$name)
  exp_vals <- stats::setNames(gsub("^[\"']|[\"']$", "", sub("^[^=]*=", "", exp_opts)), exp_names)
  diff_vals <- exp_names[exp_names %in% got & opt_vals[exp_names] != exp_vals[exp_names]]
  res <- list(
    declared = c(aggregate = length(exp_agg), assign = length(exp_asg)),
    published = c(aggregate = nrow(agg), assign = nrow(asg)),
    missing_aggregate = setdiff(exp_agg, agg$name), missing_assign = setdiff(exp_asg, asg$name),
    wrong_type = c(intersect(exp_agg, asg$name), intersect(exp_asg, agg$name)),
    extra = setdiff(c(agg$name, asg$name), c(exp_agg, exp_asg)),
    wrong_function = bad_value, versions = stale, installed_version = d$Version,
    not_exported = setdiff(c(exp_agg, exp_asg), exports),
    options_declared = length(exp_names), options_missing = setdiff(exp_names, got), options_different = diff_vals)
  show(paste("publication check", label), res)
  summary_line(sprintf("[%s] %s: declared %d agg + %d assign; published %d agg + %d assign (version %s; installed %s); missing %s; wrong type %s; extra %s; wrong function %s; not exported %s; options %d declared, missing %s, different %s",
                       E2E_PATH, label, length(exp_agg), length(exp_asg), nrow(agg), nrow(asg), paste(stale, collapse = "/"),
                       d$Version, length(c(res$missing_aggregate, res$missing_assign)), length(res$wrong_type), length(res$extra),
                       length(bad_value), length(res$not_exported), length(exp_names), length(res$options_missing),
                       length(diff_vals)))
  invisible(res)
}

ensure_driver <- function(o, conns, resource) {
  v <- rock_pkg_version("RPostgres")
  say("RPostgres on Rock: ", v, "; RPostgreSQL: ", rock_pkg_version("RPostgreSQL"))
  summary_line("[", E2E_PATH, "] Rock drivers: RPostgres ", v, ", RPostgreSQL ", rock_pkg_version("RPostgreSQL"))
  if (!identical(v, "not installed") || !identical(Sys.getenv("INSTALL_DRIVER", "0"), "1")) return(invisible(FALSE))
  say("== without a PostgreSQL driver on Rock:")
  r <- analyst_script(conns, resource)
  summary_line("[", E2E_PATH, "] RPostgres missing on Rock; connect -> ", if (r$ok) "OK" else r$error)
  capture("dsadmin.install_package(o, \"RPostgres\") [Opal > DataSHIELD > Packages > Install, CRAN]",
          dsadmin.install_package(o, "RPostgres"))
  say("RPostgres on Rock after install: ", rock_pkg_version("RPostgres"))
  invisible(TRUE)
}

# 2.10.1 client: its own version and each server's published/running dsOMOP (absent from 2.10.0).
versions <- function(conns, label) {
  ns <- asNamespace("dsOMOPClient")
  if (exists("ds.omop.client.version", envir = ns)) {
    show(paste("ds.omop.client.version()", label), tryCatch(get("ds.omop.client.version", envir = ns)(), error = function(e) conditionMessage(e)))
  }
  if (exists("ds.omop.server.version", envir = ns)) {
    v <- capture(paste("ds.omop.server.version(conns)", label), get("ds.omop.server.version", envir = ns)(conns))
    if (v$ok) {
      show(paste("ds.omop.server.version(conns)", label), v$value)
      summary_line("[", E2E_PATH, "] ds.omop.server.version(conns) ", label, ": ",
                   paste(capture.output(print(v$value)), collapse = " / "))
    }
  } else say("ds.omop.server.version() is not in this client (", as.character(packageVersion("dsOMOPClient")), ")")
}

# A successful REST response is not evidence that Rock installed the candidate.
assert_candidate_server <- function() {
  if (!identical(MODE, "candidate")) return(invisible(TRUE))
  expected <- unname(read.dcf("pkgs/dsOMOP/DESCRIPTION")[1, "Version"])
  actual <- rock_pkg_version("dsOMOP")
  if (!identical(actual, expected)) stop("Candidate installation prerequisite failed: expected dsOMOP ",
                                        expected, ", Rock has ", actual)
  invisible(TRUE)
}

# Use the coordinated source version; capabilities, not a prospective release
# label, determine whether the native contract is supported.
candidate_version <- function() {
  versions <- vapply(c("dsOMOP", "dsOMOPClient"), function(pkg)
    unname(read.dcf(file.path("pkgs", pkg, "DESCRIPTION"))[1, "Version"]), "")
  if (length(unique(versions)) != 1L) stop("Candidate package versions differ.", call. = FALSE)
  unname(versions[[1]])
}
