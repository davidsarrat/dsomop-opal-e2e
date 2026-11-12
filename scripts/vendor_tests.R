# One dsOMOP test filter run as dsOMOP's vendor workflow runs it (test_local, stop_on_failure, stop_on_warning) on
# pkgs/dsOMOP, with the per-test results written to $OUT/<filter>-results.csv (no extra package: ListReporter).
#   Rscript scripts/vendor_tests.R vendor-db-integration
filter <- commandArgs(TRUE)[[1]]
out <- Sys.getenv("OUT", "out")
dir.create(out, showWarnings = FALSE, recursive = TRUE)
lr <- testthat::ListReporter$new()
reporter <- testthat::MultiReporter$new(list(testthat::ProgressReporter$new(show_praise = FALSE), lr))
err <- tryCatch({
  testthat::test_local("pkgs/dsOMOP", filter = filter, stop_on_failure = TRUE, stop_on_warning = TRUE,
                       reporter = reporter)
  NULL
}, error = function(e) e)
df <- tryCatch(as.data.frame(lr$get_results()), error = function(e) NULL)
if (is.data.frame(df)) {
  keep <- intersect(c("file", "context", "test", "nb", "failed", "skipped", "error", "warning", "passed", "real"), names(df))
  utils::write.csv(df[, keep, drop = FALSE], file.path(out, paste0(filter, "-results.csv")), row.names = FALSE)
  cat(sprintf("\n%s: %d tests, %d expectations: %d failed, %d skipped, %d errors, %d warnings, %d passed\n", filter,
              nrow(df), sum(df$nb), sum(df$failed), sum(df$skipped), sum(df$error), sum(df$warning), sum(df$passed)))
}
if (!is.null(err)) {
  message("test_local stopped: ", conditionMessage(err))
  quit(save = "no", status = 1)
}
