# O1-O12. Missing capabilities/fixtures are FAIL, never a passing skip.
source("scripts/common.R")
suppressPackageStartupMessages(library(dsOMOPClient))
start_log("O-scenarios")
`%||%` <- function(a, b) if (is.null(a)) b else a
verdicts <- list()
check <- function(ok, message) if (!isTRUE(ok)) stop(message, call. = FALSE)
scenario <- function(id, fn) {
  elapsed <- system.time(r <- tryCatch({ fn(); NULL }, error = conditionMessage))[["elapsed"]]
  verdicts[[length(verdicts) + 1L]] <<- data.frame(id, status = if (is.null(r)) "PASS" else "FAIL",
                                                seconds = elapsed, evidence = r %||% "all assertions passed")
  utils::write.csv(do.call(rbind, verdicts), out_file("O-verdicts.csv"), row.names = FALSE)
  summary_line(id, ": ", if (is.null(r)) "PASS" else paste("FAIL", r))
}
corpus <- "pkgs/dsOMOP/inst/plans/acceptance"
recipe <- function(n) {
  d <- list.dirs(corpus, recursive = FALSE, full.names = TRUE)
  d <- d[startsWith(basename(d), sprintf("%02d-", n))]
  check(length(d) == 1L, "acceptance directory absent")
  e <- new.env(parent = globalenv()); sys.source(file.path(d, "recipe.R"), envir = e)
  e$rec
}
with_sites <- function(fn, resources = c("omop_data.o_reach", "omop_data.o_reach")) {
  conns <- analyst_login(c("good", "other")[seq_along(resources)])
  on.exit(DSI::datashield.logout(conns), add = TRUE)
  ds.omop.connect(resource = stats::setNames(resources, names(conns)), symbol = "omopO", conns = conns)
  # Cleanup must run while the DataSHIELD connections are still live.
  on.exit(ds.omop.disconnect(symbol = "omopO", conns = conns), add = TRUE, after = FALSE)
  fn(conns)
}
run_recipe <- function(rec, conns, out = NULL, ...) recipe_execute(rec, out = out, symbol = "omopO", conns = conns, ...)
# Observe the real bounded status read and deletion, without mocking either operation.
.o_trace <- list()
trace(".plan_read_status", where = asNamespace("dsOMOPClient"), print = FALSE,
      exit = quote(.GlobalEnv$.o_trace <- c(.GlobalEnv$.o_trace,
        list(list(event = "read", status = returnValue(), symbol = exec_symbol,
                  present = DSI::datashield.symbols(conns))))))
trace(".plan_remove_status", where = asNamespace("dsOMOPClient"), print = FALSE,
      tracer = quote(.GlobalEnv$.o_trace <- c(.GlobalEnv$.o_trace,
        list(list(event = "remove", symbol = exec_symbol)))))
status_read <- function() {
  reads <- Filter(function(x) x$event == "read", .o_trace)
  check(length(reads) > 0L, "no authenticated status read")
  tail(reads, 1)[[1]]
}
status_order <- function(conns) {
  r <- status_read()
  events <- vapply(.o_trace, `[[`, "", "event")
  check(match("read", events) < match("remove", events), "status was not read before deletion")
  check(all(vapply(r$present, function(x) r$symbol %in% unlist(x), TRUE)), "status absent when read")
  check(!r$symbol %in% unlist(DSI::datashield.symbols(conns)), "execution status left behind")
  r$status
}
admin_check <- function(name, resource = "omop_data.o_reach", plan = NULL) {
  o <- admin(); on.exit(opal.logout(o))
  opal.execute(o, 'loadNamespace("dsOMOP"); TRUE')
  opal.assign.resource(o, "ores", resource)
  wire <- if (is.null(plan)) "NULL" else paste0("jsonlite::fromJSON(",
    encodeString(jsonlite::toJSON(plan, auto_unbox = TRUE, null = "null", digits = NA), quote = '"'),
    ", simplifyVector = FALSE)")
  # Catch on Rock so Opal's error wrapper cannot bury the cause behind the
  # (potentially very long) serialized plan expression in the verdict CSV.
  result <- opal.execute(o, paste0('source("/tmp/o-harness/server.R"); tryCatch(list(ok = o_server_check(',
    deparse(name), ', plan_override = ', wire,
    ')), error = function(e) list(ok = FALSE, error = conditionMessage(e)))'))
  check(isTRUE(result$ok), paste("administrator fixture assertions failed:", name,
                                result$error %||% "check did not return TRUE"))
}
# Profiling reports remote refusals in result metadata as well as conditions.
# Require an explicit refusal and no returned rows or pooled value.
o_aggregate_refused <- function(captured, errors) {
  value <- captured$value
  has_value <- function(x) {
    if (is.null(x)) return(FALSE)
    if (is.data.frame(x)) return(nrow(x) > 0L)
    if (is.list(x)) return(any(vapply(x, has_value, TRUE)))
    length(x) > 0L
  }
  text <- paste(captured$error, value$meta$warnings, captured$warnings, unlist(errors), collapse = " ")
  !has_value(value$per_site) && !has_value(value$pooled) &&
    grepl("blocked|sensitive|not allowed", text, ignore.case = TRUE) &&
    (!captured$ok || inherits(value, "dsomop_result"))
}
set_strict <- function(strict) {
  o <- admin(); on.exit(opal.logout(o))
  dsadmin.set_option(o, "dsomop.query_strict", if (strict) "TRUE" else "FALSE")
}
small_recipe <- function() omop_recipe(
  populations = list(omop_population("all", index = omop_index(list(cohort_definition_id = 1))),
                     omop_population("few", index = omop_index(list(cohort_definition_id = 909)))),
  variables = list(age = omop_age()),
  outputs = list(omop_output("passing", format = "wide", rows = "all", grain = "episode"),
                 omop_output("small", format = "wide", rows = "few", grain = "episode")))

scenario("O1", function() with_sites(function(conns) {
  v <- ds.omop.server.version(conns)
  check(all(v$running == candidate_version() & v$published == candidate_version() & v$ready), "version/publication mismatch")
  caps <- dsOMOPClient:::.get_session("omopO")$capabilities
  for (cap in caps) {
    lang <- cap$recipe_language
    check(identical(as.integer(lang$version), 2L), "language version")
    check(all(c("variable.reducer", "output.wide", "population.match") %in% lang$operations), "native compiler operations missing")
    check(all(c("family", "temporary_materialization", "typed_sql", "sha256_sql", "window_frames") %in% names(lang$dialect)), "dialect contract missing")
  }
  jsonlite::write_json(caps, out_file("O1-capabilities.json"), auto_unbox = TRUE, pretty = TRUE)
}))

scenario("O2", function() with_sites(function(conns) {
  # Re-express acceptance 1's same population and variables through the simple layer.
  advanced <- recipe(1)
  study <- omop_study(index = omop_population("c1", index = omop_index(list(cohort_definition_id = 1),
    select = "all", end = omop_end("event_end"))), baseline = advanced$variables,
    outputs = "baseline", name = "c1")
  run_recipe(study, conns, out = c(baseline = "O_baseline"))
  dsBaseClient::ds.dim("O_baseline", datasources = conns)
  dsBaseClient::ds.summary("O_baseline$age", datasources = conns)
  classes <- dsBaseClient::ds.class("O_baseline$sex", datasources = conns)
  check(all(vapply(classes, function(x) "factor" %in% x, TRUE)), "derived sex is not a factor")
  dsBaseClient::ds.table("O_baseline$sex", datasources = conns)
  levels <- dsBaseClient::ds.levels("O_baseline$sex", datasources = conns)
  check(length(levels) == length(conns) && all(vapply(levels, identical, TRUE, levels[[1]])),
        "factor levels differ across identical fixture sites")
  fit <- dsBaseClient::ds.glm("cond_dm ~ age + sex", data = "O_baseline", family = "binomial", datasources = conns)
  check(!is.null(fit), "binary model did not return")
  admin_check("acceptance1", plan = recipe_to_plan(study))
}))

scenario("O3", function() with_sites(function(conns) {
  .o_trace <<- list()
  run_recipe(recipe(2), conns, out = c(baseline = "O_baseline", tte = "O_tte"))
  statuses <- status_order(conns)
  for (s in statuses) {
    check(all(c("itt", "on_treatment") %in% names(s$published$tte)), "TAR components missing from inventory")
    for (component in s$published$tte) {
      check(is.character(component$symbol), "TAR symbol missing")
      # The released event/time columns are the dsSurvival-style inputs.
      dsBaseClient::ds.summary(paste0(component$symbol, "$follow_up_days"), datasources = conns)
    }
  }
  admin_check("acceptance2") # checks fixture event and opposite-arm switch censoring
}))

matrix_cell <- function(strict, policy, mode) {
  set_strict(strict)
  with_sites(function(conns) {
    .o_trace <<- list()
    before_files <- if (mode == "staged") rock_eval('list.files("/tmp/o-staging", recursive=TRUE, all.files=TRUE)') else NULL
    r <- capture("publication matrix", run_recipe(small_recipe(), conns,
      out = c(passing = "O_passing", small = "O_small"), on_small_site = policy, output_mode = mode))
    statuses <- status_order(conns)
    check(all(vapply(statuses, function(s) all(vapply(s$rejected, function(z)
      z$code == "insufficient_support" && identical(z$message,
        "Disclosive: operation blocked - insufficient individuals to meet disclosure threshold. No further details available."), TRUE)), TRUE)), "unexpected rejection or variable support text")
    if (strict && policy == "error") {
      check(!r$ok, "strict/error must raise")
      check(!any(grepl("^O_(passing|small)", unlist(DSI::datashield.symbols(conns)))), "federation symbols survived rollback")
    } else if (policy == "skip") {
      check(r$ok && is.null(r$value$other) && !is.null(r$value$good), "skip did not retain only passing site")
      check(identical(statuses$other$status, "refused"), "skip committed a partial site")
      check(!any(grepl("^O_(passing|small)", unlist(DSI::datashield.symbols(conns["other"])))), "skipped site symbols remain")
    } else {
      check(r$ok && identical(statuses$other$status, "partial"), "non-strict/error must return partial")
      check(identical(names(statuses$other$published), "passing"), "partial family inventory")
      check(any(grepl("other:small.*insufficient_support", r$warnings)), "partial warning lacks family/code")
    }
    if (mode == "staged") {
      after_files <- rock_eval('list.files("/tmp/o-staging", recursive=TRUE, all.files=TRUE)')
      check(!inherits(after_files, "rock_error"), "could not inspect staged cleanup")
      check(!any(grepl("[.]private/", after_files)), "private staged files survived execution")
      if (strict && policy == "error") check(identical(before_files, after_files), "federation rollback left staged files")
    }
  }, c("omop_data.o_reach", "omop_data.o_small"))
}
scenario("O4", function() {
  for (strict in c(TRUE, FALSE)) for (policy in c("error", "skip")) for (mode in c("memory", "staged"))
    matrix_cell(strict, policy, mode)
  set_strict(TRUE)
})
scenario("O5", function() {
  set_strict(TRUE)
  with_sites(function(conns) {
    run_recipe(recipe(7), conns, output_mode = "staged")
    run_recipe(recipe(9), conns, output_mode = "staged")
  })
  admin_check("staged")
})
scenario("O6", function() {
  # Both compatibility directions run in separate R/library contexts (install.R and old_client.R).
  if (E2E_PATH == "upgrade") check(file.exists(out_file("O9-old.json")), "old-server phase did not complete")
  check(file.exists("scripts/o/old_client.R"), "old-client runner absent")
  # This row records only the current-server half; old-client assertions are an independently failing workflow step.
  with_sites(function(conns) {
    legacy <- omop_recipe(variables = list(omop_variable_age(year = 2020)),
                          outputs = omop_output("legacy", type = "wide"))
    run_recipe(legacy, conns, out = c(legacy = "O_legacy"))
  })
})
scenario("O7", function() {
  set_strict(TRUE)
  with_sites(function(conns) { run_recipe(recipe(10), conns); run_recipe(recipe(10), conns) })
  admin_check("matching")
})
scenario("O8", function() {
  with_sites(function(conns) {
    local <- omop_study(index = omop_event("condition_occurrence", 201820),
                        baseline = list(age = omop_age()), outputs = "baseline")
    ds.omop.dp.prepare(local, out = c(baseline = "O_dp"), symbol = "omopO", conns = conns)
    # Both logical sites use one Rock noise root. Pooling them must refuse.
    duplicate <- capture("duplicate DP node", ds.omop.dp.release("O_dp",
      omop_privacy("count", population_id = "O_fixture"), datasources = conns))
    check(!duplicate$ok && grepl("share a DP noise domain", duplicate$error), "duplicate DP node was accepted")
    released <- ds.omop.dp.release("O_dp", omop_privacy("count", population_id = "O_fixture"), datasources = conns[1L])
    check(!is.null(released), "single-node DP release missing")
    r <- capture("matching descendant DP", ds.omop.dp.prepare(recipe(10), symbol = "omopO", conns = conns))
    check(!r$ok && grepl("not_person_local", r$error), "matching DP must refuse by provenance")
  })
  admin_check("dp")
})
scenario("O9", function() {
  o <- admin(); on.exit(opal.logout(o))
  opal.execute(o, 'loadNamespace("dsOMOP"); TRUE')
  opal.assign.resource(o, "ores", "omop_data.o_big")
  current <- opal.execute(o, 'source("/tmp/o-harness/performance.R"); o_performance("ores", "candidate")')
  jsonlite::write_json(current, out_file("O9-new.json"), auto_unbox = TRUE, pretty = TRUE)
  with_sites(function(conns) {
    t <- lapply(c(1, 7), function(i) system.time(run_recipe(recipe(i), conns))[["elapsed"]])
    jsonlite::write_json(t, out_file("O9-native-10k-seconds.json"), auto_unbox = TRUE)
  }, "omop_data.o_big")
  if (E2E_PATH == "upgrade") {
    old <- jsonlite::read_json(out_file("O9-old.json"), simplifyVector = TRUE)
    # Same public v1-equivalent workloads, median of three, fixed regression tolerance.
    check(all(unlist(current$seconds) <= pmax(1, unlist(old$seconds)) * 1.25), "v1-equivalent runtime regressed >25%")
  }
})
scenario("O10", function() {
  if (E2E_PATH == "upgrade") {
    rows <- do.call(rbind, verdicts)
    check(all(rows$status[rows$id %in% c("O1", "O2", "O3")] == "PASS"), "upgraded O1-O3 failed")
    check(file.exists(out_file("O9-old.json")), "2.10.1 install phase missing")
  } else check(identical(rock_pkg_version("dsOMOP"), candidate_version()), "fresh package version")
})
scenario("O11", function() {
  set_strict(TRUE)
  with_sites(function(conns) {
    for (type in c("wide", "baseline")) {
      rec <- omop_recipe(populations = list(omop_population("gib", index = omop_index(
        omop_event("condition_occurrence", 192671, descendants = TRUE)))), variables = list(
        omop_variable(name = "year_of_birth", table = "person", column = "year_of_birth"),
        omop_variable(name = "month_of_birth", table = "person", column = "month_of_birth"),
        omop_variable(name = "birth_datetime", table = "person", column = "birth_datetime"),
        age = omop_age(year = 2020), age_group = omop_age(year = 2020, bands = TRUE, age_breaks = c(0,18,19,65))),
        outputs = omop_output("birth", type = type, population_id = "gib"))
      run_recipe(rec, conns, out = c(birth = paste0("O_birth_", type)))
      dsBaseClient::ds.summary(paste0("O_birth_",type,"$year_of_birth"), datasources = conns)
    }
    blocked <- omop_recipe(variables = omop_variable(table = "person", column = "person_source_value"),
                           outputs = omop_output("blocked", type = "wide"))
    r <- capture("class-1 assignment", run_recipe(blocked, conns))
    check(!r$ok && grepl("blocked|sensitive", r$error, ignore.case = TRUE), "class-1 column escaped")
    for (field in c("year_of_birth", "month_of_birth", "birth_datetime")) {
      for (fn in list(
        function() ds.omop.column.stats("person", field, symbol = "omopO", conns = conns),
        function() ds.omop.value.counts("person", field, symbol = "omopO", conns = conns),
        function() ds.omop.crosstab("person", field, "gender_concept_id", symbol = "omopO", conns = conns))) {
        r <- capture("aggregate birth policy", fn())
        check(o_aggregate_refused(r, DSI::datashield.errors()), "aggregate birth admission relaxed")
      }
    }
  }, "omop_data.gibleed")
  admin_check("aggregate_policy", "omop_data.gibleed")
})
scenario("O12", function() {
  for (policy in c("error", "skip")) matrix_cell(FALSE, policy, "memory")
  set_strict(TRUE)
})
untrace(".plan_read_status", where = asNamespace("dsOMOPClient"))
untrace(".plan_remove_status", where = asNamespace("dsOMOPClient"))
set_strict(TRUE)
check(all(vapply(verdicts, function(x) x$status == "PASS", TRUE)), "O1-O12 contain failures; see verdict CSV")
