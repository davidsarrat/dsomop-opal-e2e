# The sole server package-source substitution. Keep publication and every other
# administrator operation in the book's script. Run in Rock's service library,
# as scripts/common.R does, rather than root's unrelated R library.
book_install_archive <- function(opal, profile) {
  archive <- Sys.getenv("BOOK_SERVER_ARCHIVE")
  stopifnot(file.exists(archive), identical(profile, "default"))
  target <- "/tmp/book-dsOMOP_2.10.5.tar.gz"
  cat("Archive substitution: docker cp", archive, paste0("book-rock:", target), "\n")
  status <- system2("docker", c("cp", shQuote(archive), shQuote(paste0("book-rock:", target))))
  stopifnot(identical(status, 0L))
  # remotes installs Imports/Depends just as the GitHub installer does. A child
  # R process prevents old namespaces from being used after the installation.
  expression <- substitute(local({
    script <- tempfile(fileext = ".R"); log <- tempfile()
    on.exit(unlink(c(script, log)))
    writeLines(c(paste0(".libPaths(", paste(deparse(.libPaths()), collapse = ""), ")"),
      'options(repos = c(CRAN = "https://cloud.r-project.org"))',
      INSTALL,
      'stopifnot(as.character(packageVersion("dsOMOP")) == "2.10.5")'), script)
    status <- system2(file.path(R.home("bin"), "Rscript"), shQuote(script),
                      stdout = log, stderr = log)
    list(status = status, library = .libPaths(), log = readLines(log, warn = FALSE))
  }), list(INSTALL = paste0("remotes::install_local(", deparse(target), ', upgrade = "never")')))
  code <- paste(deparse(expression, width.cutoff = 500L), collapse = "\n")
  cat("Rock service archive installation expression:\n", code, "\n")
  result <- opalr::opal.execute(opal, code)
  cat(paste(result$log, collapse = "\n"), "\n")
  print(result[c("status", "library")])
  stopifnot(is.list(result), identical(as.integer(result$status), 0L))
  TRUE
}
