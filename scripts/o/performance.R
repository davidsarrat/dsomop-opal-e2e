# Same v1 workloads and fixture for old and new servers. No relaxed row cap.
o_performance <- function(symbol, phase) {
  # omopInitDS resolves resources in its immediate caller, the Opal session.
  session <- parent.frame()
  eval(substitute(dsOMOP::omopInitDS(s), list(s = symbol)), session)
  on.exit(eval(substitute(dsOMOP::omopCleanupDS(s, close = TRUE),
                          list(s = symbol)), session), add = TRUE)
  plans <- o_performance_plans()
  timings <- lapply(names(plans), function(n) {
    median(replicate(3, system.time({
      target <- new.env(parent = session)
      target$p <- plans[[n]]; target$symbol <- symbol; target$out <- setNames(list(paste0("O_perf_",n)), n)
      evalq(O_exec <- dsOMOP::omopPlanExecuteDS(symbol, p, out), target)
      if (phase == "candidate") {
        status <- evalq(dsOMOP::omopPlanStatusDS("O_exec"), target)
        stopifnot(status$status == "ok")
        evalq(dsOMOP::omopStagedRevokeDS("O_exec"), target)
      }
    })[["elapsed"]]))
  })
  names(timings) <- names(plans)
  list(phase = phase, seconds = timings, max_memory_rows = getOption("dsomop.max_memory_rows"),
       version = as.character(packageVersion("dsOMOP")))
}
o_performance_plans <- function() list(
  baseline = list(version = 1, cohort = list(type = "cohort_table", cohort_definition_id = 1L),
    outputs = list(baseline = list(type = "baseline", columns = "gender_concept_id", derived = "age_at_index"))),
  panel = list(version = 1, cohort = list(type = "cohort_table", cohort_definition_id = 1L),
    outputs = list(panel = list(type = "person_period", table = "measurement", concept_set = 3025315L,
      bin_width = 30L, window_start = 0L, window_end = 365L, grain = "episode", time_origin = "index"))))
