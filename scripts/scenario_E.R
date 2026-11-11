# Scenario E: the recipe system end to end on Opal, as the non-admin analyst, with the server's default disclosure
# options (nfilter.subset = 3). Each recipe: validate, preview, execute; then what exists server-side (dsBase dimDS /
# colnamesDS when the profile publishes them) and every refusal or warning verbatim.
source("scripts/common.R")
suppressPackageStartupMessages(library(dsOMOPClient))
start_log("scenario-E")
res <- if (identical(MODE, "candidate")) "omop_data.gibleed" else "omop_data.gibleed_tls_disable"
S <- "omop"
# The stock Rock image no longer ships dsBase; install it the way an administrator would (after the method audit,
# which therefore ran against a profile holding dsOMOP's methods only), for dimDS / colnamesDS below.
o <- admin()
if (identical(rock_pkg_version("dsBase"), "not installed")) {
  capture("dsadmin.install_package(o, \"dsBase\") [CRAN]", dsadmin.install_package(o, "dsBase"))
  say("dsBase on Rock: ", rock_pkg_version("dsBase"))
}
opal.logout(o)
conns <- analyst_login()
con <- capture(paste0("ds.omop.connect(\"", res, "\")"), ds.omop.connect(resource = res, symbol = S, conns = conns))
if (!con$ok) {
  ds_errors()
  summary_line("[", E2E_PATH, "] E: cannot connect to ", res, ": ", con$error)
  quit(save = "no", status = 0)
}
am <- tryCatch(DSI::datashield.methods(conns, type = "aggregate")$name, error = function(e) character(0))
have_base <- all(c("dimDS", "colnamesDS") %in% am)
say("dsBase dimDS/colnamesDS published in the profile: ", have_base)
show("ds.omop.disclosure.settings()", tryCatch(ds.omop.disclosure.settings(symbol = S, conns = conns), error = function(e) conditionMessage(e)))

describe <- function(sym) {
  if (!have_base) return(list(dim = NA, cols = character(0)))
  d <- tryCatch(DSI::datashield.aggregate(conns, call("dimDS", sym))[[1]], error = function(e) paste("dimDS:", conditionMessage(e)))
  cn <- tryCatch(DSI::datashield.aggregate(conns, call("colnamesDS", sym))[[1]], error = function(e) paste("colnamesDS:", conditionMessage(e)))
  say(sprintf("    server-side %s: dim %s; %d columns: %s", sym, paste(d, collapse = " x "), length(cn), paste(cn, collapse = ", ")))
  list(dim = d, cols = cn)
}
top_concepts <- function(table, n = 5) {
  r <- capture(sprintf("ds.omop.concept.prevalence(\"%s\", top_n = %d)", table, n),
               ds.omop.concept.prevalence(table, top_n = n, symbol = S, conns = conns))
  if (!r$ok) return(integer(0))
  df <- r$value$per_site[[1]]
  if (!is.data.frame(df) || !nrow(df)) return(integer(0))
  show(paste("top concepts in", table), utils::head(df, n))
  col <- c("concept_id", grep("concept_id$", names(df), value = TRUE))
  col <- col[col %in% names(df)][1]
  ids <- suppressWarnings(as.integer(df[[col]]))
  utils::head(ids[!is.na(ids) & ids > 0], n)
}
okw <- function(r) if (is.null(r)) "skipped" else if (r$ok) "ok" else "ERROR"
run_recipe <- function(id, what, rec, out, cohort = NULL) {
  say("== ", id, ": ", what)
  v <- capture(paste(id, "recipe_validate"), recipe_validate(rec, symbol = S, conns = conns))
  if (v$ok) show(paste(id, "validate"), v$value)
  p <- capture(paste(id, "recipe_preview"), recipe_preview(rec, symbol = S, conns = conns))
  if (p$ok) for (l in capture.output(utils::str(p$value, max.level = 5, list.len = 40, vec.len = 6))) say("    ", l) else ds_errors()
  e <- capture(paste(id, "recipe_execute"), recipe_execute(rec, out = out, symbol = S, conns = conns, cohort = cohort))
  if (e$ok) show(paste(id, "execute value"), e$value) else ds_errors()
  desc <- lapply(unname(out), describe)
  shapes <- vapply(seq_along(out), function(i) sprintf("%s=%s [%s]", out[[i]], paste(desc[[i]]$dim, collapse = "x"),
                                                         paste(desc[[i]]$cols, collapse = ",")), "")
  summary_line(sprintf("[%s] E %s (%s): validate %s, preview %s, execute %s; %s", E2E_PATH, id, what, okw(v), okw(p),
                       okw(e), paste(shapes, collapse = "; ")))
  for (w in unique(c(v$warnings, p$warnings, e$warnings))) summary_line("     warning: ", w)
  for (r in list(v, p, e)) if (!r$ok) summary_line("     error: ", r$error)
  invisible(list(v = v, p = p, e = e, desc = desc))
}

drugs <- top_concepts("drug_exposure")
conds <- top_concepts("condition_occurrence")
meas <- top_concepts("measurement")
obs <- top_concepts("observation")
procs <- top_concepts("procedure_occurrence")
say("concepts used: drugs ", paste(drugs, collapse = ","), "; conditions ", paste(conds, collapse = ","),
    "; measurements ", paste(meas, collapse = ","), "; observations ", paste(obs, collapse = ","),
    "; procedures ", paste(procs, collapse = ","))

gib_pop <- omop_population(id = "base", index_event = omop_index_event(192671, "condition_occurrence",
                                                                       primary_limit = "first", include_descendants = TRUE))

run_recipe("E1", "demographics only, every person", omop_recipe(
  variables = list(omop_variable_age(), omop_variable_sex()),
  outputs = omop_output(name = "demo", type = "wide")), c(demo = "E1"))

run_recipe("E2", "GI bleed 192671 + descendants (first event): age at index, sex", omop_recipe(
  populations = gib_pop,
  variables = list(omop_variable_age(reference = "index"), omop_variable_sex()),
  outputs = omop_output(name = "gib", type = "wide")), c(gib = "E2"))

run_recipe("E3", "GI bleed: NSAID exposures in the year before index (celecoxib, diclofenac with descendants; counts and time since first) + top drugs", omop_recipe(
  populations = gib_pop,
  variables = list(
    omop_variable_age(reference = "index"), omop_variable_sex(),
    omop_variable(name = "celecoxib_365", table = "drug_exposure", concept_id = 1118084, concept_name = "celecoxib",
                  format = "count", time_window = list(start = -365, end = 0), expand = TRUE),
    omop_variable(name = "diclofenac_365", table = "drug_exposure", concept_id = 1124300, concept_name = "diclofenac",
                  format = "count", time_window = list(start = -365, end = 0), expand = TRUE),
    omop_variable(name = "celecoxib_since", table = "drug_exposure", concept_id = 1118084, concept_name = "celecoxib",
                  format = "time_since", expand = TRUE)),
  blocks = if (length(drugs)) omop_variable_block(table = "drug_exposure", concept_ids = utils::head(drugs, 3),
                                                  format = "count", time_window = list(start = -365, end = 0)),
  outputs = omop_output(name = "nsaid", type = "wide")), c(nsaid = "E3"))

if (length(meas) || length(obs)) run_recipe("E4", "measurements (mean value) and observations (binary) pivoted wide, every person", omop_recipe(
  variables = list(omop_variable_age(), omop_variable_sex()),
  blocks = c(
    if (length(meas)) list(omop_variable_block(table = "measurement", concept_ids = utils::head(meas, 3), format = "mean",
                                               value_source = "value_as_number")),
    if (length(obs)) list(omop_variable_block(table = "observation", concept_ids = utils::head(obs, 3), format = "binary"))),
  outputs = omop_output(name = "labs", type = "wide")), c(labs = "E4"))

if (length(conds)) run_recipe("E5", "conditions within -30..+30 days of the GI bleed index (binary)", omop_recipe(
  populations = gib_pop,
  blocks = omop_variable_block(table = "condition_occurrence", concept_ids = utils::head(conds, 5), format = "binary",
                               time_window = list(start = -30, end = 30)),
  outputs = omop_output(name = "window", type = "wide")), c(window = "E5"))

c1 <- capture("ds.omop.cohort.create(GI bleed)", ds.omop.cohort.create(
  spec = list(type = "condition", concept_set = c(192671)), cohort_id = 300, name = "e_gib", mode = "temporary",
  symbol = S, conns = conns))
c2 <- if (length(drugs)) capture("ds.omop.cohort.create(top drug)", ds.omop.cohort.create(
  spec = list(type = "drug", concept_set = drugs[1]), cohort_id = 301, name = "e_drug", mode = "temporary",
  symbol = S, conns = conns)) else NULL
cu <- if (c1$ok && !is.null(c2) && c2$ok) capture("ds.omop.cohort.combine(union)", ds.omop.cohort.combine(
  "union", c1$value, c2$value, new_name = "e_gib_or_drug", symbol = S, conns = conns)) else NULL
if (!is.null(cu) && cu$ok) {
  run_recipe("E6", "cohort (GI bleed UNION top drug) as base, age and sex", omop_recipe(
    variables = list(omop_variable_age(), omop_variable_sex()),
    outputs = omop_output(name = "coh", type = "wide")), c(coh = "E6"), cohort = cu$value)
} else summary_line("[", E2E_PATH, "] E E6 cohort + combine: not run (", paste(c(c1$error, c2$error, cu$error), collapse = "; "), ")")

if (length(drugs)) run_recipe("E7", "drug exposure events in the 2 years before the GI bleed index, long format", omop_recipe(
  populations = gib_pop,
  blocks = omop_variable_block(table = "drug_exposure", concept_ids = utils::head(drugs, 3), format = "raw",
                               time_window = list(start = -730, end = 0)),
  outputs = omop_output(name = "events", type = "long")), c(events = "E7"))

run_recipe("E8", "several tables + filters (adults 18-100 with a GI bleed): age, sex, conditions, drugs, procedures", omop_recipe(
  variables = list(omop_variable_age(), omop_variable_sex(),
                   if (length(procs)) omop_variable(name = "proc_n", table = "procedure_occurrence", concept_id = procs[1],
                                                    format = "count")),
  blocks = c(
    if (length(conds)) list(omop_variable_block(table = "condition_occurrence", concept_ids = utils::head(conds, 3), format = "binary")),
    if (length(drugs)) list(omop_variable_block(table = "drug_exposure", concept_ids = utils::head(drugs, 3), format = "count"))),
  filters = list(omop_filter_age(18, 100), omop_filter_has_concept(192671, "condition_occurrence")),
  outputs = omop_output(name = "mix", type = "wide")), c(mix = "E8"))

if (length(drugs)) run_recipe("E9", "survival: time from the GI bleed index to the first top-drug exposure (TAR 0-365)", omop_recipe(
  populations = gib_pop,
  variables = omop_variable(name = "drug1", table = "drug_exposure", concept_id = drugs[1], format = "binary"),
  outputs = omop_output(name = "surv", type = "survival", options = list(tar = list(start_offset = 0, end_offset = 365)))),
  c(surv = "E9"))

capture("ds.omop.disconnect", ds.omop.disconnect(symbol = S, conns = conns))
DSI::datashield.logout(conns)
