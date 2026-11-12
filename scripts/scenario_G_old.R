# Scenario G, old client: the released dsOMOPClient 2.10.2 (GitHub tag OLD_CLIENT_REF of isglobal-brge/dsOMOPClient,
# installed into its own library) against this 2.10.3 server. Expected (release notes): an old client cannot use typed
# releases and does not pool protected entries; everything degrades plainly (no crash, a clear message) and the
# per-site results stay available. Verdicts in <path>-G-old-verdicts.csv; exit 1 on FAIL or ERROR.
source("scripts/common.R")
OLD_REF <- Sys.getenv("OLD_CLIENT_REF", "2.10.2")
OLD_LIB <- file.path(Sys.getenv("RUNNER_TEMP", tempdir()), paste0("dsomopclient-", OLD_REF))
start_log("scenario-G-old")
if (!dir.exists(file.path(OLD_LIB, "dsOMOPClient"))) {
  dir.create(OLD_LIB, recursive = TRUE, showWarnings = FALSE)
  capture(paste0("remotes::install_github(\"isglobal-brge/dsOMOPClient\", ref = \"", OLD_REF, "\", lib = <own library>)"),
          remotes::install_github("isglobal-brge/dsOMOPClient", ref = OLD_REF, lib = OLD_LIB, upgrade = "never",
                                  dependencies = FALSE, quiet = TRUE))
}
suppressPackageStartupMessages(library(dsOMOPClient, lib.loc = OLD_LIB))
source("scripts/g_lib.R")
VERDICT_PREFIX <- "G-old"
G_START <- Sys.time()
loaded <- as.character(utils::packageVersion("dsOMOPClient"))
say("dsOMOPClient loaded from ", find.package("dsOMOPClient"), ": ", loaded, "; server dsOMOP ", rock_pkg_version("dsOMOP"))

pooled_rows <- function(r) if (isTRUE(r$ok) && is.data.frame(r$value$pooled)) nrow(r$value$pooled) else 0L
why <- function(r) if (isTRUE(r$ok)) squash(c(r$value$meta$warnings, r$warnings, r$messages), 400) else last_server_error(r$error)

section("O1", "the old client is the released one", function() {
  verdict("O1", if (identical(loaded, OLD_REF) || identical(paste0(loaded), sub("^v", "", OLD_REF))) "PASS" else "ERROR",
          paste("dsOMOPClient", OLD_REF, "from GitHub, loaded instead of the run's client"), paste("loaded", loaded))
})

S <- NULL
section("O2", "connect and explore (the core)", function() {
  S <<- open_session("old client")
  if (!S$ok) {
    verdict("O2", "FAIL", "the 2.10.2 client connects to the 2.10.3 server", S$error)
    stop("cannot connect")
  }
  t <- capture_ds("old client: ds.omop.tables", ds.omop.tables(symbol = S$symbol, conns = S$conns))
  verdict("O2", if (t$ok) "PASS" else "FAIL", "the 2.10.2 client connects and lists the CDM tables",
          if (t$ok) paste("connect warnings:", squash(c(S$connect_warnings, ""), 200)) else t$error)
})

section("O3", "DP status and typed releases: refused plainly (old clients cannot use typed releases)", function() {
  if (!isTRUE(S$ok)) stop("no session")
  st <- capture_ds("old client: ds.omop.dp.status()", ds.omop.dp.status(S$conns))
  verdict("O3 status", if (st$ok || plain_error(st$error)) "PASS" else "FAIL", "ds.omop.dp.status() answers or refuses plainly",
          if (st$ok) "status returned" else st$error)
  prep <- capture_ds("old client: ds.omop.dp.prepare(ages)", ds.omop.dp.prepare(AGES_RECIPE, out = c(ages = "O_ages"),
                                                                                symbol = S$symbol, conns = S$conns))
  rel <- capture_ds("old client: ds.omop.dp.release(O_ages, count)", ds.omop.dp.release("O_ages", omop_privacy("count"),
                                                                                       datasources = S$conns))
  verdict("O3 typed", if (!rel$ok && plain_error(rel$error)) "PASS" else "FAIL",
          "a typed release from the 2.10.2 client is refused with a plain message (it cannot validate 2.10.3 payloads)",
          paste0("prepare ", if (prep$ok) "ok" else paste("refused:", last_server_error(prep$error)), "; release ",
                 if (rel$ok) "RETURNED A RESULT" else paste("refused:", rel$error)))
})

section("O4", "a protected catalogue release on one site: per-site result, no misleading pooled protection", function() {
  if (!isTRUE(S$ok)) stop("no session")
  for (id in c("dsomop:achilles.3", "dsomop:condition_era.length_stats")) {
    r <- capture_ds(paste0("old client: ds.omop.analysis.run(\"", id, "\")"), ds.omop.analysis.run(id, symbol = S$symbol, conns = S$conns))
    per <- isTRUE(r$ok) && is.data.frame(r$value$per_site[[1]]) && nrow(r$value$per_site[[1]]) > 0L
    lab <- if (isTRUE(r$ok)) squash(capture.output(str(r$value$meta$protection, max.level = 2)), 300) else ""
    verdict(paste0("O4 ", sub("^dsomop:", "", id)), if (per && plain_error(paste(r$error, ""))) "PASS" else "FAIL",
            "the old client shows the per-site protected frame without crashing",
            sprintf("per-site rows %s; pooled rows %d; messages: %s; protection as the old client reads it: %s",
                    if (per) nrow(r$value$per_site[[1]]) else 0L, pooled_rows(r), why(r), lab))
  }
})

section("O5", "two independent sites and both NA pooling policies: protected entries are not pooled by the old client", function() {
  s <- open_session("old client two sites", servers = c("Ethiopia", "Small"),
                    resource = c(Ethiopia = RES, Small = "omop_data.gibleed_small"))
  on.exit(close_session(s))
  if (!s$ok) stop("cannot connect: ", s$error)
  obj <- make_objects(s, prepared = NULL, loader = FALSE)
  arms <- unname(obj$cohorts[c("T", "C")])
  rs <- capture_ds("old client: condition_era.length_stats over two sites", ds.omop.analysis.run(
    "dsomop:condition_era.length_stats", symbol = s$symbol, conns = s$conns))
  verdict("O5 record_summary", if (rs$ok && pooled_rows(rs) == 0L && length(rs$value$per_site) == 2L) "PASS" else
    if (!rs$ok && plain_error(rs$error)) "PASS" else "FAIL",
          "a protected record summary over two sites is not pooled by the old client; both per-site frames are kept",
          if (rs$ok) sprintf("pooled rows %d; per-site %d; messages: %s", pooled_rows(rs), length(rs$value$per_site), why(rs)) else rs$error)
  for (pol in c("strict", "pooled_only_ok")) {
    r <- capture_ds(paste("old client: cm.effect_estimate (poisson) over two sites,", pol), ds.omop.analysis.run(
      "dsomop:cm.effect_estimate", params = c(list(outcome_concept_id = "192671", model_type = "poisson"), TAR730),
      cohort = arms, pooling_policy = pol, symbol = s$symbol, conns = s$conns))
    verdict(paste0("O5 effect_", pol), if ((r$ok && pooled_rows(r) == 0L) || (!r$ok && plain_error(r$error))) "PASS" else "FAIL",
            paste0("pooling_policy = \"", pol, "\": the old client does not pool the protected effect; it refuses plainly or keeps per-site frames"),
            if (r$ok) sprintf("pooled rows %d; per-site %d; messages: %s", pooled_rows(r), length(r$value$per_site), why(r)) else r$error)
  }
})

section("O6", "two connections to one node: no double-counted pooled result", function() {
  s <- open_session("old client duplicate connections", servers = c("SiteA", "SiteB"))
  on.exit(close_session(s))
  if (!s$ok) stop("cannot connect: ", s$error)
  r <- capture_ds("old client: achilles.3 over two connections to one node", ds.omop.analysis.run("dsomop:achilles.3",
                                                                                                symbol = s$symbol, conns = s$conns))
  verdict("O6", if ((r$ok && pooled_rows(r) == 0L) || (!r$ok && plain_error(r$error))) "PASS" else "FAIL",
          "the old client does not pool a protected release over two connections to the same node",
          if (r$ok) sprintf("pooled rows %d; messages: %s", pooled_rows(r), why(r)) else r$error)
})

close_session(S)
tab <- write_verdicts("G-old")
counts <- table(factor(tab$status, levels = c("PASS", "FAIL", "INFO", "ERROR")))
summary_line(sprintf("[%s] G-old (dsOMOPClient %s against dsOMOP %s): %d checks: PASS %d, FAIL %d, INFO %d, ERROR %d", E2E_PATH,
                     loaded, rock_pkg_version("dsOMOP"), nrow(tab), counts[["PASS"]], counts[["FAIL"]], counts[["INFO"]], counts[["ERROR"]]))
if (counts[["FAIL"]] + counts[["ERROR"]] > 0L) quit(save = "no", status = 1)
