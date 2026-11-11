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
analyst_login <- function() {
  b <- DSI::newDSLoginBuilder()
  # The server is named as APHRC's is, so error texts compare one to one.
  b$append(server = "Ethiopia", url = OPAL_URL, user = "analyst", password = Sys.getenv("ANALYST_PW"),
           driver = "OpalDriver", options = "list(ssl_verifyhost = 0, ssl_verifypeer = 0)")
  DSI::datashield.login(b$build())
}

capture <- function(label, expr) {
  t0 <- Sys.time()
  warnings <- character(0)
  res <- tryCatch(
    list(ok = TRUE, value = withCallingHandlers(expr, warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    }, message = function(m) {
      say("  [message] ", trimws(conditionMessage(m))); invokeRestart("muffleMessage")
    })),
    error = function(e) list(ok = FALSE, error = conditionMessage(e)))
  res$warnings <- warnings
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
rock_r <- function(code) {
  suppressWarnings(system2("docker", c("exec", Sys.getenv("ROCK"), "Rscript", "-e", shQuote(code)),
                           stdout = TRUE, stderr = TRUE))
}
rock_pkg_version <- function(pkg) {
  v <- rock_r(sprintf('cat(if (requireNamespace("%s", quietly = TRUE)) as.character(packageVersion("%s")) else "not installed")', pkg, pkg))
  tail(v, 1)
}
installed_description <- function() {
  # The DESCRIPTION Rock has installed, as Opal reads it.
  txt <- rock_r('d <- read.dcf(system.file("DESCRIPTION", package = "dsOMOP")); cat(jsonlite::toJSON(as.list(as.data.frame(d)), auto_unbox = TRUE))')
  jsonlite::fromJSON(tail(txt, 1))
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
  normalizePath(list.files(".", pattern = "^dsOMOP_.*\\.tar\\.gz$", full.names = TRUE)[1])
}
install_candidate_deps <- function(o) {
  d <- read.dcf("pkgs/dsOMOP/DESCRIPTION")
  imports <- trimws(sub("\\(.*", "", strsplit(gsub("\n", " ", d[1, "Imports"]), ",")[[1]]))
  imports <- setdiff(imports[nzchar(imports)], c("stats", "utils", "methods", "tools", "grDevices", "graphics", "parallel"))
  for (p in imports) if (identical(rock_pkg_version(p), "not installed")) {
    capture(paste0("dsadmin.install_package(o, \"", p, "\") [CRAN dependency of the candidate]"), dsadmin.install_package(o, p))
  }
}
install_server <- function(o, ref) {
  if (identical(ref, "candidate")) {
    install_candidate_deps(o)
    tb <- build_candidate()
    r <- capture(paste0("dsadmin.install_local_package(o, \"", basename(tb), "\")"), dsadmin.install_local_package(o, tb))
    if (!r$ok || !grepl("^2\\.", rock_pkg_version("dsOMOP"))) {
      say("local install through Opal failed; installing inside Rock with R CMD INSTALL")
      system2("docker", c("cp", tb, paste0(Sys.getenv("ROCK"), ":/tmp/")))
      say(paste(tail(rock_r(sprintf('install.packages("/tmp/%s", repos = NULL, type = "source")', basename(tb))), 5), collapse = "\n"))
    }
  } else {
    r <- capture(sprintf("dsadmin.install_github_package(o, \"dsOMOP\", username = \"isglobal-brge\", ref = \"%s\")", ref),
                 dsadmin.install_github_package(o, "dsOMOP", username = "isglobal-brge", ref = ref))
  }
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
  exports <- rock_r('writeLines(getNamespaceExports("dsOMOP"))')
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
  say("RPostgres on Rock: ", v)
  if (!identical(v, "not installed")) return(invisible(FALSE))
  say("== without a PostgreSQL driver on Rock:")
  r <- analyst_script(conns, resource)
  summary_line("[", E2E_PATH, "] RPostgres missing on Rock; connect -> ", if (r$ok) "OK" else r$error)
  capture("dsadmin.install_package(o, \"RPostgres\") [Opal > DataSHIELD > Packages > Install, CRAN]",
          dsadmin.install_package(o, "RPostgres"))
  say("RPostgres on Rock after install: ", rock_pkg_version("RPostgres"))
  invisible(TRUE)
}
