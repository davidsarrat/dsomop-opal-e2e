# Targeted network/install probe on the test pod, in a disposable library.
# No Opal service or product suite is invoked.
source("scripts/install_historical.R")
local({
  scratch <- tempfile("historical-install-probe-"); dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE))
  lib <- file.path(scratch, "library"); dir.create(lib)
  previous <- .libPaths(); .libPaths(c(lib, previous))
  on.exit(.libPaths(previous), add = TRUE)
  for (version in c("2.10.1", "2.10.4")) {
    directory <- file.path(scratch, version); dir.create(directory)
    src <- historical_source(version, directory)
    cat("Downloaded", version, "archive bytes", file.info(src$archive)$size,
        "MD5", unname(tools::md5sum(src$archive)), "\n")
    result <- eval(parse(text = historical_install_code(src$archive)))
    if (!identical(result$status, 0L)) cat(paste(result$log, collapse = "\n"), "\n")
    stopifnot(identical(result$status, 0L), identical(result$library, lib),
              identical(as.character(utils::packageVersion("dsOMOP", lib.loc = lib)), version),
              !file.exists(src$archive))
    cat("PASS: historical", version, "installed in the disposable library; archive removed\n")
  }
})
