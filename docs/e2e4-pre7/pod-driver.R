test_that("installed real-Opal harness administrator checks pass", {
  root <- Sys.getenv("DSOMOP_O_CHECKOUT")
  code <- sprintf('setwd(%s); source("scripts/tests/o-contract.R"); source("scripts/tests/o-installed.R")',
                  encodeString(root, quote = '"'))
  runner <- tempfile(fileext = ".R")
  on.exit(unlink(runner))
  writeLines(code, runner)
  testdir <- file.path(Sys.getenv("DSOMOP_O_SOURCE"), "tests/testthat")
  mode <- file.info(testdir)$mode
  on.exit(Sys.chmod(testdir, mode), add = TRUE)
  Sys.chmod(testdir, "0555")
  status <- system2("setpriv", c("--bounding-set=-dac_override,-dac_read_search",
                    file.path(R.home("bin"), "Rscript"), runner))
  expect_identical(status, 0L)
})
