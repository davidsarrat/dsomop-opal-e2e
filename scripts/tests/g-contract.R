# Targeted harness regressions: Rscript scripts/tests/g-contract.R
source("scripts/g_contract.R")
stopifnot(identical(g_status_call(), quote(omopDpStatusDS("dsomop-protected-release-v1"))))
r <- list(ok = TRUE, value = list(pooled = data.frame(estimate = NA_real_,
                              estimate_fixed = 1.4, estimate_random = 1.4)))
stopifnot(identical(g_pooled_effect(r), c(1.4, 1.4)), is.na(g_pooled_effect(list(ok = FALSE))))
stopifnot(identical(g_new_log_lines(c("old root", "old"), c("old root", "old", "new")), "new"),
          identical(g_new_log_lines(c("old root", "old"), c("new root")), "new root"),
          length(g_new_log_lines(c("old"), c("old"))) == 0L)
injected <- paste0('method=omopAnalysisRunDS detail={"data_generation":"', strrep("0", 64), '"}')
stopifnot(!g_private_hex(injected), g_private_hex(paste(injected, strrep("a", 64))),
          g_private_hex(paste0('"generation_id":"', strrep("0", 64), '"')))

# Extract only the install/verification functions so no service libraries or
# credentials are required. Simulate the actual 201/no-op upgrade, and failure.
common <- parse("scripts/common.R")
get_fn <- function(name) {
  x <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("<-")) &&
    identical(x[[2]], as.name(name)), as.list(common))
  stopifnot(length(x) == 1L)
  eval(x[[1]])
}
local({
  MODE <- "candidate"
  expected <- unname(read.dcf("pkgs/dsOMOP/DESCRIPTION")[1, "Version"])
  actual <- "2.10.2"
  fallback <- 0L
  install_candidate_deps <- function(o) NULL
  build_candidate <- function() "/tmp/dsOMOP_2.10.3.tar.gz"
  capture <- function(label, expr) list(ok = TRUE)
  say <- show <- function(...) NULL
  system2 <- function(...) 0L
  rock_pkg_version <- function(pkg) actual
  rock_eval <- function(code) {
    fallback <<- fallback + 1L
    actual <<- expected
    list(status = 0L, log = "installed")
  }
  assert_candidate_server <- get_fn("assert_candidate_server")
  install_server <- get_fn("install_server")
  environment(assert_candidate_server) <- environment()
  environment(install_server) <- environment()
  install_server(NULL, "candidate")
  stopifnot(fallback == 1L, identical(actual, expected))
  # A different archive at the same version must still be installed.
  install_server(NULL, "candidate")
  stopifnot(fallback == 2L)
  actual <- "2.10.2"
  rock_eval <- function(code) list(status = 1L, log = "installation failed")
  error <- tryCatch({ install_server(NULL, "candidate"); "" }, error = conditionMessage)
  stopifnot(grepl("installation failed", error))
  error <- tryCatch({ assert_candidate_server(); "" }, error = conditionMessage)
  stopifnot(grepl("expected dsOMOP", error))
})
cat("Harness contract regressions passed\n")

local({
  common <- parse("scripts/g_lib.R")
  environment(get_fn) <- environment()
  calls <- character()
  ready <- FALSE
  admin <- function() "admin-session"
  opal.logout <- function(o) NULL
  opal.execute <- function(o, code) {
    calls <<- c(calls, code)
    if (grepl('loadNamespace("dsOMOP")', code, fixed = TRUE)) ready <<- TRUE
    "ok"
  }
  opal.assign.resource <- function(o, symbol, resource) {
    if (!ready) stop("No resolver could be found")
    calls <<- c(calls, "assign resource")
  }
  admin_handle_eval <- get_fn("admin_handle_eval")
  environment(admin_handle_eval) <- environment()
  stopifnot(identical(admin_handle_eval("probe", resource = "fixture"), "ok"),
            identical(calls[2], "assign resource"), identical(tail(calls, 1), "probe"))
})
cat("Administrator resolver ordering regression passed\n")

local({
  frame <- function(h) {
    x <- data.frame(bin = 1:10, concept_id = 8507, value = pmax(0, h))
    attr(x, "dsomop_release") <- list(owners = list(list(owner = "birth-year", cap = 1,
      components = list(list(stratum = "gender=8507", n = sum(h), h = h)))))
    x
  }
  a <- frame(-5:4)
  b <- frame(-4:5)
  stopifnot(identical(unname(g_component_changes(a, b)), c(11L, 11L)),
            g_component_changes(a, a)[["changed"]] == 0)
  # A changed display or public metadata cannot make a stale basis pass.
  stale <- a; stale$value <- b$value; stale$concept_id <- 999
  stopifnot(g_component_changes(a, stale)[["changed"]] == 0)
  attr(b, "dsomop_release")$owners[[1]]$components[[1]]$h <- NULL
  stopifnot(all(is.na(g_component_changes(a, b))))
  stopifnot(identical(g_measurement_params(), list(concept_id = "3004410")))
  scenario <- paste(readLines("scripts/scenario_G.R"), collapse = "\n")
  stopifnot(length(gregexpr("g_measurement_params()", scenario, fixed = TRUE)[[1]]) == 2L)
})
cat("Signed-component redraw and measurement-request regressions passed\n")

local({
  common <- parse("scripts/common.R")
  environment(get_fn) <- environment()
  build_candidate <- get_fn("build_candidate")
  environment(build_candidate) <- environment()
  say <- function(...) NULL
  system2 <- function(...) structure("build error", status = 1L)
  error <- tryCatch({ build_candidate(); "" }, error = conditionMessage)
  stopifnot(grepl("Candidate build failed", error))
  system2 <- function(...) "built"
  normalizePath <- function(path, mustWork) { stopifnot(mustWork); path }
  expected <- paste0("dsOMOP_", unname(read.dcf("pkgs/dsOMOP/DESCRIPTION")[1, "Version"]), ".tar.gz")
  stopifnot(identical(build_candidate(), expected))
  install_candidate_deps <- get_fn("install_candidate_deps")
  environment(install_candidate_deps) <- environment()
  rock_pkg_version <- function(pkg) "not installed"
  capture <- function(...) list(ok = TRUE)
  error <- tryCatch({ install_candidate_deps(NULL); "" }, error = conditionMessage)
  stopifnot(grepl("dependency did not install", error))
})
cat("Exact-archive and missing-dependency install regressions passed\n")

local({
  scenario <- paste(readLines("scripts/scenario_D.R"), collapse = "\n")
  stopifnot(grepl('ds.omop.analysis.run("dsomop:achilles.3",', scenario, fixed = TRUE),
            grepl('ds.omop.ohdsi.summary("cohort_diagnostics",', scenario, fixed = TRUE),
            grepl('absent fixture; expected refusal', scenario, fixed = TRUE),
            grepl('g_check_site_errors(capture(client, expr))', scenario, fixed = TRUE))
})
cat("Scenario D positive fixture selection regressions passed\n")

local({
  r <- list(ok = TRUE, value = list(Ethiopia = data.frame(n = 10)), secs = 0.1)
  stopifnot(identical(g_check_site_errors(r), r))
  attr(r$value, "ds_errors") <- list(Small = "Cohort definition 1 not found.")
  checked <- g_check_site_errors(r)
  stopifnot(!checked$ok, grepl("not found", checked$error), identical(checked$value, r$value))
  failed <- list(ok = FALSE, error = "transport failed")
  stopifnot(identical(g_check_site_errors(failed), failed))
})
cat("Partial client errors cannot pass the method audit\n")
