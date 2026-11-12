# The new client (this run's dsOMOPClient) against the real old server (dsOMOP <old_ref>, installed at A1 of the
# upgrade path, before the upgrade). Sourced by path_upgrade.R. Expected (2.10.3): an explicit upgrade warning naming
# the old server, honest per-site legacy results without 2.10.3 protection claims, and both NA pooling policies as
# 2.10.2 defined them. Not executable here: a mixed old + new server federation (one Rock per run).
# Verdicts (V ...) go to upgrade-V-verdicts.csv; scenario G adds them to its table.
suppressPackageStartupMessages(library(dsOMOPClient))
source("scripts/g_lib.R")
VERDICT_PREFIX <- "V"
VERDICTS <- list()
G_START <- Sys.time()
server_version <- rock_pkg_version("dsOMOP")
say("== the new client ", as.character(packageVersion("dsOMOPClient")), " against the old server dsOMOP ", server_version)
warned <- function(...) grepl(UPGRADE_RE, said(...), ignore.case = TRUE)

V <- NULL
section("V1", "connect: an explicit upgrade warning", function() {
  V <<- open_session("new client, old server")
  if (!V$ok) stop("cannot connect: ", V$error)
  sv <- capture_ds("ds.omop.server.version()", ds.omop.server.version(V$conns))
  w <- grepl(UPGRADE_RE, paste(c(V$connect_warnings, V$login_warnings, sv$warnings, sv$messages), collapse = " | "), ignore.case = TRUE)
  verdict("V1", if (w) "PASS" else "FAIL",
          "connecting the 2.10.3 client to an old server warns explicitly that the server lacks the 2.10.3 fixes",
          sprintf("server %s; connect warnings: %s; server.version: %s", server_version, squash(c(V$connect_warnings, ""), 300),
                  if (sv$ok) squash(capture.output(print(sv$value)), 300) else sv$error))
})

section("V2", "typed release: honest per-site legacy result with an upgrade warning, no 2.10.3 claims", function() {
  if (!isTRUE(V$ok)) stop("no session")
  prep <- capture_ds("ds.omop.dp.prepare(ages) on the old server", ds.omop.dp.prepare(AGES_RECIPE, out = c(ages = "V_ages"),
                                                                                     symbol = V$symbol, conns = V$conns))
  rel <- capture_ds("ds.omop.dp.release(V_ages, count) on the old server", ds.omop.dp.release("V_ages", omop_privacy("count"),
                                                                                             datasources = V$conns))
  claims <- if (rel$ok) identical(rel$value$meta$privacy$contract, "protected_release_fixed_basis_or_realised_v1") ||
    identical(rel$value$per_site[[1]]$protocol, "dsomop-protected-release-v1") else FALSE
  w <- warned(prep, rel)
  ok <- (rel$ok && w && !claims) || (!rel$ok && plain_error(rel$error) && grepl(UPGRADE_RE, rel$error, ignore.case = TRUE))
  verdict("V2", if (ok) "PASS" else "FAIL",
          "a typed release on the old server: a per-site legacy result with an explicit upgrade warning (or a plain refusal naming the upgrade), never 2.10.3 claims",
          sprintf("release %s; warnings: %s; contract %s; claims 2.10.3 protection: %s", if (rel$ok) "returned" else paste("refused:", rel$error),
                  squash(said(prep, rel), 300), if (rel$ok) rel$value$meta$privacy$privacy_contract %||% "?" else "-", claims))
})

section("V3", "catalogue release: per-site result, an upgrade warning, no fixed-synopsis labels", function() {
  if (!isTRUE(V$ok)) stop("no session")
  r <- capture_ds("ds.omop.analysis.run(achilles.3) on the old server", ds.omop.analysis.run("dsomop:achilles.3", symbol = V$symbol,
                                                                                             conns = V$conns))
  labs <- if (r$ok) vapply(r$value$meta$protection, function(l) paste(l$protection %||% "", collapse = "/"), "") else character(0)
  w <- warned(r) || (r$ok && any(grepl(UPGRADE_RE, r$value$meta$warnings, ignore.case = TRUE)))
  ok <- r$ok && w && !any(labs %in% c("fixed_synopsis", "realised_sticky"))
  verdict("V3", if (ok) "PASS" else "FAIL",
          "a catalogue release from the old server: per-site frames, an explicit upgrade warning, its own (old) protection labels",
          if (r$ok) sprintf("labels %s; warnings: %s", paste(labs, collapse = ","), squash(c(r$value$meta$warnings, said(r)), 300)) else r$error)
})

section("V4", "both NA pooling policies on the old server (two independent sites)", function() {
  s <- open_session("new client, old server, two sites", servers = c("Ethiopia", "Small"),
                    resource = c(Ethiopia = RES, Small = "omop_data.gibleed_small"))
  on.exit(close_session(s))
  if (!s$ok) stop("cannot connect: ", s$error)
  obj <- make_objects(s, prepared = NULL, loader = FALSE)
  arms <- unname(obj$cohorts[c("T", "C")])
  params <- c(list(outcome_concept_id = "192671", model_type = "poisson"), TAR730)
  per <- capture_ds("old server per-site effect", raw_run(s, "dsomop:cm.effect_estimate", params, arms))
  fin <- if (per$ok) vapply(per$value, function(df) is.data.frame(df) && any(is.finite(suppressWarnings(as.numeric(df$estimate)))), logical(1)) else NA
  st <- capture_ds("old server, strict", ds.omop.analysis.run("dsomop:cm.effect_estimate", params = params, cohort = arms,
                                                              pooling_policy = "strict", symbol = s$symbol, conns = s$conns))
  po <- capture_ds("old server, pooled_only_ok", ds.omop.analysis.run("dsomop:cm.effect_estimate", params = params, cohort = arms,
                                                                       pooling_policy = "pooled_only_ok", symbol = s$symbol, conns = s$conns))
  est <- function(r) if (r$ok && is.data.frame(r$value$pooled) && "estimate" %in% names(r$value$pooled)) as.numeric(r$value$pooled$estimate) else NA
  mixed <- isTRUE(fin[["Ethiopia"]]) && !isTRUE(fin[["Small"]])
  if (!mixed) {
    verdict("V4", "INFO", "NA pooling policies on the old server",
            sprintf("pattern not produced (finite per site: %s); strict pooled %s, pooled_only_ok pooled %s",
                    paste(names(fin), fin, collapse = ", "), paste(est(st), collapse = "/"), paste(est(po), collapse = "/")))
  } else {
    verdict("V4a strict", if ((!st$ok && plain_error(st$error)) || (st$ok && !any(is.finite(est(st))))) "PASS" else "FAIL",
            "old server, strict: one NA site blocks the pooled effect", if (st$ok) paste("pooled", paste(est(st), collapse = "/"), squash(st$value$meta$warnings, 200)) else st$error)
    verdict("V4b pooled_only_ok", if (po$ok && any(is.finite(est(po))) && any(grepl("Dropped server", po$value$meta$warnings))) "PASS" else "FAIL",
            "old server, pooled_only_ok: the finite site is pooled and the NA one named", if (po$ok) paste("pooled", paste(est(po), collapse = "/"), squash(po$value$meta$warnings, 200)) else po$error)
  }
})

verdict("V5", "INFO", "a mixed federation of a 2.10.2 and a 2.10.3 server", "not executable here: one Opal/Rock per run")
close_session(V)
write_verdicts("V")
