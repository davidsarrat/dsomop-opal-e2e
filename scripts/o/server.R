O_SOURCE_ROOT <- Sys.getenv("DSOMOP_O_SOURCE", "/tmp/o-server-source")
O_HARNESS_ROOT <- Sys.getenv("DSOMOP_O_HARNESS", "/tmp/o-harness")
# Administrator-only fixture assertions on installed dsOMOP in real Rock sessions.
# Returns TRUE or a failing assertion; no patient rows are sent to the client.
source(file.path(O_HARNESS_ROOT, "fixtures.R"))
o_ns <- function(name) get(name, asNamespace("dsOMOP"))
o_plan <- function(n) {
  dirs <- list.dirs(file.path(O_SOURCE_ROOT, "inst/plans/acceptance"), recursive = FALSE)
  d <- dirs[startsWith(basename(dirs), sprintf("%02d-", n))]
  stopifnot(length(d) == 1L)
  list(plan = jsonlite::fromJSON(file.path(d, "plan.json"), simplifyVector = FALSE),
       expected = jsonlite::fromJSON(file.path(d, "expected.json"), simplifyVector = TRUE))
}
o_error <- function(expr, pattern) {
  msg <- tryCatch({force(expr); ""}, error = conditionMessage)
  if (!nzchar(msg) || !grepl(pattern, msg, ignore.case = TRUE))
    stop("Expected refusal matching '", pattern, "'; received: ", msg)
  invisible(TRUE)
}
o_rows <- function(x) {
  # SQL BIGINT analytic keys arrive as decimal strings; the frozen JSON oracle
  # uses numbers. Compare key identity exactly without numeric coercion.
  if ("set_id" %in% names(x)) x$set_id <- as.character(x$set_id)
  x <- as.data.frame(lapply(x, function(v) if (is.factor(v)) as.character(v) else v), stringsAsFactors = FALSE)
  key <- do.call(paste, c(lapply(x, function(v) ifelse(is.na(v), "<NA>", as.character(v))), sep = "\034"))
  x <- x[order(key), , drop = FALSE]; rownames(x) <- NULL
  x
}
o_execute <- function(plan, handle, mode = "memory", dp = FALSE, ...) {
  .dsomop_handle_ores <- handle
  target <- environment()
  out <- setNames(paste0("O_admin_", names(plan$outputs)), names(plan$outputs))
  method <- if (dp) dsOMOP::omopDpPlanExecuteDS else dsOMOP::omopPlanExecuteDS
  O_exec <- method("ores", plan, as.list(out), output_mode = mode, ...)
  status <- dsOMOP::omopPlanStatusDS("O_exec")
  if (status$status != "ok") stop("fixture execution refused: ", paste(vapply(status$rejected, `[[`, "", "code"), collapse = ","))
  frames <- list()
  for (root in names(status$published)) for (comp in names(status$published[[root]])) {
    item <- status$published[[root]][[comp]]
    key <- if (comp == root) root else paste(root, comp, sep = ".")
    frames[[key]] <- get(item$symbol, envir = target)
  }
  list(frames = frames, status = status, env = target)
}
o_revoke <- function(run) evalq(dsOMOP::omopStagedRevokeDS("O_exec"), run$env)
o_compare <- function(run, oracle, handle) {
  for (component in names(oracle$outputs)) {
    spec <- oracle$outputs[[component]]; actual <- run$frames[[component]]
    stopifnot(is.data.frame(actual), setequal(names(actual), spec$released_columns))
    expected <- spec$rows
    public <- attr(actual, "dsomop_pseudonymization", exact = TRUE)
    tokens <- o_ns(".pseudonymizeIdentifiers")(data.frame(person_id = expected$person_id), o_ns(".personKey")(handle), public)
    expected$person_id <- tokens$person_id
    cols <- unique(c("person_id", spec$comparison_columns))
    # Compare complete multisets per genuine person, preserving repeated rows.
    stopifnot(isTRUE(all.equal(o_rows(actual[cols]), o_rows(expected[cols]), check.attributes = FALSE)))
  }
  invisible(TRUE)
}
o_installed_tests <- function(files) {
  # Focused existing aggregate/publisher regressions run against the installed namespace.
  old <- getwd(); on.exit(setwd(old)); setwd(file.path(O_SOURCE_ROOT, "tests/testthat"))
  opts <- options(); on.exit(options(opts), add = TRUE)
  e <- new.env(parent = asNamespace("dsOMOP"))
  for (n in getNamespaceExports("testthat")) assign(n, getExportedValue("testthat", n), e)
  sys.source("helper-db.R", envir = e)
  for (f in c("helper-publication.R", "helper-safe-bins.R")) sys.source(f, envir = e)
  for (f in files) {
    pattern <- switch(f,
      "test-assignment-policy.R" = "assignment and aggregate admission|assigned age bands|baseline keeps",
      "test-queries.R" = "BLOCKED for exact birth components",
      "test-ohdsi-results.R" = "public OHDSI endpoint rejects raw CDM",
      "test-analysis-catalog.R" = "external aggregate firewall",
      ".*")
    # Docker-copied fixtures are read-only to Rock. Let testthat select the
    # descriptions in place; retain the original cwd for test_path() fixtures.
    # Only the three explicit helpers above belong in this installed-code probe.
    tests <- Filter(function(x) is.call(x) && identical(x[[1]], as.name("test_that")),
                    as.list(parse(f)))
    descriptions <- vapply(tests, function(x) as.character(x[[2]]), "")
    descriptions <- descriptions[grepl(pattern, descriptions)]
    stopifnot(length(descriptions) > 0L)
    # desc is one exact (possibly nested) test path, not a regex or a union.
    selections <- if (identical(pattern, ".*")) list(NULL) else as.list(descriptions)
    results <- lapply(selections, function(description) as.data.frame(
      testthat::test_file(f, env = e, reporter = "silent", desc = description,
                         load_helpers = FALSE)))
    d <- do.call(rbind, results)
    failed <- d$failed > 0 | d$error | d$skipped
    if (!nrow(d) || any(failed))
      stop("Installed fixture checks failed in ", f, ": ", paste(d$test[failed], collapse = "; "))
    cat("Installed checks:", f, "tests=", nrow(d), "assertions=", sum(d$passed), "\n")
  }
  if ("test-analysis-catalog.R" %in% files) {
    for (field in c("year_of_birth", "month_of_birth", "birth_datetime")) {
      columns <- c(setNames(list(list(semantic = "category", levels = "1980")), field),
                   list(n_persons = list(semantic = "count")))
      entry <- o_ns(".omopAnalysisEntry")(
        name = "birth_probe", description = "birth admission probe", domain = "general", params = list(),
        compute = list(kind = "r", sql = NULL, fn = function(...) data.frame()),
        dependencies = list(tables = character(), packages = character()),
        disclosure = o_ns(".omopAnalysisDisclosure")(unit = "person", count_cols = "n_persons"),
        scope = o_ns(".omopAnalysisScope")(FALSE, FALSE, 0L), mode = "aggregate",
        meta = list(output_contract = list(version = 1L, columns = columns, max_rows = 20L)))
      o_error(o_ns(".omopAnalysisValidateExternalEntry")(entry, "testPack", "testpack:birth_probe"),
              "sensitive/free-text")
    }
  }
  TRUE
}
# Fixture writes commit before calling a public method: that method owns its
# read transaction. Restore birth values on success AND assertion failure.
o_with_birth_fixture <- function(h, fn) {
  person <- as.character(DBI::dbQuoteIdentifier(h$conn, DBI::Id(schema = h$cdm_schema, table = "person")))
  backup <- as.character(DBI::dbQuoteIdentifier(h$conn, basename(tempfile("o_birth_"))))
  DBI::dbExecute(h$conn, paste0("CREATE TEMP TABLE ", backup,
    " AS SELECT person_id, year_of_birth FROM ", person))
  on.exit(DBI::dbWithTransaction(h$conn, {
    DBI::dbExecute(h$conn, paste0("UPDATE ", person,
      " AS p SET year_of_birth=b.year_of_birth FROM ", backup, " AS b WHERE p.person_id=b.person_id"))
    DBI::dbExecute(h$conn, paste0("DROP TABLE ", backup))
  }), add = TRUE)
  DBI::dbWithTransaction(h$conn, {
    DBI::dbExecute(h$conn, paste0("UPDATE ", person, " SET year_of_birth=1980"))
    DBI::dbExecute(h$conn, paste0("UPDATE ", person,
      " SET year_of_birth=2002 WHERE person_id=(SELECT MIN(person_id) FROM ", person, ")"))
  })
  fn()
}
o_server_check <- function(name, plan_override = NULL) {
  old <- options(nfilter.subset = 5L, dsomop.query_strict = TRUE)
  on.exit(options(old))
  # The resource is owned by the invoking Opal R session, not this helper.
  session <- parent.frame()
  evalq(dsOMOP::omopInitDS("ores"), session)
  on.exit(evalq(dsOMOP::omopCleanupDS("ores", close = TRUE), session), add = TRUE)
  h <- evalq(dsOMOP:::.getHandle("ores"), session)
  if (name %in% c("acceptance1", "acceptance2")) {
    a <- o_plan(if (name == "acceptance1") 1 else 2)
    if (!is.null(plan_override)) {
      stopifnot(name == "acceptance1", length(plan_override$outputs) == 1L)
      a$plan <- plan_override
      names(a$expected$outputs) <- names(plan_override$outputs)
    }
    r <- o_execute(a$plan, h); on.exit(o_revoke(r), add = TRUE, after = FALSE)
    o_compare(r, a$expected, h)
    if (name == "acceptance1") {
      frame <- r$frames[[1L]]
      stopifnot(is.factor(frame$sex), identical(levels(frame$sex), c("F", "M")))
      staged <- o_execute(a$plan, h, "staged")
      on.exit(o_revoke(staged), add = TRUE, after = FALSE)
      for (component in names(r$frames)) {
        chunks <- list()
        o_ns(".publishReadChunks")(staged$frames[[component]], function(x) chunks[[length(chunks)+1L]] <<- x)
        restored <- do.call(rbind, chunks)
        memory <- r$frames[[component]]
        for (col in names(memory)[vapply(memory, is.factor, TRUE)]) {
          stopifnot(is.factor(restored[[col]]), identical(is.ordered(restored[[col]]), is.ordered(memory[[col]])),
            identical(levels(restored[[col]]), levels(memory[[col]])),
            identical(as.character(restored[[col]]), as.character(memory[[col]])))
        }
      }
    }
  } else if (name == "staged") {
    for (n in c(7, 9)) {
      a <- o_plan(n); r <- o_execute(a$plan, h, "staged")
      descriptors <- r$frames
      paths <- vapply(descriptors, dsOMOP::omopStagedDatasetPath, "")
      stopifnot(all(file.exists(paths)))
      for (d in descriptors) {
        # A copied descriptor with an uncommitted identity cannot open a file.
        forged <- d; forged$dataset_id <- paste0(d$dataset_id, ".uncommitted")
        o_error(dsOMOP::omopStagedDatasetPath(forged), "manifest|commit|invalid|match")
      }
      o_revoke(r)
      stopifnot(!any(file.exists(paths)))
      for (d in descriptors) o_error(dsOMOP::omopStagedDatasetPath(d), "revok|manifest|commit|exist|available")
    }
    o_installed_tests("test-publication.R") # late chunks/manifest errors before commit
  } else if (name == "staged_matrix_cleanup") {
    # Transactional file cleanup is failure-injected in the installed publisher.
    # Analyst federation file absence is independently checked from its status trace.
    o_installed_tests("test-publication.R")
  } else if (name == "matching") {
    a <- o_plan(10)
    r <- o_execute(a$plan, h); o_compare(r, a$expected, h); o_revoke(r)
    e <- o_fixture_env(); sqlite <- e$build_extended_reach_handle(100L)
    on.exit(DBI::dbDisconnect(sqlite$conn), add = TRUE, after = FALSE)
    # Same public key contract makes cross-dialect fixture identity comparable.
    sqlite$person_key <- NULL # discard the synthetic fixture's historical raw key
    for (field in grep("person_key|pseudonym", ls(h), value = TRUE)) sqlite[[field]] <- h[[field]]
    r <- o_execute(a$plan, sqlite); o_compare(r, a$expected, sqlite); o_revoke(r)
    # Reordering keeps the fixture's values unchanged. Finish the write
    # transaction before the public executor opens its own read snapshot.
    DBI::dbWithTransaction(h$conn, {
      for (table in DBI::dbListTables(sqlite$conn)) {
        id <- DBI::Id(schema = h$cdm_schema, table = table)
        d <- DBI::dbReadTable(h$conn, id)
        DBI::dbExecute(h$conn, paste("TRUNCATE TABLE", DBI::dbQuoteIdentifier(h$conn, id)))
        DBI::dbWriteTable(h$conn, id, d[rev(seq_len(nrow(d))), , drop = FALSE], append = TRUE)
      }
    })
    h$blueprint <- NULL
    r <- o_execute(a$plan, h); o_compare(r, a$expected, h); o_revoke(r)
    # Reload all SQLite fixture rows in reverse order, keeping immutable identities.
    for (table in DBI::dbListTables(sqlite$conn)) {
      d <- DBI::dbReadTable(sqlite$conn, table)
      DBI::dbWriteTable(sqlite$conn, table, d[rev(seq_len(nrow(d))), , drop = FALSE], overwrite = TRUE)
    }
    sqlite$blueprint <- NULL
    r <- o_execute(a$plan, sqlite); o_compare(r, a$expected, sqlite); o_revoke(r)
    # The reference oracle is evaluated with another seed, independently of compiler code.
    source(file.path(O_HARNESS_ROOT, "matching_oracle.R"), local = TRUE)
    independent <- o_matching_oracle(sqlite$conn, 20261112L)
    expected <- jsonlite::read_json(file.path(O_HARNESS_ROOT, "matching-seed-20261112.json"), simplifyVector = TRUE)
    stopifnot(isTRUE(all.equal(independent$outputs$cc_table$rows, expected$outputs$cc_table$rows, check.attributes = FALSE)))
    stopifnot(!identical(o_rows(expected$outputs$cc_table$rows), o_rows(a$expected$outputs$cc_table$rows)))
    for (p in names(a$plan$populations)) if (!is.null(a$plan$populations[[p]]$match))
      a$plan$populations[[p]]$match$seed <- 20261112L
    r <- o_execute(a$plan, sqlite); o_compare(r, expected, sqlite); o_revoke(r)
    r <- o_execute(a$plan, h); o_compare(r, expected, h); o_revoke(r)
  } else if (name == "dp") {
    # Real native DP entry refuses authenticated scope taints before commit.
    a <- list(plan = jsonlite::fromJSON(file.path(O_HARNESS_ROOT, "dp-plan.json"), simplifyVector = FALSE))
    # A result-cohort scope is not person-local, even when every output is wide.
    o_error(o_execute(a$plan, h, dp = TRUE, scope = 1L), "not_person_local")
    ordinary <- o_execute(a$plan, h)
    on.exit(o_revoke(ordinary), add = TRUE, after = FALSE)
    external <- ordinary$frames[[1]]
    stopifnot(inherits(external, "omop.table"))
    o_error(o_execute(a$plan, h, dp = TRUE, scope_table_1 = external), "not_person_local")
    target <- new.env(parent = emptyenv())
    .dsomop_handle_ores <- h
    out <- as.list(setNames(paste0("O_failed_", names(a$plan$outputs)), names(a$plan$outputs)))
    before <- list.files(o_ns(".stagingBaseDir")(), recursive = TRUE, all.files = TRUE)
    o_error(o_ns(".omopPlanExecuteDS")("ores", a$plan, out, target_env = target,
      seal_factory = function(ctx) function(value, candidate) {
        stopifnot(length(ls(target, all.names = TRUE)) == 0L)
        stop("O8 injected sealing failure")
      }), "O8 injected sealing failure")
    stopifnot(length(ls(target, all.names = TRUE)) == 0L,
      identical(before, list.files(o_ns(".stagingBaseDir")(), recursive = TRUE, all.files = TRUE)))
  } else if (name == "aggregate_policy") {
    o_installed_tests(c("test-assignment-policy.R", "test-queries.R", "test-ohdsi-results.R", "test-analysis-catalog.R"))
    dist <- o_ns(".omopAchillesObsPeriodDist")(h, list(), "duration", "age_decile")
    stopifnot(nrow(dist) > 0L, "age_decile" %in% names(dist))
    bands <- strsplit(as.character(dist$age_decile), "-", fixed = TRUE)
    stopifnot(all(vapply(bands, function(b) length(b) == 2L &&
      as.integer(b[[1]]) %% 10L == 0L && as.integer(b[[2]]) - as.integer(b[[1]]) == 9L, TRUE)))
    # Public requested narrow band: construct a synthetic one-person band on GiBleed.
    # Restore this fixture-only change even when an assertion fails; the
    # public executor must be free to own its read transaction.
    o_with_birth_fixture(h, function() {
      p <- if (is.null(plan_override)) jsonlite::fromJSON(
        file.path(O_HARNESS_ROOT, "birth-plan.json"), simplifyVector = FALSE) else plan_override
      r <- o_execute(p, h); on.exit(o_revoke(r), add = TRUE)
      x <- r$frames[[1]]
      stopifnot(sum(as.character(x$age_group) == "18-18", na.rm = TRUE) == 1L,
                all(c("year_of_birth", "month_of_birth", "birth_datetime", "age") %in% names(x)))
    })
  } else stop("unknown administrator check: ", name)
  TRUE
}
