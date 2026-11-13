# Scenario D: every DataSHIELD method dsOMOP declares, exercised through dsOMOPClient as the non-admin analyst on a
# real Opal; Opal's own DataSHIELD log says which server functions actually ran.
source("scripts/common.R")
suppressPackageStartupMessages(library(dsOMOPClient))
start_log("scenario-D")
res <- if (identical(MODE, "candidate")) "omop_data.gibleed" else "omop_data.gibleed_tls_disable"
o <- admin()
d <- installed_description()
agg <- split_field(d$AggregateMethods)
asg <- split_field(d$AssignMethods)
say("dsOMOP ", d$Version, " declares ", length(agg), " aggregate + ", length(asg), " assign methods; client ",
    as.character(packageVersion("dsOMOPClient")), "; resource ", res)
audit_start <- Sys.time()

rows <- list()
note <- function(methods, client, r) {
  for (m in methods) rows[[length(rows) + 1]] <<- data.frame(
    method = m, type = if (m %in% agg) "aggregate" else if (m %in% asg) "assign" else "undeclared",
    client = client, ok = r$ok, secs = r$secs, error = if (r$ok) "" else gsub("[\r\n]+", " ", r$error),
    stringsAsFactors = FALSE)
}
step <- function(methods, client, expr) {
  r <- capture(client, expr)
  if (!r$ok) ds_errors()
  note(methods, client, r)
  invisible(r)
}
S <- "omop"
conns <- analyst_login()
con <- step(c("omopPingDS", "omopInitDS", "omopGetCapabilitiesDS"), "ds.omop.connect",
            ds.omop.connect(resource = res, symbol = S, conns = conns))
if (con$ok) {
  rs <- dsOMOPClient:::.get_session(S)$res_symbol
  step("omopPingDS", "ds.omop.status", ds.omop.status(symbol = S))
  step("omopDisclosureSettingsDS", "ds.omop.disclosure.settings", ds.omop.disclosure.settings(symbol = S, conns = conns))
  step("omopListTablesDS", "ds.omop.tables", ds.omop.tables(symbol = S, conns = conns))
  step("omopListColumnsDS", "ds.omop.columns", ds.omop.columns("person", symbol = S, conns = conns))
  step("omopRelationshipGraphDS", "ds.omop.joins", ds.omop.joins(symbol = S, conns = conns))
  step(c("omopGetCapabilitiesDS", "omopRelationshipGraphDS"), "ds.omop.snapshot", ds.omop.snapshot(symbol = S, conns = conns))
  step("omopTableStatsDS", "ds.omop.table.stats", ds.omop.table.stats("person", symbol = S, conns = conns))
  step("omopColumnStatsDS", "ds.omop.column.stats", ds.omop.column.stats("person", "year_of_birth", symbol = S, conns = conns))
  step("omopDomainCoverageDS", "ds.omop.domain.coverage", ds.omop.domain.coverage(symbol = S, conns = conns))
  step("omopMissingnessDS", "ds.omop.missingness", ds.omop.missingness("person", symbol = S, conns = conns))
  step("omopValueCountsDS", "ds.omop.value.counts", ds.omop.value.counts("person", "gender_concept_id", symbol = S, conns = conns))
  step("omopCrossTabDS", "ds.omop.crosstab", ds.omop.crosstab("person", "gender_concept_id", "race_concept_id", symbol = S, conns = conns))
  step("omopSearchConceptsDS", "ds.omop.concept.search", ds.omop.concept.search("hemorrhage", symbol = S, conns = conns))
  step("omopLookupConceptsDS", "ds.omop.concept.lookup", ds.omop.concept.lookup(c(192671, 8507), symbol = S, conns = conns))
  step("omopGetDescendantsDS", "ds.omop.concept.descendants", ds.omop.concept.descendants(192671, symbol = S, conns = conns))
  step("omopExpandConceptSetDS", "ds.omop.concept.expand",
       ds.omop.concept.expand(ds.omop.concept.set(192671, include_descendants = TRUE), symbol = S, conns = conns))
  step("omopConceptAncestorsDS", "ds.omop.concept.ancestors", ds.omop.concept.ancestors(192671, symbol = S, conns = conns))
  step("omopConceptSynonymsDS", "ds.omop.concept.synonyms", ds.omop.concept.synonyms(192671, symbol = S, conns = conns))
  step("omopConceptRelationshipsDS", "ds.omop.concept.relationships", ds.omop.concept.relationships(192671, symbol = S, conns = conns))
  step("omopListConceptsDS", "ds.omop.concept.list", ds.omop.concept.list(domain = "Condition", limit = 10, symbol = S, conns = conns))
  step("omopVocabulariesDS", "ds.omop.vocab.vocabularies", ds.omop.vocab.vocabularies(symbol = S, conns = conns))
  step("omopDomainsDS", "ds.omop.vocab.domains", ds.omop.vocab.domains(symbol = S, conns = conns))
  step("omopConceptClassesDS", "ds.omop.vocab.classes", ds.omop.vocab.classes(symbol = S, conns = conns))
  step("omopCdmSourceDS", "ds.omop.cdm.source", ds.omop.cdm.source(symbol = S, conns = conns))
  step("omopCdmVersionDS", "ds.omop.cdm.version", ds.omop.cdm.version(symbol = S, conns = conns))
  step("omopConceptPrevalenceDS", "ds.omop.concept.prevalence", ds.omop.concept.prevalence("condition_occurrence", symbol = S, conns = conns))
  step(c("omopNumericRangeDS", "omopNumericHistogramDS"), "ds.omop.value.histogram",
       ds.omop.value.histogram("person", "year_of_birth", symbol = S, conns = conns))
  # omopNumericRangeDS and omopOhdsiResultContractDS are only sent in pooled mode (two-pass pooling).
  step(c("omopNumericRangeDS", "omopNumericHistogramDS"), "ds.omop.value.histogram (pooled)",
       ds.omop.value.histogram("person", "year_of_birth", scope = "pooled", symbol = S, conns = conns))
  step("omopNumericQuantilesDS", "ds.omop.value.quantiles", ds.omop.value.quantiles("person", "year_of_birth", symbol = S, conns = conns))
  step("omopDateCountsDS", "ds.omop.date.counts", ds.omop.date.counts("condition_occurrence", symbol = S, conns = conns))
  step("omopConceptDrilldownDS", "ds.omop.concept.drilldown",
       ds.omop.concept.drilldown("condition_occurrence", 192671, symbol = S, conns = conns))
  step("omopLocateConceptDS", "ds.omop.concept.locate", ds.omop.concept.locate(192671, symbol = S, conns = conns))
  step("omopSafeCutpointsDS", "ds.omop.safe.cutpoints", ds.omop.safe.cutpoints("person", "year_of_birth", symbol = S, conns = conns))

  # Achilles and OHDSI result tables (GiBleed ships none: a clear refusal is the expected answer).
  step("omopAchillesStatusDS", "ds.omop.achilles.status", ds.omop.achilles.status(symbol = S, conns = conns))
  step("omopAchillesAnalysesDS", "ds.omop.achilles.analyses", ds.omop.achilles.analyses(symbol = S, conns = conns))
  step("omopAchillesResultsDS", "ds.omop.achilles.results", ds.omop.achilles.results(c(2L), symbol = S, conns = conns))
  step("omopAchillesDistributionDS", "ds.omop.achilles.distribution", ds.omop.achilles.distribution(c(103L), symbol = S, conns = conns))
  step("omopAchillesCatalogDS", "ds.omop.achilles.catalog", ds.omop.achilles.catalog(symbol = S, conns = conns))
  step("omopOhdsiStatusDS", "ds.omop.ohdsi.status", ds.omop.ohdsi.status(symbol = S, conns = conns))
  step("omopOhdsiTablesDS", "ds.omop.ohdsi.tables", ds.omop.ohdsi.tables(symbol = S, conns = conns))
  step(c("omopOhdsiResultContractDS", "omopOhdsiResultsDS"), "ds.omop.ohdsi.results",
       ds.omop.ohdsi.results("achilles_results", symbol = S, conns = conns))
  step(c("omopOhdsiResultContractDS", "omopOhdsiResultsDS"), "ds.omop.ohdsi.results (pooled)",
       ds.omop.ohdsi.results("achilles_results", scope = "pooled", symbol = S, conns = conns))
  step("omopOhdsiSummaryDS", "ds.omop.ohdsi.summary", ds.omop.ohdsi.summary("cohort_diagnostics", symbol = S, conns = conns))

  # Cohorts.
  step("omopCohortListDS", "ds.omop.cohort.list", ds.omop.cohort.list(symbol = S, conns = conns))
  c1 <- step("omopCohortCreateDS", "ds.omop.cohort.create (condition)",
             ds.omop.cohort.create(spec = list(type = "condition", concept_set = c(192671)), cohort_id = 100,
                                   name = "gi_bleed", mode = "temporary", symbol = S, conns = conns))
  if (c1$ok) step("omopCohortGetDefinitionDS", "ds.omop.cohort.definition (created cohort)",
                  ds.omop.cohort.definition(100, symbol = S, conns = conns))
  c2 <- step("omopCohortCreateDS", "ds.omop.cohort.create (drug)",
             ds.omop.cohort.create(spec = list(type = "drug", concept_set = c(1118084)), cohort_id = 101,
                                   name = "celecoxib", mode = "temporary", symbol = S, conns = conns))
  if (c1$ok && c2$ok) {
    step("omopCohortCombineDS", "ds.omop.cohort.combine",
         ds.omop.cohort.combine("union", c1$value, c2$value, new_name = "either", symbol = S, conns = conns))
  } else note("omopCohortCombineDS", "ds.omop.cohort.combine (skipped: no cohorts)", list(ok = FALSE, secs = 0, error = "skipped"))

  # Plans: preview, validate, execute (memory mode; concept columns harmonized into factors across servers).
  plan <- ds.omop.plan()
  plan <- ds.omop.plan.cohort(plan, spec = list(type = "condition", concept_set = c(192671)))
  plan <- ds.omop.plan.baseline(plan, columns = c("gender_concept_id", "race_concept_id"), derived = c("age_at_index"))
  plan <- ds.omop.plan.events(plan, name = "drugs", table = "drug_exposure", concept_set = c(1118084, 1124300),
                              representation = list(format = "long"))
  plan <- ds.omop.plan.options(plan, translate_concepts = FALSE, factor_concepts = TRUE)
  step("omopPlanPreviewDS", "ds.omop.plan.preview", ds.omop.plan.preview(plan, symbol = S, conns = conns))
  step("omopPlanPreviewDS", "ds.omop.plan.validate", ds.omop.plan.validate(plan, symbol = S, conns = conns))
  step(c("omopPlanExecuteDS", "omopFactorLevelsDS", "omopAsFactorColumnsDS"), "ds.omop.plan.execute",
       ds.omop.plan.execute(plan, out = c(baseline = "D", drugs = "E"), symbol = S, conns = conns))
  step("omopCohortFromTableDS", "ds.omop.cohort.from_table", ds.omop.cohort.from_table("D", symbol = S, conns = conns))
  step("omopMergeDS", "ds.omop.merge", ds.omop.merge("D", "E", by = "person_id", type = "left", newobj = "DE", symbol = S, conns = conns))
  fr <- step("omopFilterDS", "ds.omop.filter (gender == 8532)", ds.omop.filter("D", var = "gender_concept_id", op = "==", value = 8532, newobj = "DF", symbol = S, conns = conns))
  if (!fr$ok) step("omopFilterDS", "ds.omop.filter (gender == \"8532\")", ds.omop.filter("D", var = "gender_concept_id", op = "==", value = "8532", newobj = "DF", symbol = S, conns = conns))
  step("omopSelectDS", "ds.omop.select", ds.omop.select("D", cols = c("person_id", "year_of_birth"), newobj = "DS2", symbol = S, conns = conns))
  step("omopBindRowsDS", "ds.omop.bind_rows", ds.omop.bind_rows("D", "DF", newobj = "DB", symbol = S, conns = conns))

  # Disclosure probe (reported, not counted): an exact birth component in a server-side table, with and without
  # block_sensitive.
  for (bs in c(TRUE, FALSE)) {
    probe <- ds.omop.plan.baseline(ds.omop.plan.cohort(ds.omop.plan(), spec = list(type = "condition", concept_set = c(192671))),
                                   columns = c("gender_concept_id", "year_of_birth"), derived = c("age_at_index"))
    probe <- ds.omop.plan.options(probe, block_sensitive = bs, factor_concepts = FALSE)
    pr <- capture(paste0("probe: baseline with year_of_birth, block_sensitive = ", bs),
                  ds.omop.plan.execute(probe, out = c(baseline = paste0("PROBE", as.integer(bs))), symbol = S, conns = conns))
    summary_line("[", E2E_PATH, "] D probe: server-side table with exact year_of_birth (block_sensitive = ", bs, "): ",
                 if (pr$ok) "allowed" else paste0("refused: ", sub(".*' -> ", "", pr$error)))
  }

  # The analysis catalog (aggregate entries and an assign-mode entry).
  al <- step("omopAnalysisListDS", "ds.omop.analysis.list", ds.omop.analysis.list(symbol = S, conns = conns))
  catalog <- if (al$ok && is.data.frame(al$value$pooled)) al$value$pooled else NULL
  if (!is.null(catalog)) {
    say("analysis catalog: ", nrow(catalog), " entries; columns ", paste(names(catalog), collapse = ", "))
    if ("mode" %in% names(catalog)) show("catalog modes", table(catalog$mode))
  }
  step("omopAnalysisGetDS", "ds.omop.analysis.get", ds.omop.analysis.get("dsomop:condition.duration_stats", symbol = S, conns = conns))
  # GiBleed's condition durations do not meet the final support gate. Use a
  # supported public partition for positive aggregate-method coverage; G keeps
  # explicit low-support refusals as negative controls.
  step("omopAnalysisRunDS", "ds.omop.analysis.run (aggregate)",
       ds.omop.analysis.run("dsomop:achilles.3", symbol = S, conns = conns))
  assign_names <- if (!is.null(catalog) && all(c("mode", "name") %in% names(catalog))) catalog$name[catalog$mode == "assign"] else character(0)
  say("assign-mode entries: ", length(assign_names), if (length(assign_names)) paste0(" (first: ", paste(head(assign_names, 5), collapse = ", "), ")") else "")
  done_assign <- FALSE
  for (nm in head(assign_names, 4)) {
    r <- step("omopAnalysisRunAssignDS", paste0("ds.omop.analysis.run (assign) ", nm),
              ds.omop.analysis.run(nm, type = "split", symbol = S, conns = conns))
    if (r$ok) { done_assign <- TRUE; break }
  }
  if (!length(assign_names)) note("omopAnalysisRunAssignDS", "ds.omop.analysis.run (assign)", list(ok = FALSE, secs = 0, error = "no assign-mode entry found in the catalog"))

  # Differential privacy: status, a prepared table, a release and a QueryLibrary sticky release.
  step("omopDpStatusDS", "ds.omop.dp.status", ds.omop.dp.status(conns))
  recipe <- omop_recipe(variables = omop_variable_age(name = "age_at_2025", year = 2025),
                        outputs = omop_output(name = "ages", type = "wide"))
  dp <- step("omopDpPlanExecuteDS", "ds.omop.dp.prepare", ds.omop.dp.prepare(recipe, out = c(ages = "DP_ages"), symbol = S, conns = conns))
  step(c("omopDpReleaseDS", "omopDisclosureSettingsDS"), "ds.omop.dp.release",
       ds.omop.dp.release("DP_ages", omop_privacy("count"), datasources = conns))
  sticky <- tryCatch(omop_querylibrary_sticky("PE12", variable = "age_at_2025", breaks = seq(0, 120, by = 10)),
                     error = function(e) { say("omop_querylibrary_sticky: ", conditionMessage(e)); NULL })
  if (!is.null(sticky)) {
    step(c("omopQueryLibraryStickyCatalogDS", "omopDpReleaseDS"), "ds.omop.querylibrary.sticky.release",
         ds.omop.querylibrary.sticky.release("DP_ages", sticky, datasources = conns))
  }

  # Server methods no client function names any more (kept for older clients): called directly.
  ql <- step("omopQueryListDS", "DSI::datashield.aggregate(omopQueryListDS)",
             DSI::datashield.aggregate(conns, call("omopQueryListDS", rs)))
  qid <- NULL
  if (ql$ok) {
    q <- ql$value[[1]]
    if (is.data.frame(q) && nrow(q)) qid <- as.character(q[[intersect(c("id", "query_id", "name"), names(q))[1]]][1])
    say("first query id: ", qid %||% "none")
  }
  if (!is.null(qid)) {
    step("omopQueryGetDS", "DSI::datashield.aggregate(omopQueryGetDS)", DSI::datashield.aggregate(conns, call("omopQueryGetDS", rs, qid)))
    step("omopQueryExecDS", "DSI::datashield.aggregate(omopQueryExecDS)", DSI::datashield.aggregate(conns, call("omopQueryExecDS", rs, qid)))
  } else {
    note(c("omopQueryGetDS", "omopQueryExecDS"), "DSI::datashield.aggregate (skipped: no query id)", list(ok = FALSE, secs = 0, error = "skipped"))
  }
  step("omopCleanupDS", "ds.omop.disconnect", ds.omop.disconnect(symbol = S, conns = conns))
}
DSI::datashield.logout(conns)

calls <- do.call(rbind, rows)
utils::write.csv(calls, out_file("method-audit-calls.csv"), row.names = FALSE)

# Opal's DataSHIELD log: which dsOMOP functions really ran on the server during the audit.
ran <- stats::setNames(rep(NA_integer_, length(c(agg, asg))), c(agg, asg))
lg <- tryCatch(dsadmin.log(o), error = function(e) { say("dsadmin.log: ", conditionMessage(e)); NULL })
if (!is.null(lg) && nrow(lg)) {
  txt <- apply(lg, 1, function(r) paste(unlist(r), collapse = " "))
  writeLines(txt, out_file("datashield-log.txt"))
  for (m in names(ran)) ran[[m]] <- sum(grepl(paste0("\\b", m, "\\("), txt))
}

fail_re <- "No such DataSHIELD|could not find function|is not an exported object|[Pp]arse error|unexpected (symbol|string|numeric|input)|serializ|Internal Server Error|\\(500\\)|Bad Gateway"
audit <- do.call(rbind, lapply(c(agg, asg), function(m) {
  r <- calls[calls$method == m, , drop = FALSE]
  status <- if (!nrow(r)) "NOT-EXERCISED" else if (any(r$ok)) "PASS" else if (any(grepl(fail_re, r$error))) "FAIL" else "REFUSED"
  data.frame(method = m, type = if (m %in% agg) "aggregate" else "assign",
             client = paste(unique(r$client), collapse = " | "), status = status,
             server_calls_in_opal_log = ran[[m]],
             error = if (status == "PASS") "" else paste(unique(r$error[!r$ok]), collapse = " || "),
             stringsAsFactors = FALSE)
}))
utils::write.csv(audit, out_file("method-audit.csv"), row.names = FALSE)
show("method audit", audit[, c("method", "type", "status", "server_calls_in_opal_log", "client")])
tab <- table(factor(audit$status, levels = c("PASS", "REFUSED", "FAIL", "NOT-EXERCISED")))
summary_line(sprintf("[%s] D: %d methods: PASS %d, REFUSED %d (to review), FAIL %d, NOT-EXERCISED %d; ran per Opal log: %d; PASS but absent from Opal log: %s",
                     E2E_PATH, nrow(audit), tab[["PASS"]], tab[["REFUSED"]], tab[["FAIL"]], tab[["NOT-EXERCISED"]],
                     sum(audit$server_calls_in_opal_log > 0, na.rm = TRUE),
                     paste(audit$method[audit$status == "PASS" & !is.na(audit$server_calls_in_opal_log) & audit$server_calls_in_opal_log == 0], collapse = ", ")))
for (i in which(audit$status != "PASS")) summary_line("   ", audit$status[i], " ", audit$method[i], " [", audit$client[i], "]: ", substr(audit$error[i], 1, 400))
opal.logout(o)
