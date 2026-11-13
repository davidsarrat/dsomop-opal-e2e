test_that("profile O9 panel through publication", {
  e <- new.env(parent = asNamespace("dsOMOP"))
  sys.source(test_path("..", "fixtures", "create_reach_db.R"), e)
  h <- e$build_reach_handle(10000L)
  on.exit(DBI::dbDisconnect(h$conn), add = TRUE)
  .ws7_keys(list(h))
  .dsomop_handle_ores <- h
  p <- list(version = 1, cohort = list(type = "cohort_table", cohort_definition_id = 1L),
    outputs = list(panel = list(type = "person_period", table = "measurement", concept_set = 3025315L,
      bin_width = 30L, window_start = 0L, window_end = 365L, grain = "episode", time_origin = "index")))
  path <- tempfile(); on.exit(unlink(path), add = TRUE)
  Rprof(path, interval = 0.01)
  O_exec <- omopPlanExecuteDS("ores", p, list(panel = "O_perf_panel"))
  Rprof(NULL)
  print(head(summaryRprof(path)$by.total, 35))
  print(head(summaryRprof(path)$by.self, 20))
  expect_identical(omopPlanStatusDS("O_exec")$status, "ok")
  omopStagedRevokeDS("O_exec")
})
