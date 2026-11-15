# Targeted installer and full A1/A1b control-flow regressions, without Opal.
source("scripts/install_historical.R")
reject <- function(expr, pattern) {
  msg <- tryCatch({ force(expr); "NO ERROR" }, error = conditionMessage)
  stopifnot(grepl(pattern, msg, fixed = TRUE))
}
# Substitute transports only; retain the real orchestration and archive checks.
replace_calls <- function(x, mapping) {
  if (!is.call(x)) return(x)
  head <- paste(deparse(x[[1L]]), collapse = "")
  if (head %in% names(mapping)) x[[1L]] <- as.name(mapping[[head]])
  for (i in seq_along(x)[-1L]) x[[i]] <- replace_calls(x[[i]], mapping)
  x
}
local({
  scratch <- tempfile(); dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE))
  source_dir <- file.path(scratch, "source"); dir.create(source_dir)
  package_dir <- file.path(source_dir, "dsOMOP-test"); dir.create(package_dir)
  writeLines(c("Package: dsOMOP", "Version: 2.10.4"), file.path(package_dir, "DESCRIPTION"))
  archive <- file.path(scratch, "source.tar.gz")
  previous <- setwd(source_dir)
  utils::tar(archive, files = "dsOMOP-test", compression = "gzip", tar = "internal")
  setwd(previous)
  fetch <- function(url, destfile, ...) {
    stopifnot(startsWith(url, "https://codeload.github.com/isglobal-brge/dsOMOP/tar.gz/"))
    file.copy(archive, destfile); 0L
  }
  historical_source <- historical_source
  environment(historical_source) <- environment()
  body(historical_source) <- replace_calls(body(historical_source), c("utils::download.file" = "fetch"))
  destination <- file.path(scratch, "download"); dir.create(destination)
  stopifnot(identical(historical_source("2.10.4", destination)$version, "2.10.4"),
            identical(historical_source("refs/tags/2.10.4", destination)$version, "2.10.4"),
            identical(historical_source(strrep("a", 40), destination)$version, "2.10.4"))
  reject(historical_source("2.10.1", destination), "does not match requested tag")
  reject(historical_source(NA_character_, destination), "nonempty string")
  fetch <- function(...) 1L
  reject(historical_source("2.10.4", destination), "download failed")
})

local({
  installed_calls <- 0L
  actual <- "2.10.4"
  manager_ok <- TRUE
  copied <- 0L
  result <- list(status = 0L, log = "installed")
  historical_source <- function(ref, directory) list(archive = file.path(directory, "source.tar.gz"), version = "2.10.4")
  capture <- function(...) list(ok = manager_ok)
  system2 <- function(...) copied
  rock_eval <- function(code) { installed_calls <<- installed_calls + 1L; result }
  rock_pkg_version <- function(...) actual
  say <- show <- function(...) NULL
  install <- install_historical_server; environment(install) <- environment()
  stopifnot(install(NULL, "2.10.4")$ok, installed_calls == 1L)
  # Existing same-version code and a manager error/no-op cannot bypass install.
  manager_ok <- FALSE
  stopifnot(install(NULL, "2.10.4")$ok, installed_calls == 2L)
  actual <- "not installed"
  reject(install(NULL, "2.10.4"), "Rock reports not installed")
  actual <- "2.10.1"
  reject(install(NULL, "2.10.4"), "expected dsOMOP 2.10.4")
  actual <- "2.10.4"
  for (bad in list(list(status = 1L, log = "failure"), list(), structure("failure", class = "rock_error"))) {
    result <- bad
    reject(install(NULL, "2.10.4"), "installation failed")
  }
  copied <- 1L
  reject(install(NULL, "2.10.4"), "Cannot copy")
})

local({
  # Execute the generated service wrapper, including exit-status propagation,
  # service library arguments, logging and cleanup (no real package install).
  archive <- tempfile("archive with 'quote "); writeLines("fixture", archive)
  on.exit(unlink(archive))
  system2 <- function(command, args, stdout, stderr) {
    stopifnot(basename(command) == "Rscript", identical(args[3], shQuote(archive)),
              identical(args[4], shQuote(.libPaths()[1])), identical(stdout, stderr),
              grepl('dependencies = NA, upgrade = "never", force = TRUE', args[2], fixed = TRUE))
    writeLines("captured installation failure", stdout)
    1L
  }
  installed <- eval(parse(text = historical_install_code(archive)))
  stopifnot(identical(installed$status, 1L), identical(installed$log, "captured installation failure"),
            !file.exists(archive))
})

local({
  source("scripts/g_contract.R", local = TRUE)
  path <- as.list(parse("scripts/path_upgrade.R"))
  upgrade <- which(vapply(path, function(x) is.call(x) && identical(x[[1]], as.name("say")) &&
    identical(x[[2]], "== A2: upgrade to "), logical(1L)))
  stopifnot(length(upgrade) == 1L)
  setup <- path[seq_len(upgrade - 1L)]
  setup <- lapply(setup, replace_calls, mapping = c("dsadmin.publish_package" = "publish",
    "dsOMOPClient::ds.omop.connect" = "connect", "dsOMOPClient::ds.omop.disconnect" = "disconnect",
    "DSI::datashield.aggregate" = "aggregate", "DSI::datashield.logout" = "logout"))
  scratch <- tempfile(); dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE))
  MODE <- "candidate"
  source <- start_log <- say <- show <- summary_line <- show_dsomop_methods <- function(...) NULL
  admin <- analyst_login <- function(...) list()
  server_target <- function() "candidate"
  install_server <- function(...) NULL
  version <- "2.10.4"
  rock_pkg_version <- function(...) version
  published <- FALSE
  publish <- function(...) published <<- TRUE
  connect <- function(...) { stopifnot(published); TRUE }
  disconnect <- function(...) TRUE
  logged_out <- 0L
  logout <- function(...) logged_out <<- logged_out + 1L
  root <- "secrets/dp_noise_root | 32 | 600 | 2026-11-15T00:15:00.000"
  rock_eval <- function(...) root
  out_file <- function(name) file.path(scratch, name)
  aggregate <- function(conns, call) {
    stopifnot(identical(call, g_status_call("2.10.4")))
    list(Ethiopia = list(noise_key_id = "dpk_valid_baseline"))
  }
  capture <- function(label, expr) list(ok = TRUE, value = expr)
  ds_errors <- function() NULL
  for (x in setup) eval(x)
  stopifnot(logged_out == 1L, published,
    identical(readLines(out_file("dp-root-before-upgrade.txt")),
      c("version=2.10.4", "noise_key_id=dpk_valid_baseline", paste0("file=", root))))
  unlink(out_file("dp-root-before-upgrade.txt"))
  # Replay the actual 201/not-installed case: stop before publication/login/A2.
  version <- "not installed"; published <- FALSE
  reject(for (x in setup) eval(x), "refusing to upgrade")
  stopifnot(!published, logged_out == 1L, !file.exists(out_file("dp-root-before-upgrade.txt")))
  version <- "2.10.4"
  aggregate <- function(...) list(Ethiopia = list(noise_key_id = NA_character_))
  reject(for (x in setup) eval(x), "A1b harness baseline failed")
  stopifnot(logged_out == 2L, !file.exists(out_file("dp-root-before-upgrade.txt")))
})
cat("Historical source, verified installation and A1/A1b regressions passed\n")
