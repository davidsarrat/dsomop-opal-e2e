# Targeted A1b/G1d replay without Opal: Rscript scripts/tests/g-upgrade-root.R
source("scripts/g_contract.R")
stopifnot(identical(g_status_call("2.10.2"), quote(omopDpStatusDS())),
          identical(g_status_call("2.6.0"), quote(omopDpStatusDS())),
          identical(g_status_call("2.10.3"), quote(omopDpStatusDS("dsomop-protected-release-v1"))),
          identical(g_status_call("2.10.4"), g_status_call()),
          identical(g_status_call("2.10.5"), g_status_call()))

local({
  key <- paste0("dpk_", strrep("a", 40))
  root <- "secrets/dp_noise_root | 32 | 600 | 2026-11-14T23:31:32.439"
  status <- list(ok = TRUE, value = list(Ethiopia = list(noise_key_id = key)))
  record <- g_root_baseline("2.10.4", status, root)
  stopifnot(identical(record, c("version=2.10.4", paste0("noise_key_id=", key), paste0("file=", root))))
  rejected <- function(status, files = root) {
    error <- tryCatch({ g_root_baseline("2.10.4", status, files); "" }, error = conditionMessage)
    stopifnot(grepl("A1b harness baseline failed", error, fixed = TRUE))
  }
  rejected(list(ok = FALSE, error = "current-client protocol required"))
  for (bad in list(NULL, NA_character_, "NA", "", " ", c(key, key))) {
    broken <- status
    broken$value[[1L]]$noise_key_id <- bad
    rejected(broken)
  }
  rejected(status, "secrets/pseudonym_root | 32 | 600 | 2026-11-14T23:31:32.439")
  rejected(status, c(root, root))
  rejected(status, structure(root, class = "rock_error"))

  # Execute the real G1d section with transport and disk reads replaced. In
  # particular, a newly recreated root must not pass even with the same key.
  sections <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("section")) &&
                       identical(x[[2]], "G1d"), as.list(parse("scripts/scenario_G.R")))
  stopifnot(length(sections) == 1L)
  run <- eval(sections[[1L]][[4L]])
  `%||%` <- function(a, b) if (is.null(a)) b else a
  E2E_PATH <- "upgrade"
  old_env <- Sys.getenv("OLD_REF", unset = NA_character_)
  on.exit(if (is.na(old_env)) Sys.unsetenv("OLD_REF") else Sys.setenv(OLD_REF = old_env))
  Sys.setenv(OLD_REF = "2.10.4")
  ROOT_CREATED_RE <- "created the DP noise root"
  out_file <- function(...) "baseline"
  exists <- TRUE
  file.exists <- function(...) exists
  readLines <- function(...) record
  current <- root
  state_files <- function() list(state_files = current)
  root_line <- function(st) grep("^secrets/dp_noise_root \\|", st$state_files, value = TRUE)
  open_session <- function(...) list()
  close_session <- function(...) NULL
  capture_ds <- function(label, expr) expr
  raw_status <- function(...) status
  logs <- ROOT_CREATED_RE
  rock_log <- function() logs
  result <- NULL
  verdict <- function(id, status, title, evidence) result <<- list(status = status, evidence = evidence)
  run(); stopifnot(identical(result$status, "PASS"))
  current <- character()
  run(); stopifnot(identical(result$status, "FAIL"))
  current <- sub("32.439", "33.000", root, fixed = TRUE)
  run(); stopifnot(identical(result$status, "FAIL"))
  current <- root
  status$value[[1]]$noise_key_id <- paste0("dpk_", strrep("b", 40))
  run(); stopifnot(identical(result$status, "FAIL"))
  status$value[[1]]$noise_key_id <- key
  logs <- rep(ROOT_CREATED_RE, 2)
  run(); stopifnot(identical(result$status, "FAIL"))
  logs <- ROOT_CREATED_RE
  # The actual failed run's baseline must stay red, not become a false PASS.
  record <- c("version=2.10.4", "noise_key_id=NA", "file=secrets/pseudonym_root | 32 | 600 | timestamp")
  run(); stopifnot(identical(result$status, "FAIL"))
  exists <- FALSE
  run(); stopifnot(identical(result$status, "FAIL"), grepl("harness baseline missing", result$evidence))
  E2E_PATH <- "fresh"
  run(); stopifnot(identical(result$status, "INFO"))
  E2E_PATH <- "upgrade"
  Sys.setenv(OLD_REF = "1.1.1")
  run(); stopifnot(identical(result$status, "INFO"))
  Sys.setenv(OLD_REF = "6a22d259db95a3bfd264d029b653587f935e32db")
  run(); stopifnot(identical(result$status, "INFO"))
})
cat("Upgrade noise-root handshake, baseline and G1d regressions passed\n")
