# Scenario G: the dsOMOP 2.10.3 checks that need a real Opal/Rock (design/2.10.5/p0-report.md section 8,
# astra-p0-spec-v2.md section 10.4 and astra-p0-rereview.md section 9), as non-admin analysts on omop_data.gibleed
# (GiBleed, PostgreSQL 16). Each check states its expected result; verdicts are PASS, FAIL (a product failure, with
# its evidence), INFO or ERROR (the harness section stopped), in the summary and in <path>-G-verdicts.csv.
#   G1   every declared method and option is published; the analyst sees dsOMOP's methods
#   G1d  (upgrade path) the noise root created by the old version survives the upgrade and the publish
#   G2   DSI transport of the 2.10.3 payloads (status, typed release, catalogue release, pooling descriptors) and the
#        canonical meaning of transported requests (numeric strings, defaults, reordered fields, empty lists)
#   G3   the automatic data generation: DP-only mode with no custodial setting, derivation time, equal answers across
#        sessions, recreated handles, equivalent cohorts and a Rock restart; the analyst cannot see or move it
#   G4   the shared Rock identity: a noise-root bootstrap race and identical concurrent calls of two users
#   G5   a restored workspace with sealed tables (capsule v3)
#   G6   repeated logical-site connections (two connections to this one node)
#   G7   the combined dsBase + dsOMOP method profile (recorded, never claimed safe)
#   G8   the audit lines in Rock's Rserve.log
#   G9   tools-disabled gate ordering
#   G10  one protected route per family: grouped-time Cox, SCCS, person-time/MDRR, QueryLibrary record summaries
#   G11  no admission history after many distinct questions
#   G12  generation cache pressure (17 handles in one session) after a data change
#   G13  a coherent snapshot under concurrent loads, with and without connection loss
#   G14  NA pooling policies over two independent sites (a large and a small one)
#   G15  known aliases replay one owner; one-site pooling equals the site (binary rates, weighted histograms)
#   G16  cold and warm first-release latency on GiBleed and on a synthetic CDM of BIG_PERSONS persons
#   G17  the restored routes: interaction Cox, record H fallback, capped recurrent counts and event-time H
#   G18  no private fingerprint, map or support in DSI success, error, status or audit payloads
#   G19  snapshot_id has no effect: none configured, a changed label in an open session, a restore after a change
#   G20  another database user over the same CDM: corpus alias, source visibility, read-failure recovery
#   G21  generation replay across data loads, in-place edits and person changes (old/new handles, new sessions)
# On the upgrade path, path_upgrade.R also ran combo_old_server.R (the new client against the real 2.10.2 server);
# its V verdicts are added to this table. The script exits 1 when any check is FAIL or ERROR.
source("scripts/common.R")
suppressPackageStartupMessages(library(dsOMOPClient))
source("scripts/g_lib.R")
start_log("scenario-G")
assert_candidate_server()
G_START <- Sys.time()
WS <- "g_sealed"
BIG_PERSONS <- as.integer(Sys.getenv("BIG_PERSONS", "0"))

O <- admin()
INFO <- list()
S1_PROBES <- NULL
S1_OBJ <- NULL
S1_STATUS <- NULL
OBJS <- list()          # everything the analyst received (G3d, G18)
remember <- function(x) OBJS[[length(OBJS) + 1L]] <<- x
probe_one_g <- probe_one
probe_one <- function(s, kind, q, obj) {
  r <- probe_one_g(s, kind, q, obj)
  if (isTRUE(r$ok)) remember(r$value)
  r
}
uniq_offset <- function() 10L * N_SESSIONS
make_objects_g <- make_objects
make_objects <- function(s, prepared = "G_ages", loader = TRUE, cohorts = TRUE, id_offset = uniq_offset()) {
  # Cohort ids differ per handle: two handles of one R session never reuse a cohort table name.
  old <- COHORT_SPECS
  on.exit(COHORT_SPECS <<- old)
  for (k in names(COHORT_SPECS)) COHORT_SPECS[[k]]$id <<- old[[k]]$id + id_offset
  make_objects_g(s, prepared = prepared, loader = loader, cohorts = cohorts)
}

# ======================================================================================================================
section("G0", "setup: versions, Rock identity, state directory, profile, a second analyst, extra resources", function() {
  say("dsOMOP on Rock ", rock_pkg_version("dsOMOP"), "; dsBase ", rock_pkg_version("dsBase"), "; dsOMOPClient ",
      as.character(packageVersion("dsOMOPClient")), "; path ", E2E_PATH, "; mode ", MODE)
  verdict("G0", "INFO", "versions and the PostgreSQL driver on Rock",
          sprintf("dsOMOP %s, dsOMOPClient %s, dsBase %s; RPostgres %s, RPostgreSQL %s", rock_pkg_version("dsOMOP"),
                  as.character(packageVersion("dsOMOPClient")), rock_pkg_version("dsBase"), rock_pkg_version("RPostgres"),
                  rock_pkg_version("RPostgreSQL")))
  st <- state_files()
  show("Rock R sessions (administrator view): identity and the dsOMOP state directory", st)
  INFO$state0 <<- st
  mounts <- tryCatch(system2("docker", c("inspect", ROCK, "--format", shQuote("{{json .Mounts}}")), stdout = TRUE, stderr = TRUE),
                     error = function(e) conditionMessage(e))
  show("Rock container mounts", mounts)
  on_volume <- tryCatch(any(vapply(jsonlite::fromJSON(paste(mounts, collapse = ""), simplifyVector = FALSE), function(m) {
    startsWith(paste0(st$state_dir, "/"), paste0(m$Destination, "/"))
  }, logical(1))), error = function(e) NA)
  verdict("G0a", "INFO", "where the noise root lives (Rock's R user, state directory, on a container volume?)",
          sprintf("user %s, HOME %s, state %s, owner %s, mode %s, writable %s, on a volume: %s; files: %s", st$user, st$home, st$state_dir,
                  st$state_owner, st$state_mode, st$state_writable, on_volume,
                  paste(sub(" \\|.*", "", st$state_files), collapse = ", ")))
  opts <- tryCatch(dsadmin.get_options(O), error = function(e) NULL)
  show("DataSHIELD profile options", opts)
  if (is.data.frame(opts)) {
    custodial <- opts$name[grepl("dsomop", opts$name) & !startsWith(opts$name, "default.")]
    verdict("G0b", "INFO", "custodial dsOMOP options set in the profile before G (the declared defaults aside)",
            if (length(custodial)) paste(custodial, collapse = ", ") else "none")
  }
  capture("oadmin.user_add(o, \"analyst2\")", oadmin.user_add(O, "analyst2", password = Sys.getenv("ANALYST2_PW")))
  capture("dsadmin.perm_add(o, \"analyst2\", \"user\", \"use\")", dsadmin.perm_add(O, "analyst2", "user", "use"))
  for (r in c("gibleed", "gibleed_tls_disable")) {
    capture(paste0("opal.resource_perm_add(o, \"omop_data\", \"", r, "\", \"analyst2\", \"view\")"),
            opal.resource_perm_add(O, "omop_data", r, subject = "analyst2", type = "user", permission = "view"))
  }
  big <- tryCatch(psql_value("SELECT count(*) FROM pg_database WHERE datname = 'omopbig'", db = "postgres"),
                  error = function(e) "0")
  # The large CDM counts only when its build finished (every synthetic person and the primary keys are there).
  INFO$big <<- identical(big, "1") && isTRUE(tryCatch(as.numeric(psql_value(paste0(
    "SELECT count(*) FROM cdm.person WHERE person_id > 10000000"), db = "omopbig")) >= BIG_PERSONS &&
    identical(psql_value("SELECT count(*) FROM pg_indexes WHERE schemaname = 'cdm' AND indexname = 'person_pkey'", db = "omopbig"), "1"),
    error = function(e) FALSE))
  if (INFO$big) {
    url <- paste0("omop+dbi:postgresql://omopdb:5432/omopbig?cdm_schema=cdm")
    capture("opal.resource_create(o, \"omop_data\", \"gibleed_big\", ...)",
            opal.resource_create(O, "omop_data", "gibleed_big", url, format = "omop.dbi.db", identity = "omop",
                                 secret = Sys.getenv("OMOPDB_PW")))
    capture("opal.resource_perm_add(o, \"omop_data\", \"gibleed_big\", \"analyst\", \"view\")",
            opal.resource_perm_add(O, "omop_data", "gibleed_big", subject = "analyst", type = "user", permission = "view"))
  }
  say("synthetic large CDM omopbig present: ", INFO$big)
  INFO$db0 <<- psql_value(paste0("SELECT (SELECT count(*) FROM cdm.person) || '|' || (SELECT max(person_id) FROM cdm.person)",
                                 " || '|' || (SELECT count(*) FROM cdm.procedure_occurrence) || '|' || ",
                                 "(SELECT count(*) FROM cdm.condition_occurrence)"))
  say("CDM state at the start of G (persons|max person id|procedures|conditions): ", INFO$db0)
})

section("G1", "registrations and publication of the installed package", function() {
  pub <- check_publication(O, "scenario G")
  n_bad <- c(missing = length(c(pub$missing_aggregate, pub$missing_assign)), wrong_type = length(pub$wrong_type),
             extra = length(pub$extra), wrong_function = length(pub$wrong_function),
             not_exported = length(pub$not_exported), options_missing = length(pub$options_missing),
             options_different = length(pub$options_different))
  pkgv <- read.dcf("pkgs/dsOMOP/DESCRIPTION")[1, "Version"][[1]]
  target <- if (identical(MODE, "candidate")) pkgv else Sys.getenv("SERVER_REF")
  ok <- all(n_bad == 0L) && identical(unique(pub$versions), pub$installed_version) &&
    (!identical(MODE, "candidate") || identical(pub$installed_version, pkgv))
  verdict("G1a", if (ok) "PASS" else "FAIL",
          "every declared method and option of the installed dsOMOP is published as dsOMOP::<name> at its version",
          sprintf("installed %s (target %s); declared %d agg + %d assign, published %d + %d, published version %s; %s",
                  pub$installed_version, target, pub$declared[[1]], pub$declared[[2]], pub$published[[1]], pub$published[[2]],
                  paste(pub$versions, collapse = "/"), paste(names(n_bad), n_bad, sep = " ", collapse = ", ")))
  conns <- analyst_login()
  on.exit(try(DSI::datashield.logout(conns), silent = TRUE))
  d <- installed_description()
  miss <- character(0)
  for (type in c("aggregate", "assign")) {
    m <- DSI::datashield.methods(conns, type = type)
    declared <- split_field(if (type == "aggregate") d$AggregateMethods else d$AssignMethods)
    have <- m[m$name %in% declared, , drop = FALSE]
    if ("value" %in% names(m)) have <- have[have$value == paste0("dsOMOP::", have$name), , drop = FALSE]
    miss <- c(miss, setdiff(declared, have$name))
  }
  verdict("G1c", if (!length(miss)) "PASS" else "FAIL", "the analyst sees every dsOMOP method in the profile",
          if (length(miss)) paste("missing:", paste(miss, collapse = ", ")) else "all declared methods listed with dsOMOP:: functions")
})

section("G19a", "no snapshot_id configured anywhere (expected: none in the profile, or an empty stale default only)", function() {
  opts <- tryCatch(dsadmin.get_options(O), error = function(e) NULL)
  stale <- if (is.data.frame(opts)) opts[grepl("snapshot_id", opts$name), , drop = FALSE] else NULL
  empty <- is.data.frame(stale) && all(gsub("[\"' ]", "", stale$value) == "")
  verdict("G19a", if (!is.data.frame(stale) || !nrow(stale)) "PASS" else if (empty) "INFO" else "FAIL",
          "no dsomop.dp.snapshot_id in the DataSHIELD profile (2.10.3 dropped it from DESCRIPTION)",
          if (is.data.frame(stale) && nrow(stale)) paste0("present: ", paste(stale$name, stale$value, sep = " = ", collapse = "; "),
                                                         if (empty) " (an empty stale default; G19b-c show whether it matters)" else "") else "none")
})

section("G1d", "upgrade: the old version's noise root survives the upgrade and the publish", function() {
  f <- out_file("dp-root-before-upgrade.txt")
  if (!file.exists(f)) {
    old_ref <- Sys.getenv("OLD_REF", "0")
    expected <- identical(E2E_PATH, "upgrade") && grepl("^2\\.[0-9]+\\.[0-9]+$", old_ref) &&
      utils::compareVersion(old_ref, "2.6.0") >= 0
    verdict("G1d", if (expected) "FAIL" else "INFO", "noise root across the upgrade",
            if (expected) "harness baseline missing: A1b did not record the old-version DP root" else
              "not applicable (no old-version DP root recorded on this path)")
    return(invisible())
  }
  before <- readLines(f)
  key0 <- sub("^noise_key_id=", "", grep("^noise_key_id=", before, value = TRUE))
  file0 <- sub("^file=", "", grep("secrets/dp_noise_root \\|", before, value = TRUE))
  s <- open_session("G1d")
  on.exit(close_session(s))
  stv <- capture_ds("G1d: omopDpStatusDS()", raw_status(s))
  key1 <- if (stv$ok) stv$value[[1]]$noise_key_id %||% NA else NA
  file1 <- root_line(state_files())
  created <- sum(grepl(ROOT_CREATED_RE, rock_log()))
  same_file <- length(file0) == 1L && length(file1) == 1L && identical(file0, file1)
  ok <- isTRUE(stv$ok) && identical(key0, key1) && same_file && created == 1L
  verdict("G1d", if (ok) "PASS" else "FAIL",
          "the upgraded server uses the noise root the old version created (same key id, same file, created once)",
          sprintf("old %s key %s; now key %s; root file before [%s] now [%s]; root-creation lines in Rserve.log: %d",
                  sub("^version=", "", before[1]), key0, key1, paste(file0, collapse = " "), paste(file1, collapse = " "), created))
})

section("G4", "shared Rock identity: noise-root bootstrap race and concurrent identical calls of two users", function() {
  mv <- rock_eval('local({ p <- dsOMOP:::.dsomopSecretPath("dp_noise_root"); if (!file.exists(p)) return("absent");
    d <- file.path(Sys.getenv("HOME"), "e2e-moved-roots"); dir.create(d, showWarnings = FALSE, mode = "0700");
    if (file.rename(p, file.path(d, format(Sys.time(), "dp_noise_root.%Y%m%d%H%M%S")))) "moved aside" else "rename failed" })')
  say("existing noise root: ", paste(mv, collapse = " "))
  n0 <- sum(grepl(ROOT_CREATED_RE, rock_log()))
  s <- open_session("G4 pair", servers = c("Ethiopia", "Ethiopia2"), users = c("analyst", "analyst2"))
  on.exit(close_session(s))
  if (!s$ok) stop("the two sessions cannot connect: ", s$error)
  st <- capture_ds("G4: omopDpStatusDS() on both sessions at once (first DP call: root bootstrap)",
                   DSI::datashield.aggregate(s$conns, g_status_call(), async = TRUE))
  keys <- if (st$ok) vapply(st$value, function(x) as.character(x$noise_key_id %||% NA), "") else NA
  if (st$ok) remember(st$value)
  roots <- root_line(state_files())
  n1 <- sum(grepl(ROOT_CREATED_RE, rock_log()))
  ok <- isTRUE(st$ok) && length(unique(keys)) == 1L && !anyNA(keys) && length(roots) == 1L && (n1 - n0) == 1L
  verdict("G4a", if (ok) "PASS" else "FAIL",
          "two sessions bootstrapping the noise root at once end with one root (one key id, one file, created once)",
          sprintf("previous root %s; key ids %s; root files %d [%s]; root-creation log lines added %d",
                  paste(mv, collapse = " "), paste(keys, collapse = " "), length(roots), paste(roots, collapse = " "), n1 - n0))
  obj <- make_objects(s)
  INFO$pair_probes <<- run_probes(s, obj)
  show("G4 probes (both sessions answered each question at once)", probe_table(INFO$pair_probes))
  equality_verdict("G4b", "identical concurrent questions from two users (analyst, analyst2) get identical answers",
                   compare_probes(INFO$pair_probes, INFO$pair_probes), compare_probes(INFO$pair_probes, INFO$pair_probes, "full"))
})

section("G6", "repeated logical-site connections: two connections to this one node", function() {
  s <- open_session("G6 pair", servers = c("SiteA", "SiteB"))
  on.exit(close_session(s))
  if (!s$ok) stop("the two connections cannot connect: ", s$error)
  obj <- make_objects(s, prepared = NULL, cohorts = FALSE)
  dup_re <- "same logical node|Duplicate logical source|logical source|share a DP noise domain|one logical privacy node"
  for (id in c("dsomop:achilles.3", "dsomop:condition_era.length_stats")) {
    r <- capture_ds(paste0("G6: ds.omop.analysis.run(\"", id, "\") pooled over both connections"),
                    ds.omop.analysis.run(id, symbol = s$symbol, conns = s$conns))
    msg <- if (r$ok) paste(r$value$meta$warnings, collapse = " | ") else r$error
    refused <- (!r$ok && grepl(dup_re, r$error)) || (r$ok && is.null(r$value$pooled) && grepl(dup_re, msg))
    verdict(paste0("G6a ", sub("^dsomop:", "", id)), if (refused && plain_error(msg)) "PASS" else "FAIL",
            "pooling a protected catalogue release over two connections to one node is refused with a clear message",
            if (r$ok) paste0("pooled ", if (is.null(r$value$pooled)) "NULL" else paste(nrow(r$value$pooled), "rows"),
                             "; warnings: ", msg) else msg)
    sp <- capture_ds(paste0("G6: split view of ", id), raw_run(s, id))
    same <- sp$ok && length(unique(vapply(sp$value, function(x) md5(canon(answer_of(x))), ""))) == 1L
    verdict(paste0("G6b ", sub("^dsomop:", "", id)), if (same) "PASS" else "FAIL",
            "the per-connection results stay available and are identical",
            if (sp$ok) paste("per-site answers", if (same) "identical" else "differ") else sp$error)
  }
  if (!is.na(obj$loader)) {
    r <- capture_ds("G6: ds.omop.dp.release(loader, count) pooled over both connections",
                    ds.omop.dp.release(obj$loader, omop_privacy("count", population_id = "g_loader"), datasources = s$conns))
    msg <- if (r$ok) paste(r$value$meta$warnings, collapse = " | ") else r$error
    verdict("G6c", if (!r$ok && grepl(dup_re, r$error) && plain_error(r$error)) "PASS" else "FAIL",
            "a typed release over two connections to one node is refused with a clear message",
            if (r$ok) paste0("released; pooled ", if (is.null(r$value$pooled)) "NULL" else "present", "; ", msg) else msg)
    r2 <- capture_ds("G6: ds.omop.dp.release(loader, count, pool = FALSE) over both connections",
                     ds.omop.dp.release(obj$loader, omop_privacy("count", population_id = "g_loader"), datasources = s$conns,
                                        pool = FALSE))
    verdict("G6d", "INFO", "a typed release with pool = FALSE over two connections to one node",
            if (r2$ok) "per-site releases returned" else paste("refused:", r2$error))
  } else verdict("G6c", "FAIL", "a typed release over two connections to one node", paste("no loader table:", obj$loader_error))
})

section("G2", "reference session S1: DSI transport of the 2.10.3 payloads", function() {
  s <- open_session("S1")
  INFO$s1 <<- s
  if (!s$ok) stop("S1 cannot connect: ", s$error)
  st <- capture_ds("S1: omopDpStatusDS()", raw_status(s))
  stc <- capture_ds("S1: ds.omop.dp.status() (client validation)", ds.omop.dp.status(s$conns))
  if (st$ok) {
    remember(st$value)
    S1_STATUS <<- st$value[[1]]
    show("S1 DP status (raw)", S1_STATUS)
  }
  need <- list(enabled = TRUE, ready = TRUE, privacy_contract = "protected_release_fixed_basis_or_realised_v1",
               history_based_admission = FALSE, privacy_call_quota = "none", persistent_state = "noise_root_only",
               data_generation = "person_membership_digest", tools_mode = "auto", exclusive = FALSE,
               noise_provider = "persistent_file")
  bad <- if (st$ok) names(need)[!vapply(names(need), function(n) identical(S1_STATUS[[n]], need[[n]]), logical(1))] else names(need)
  verdict("G2a", if (st$ok && stc$ok && !length(bad)) "PASS" else "FAIL",
          "the 2.10.3 DP status crosses DSI and the 2.10.3 client accepts it (contract, no quota, no history, automatic generation)",
          if (!st$ok) st$error else if (!stc$ok) stc$error else if (length(bad)) paste("unexpected:", paste(bad, vapply(bad, function(n) squash(deparse(S1_STATUS[[n]]), 80), ""), sep = "=", collapse = "; ")) else
            paste0("contract ", S1_STATUS$privacy_contract, ", epsilon ", S1_STATUS$release_epsilon, ", provider ",
                   S1_STATUS$noise_provider, ", tools_mode ", S1_STATUS$tools_mode, ", generation ", S1_STATUS$data_generation))
  S1_OBJ <<- make_objects(s, id_offset = 0L)
  S1_PROBES <<- run_probes(s, S1_OBJ)
  show("S1 probe answers (the reference)", probe_table(S1_PROBES))
  INFO$timing <<- list(S1 = c(first = first_fixed_secs(S1_PROBES),
                              repeat_secs = probe_one(s, "catalog", FIXED_Q[[1]], S1_OBJ)$secs %||% NA))
  failed <- names(S1_PROBES)[!vapply(S1_PROBES, function(p) isTRUE(p$ok), logical(1))]
  verdict("G2b", if (!length(failed)) "PASS" else "FAIL",
          "every reference question (fixed, scoped, typed) answers through DSI",
          if (length(failed)) paste(vapply(failed, function(k) paste0(k, ": ", squash(S1_PROBES[[k]]$error, 400)), ""), collapse = "; ") else
            paste(names(S1_PROBES), vapply(S1_PROBES, function(p) unique(vapply(p$per, `[[`, "", "protection"))[1], ""), sep = "=", collapse = ", "))
  for (k in c("loader_count", "prepared_hist")) {
    q <- TYPED_Q[[k]]
    sym <- S1_OBJ[[q$table]]
    if (is.na(sym)) next
    priv <- do.call(omop_privacy, q$spec)
    r <- capture_ds(paste0("S1: ds.omop.dp.release(", sym, ", ", q$spec$statistic, ") through the client"),
                    ds.omop.dp.release(sym, priv, datasources = s$conns))
    p <- if (r$ok) r$value$per_site[[1]] else NULL
    ok <- r$ok && identical(p$protocol, "dsomop-protected-release-v1") &&
      grepl("^dsl_[0-9a-f]{40}$", p$source$logical_source_id %||% "") &&
      is.numeric(p$components$signed) && all(is.finite(p$components$signed)) && !is.null(r$value$pooled)
    if (r$ok) remember(r$value)
    verdict(paste0("G2c ", k), if (ok) "PASS" else "FAIL",
            "a typed protected payload crosses DSI intact and the client validates and pools it",
            if (r$ok) sprintf("protocol %s, protection %s, %d signed components, logical source %s, pooled %s, warnings: %s",
                              p$protocol, p$protection, length(p$components$signed), p$source$logical_source_id,
                              if (is.null(r$value$pooled)) "NULL" else "present", squash(r$value$meta$warnings, 300)) else r$error)
  }
  for (id in c("dsomop:achilles.3", "dsomop:condition_era.length_stats", "dsomop:incidence.rate")) {
    meta <- capture_ds(paste0("S1: omopAnalysisGetDS(", id, ")"),
                       DSI::datashield.aggregate(s$conns, call("omopAnalysisGetDS", s$rs, id)))
    rp <- if (meta$ok) meta$value[[1]]$release_pooling else NULL
    coh <- if (identical(id, "dsomop:incidence.rate")) S1_OBJ$cohorts$T else NULL
    params <- if (identical(id, "dsomop:incidence.rate")) SCOPED_Q$incidence$params else list()
    r <- capture_ds(paste0("S1: ds.omop.analysis.run(\"", id, "\") through the client"),
                    ds.omop.analysis.run(id, params = params, cohort = coh, symbol = s$symbol, conns = s$conns))
    if (r$ok) remember(r$value)
    key <- c("dsomop:achilles.3" = "achilles_3", "dsomop:condition_era.length_stats" = "condition_era",
             "dsomop:incidence.rate" = "incidence")[[id]]
    raw1 <- S1_PROBES[[key]]
    rel <- if (isTRUE(raw1$ok)) attr(raw1$value[[1]], "dsomop_release", exact = TRUE) else NULL
    ok <- meta$ok && identical(rp$strategy, "protected_components") && r$ok && !is.null(r$value$pooled) &&
      identical(rel$protocol, "dsomop-protected-release-v1")
    verdict(paste0("G2d ", sub("^dsomop:", "", id)), if (ok) "PASS" else "FAIL",
            "a protected catalogue release carries its payload and pooling descriptor through DSI; the client pools it",
            sprintf("release_pooling %s; payload protocol %s; client %s; pooled %s; protection %s",
                    rp$strategy %||% "absent", rel$protocol %||% "absent", if (r$ok) "ok" else squash(r$error, 400),
                    if (r$ok && !is.null(r$value$pooled)) paste(nrow(r$value$pooled), "rows") else "NULL",
                    if (r$ok) paste(vapply(r$value$meta$protection, function(l) l$protection %||% "", ""), collapse = "/") else ""))
  }
  variants <- list(
    sccs = list(id = "dsomop:sccs.incidence_rate_ratio", v = list(
      strings = list(exposure_concept_id = "1118084", outcome_concept_id = "192671", window = "30"),
      numbers_reordered = list(window = 30, outcome_concept_id = 192671, exposure_concept_id = 1118084),
      default_window = list(exposure_concept_id = "1118084", outcome_concept_id = "192671"),
      explicit_defaults = list(exposure_concept_id = "1118084", exposure_domain_code = "1", outcome_concept_id = "192671",
                               outcome_domain_code = "0", window = "30"))),
    age_decade = list(id = "dsomop:person.age_distribution_decade", v = list(
      string = list(reference_year = "2020"), number = list(reference_year = 2020), integer = list(reference_year = 2020L))),
    achilles_3 = list(id = "dsomop:achilles.3", v = list(
      empty_list = list(), empty_object = stats::setNames(list(), character(0)))))
  for (g in names(variants)) {
    res <- lapply(variants[[g]]$v, function(p) capture_ds(sprintf("S1: %s with %s", variants[[g]]$id,
                                                                    squash(jsonlite::toJSON(p, auto_unbox = TRUE), 160)),
                                                            raw_run(s, variants[[g]]$id, p)))
    oks <- vapply(res, `[[`, logical(1), "ok")
    ans <- if (all(oks)) vapply(res, function(r) md5(canon(answer_of(r$value[[1]]))), "") else character(0)
    verdict(paste0("G2e ", g), if (all(oks) && length(unique(ans)) == 1L) "PASS" else "FAIL",
            "requests that differ only in transport form (strings, numbers, defaults, field order, empty list) get one answer",
            if (!all(oks)) paste(names(res)[!oks], vapply(res[!oks], `[[`, "", "error"), sep = ": ", collapse = "; ") else
              paste(names(ans), substr(ans, 1, 10), sep = "=", collapse = ", "))
  }
  if (!is.na(S1_OBJ$loader)) {
    r <- capture_ds("S1: typed count with the spec fields reordered", raw_typed(s, S1_OBJ$loader, rev(TYPED_Q$loader_count$spec)))
    same <- r$ok && isTRUE(S1_PROBES$loader_count$ok) && identical(md5(canon(r$value[[1]])), S1_PROBES$loader_count$per[[1]]$answer)
    verdict("G2e typed_reordered", if (same) "PASS" else "FAIL", "a typed spec with reordered fields gets the same payload",
            if (r$ok) if (same) "identical payload" else "payload differs" else r$error)
  }
})

section("G3c1", "recreated handles in the same session (disconnect, connect again)", function() {
  s <- INFO$s1
  if (!isTRUE(s$ok)) stop("no S1 session")
  s <- disconnect_session(s)
  s$label <- "S1 handle 2"
  s <- connect_session(s)
  INFO$s1 <<- s
  if (!s$ok) stop("S1 cannot reconnect: ", s$error)
  obj <- make_objects(s, prepared = NULL, loader = FALSE)
  obj$loader <- S1_OBJ$loader
  obj$prepared <- S1_OBJ$prepared
  p <- run_probes(s, obj)
  show("S1 handle 2 probes", probe_table(p))
  equality_verdict("G3c1", "answers on a recreated handle equal the first handle's (typed tables sealed under the first)",
                   compare_probes(S1_PROBES, p), compare_probes(S1_PROBES, p, "full"))
  INFO$s1_obj <<- obj
})

section("G3c2", "equivalent cohort definitions get the same realised answers", function() {
  s <- INFO$s1
  if (!isTRUE(s$ok)) stop("no S1 session")
  spec <- COHORT_SPECS$T$spec
  a <- capture_ds("S1: cohort A (celecoxib, id 9701)", ds.omop.cohort.create(spec = spec, cohort_id = 9701L, name = "g_a",
                                                                           symbol = s$symbol, conns = s$conns))
  b <- capture_ds("S1: cohort B (the same definition, id 9702)", ds.omop.cohort.create(spec = spec, cohort_id = 9702L, name = "g_b",
                                                                                     symbol = s$symbol, conns = s$conns))
  u <- if (a$ok) capture_ds("S1: cohort A union A", ds.omop.cohort.combine("union", a$value, a$value, new_name = "g_aua",
                                                                          symbol = s$symbol, conns = s$conns)) else a
  i <- if (a$ok && b$ok) capture_ds("S1: cohort A intersect B", ds.omop.cohort.combine("intersect", a$value, b$value,
                                                                                      new_name = "g_aib", symbol = s$symbol,
                                                                                      conns = s$conns)) else b
  cohorts <- list(A = a, B = b, A_union_A = u, A_intersect_B = i)
  q <- SCOPED_Q$incidence
  ans <- lapply(names(cohorts), function(k) {
    if (!cohorts[[k]]$ok) return(list(ok = FALSE, error = cohorts[[k]]$error))
    r <- capture_ds(paste0("S1: incidence.rate over cohort ", k), raw_run(s, q$id, q$params, cohorts[[k]]$value))
    if (r$ok) { remember(r$value); list(ok = TRUE, answer = md5(canon(answer_of(r$value[[1]]))), protection = protection_of(r$value[[1]])) } else
      list(ok = FALSE, error = r$error)
  })
  names(ans) <- names(cohorts)
  ok <- all(vapply(ans, `[[`, logical(1), "ok"))
  eq <- ok && length(unique(vapply(ans, `[[`, "", "answer"))) == 1L
  ref <- S1_PROBES$incidence
  eq_ref <- ok && isTRUE(ref$ok) && identical(ans$A$answer, ref$per[[1]]$answer)
  verdict("G3c2", if (eq && eq_ref) "PASS" else "FAIL",
          "incidence over equivalent cohorts (same definition twice, A union A, A intersect B) equals the reference",
          if (!ok) paste(names(ans)[!vapply(ans, `[[`, logical(1), "ok")], collapse = ", ") else
            paste0(paste(names(ans), substr(vapply(ans, `[[`, "", "answer"), 1, 10), sep = "=", collapse = ", "),
                   "; reference ", substr(ref$per[[1]]$answer %||% "", 1, 10), "; protection ", ans$A$protection))
})

section("G3d", "the analyst cannot see or move the automatic data generation", function() {
  s <- INFO$s1
  if (!isTRUE(s$ok)) stop("no S1 session")
  demo <- capture_ds("S1: recipe_execute(demographics -> G_demo)", recipe_execute(omop_recipe(
    variables = list(omop_variable_age(), omop_variable_sex()), outputs = omop_output(name = "demo", type = "wide")),
    out = c(demo = "G_demo"), symbol = s$symbol, conns = s$conns))
  s <- disconnect_session(s)
  s$label <- "S1 handle 3"
  s <- connect_session(s)
  INFO$s1 <<- s
  if (!s$ok) stop("S1 cannot reconnect: ", s$error)
  p <- run_probes(s, list(cohorts = list()), sets = "fixed")
  equality_verdict("G3d2", "fixed synopses derived after the analyst's own cohorts, tables and plan outputs are unchanged",
                   compare_probes(S1_PROBES, p))
  inj <- list(
    typed = if (!is.na(S1_OBJ$loader)) capture_ds("S1: typed count with injected data_generation/snapshot_id/privacy_epoch",
      raw_typed(s, S1_OBJ$loader, c(TYPED_Q$loader_count$spec, list(data_generation = strrep("0", 64), snapshot_id = "cdm_x",
                                                                       privacy_epoch = 2L)))) else NULL,
    catalogue = capture_ds("S1: achilles.3 with injected snapshot_id/privacy_epoch/data_generation params",
      raw_run(s, "dsomop:achilles.3", list(snapshot_id = "cdm_x", privacy_epoch = "2", data_generation = strrep("0", 64)))))
  refs <- list(typed = S1_PROBES$loader_count, catalogue = S1_PROBES$achilles_3)
  res <- vapply(names(inj), function(k) {
    r <- inj[[k]]
    if (is.null(r)) return("not run")
    if (!r$ok) return(paste0("refused (", last_server_error(r$error), ")"))
    a <- md5(canon(answer_of(r$value[[1]])))
    if (isTRUE(refs[[k]]$ok) && identical(a, refs[[k]]$per[[1]]$answer)) "ignored: same answer" else "HONOURED: the answer changed"
  }, "")
  verdict("G3d3", if (!any(grepl("HONOURED", res))) "PASS" else "FAIL",
          "generation-like fields injected by the analyst are refused or ignored", paste(names(res), res, sep = ": ", collapse = "; "))
  cands <- hex64(paste(vapply(OBJS, canon, ""), collapse = "\n"))
  code <- paste0('local({ ', HANDLE_CODE, '
    dsOMOP:::.dsomopDpEnsureRuntime(h)
    p <- dsOMOP:::.dsomopDpPolicy()
    dsOMOP:::.dsomopWithReadSnapshot(h, {
    t_snap <- system.time(snap <- dsOMOP:::.dsomopDpMembershipHash(h))[["elapsed"]]
    t_gen <- system.time(g <- dsOMOP:::.dsomopDpDataGeneration(h, p))[["elapsed"]]
    cands <- ', paste(deparse(cands), collapse = ""), '
    list(snapshot_seconds = t_snap, generation_seconds = t_gen, available = isTRUE(g$available),
         tables = 1L, tables_present = 1L, method = snap$method,
         candidates = length(cands), generation_released = isTRUE(g$available) && any(cands == g$id),
         generation_prefix_released = isTRUE(g$available) && any(vapply(cands, function(x) grepl(substr(g$id, 1, 16), x, fixed = TRUE), logical(1))))
    })
  })')
  g <- admin_handle_eval(code)
  show("generation check in an administrator R session on Rock (values stay on Rock)", g)
  INFO$admin_generation <<- g
  if (inherits(g, "rock_error") || !is.list(g)) {
    verdict("G3d1", "ERROR", "the generation never reaches the analyst (checked on Rock against every 64-hex value received)",
            paste("the administrator check could not run (this head's generation internals):", paste(g, collapse = " ")))
  } else {
    verdict("G3d1", if (isTRUE(g$available) && !isTRUE(g$generation_released) && !isTRUE(g$generation_prefix_released)) "PASS" else "FAIL",
            "the generation never reaches the analyst (checked on Rock against every 64-hex value received)",
            sprintf("generation available on Rock: %s; %d candidate 64-hex values in %d received objects; released: %s",
                    g$available, g$candidates, length(OBJS), g$generation_released))
  }
})

section("G10", "one protected route per family on GiBleed: finite or a stable unavailable row, never an error", function() {
  s <- INFO$s1
  if (!isTRUE(s$ok)) stop("no S1 session")
  numeric_n <- psql_value("SELECT COUNT(*) FROM cdm.measurement WHERE value_as_number IS NOT NULL")
  if (identical(numeric_n, "0")) {
    empty <- capture_ds("GiBleed's all-null numeric measurements", raw_run(s, "dsomop:measurement.value_stats"))
    verdict("G10 measurement_empty", if (!empty$ok && grepl("Disclosive", empty$error)) "PASS" else "FAIL",
            "an all-null numeric population is refused by the final support gate",
            if (empty$ok) "unexpected release" else last_server_error(empty$error))
  }
  cleanup_measurements <- numeric_measurement_fixture()
  on.exit(cleanup_measurements(), add = TRUE)
  obj <- make_objects(s, prepared = NULL, loader = FALSE)
  INFO$s1_obj3 <<- obj
  fam <- list(
    cox = list(id = "dsomop:cm.effect_estimate", cohort = c("T", "C"),
               params = c(list(outcome_concept_id = "192671", model_type = "cox"), TAR730), main = "estimate", label = "cox|exit"),
    poisson = list(id = "dsomop:cm.effect_estimate", cohort = c("T", "C"),
                   params = c(list(outcome_concept_id = "192671", model_type = "poisson"), TAR730), main = "estimate"),
    sccs = list(id = "dsomop:sccs.incidence_rate_ratio",
                params = list(exposure_concept_id = "1118084", outcome_concept_id = "192671", window = "30"), main = "irr"),
    person_time = list(id = "dsomop:incidence.rate", cohort = "T", params = c(list(outcome_concept_id = "192671"), TAR365),
                       main = c("person_days", "rate")),
    mdrr = list(id = "dsomop:cm.mdrr", cohort = c("T", "C"), params = c(list(outcome_concept_id = "192671"), TAR365), main = "mdrr"),
    condition_era = list(id = "dsomop:condition_era.length_stats", main = c("mean", "avg", "n_persons")),
    drug_era = list(id = "dsomop:drug_era.length_stats", main = c("mean", "avg", "n_persons")),
    observation_period = list(id = "dsomop:observation_period.length_stats", main = c("mean", "avg", "n_persons")),
    observation_months = list(id = "dsomop:observation_period.length_months_stats", main = c("mean", "avg", "n_persons")),
    measurement_value = list(id = "dsomop:measurement.value_stats", params = g_measurement_params(),
                             main = c("n_persons", "n_values", "mean_value")),
    drug_quantity = list(id = "dsomop:drug.quantity_stats", main = c("n_persons", "n_records", "mean")))
  for (k in names(fam)) {
    f <- fam[[k]]
    coh <- if (is.null(f$cohort)) NULL else { x <- unname(obj$cohorts[f$cohort]); if (length(x) == 1L) x[[1L]] else x }
    r <- capture_ds(sprintf("S1: %s %s through the client", k, f$id),
                    ds.omop.analysis.run(f$id, params = f$params %||% list(), cohort = coh, symbol = s$symbol, conns = s$conns))
    r1 <- capture_ds(sprintf("S1: %s raw, first", k), raw_run(s, f$id, f$params %||% list(), coh))
    r2 <- capture_ds(sprintf("S1: %s raw, again", k), raw_run(s, f$id, f$params %||% list(), coh))
    df <- if (r1$ok) r1$value[[1]] else NULL
    if (r$ok) remember(r$value)
    if (!is.null(df)) {
      remember(df)
      show(paste("G10", k, "per-site frame"), df)
      show(paste("G10", k, "protection label"), attr(df, "dsomop_protection", exact = TRUE))
    }
    stable <- r1$ok && r2$ok && identical(canon(r1$value), canon(r2$value))
    cols <- if (is.data.frame(df)) intersect(f$main, names(df)) else character(0)
    finite <- if (length(cols)) any(vapply(cols, function(cn) any(is.finite(suppressWarnings(as.numeric(df[[cn]])))), logical(1))) else FALSE
    lab_txt <- if (!is.null(df)) canon(attr(df, "dsomop_protection", exact = TRUE)) else ""
    reason <- g_has_unavailable_reason(df)
    label_ok <- is.null(f$label) || grepl(f$label, lab_txt, ignore.case = TRUE)
    status <- if (!r$ok || !r1$ok) "FAIL" else if (!stable || !label_ok) "FAIL" else if (finite || reason) "PASS" else "FAIL"
    verdict(paste0("G10 ", k), status, sprintf("%s: a finite protected result or a stable unavailable row, labelled as asked", f$id),
            if (!r$ok || !r1$ok) paste(r$error, r1$error) else
              sprintf("%s; %d rows; %s; stable on repeat: %s; label matches: %s; protection %s; pooled %s",
                      if (finite) "finite" else if (reason) "unavailable with a reason" else "no finite value and no reason",
                      nrow(df), paste(vapply(cols, function(cn) paste0(cn, "=", squash(format(utils::head(df[[cn]], 4)), 80)), ""), collapse = " "),
                      stable, label_ok, protection_of(df), if (is.null(r$value$pooled)) "NULL" else paste(nrow(r$value$pooled), "rows")))
  }
})

section("G17", "restored routes: interaction Cox, record H fallback, capped recurrent counts, event-time H", function() {
  cleanup_measurements <- numeric_measurement_fixture()
  on.exit(cleanup_measurements(), add = TRUE)
  s <- INFO$s1
  if (!isTRUE(s$ok)) stop("no S1 session")
  obj <- INFO$s1_obj3
  arms <- unname(obj$cohorts[c("T", "C")])
  run2 <- function(label, id, params, cohort = NULL) {
    a <- capture_ds(paste0("S1: ", label), raw_run(s, id, params, cohort))
    b <- capture_ds(paste0("S1: ", label, " (repeat)"), raw_run(s, id, params, cohort))
    df <- if (a$ok) a$value[[1]] else NULL
    if (!is.null(df)) { remember(df); show(paste("G17", label), df); show(paste("G17", label, "label"), attr(df, "dsomop_protection", exact = TRUE)) }
    list(ok = a$ok, error = a$error, df = df, stable = a$ok && b$ok && identical(canon(a$value), canon(b$value)),
         label = if (!is.null(df)) canon(attr(df, "dsomop_protection", exact = TRUE)) else "")
  }
  finite_any <- function(df, col) is.data.frame(df) && col %in% names(df) && any(is.finite(suppressWarnings(as.numeric(df[[col]]))))
  # Interaction Cox: available wherever the Poisson interaction of the same family is (expected: finite Cox estimates,
  # or NA rows with a reason only where Poisson is NA too), labelled as a Cox/exit-time estimand.
  ip <- run2("interaction poisson by sex", "dsomop:cm.interaction_estimate",
             c(list(outcome_concept_id = "192671", subgroup_kind = "sex", model_type = "poisson"), TAR730), arms)
  ic <- run2("interaction cox by sex", "dsomop:cm.interaction_estimate",
             c(list(outcome_concept_id = "192671", subgroup_kind = "sex", model_type = "cox"), TAR730), arms)
  fp <- finite_any(ip$df, "estimate")
  fc <- finite_any(ic$df, "estimate")
  # Each run draws a new noise root. On this small fixture the noise can make
  # every subgroup uninformative: a Poisson interval spanning more than
  # exp(2 * 1.96 * 1.5) (about 360-fold) says nothing, and the Cox route then
  # rightly withholds its estimate with a reason instead of a number.
  informative <- function(df) is.data.frame(df) && all(c("estimate", "se_log_estimate") %in% names(df)) && {
    se <- suppressWarnings(as.numeric(df$se_log_estimate))
    any(is.finite(suppressWarnings(as.numeric(df$estimate))) & is.finite(se) & se <= 1.5)
  }
  fpi <- informative(ip$df)
  lab_c <- grepl("cox|exit", ic$label, ignore.case = TRUE)
  st <- if (!ic$ok || !ip$ok) "FAIL" else if (!ic$stable) "FAIL" else if (fc && lab_c) "PASS" else
    if (!fc && !fpi && grepl("unavailable|withheld|reason", ic$label)) "PASS" else "FAIL"
  verdict("G17a interaction_cox", st,
          "interaction Cox gives finite grouped-time Cox estimates where the Poisson interaction is informative, labelled as Cox",
          sprintf("poisson finite: %s; poisson informative: %s; cox finite: %s; cox label names Cox/exit: %s; stable: %s; %s", fp, fpi, fc, lab_c, ic$stable,
                  if (!ic$ok) ic$error else if (is.data.frame(ic$df) && "estimate" %in% names(ic$df)) paste("cox estimates", squash(format(ic$df$estimate), 120)) else ""))
  # Record H fallback: unregistered quantity / measurement scales still release a coarse value histogram (family H)
  # reconciled to the protected records (expected: an H owner or histogram cells next to N/R).
  for (id in c("dsomop:drug.quantity_stats", "dsomop:measurement.value_stats")) {
    r <- run2(sub("^dsomop:", "", id), id,
              if (identical(id, "dsomop:measurement.value_stats")) g_measurement_params() else list())
    rel <- if (is.data.frame(r$df)) attr(r$df, "dsomop_release", exact = TRUE) else NULL
    fams <- vapply(rel$owners %||% list(), function(o) as.character(o$family %||% ""), "")
    alloc_h <- vapply(rel$owners %||% list(), function(o) as.numeric(o$allocation$H %||% o$allocation_fraction$H %||% 0)[1], numeric(1))
    has_cells <- vapply(rel$owners %||% list(), function(o) length(o$cell_keys) > 0L || length(o$cells) > 0L, logical(1))
    hist_cols <- if (is.data.frame(r$df)) grep("bin|hist|break|quantile|median|^p[0-9]", names(r$df), value = TRUE) else character(0)
    has_h <- any(vapply(rel$owners %||% list(), function(o)
      any(vapply(o$components %||% list(), function(c)
        is.numeric(c$h) && length(c$h) > 0L && all(is.finite(c$h)), logical(1))), logical(1)))
    verdict(paste0("G17b ", sub("^dsomop:", "", id)), if (r$ok && r$stable && has_h) "PASS" else "FAIL",
            "unregistered scales carry finite signed H components (synthetic numeric measurements), stable on repeat",
            sprintf("owner families %s; H allocations %s; histogram cells %s; histogram columns %s; stable %s%s",
                    paste(unique(fams), collapse = "/"), paste(alloc_h, collapse = "/"), any(has_cells),
                    paste(hist_cols, collapse = ","), r$stable, if (!r$ok) paste("; error", r$error) else ""))
  }
  # Capped recurrent counts: incidence's recurrent `outcomes` is released (expected: finite wherever person_outcomes is,
  # with a capped-recurrent estimand label).
  inc <- run2("incidence (recurrent outcomes)", "dsomop:incidence.rate", c(list(outcome_concept_id = "192671"), TAR365),
              obj$cohorts$T)
  rec <- finite_any(inc$df, "outcomes")
  po <- finite_any(inc$df, "person_outcomes")
  lab_r <- grepl("recurr|capped at [0-9]+ (event|outcome)|events per person|all (outcome )?events", inc$label, ignore.case = TRUE)
  verdict("G17c recurrent_counts", if (inc$ok && inc$stable && (rec || !po) && lab_r) "PASS" else "FAIL",
          "incidence releases capped recurrent outcome counts next to first-outcome persons, labelled as such",
          sprintf("outcomes finite: %s; person_outcomes finite: %s; label names recurrent capped events: %s; %s", rec, po, lab_r,
                  if (is.data.frame(inc$df)) paste("outcomes", squash(format(inc$df$outcomes), 100)) else inc$error))
  # Event-time H: char.time_to_event with first_occurrence_only = 0 (all events, capped) is its own estimand
  # (expected: a different label and a different answer from first_occurrence_only = 1).
  tte <- lapply(c(all = "0", first = "1"), function(f) run2(paste0("time_to_event first_occurrence_only=", f),
                                                             "dsomop:char.time_to_event",
                                                             list(outcome_concept_id = "192671", first_occurrence_only = f),
                                                             obj$cohorts$T))
  ok <- all(vapply(tte, `[[`, logical(1), "ok"))
  differ_label <- ok && !identical(tte$all$label, tte$first$label)
  differ_answer <- ok && !identical(canon(answer_of(tte$all$df)), canon(answer_of(tte$first$df)))
  first_word <- ok && grepl("first outcome|first event", tte$all$label, ignore.case = TRUE)
  verdict("G17d event_time_H", if (ok && tte$all$stable && differ_label && differ_answer && !first_word) "PASS" else "FAIL",
          "time to event over all (capped recurrent) events is its own estimand, not the first-event one",
          sprintf("labels differ: %s; answers differ: %s; all-events label still says first outcome: %s; stable %s%s", differ_label,
                  differ_answer, first_word, if (ok) tte$all$stable else NA,
                  if (!ok) paste("; errors", paste(vapply(tte, function(x) x$error %||% "", ""), collapse = " | ")) else ""))
})

section("G15", "known aliases replay one owner; one-site pooling equals the site (binary rates, weighted histograms)", function() {
  s <- INFO$s1
  if (!isTRUE(s$ok)) stop("no S1 session")
  obj <- INFO$s1_obj3
  arms <- unname(obj$cohorts[c("T", "C")])
  # G15a: the MDRR aliases are one owner (expected: identical MDRR values).
  ids <- c("dsomop:cm.mdrr", "dsomop:ohdsi.cohort_method.cm_result", "dsomop:cm.diagnostics_summary")
  vals <- lapply(ids, function(id) {
    r <- capture_ds(paste0("S1: ", id), raw_run(s, id, c(list(outcome_concept_id = "192671"), TAR365), arms))
    if (!r$ok) return(list(ok = FALSE, error = r$error))
    df <- r$value[[1]]
    remember(df)
    col <- grep("^mdrr$", names(df), value = TRUE)
    list(ok = length(col) == 1L, v = if (length(col)) sort(unique(round(as.numeric(df[[col]]), 9))) else NULL,
         error = if (!length(col)) paste("no mdrr column:", paste(names(df), collapse = ",")) else "")
  })
  names(vals) <- ids
  ok <- all(vapply(vals, `[[`, logical(1), "ok"))
  same <- ok && length(unique(lapply(vals, `[[`, "v"))) == 1L
  verdict("G15a mdrr_aliases", if (same) "PASS" else "FAIL", "cm.mdrr, cm_result and the diagnostics summary release one MDRR",
          paste(sub("^dsomop:", "", ids), vapply(vals, function(x) if (isTRUE(x$ok)) paste(x$v, collapse = "/") else paste("error:", squash(x$error, 150)), ""),
                sep = "=", collapse = "; "))
  # G15b: a binary rate pooled over one site equals the site's own release (all persons and nonmissing denominators).
  gender <- capture_ds("S1: ds.omop.dp.prepare(gender_concept_id -> G_gender)", ds.omop.dp.prepare(omop_recipe(
    variables = omop_variable(name = "gender_concept_id", table = "person", column = "gender_concept_id"),
    outputs = omop_output(name = "g", type = "wide")), out = c(g = "G_gender"), symbol = s$symbol, conns = s$conns))
  for (den in c("all_persons", "nonmissing")) {
    if (!gender$ok) { verdict(paste0("G15b binary_", den), "FAIL", "one-site pooled binary rate equals the site", gender$error); next }
    r <- capture_ds(paste0("S1: binary_rate gender 8532, denominator ", den), ds.omop.dp.release("G_gender", omop_privacy(
      "binary_rate", variable = "gender_concept_id", positive = "8532", reducer = "any", denominator = den,
      population_id = "g_gender"), datasources = s$conns))
    if (r$ok) remember(r$value)
    p <- if (r$ok) r$value$per_site[[1]] else NULL
    pl <- if (r$ok) r$value$pooled else NULL
    close_enough <- function(a, b) is.numeric(a) && is.numeric(b) && length(a) == 1L && length(b) == 1L &&
      abs(a - b) <= max(0.01, 1e-6 * abs(a))
    eq <- r$ok && close_enough(p$noisy_numerator, pl$noisy_numerator) && close_enough(p$noisy_denominator, pl$noisy_denominator)
    verdict(paste0("G15b binary_", den), if (eq) "PASS" else "FAIL",
            "a typed binary rate pooled over one site equals that site's numerator and denominator",
            if (r$ok) sprintf("site %s/%s = %s; pooled %s/%s = %s", p$noisy_numerator, p$noisy_denominator, p$value %||% NA,
                              pl$noisy_numerator %||% NA, pl$noisy_denominator %||% NA, pl$estimate %||% NA) else r$error)
  }
  # G15c: a weighted (records) numeric histogram pooled over one site equals the site's own histogram.
  ml <- capture_ds("S1: pinned loader dsomop:measurement.load (assign)", ds.omop.analysis.run("dsomop:measurement.load",
                                                                                            type = "split", symbol = s$symbol,
                                                                                            conns = s$conns))
  if (ml$ok) {
    sym <- ml$value$meta$assign_symbol
    r <- capture_ds("S1: weighted numeric histogram of value_as_number (records)", ds.omop.dp.release(sym, omop_privacy(
      "numeric_histogram", variable = "value_as_number", breaks = c(0, 10, 50, 100, 500, 1000), reducer = "records",
      max_contributions = 10, population_id = "g_meas"), datasources = s$conns))
    if (r$ok) remember(r$value)
    p <- if (r$ok) r$value$per_site[[1]] else NULL
    pl <- if (r$ok) r$value$pooled else NULL
    eq <- r$ok && is.numeric(p$counts) && is.numeric(pl$counts) && length(p$counts) == length(pl$counts) &&
      all(abs(p$counts - pl$counts) <= pmax(0.01, 1e-6 * abs(p$counts)))
    verdict("G15c weighted_histogram", if (eq) "PASS" else "FAIL",
            "a weighted numeric histogram pooled over one site equals that site's histogram",
            if (r$ok) sprintf("site [%s]; pooled [%s]", paste(p$counts, collapse = ", "), paste(pl$counts, collapse = ", ")) else r$error)
  } else verdict("G15c weighted_histogram", "FAIL", "a weighted numeric histogram pooled over one site equals the site", ml$error)
})

section("G11", "no admission history: many distinct questions, then the same answer to the first", function() {
  s <- INFO$s1
  if (!isTRUE(s$ok)) stop("no S1 session")
  years <- 1981:2020
  ok <- vapply(years, function(y) capture(paste0("S1: age_distribution_decade reference_year ", y),
                                          raw_run(s, "dsomop:person.age_distribution_decade", list(reference_year = as.character(y))))$ok,
               logical(1))
  again <- probe_one(s, "catalog", FIXED_Q$age_decade, list())
  typed_again <- if (!is.na(S1_OBJ$loader)) probe_one(s, "typed", TYPED_Q$loader_count, S1_OBJ) else list(ok = FALSE, error = "no loader")
  c1 <- isTRUE(again$ok) && isTRUE(S1_PROBES$age_decade$ok) && identical(again$per[[1]]$answer, S1_PROBES$age_decade$per[[1]]$answer)
  c2 <- isTRUE(typed_again$ok) && isTRUE(S1_PROBES$loader_count$ok) &&
    identical(typed_again$per[[1]]$answer, S1_PROBES$loader_count$per[[1]]$answer)
  verdict("G11", if (all(ok) && c1 && c2) "PASS" else "FAIL",
          "after 40 distinct valid questions every question still answers and the first answers are unchanged",
          sprintf("%d/%d answered; reference catalogue answer %s; typed answer %s", sum(ok), length(ok),
                  if (c1) "unchanged" else "CHANGED or failed", if (c2) "unchanged" else "CHANGED or failed"))
})

section("G5a", "save a workspace holding the sealed tables", function() {
  s <- INFO$s1
  if (is.null(s$conns)) stop("no S1 session")
  show("S1 symbols before saving", DSI::datashield.symbols(s$conns))
  r <- capture_ds(paste0("S1: DSI::datashield.workspace_save(conns, \"", WS, "\")"), DSI::datashield.workspace_save(s$conns, WS))
  INFO$ws_saved <<- r$ok
  if (!r$ok) verdict("G5", "FAIL", "a workspace with sealed tables can be saved", r$error)
  close_session(s)
  INFO$s1 <<- NULL
})

section("G3c3", "a second analyst session (another R process) gets the reference answers", function() {
  s <- open_session("S2")
  on.exit(close_session(s))
  if (!s$ok) stop("S2 cannot connect: ", s$error)
  obj <- make_objects(s)
  p <- run_probes(s, obj)
  show("S2 probes", probe_table(p))
  equality_verdict("G3c3", "answers in a new analyst session equal the reference session's",
                   compare_probes(S1_PROBES, p), compare_probes(S1_PROBES, p, "full"))
  equality_verdict("G4c", "answers of the concurrent two-user sessions (G4) equal the reference session's",
                   compare_probes(S1_PROBES, INFO$pair_probes))
  rep1 <- probe_one(s, "catalog", FIXED_Q[[1]], obj)
  INFO$timing$S2 <<- c(first = first_fixed_secs(p), repeat_secs = rep1$secs %||% NA)
})

section("G5b", "restore the workspace: sealed tables (capsule v3) release as before", function() {
  if (!isTRUE(INFO$ws_saved)) stop("no saved workspace")
  s <- open_session("S3 restored", restore = WS)
  on.exit(close_session(s))
  have <- if (!is.null(s$conns)) unlist(DSI::datashield.symbols(s$conns)) else character(0)
  restored <- c(S1_OBJ$loader, S1_OBJ$prepared)
  verdict("G5 symbols", if (all(restored %in% have)) "PASS" else "FAIL", "the sealed tables are in the restored session",
          paste("restored:", paste(intersect(restored, have), collapse = ", "), "| missing:", paste(setdiff(restored, have), collapse = ", ")))
  if (!s$ok) stop("the restored session cannot connect: ", s$error)
  p <- run_probes(s, list(loader = S1_OBJ$loader, prepared = S1_OBJ$prepared), sets = "typed")
  show("S3 typed probes on the restored tables", probe_table(p))
  equality_verdict("G5", "typed releases of tables restored from a saved workspace equal the releases before saving",
                   compare_probes(S1_PROBES, p), compare_probes(S1_PROBES, p, "full"))
})

section("G19", "a changed snapshot label: in an open session, in a new session, and restoring a sealed table", function() {
  # Expected: the label is display only. A changed label changes no answer, route or admission (no refusal, no
  # "policy changed" fallback, no provenance mismatch).
  s <- open_session("G19 open session")
  on.exit(close_session(s), add = TRUE)
  if (!s$ok) stop("cannot connect: ", s$error)
  obj <- make_objects(s, prepared = "G_ages19")
  pa <- run_probes(s, obj)
  la <- capture_ds("G19: status before the label change", raw_status(s))
  orig <- psql_value("SELECT cdm_source_name FROM cdm.cdm_source LIMIT 1")
  restore_label <- function() psql(sprintf("UPDATE cdm.cdm_source SET cdm_source_name = %s", sql_quote(orig)), label = "restore cdm_source_name")
  on.exit(try(restore_label(), silent = TRUE), add = TRUE)
  psql(sprintf("UPDATE cdm.cdm_source SET cdm_source_name = %s", sql_quote(paste0(orig, " (e2e relabel)"))),
       label = "change cdm_source_name (the derived snapshot label's input)")
  lb <- capture_ds("G19: status after the label change, same session", raw_status(s))
  pb <- run_probes(s, obj)
  show("G19 open-session probes after the label change", probe_table(pb))
  label_a <- if (la$ok) la$value[[1]]$snapshot_id else NA
  label_b <- if (lb$ok) lb$value[[1]]$snapshot_id else NA
  verdict("G19b label", if (lb$ok) "INFO" else "FAIL", "the DP status in the open session after the label's input changed",
          sprintf("label before %s, after %s%s", label_a, label_b, if (!lb$ok) paste("; status refused:", last_server_error(lb$error)) else ""))
  tab <- compare_probes(pa, pb)
  tab_full <- compare_probes(pa, pb, "full")
  prot_same <- all(vapply(names(pa), function(k) isTRUE(pa[[k]]$ok) && isTRUE(pb[[k]]$ok) &&
                            identical(pa[[k]]$per[[1]]$protection, pb[[k]]$per[[1]]$protection), logical(1)))
  equality_verdict("G19b", "after the snapshot label changes in an open session, every answer and route is unchanged", tab, tab_full)
  verdict("G19b routes", if (prot_same) "PASS" else "FAIL", "the protection route of every question is unchanged after the label change",
          paste(names(pb), vapply(pb, function(p) if (isTRUE(p$ok)) p$per[[1]]$protection else paste("refused:", last_server_error(p$error)), ""),
                sep = "=", collapse = "; "))
  s2 <- open_session("G19 new session after the label change")
  p2 <- if (s2$ok) run_probes(s2, make_objects(s2)) else list()
  close_session(s2)
  equality_verdict("G19b2", "a new session after the label change gets the reference answers (the label is not data)",
                   compare_probes(S1_PROBES, p2))
  restore_label()
  if (!isTRUE(INFO$ws_saved)) return(invisible())
  set_option("dsomop.dp.snapshot_id", "\"e2e-label-two\"")
  on.exit(rm_option("dsomop.dp.snapshot_id"), add = TRUE)
  sr <- open_session("G19 restored after a label change", restore = WS)
  pr <- if (sr$ok) run_probes(sr, list(loader = S1_OBJ$loader, prepared = S1_OBJ$prepared, cohorts = list()),
                              sets = c("fixed", "typed")) else list()
  stl <- if (sr$ok) capture_ds("G19: status with the deprecated label option", raw_status(sr)) else sr
  close_session(sr)
  equality_verdict("G19c", "a v3 sealed table restored after a label change (deprecated option) releases as before; fixed answers unchanged",
                   compare_probes(S1_PROBES, pr), compare_probes(S1_PROBES, pr, "full"))
  verdict("G19c label", "INFO", "the status label with dsomop.dp.snapshot_id set",
          if (stl$ok) paste("snapshot_id", stl$value[[1]]$snapshot_id) else paste("refused:", last_server_error(stl$error)))
})

section("G3a", "DP-only mode with no custodial setting besides the switch", function() {
  set_option("dsomop.dp.exclusive", "TRUE")
  on.exit(rm_option("dsomop.dp.exclusive"), add = TRUE)
  opts <- tryCatch(dsadmin.get_options(O), error = function(e) NULL)
  custodial <- if (is.data.frame(opts)) opts$name[grepl("dsomop", opts$name) & !startsWith(opts$name, "default.")] else NA
  s <- open_session("S4 DP-only", restore = if (isTRUE(INFO$ws_saved)) WS else NULL)
  on.exit(close_session(s), add = TRUE)
  if (!s$ok) stop("the DP-only session cannot connect: ", s$error)
  st <- capture_ds("S4: omopDpStatusDS()", raw_status(s))
  stv <- if (st$ok) st$value[[1]] else list()
  mode_ok <- identical(stv$tools_mode, "dp") && identical(stv$exclusive, TRUE) && identical(stv$ready, TRUE)
  verdict("G3a1", if (mode_ok) "PASS" else "FAIL", "the switch alone puts the community tools in DP-only mode",
          sprintf("custodial dsOMOP options: %s; tools_mode %s, exclusive %s, ready %s, noise provider %s",
                  paste(custodial, collapse = ", "), stv$tools_mode %||% NA, stv$exclusive %||% NA, stv$ready %||% NA,
                  stv$noise_provider %||% NA))
  obj <- make_objects(s, prepared = NULL, loader = FALSE)
  obj$loader <- S1_OBJ$loader
  obj$prepared <- S1_OBJ$prepared
  fixed <- run_probes(s, obj, sets = "fixed")
  show("S4 fixed probes", probe_table(fixed))
  prot <- vapply(fixed, function(p) if (isTRUE(p$ok)) unique(vapply(p$per, `[[`, "", "protection"))[1] else "", "")
  equality_verdict("G3a2", "fixed synopses answer in DP-only mode, identical to auto mode", compare_probes(S1_PROBES, fixed))
  verdict("G3a3", if (length(prot) && all(prot == "fixed_synopsis")) "PASS" else "FAIL", "DP-only answers are all fixed synopses",
          paste(names(prot), prot, sep = "=", collapse = ", "))
  scoped <- run_probes(s, obj, sets = c("scoped", "realised"))
  refused <- vapply(scoped, function(p) !isTRUE(p$ok) && grepl("DP-only|fixed-synopsis|exclusive", p$error) && plain_error(p$error), logical(1))
  verdict("G3a4", if (length(refused) && all(refused)) "PASS" else "FAIL",
          "realised questions (scoped or data-enumerated) are refused in DP-only mode with a stable message",
          paste(names(scoped), vapply(scoped, function(p) if (isTRUE(p$ok)) "ANSWERED" else last_server_error(p$error), ""), sep = ": ", collapse = "; "))
  if (isTRUE(INFO$ws_saved)) {
    typed <- run_probes(s, obj, sets = "typed")
    show("S4 typed probes on the restored tables", probe_table(typed))
    lt <- compare_probes(S1_PROBES, typed, keys = c("loader_count", "loader_records"))
    lp <- vapply(typed[c("loader_count", "loader_records")], function(p) if (isTRUE(p$ok)) p$per[[1]]$protection else "", "")
    verdict("G3a5", if (all(lt$equal) && all(lp == "fixed_synopsis")) "PASS" else "FAIL",
            "typed counts of a restored pinned loader table release as fixed synopses in DP-only mode, equal to auto mode",
            paste(lt$probe, ifelse(lt$equal, "equal", lt$detail), lp, sep = " ", collapse = "; "))
    pr <- typed[c("prepared_count", "prepared_hist")]
    pref <- vapply(pr, function(p) !isTRUE(p$ok) && grepl("no fixed-synopsis protection|DP-only", p$error) && plain_error(p$error), logical(1))
    verdict("G3a6", if (all(pref)) "PASS" else "FAIL", "typed releases of a prepared (realised) table are refused in DP-only mode with the stable message",
            paste(names(pr), vapply(pr, function(p) if (isTRUE(p$ok)) "RELEASED" else last_server_error(p$error), ""), sep = ": ", collapse = "; "))
  }
  ld <- capture_ds("S4: pinned loader dsomop:condition_occurrence.load in DP-only mode",
                   ds.omop.analysis.run("dsomop:condition_occurrence.load", type = "split", symbol = s$symbol, conns = s$conns))
  lc <- if (ld$ok) probe_one(s, "typed", TYPED_Q$loader_count, list(loader = ld$value$meta$assign_symbol)) else NULL
  verdict("G3a7", if (ld$ok && isTRUE(lc$ok) && identical(lc$per[[1]]$protection, "fixed_synopsis")) "PASS" else "FAIL",
          "a fresh DP-only session can create the pinned loader table its typed fixed synopses need, and release its count",
          if (!ld$ok) paste("loader refused:", last_server_error(ld$error)) else
            if (!isTRUE(lc$ok)) paste("count refused:", squash(lc$error, 300)) else paste("count released as", lc$per[[1]]$protection))
})

section("G9", "community tools disabled: the gate comes first, the core keeps working", function() {
  set_option("dsomop.tools.enabled", "FALSE")
  on.exit(rm_option("dsomop.tools.enabled"), add = TRUE)
  s <- open_session("S5 tools disabled")
  on.exit(close_session(s), add = TRUE)
  t <- if (s$ok) capture_ds("S5: ds.omop.tables (core)", ds.omop.tables(symbol = s$symbol, conns = s$conns)) else s
  gate_re <- "community tools .* are disabled|tools are disabled|dsomop.tools.enabled"
  rel <- capture_ds("S5: omopDpReleaseDS on a symbol that does not exist", raw_typed(s, "g_no_such_table", TYPED_Q$loader_count$spec))
  cat_r <- if (s$ok) capture_ds("S5: achilles.3", raw_run(s, "dsomop:achilles.3")) else s
  stq <- capture_ds("S5: omopDpStatusDS()", raw_status(s))
  ok <- isTRUE(s$ok) && isTRUE(t$ok) && !rel$ok && grepl(gate_re, rel$error) && !grepl("not found", rel$error) &&
    !cat_r$ok && grepl(gate_re, cat_r$error) && !stq$ok && grepl(gate_re, stq$error)
  verdict("G9", if (ok) "PASS" else "FAIL",
          "with the tools disabled: connect and tables work; typed release, catalogue and DP status are refused by the gate before any argument is read",
          sprintf("connect %s; tables %s; typed release: %s; catalogue: %s; status: %s", s$ok, t$ok,
                  if (rel$ok) "RELEASED" else last_server_error(rel$error), if (cat_r$ok) "ANSWERED" else last_server_error(cat_r$error),
                  if (stq$ok) "ANSWERED" else last_server_error(stq$error)))
  INFO$g9_time <<- Sys.time()
})

section("G21", "generation replay across data loads, in-place edits and person changes", function() {
  # Expected (2.10.3 round 3: a per-request person-membership digest, no session cache): an unrelated clinical insert,
  # an in-place edit and their undo redraw nothing, on the warm worker's old handle, a new handle and a new session; a
  # person insert, a person delete and a balanced replacement (same count and largest id) redraw every fixed synopsis,
  # the same way in all three; undoing a change restores the original answers exactly.
  ids <- strsplit(psql_value(paste0(
    "SELECT (SELECT min(person_id) FROM cdm.person) || '|' || (SELECT max(person_id) FROM cdm.person) || '|' || ",
    "(SELECT max(procedure_occurrence_id) FROM cdm.procedure_occurrence) || '|' || ",
    "(SELECT max(observation_period_id) FROM cdm.observation_period) || '|' || ",
    "(SELECT person_id FROM cdm.person ORDER BY person_id OFFSET 10 LIMIT 1) || '|' || ",
    "COALESCE((SELECT min(g) FROM generate_series(1, (SELECT max(person_id) FROM cdm.person)::int) g ",
    "WHERE NOT EXISTS (SELECT 1 FROM cdm.person WHERE person_id = g)), 0)")), "|", fixed = TRUE)[[1]]
  ids <- stats::setNames(as.numeric(ids), c("pmin", "pmax", "proc_max", "op_max", "victim", "gap"))
  show("ids used by the data changes", ids)
  victim_json <- psql_value(sprintf("SELECT row_to_json(p)::text FROM cdm.person p WHERE person_id = %.0f", ids[["victim"]]))
  keys <- c(names(FIXED_Q), "incidence", "loader_count")
  so <- open_session("R-old")
  on.exit(close_session(so), add = TRUE)
  if (!so$ok) stop("cannot connect: ", so$error)
  oobj <- make_objects(so, prepared = NULL)
  R0 <- run_probes(so, oobj, keys = keys)
  equality_verdict("G21 st0", "before any change the warm worker's answers equal the reference session's", compare_probes(S1_PROBES, R0))
  measure <- function(tag) {
    out <- list(old_handle = run_probes(so, oobj, keys = keys))
    h <- so
    h$label <- paste0(tag, " new handle")
    h <- connect_session(h)
    out$new_handle <- if (h$ok) {
      hobj <- make_objects(h, prepared = NULL, loader = FALSE)
      hobj$loader <- oobj$loader
      run_probes(h, hobj, keys = keys)
    } else list()
    disconnect_session(h)
    s <- open_session(paste0(tag, " new session"))
    out$new_session <- if (s$ok) run_probes(s, make_objects(s, prepared = NULL), keys = keys) else list()
    close_session(s)
    out
  }
  judge_replay <- function(id, title, m) {
    tab <- do.call(rbind, lapply(names(m), function(ctx) { t <- compare_probes(R0, m[[ctx]], keys = keys); t$probe <- paste0(ctx, ":", t$probe); t }))
    equality_verdict(id, title, tab)
  }
  fixed_keys <- names(FIXED_Q)
  judge_redraw <- function(id, title, m) {
    # Only the live fixed questions are comparable across contexts: the old handle's cohorts and loader table were
    # materialised before the change.
    agree <- rbind(compare_probes(m$old_handle, m$new_handle, keys = fixed_keys),
                   compare_probes(m$old_handle, m$new_session, keys = fixed_keys))
    ch <- lapply(fixed_keys, function(k) {
      a <- R0[[k]]
      b <- m$new_session[[k]]
      if (!isTRUE(a$ok) || !isTRUE(b$ok)) return(c(cells = NA, changed = NA))
      g_component_changes(a$value[[1]], b$value[[1]])
    })
    names(ch) <- fixed_keys
    redrawn <- vapply(ch, function(x) is.finite(x[["cells"]]) && x[["cells"]] >= 1 && x[["changed"]] > x[["cells"]] / 2, logical(1))
    eligible <- vapply(ch, function(x) is.finite(x[["cells"]]) && x[["cells"]] >= 1, logical(1))
    ok <- all(agree$equal) && all(eligible) && all(redrawn)
    verdict(id, if (ok) "PASS" else "FAIL", title,
            sprintf("old handle, new handle and new session agree: %s%s; fixed synopses redrawn (changed/signed components vs before): %s",
                    all(agree$equal), if (any(!agree$equal)) paste0(" (", paste(agree$probe[!agree$equal], collapse = ","), ")") else "",
                    paste(fixed_keys, vapply(ch, function(x) paste0(x[["changed"]], "/", x[["cells"]]), ""), sep = " ", collapse = "; ")))
  }
  state <- function(tag, sql) { psql(sql, label = tag); measure(tag) }
  proc_id <- ids[["proc_max"]] + 1
  undo <- character(0)
  on.exit(for (u in rev(undo)) try(psql(u, label = "undo"), silent = TRUE), add = TRUE)
  undo <- c(undo, sprintf("DELETE FROM cdm.procedure_occurrence WHERE procedure_occurrence_id = %.0f", proc_id))
  m1 <- state("st1 unrelated insert", sprintf(paste0(
    "INSERT INTO cdm.procedure_occurrence (procedure_occurrence_id, person_id, procedure_concept_id, procedure_date, ",
    "procedure_type_concept_id, quantity) VALUES (%.0f, %.0f, 4127886, DATE '2015-06-15', 38000275, 1)"), proc_id, ids[["pmin"]]))
  judge_replay("G21 st1", "an unrelated clinical insert (a procedure row of an existing person) redraws nothing anywhere", m1)
  # G12: cache pressure on the warm worker right after the change.
  a1 <- run_probes(so, oobj, keys = "achilles_3")
  extra <- list()
  for (i in 1:17) {
    e <- so
    e$label <- paste0("R-old extra handle ", i)
    e <- connect_session(e)
    if (e$ok) { capture(paste0(e$label, ": achilles.3"), raw_run(e, "dsomop:achilles.3")); extra[[length(extra) + 1L]] <- e }
  }
  a2 <- run_probes(so, oobj, keys = "achilles_3")
  for (e in extra) disconnect_session(e)
  c12 <- rbind(compare_probes(a1, a2), compare_probes(a2, m1$new_session, keys = "achilles_3"))
  equality_verdict("G12", "after 17 more handles in the session (generation cache pressure), the old handle answers as before and as a new session",
                   c12)
  m2 <- state("st2 in-place edit", sprintf("UPDATE cdm.procedure_occurrence SET quantity = 2 WHERE procedure_occurrence_id = %.0f", proc_id))
  judge_replay("G21 st2", "an in-place edit of that unrelated row redraws nothing anywhere", m2)
  m3 <- state("st3 undo the insert", undo[length(undo)])
  undo <- undo[-length(undo)]
  judge_replay("G21 st3", "deleting the unrelated row again restores the original answers everywhere", m3)
  newp <- ids[["pmax"]] + 1
  undo <- c(undo, sprintf("BEGIN; DELETE FROM cdm.observation_period WHERE observation_period_id = %.0f; DELETE FROM cdm.person WHERE person_id = %.0f; COMMIT;",
                          ids[["op_max"]] + 1, newp))
  m4 <- state("st4 person insert", sprintf(paste0(
    "BEGIN; INSERT INTO cdm.person (person_id, gender_concept_id, year_of_birth, race_concept_id, ethnicity_concept_id) ",
    "VALUES (%.0f, 8532, 1955, 0, 0); INSERT INTO cdm.observation_period (observation_period_id, person_id, ",
    "observation_period_start_date, observation_period_end_date, period_type_concept_id) VALUES (%.0f, %.0f, ",
    "DATE '2000-01-01', DATE '2015-12-31', 44814724); COMMIT;"), newp, ids[["op_max"]] + 1, newp))
  judge_redraw("G21 st4", "a person insert redraws every fixed synopsis, identically on the old handle, a new handle and a new session", m4)
  m5 <- state("st5 person delete (undo)", undo[length(undo)])
  undo <- undo[-length(undo)]
  judge_replay("G21 st5", "deleting the inserted person restores the original answers everywhere", m5)
  restore_victim <- sprintf("INSERT INTO cdm.person SELECT * FROM json_populate_record(NULL::cdm.person, %s)", sql_quote(victim_json))
  undo <- c(undo, restore_victim)
  m6 <- state("st6 existing person deleted", sprintf("DELETE FROM cdm.person WHERE person_id = %.0f", ids[["victim"]]))
  judge_redraw("G21 st6", "deleting an existing person row redraws every fixed synopsis, identically everywhere", m6)
  m7 <- state("st7 person restored", restore_victim)
  undo <- undo[-length(undo)]
  judge_replay("G21 st7", "restoring that person row restores the original answers everywhere", m7)
  {
    repl <- ids[["gap"]]
    undo <- c(undo, sprintf("BEGIN; DELETE FROM cdm.person WHERE person_id = %.0f; %s; COMMIT;", repl, restore_victim))
    m8 <- state("st8 balanced replacement", sprintf(paste0(
      "BEGIN; DELETE FROM cdm.person WHERE person_id = %.0f; INSERT INTO cdm.person (person_id, gender_concept_id, ",
      "year_of_birth, race_concept_id, ethnicity_concept_id) SELECT %.0f, gender_concept_id, year_of_birth, race_concept_id, ",
      "ethnicity_concept_id FROM json_populate_record(NULL::cdm.person, %s); COMMIT;"), ids[["victim"]], repl, sql_quote(victim_json)))
    judge_redraw("G21 st8", sprintf("a balanced replacement (person %.0f out, person %.0f in: same count and largest id) redraws every fixed synopsis", ids[["victim"]], repl), m8)
    m9 <- state("st9 replacement undone", undo[length(undo)])
    undo <- undo[-length(undo)]
    judge_replay("G21 st9", "undoing the replacement restores the original answers everywhere", m9)
  }
  db1 <- psql_value(paste0("SELECT (SELECT count(*) FROM cdm.person) || '|' || (SELECT max(person_id) FROM cdm.person)",
                           " || '|' || (SELECT count(*) FROM cdm.procedure_occurrence) || '|' || ",
                           "(SELECT count(*) FROM cdm.condition_occurrence)"))
  verdict("G21 db", if (identical(db1, INFO$db0)) "INFO" else "ERROR", "the CDM is back to its state at the start of G",
          paste("start", INFO$db0, "now", db1))
})

section("G20", "another database user over the same CDM: corpus alias, source visibility, read-failure recovery", function() {
  sr <- open_session("Reader", resource = "omop_data.gibleed_reader")
  on.exit(close_session(sr), add = TRUE)
  if (!sr$ok) stop("the reader resource cannot connect: ", sr$error)
  p1 <- run_probes(sr, list(cohorts = list()), sets = "fixed")
  equality_verdict("G20a", "a session connecting as another database user (e2e_reader) over the same CDM gets the reference answers",
                   compare_probes(S1_PROBES, p1))
  on.exit(try(psql("GRANT SELECT ON ALL TABLES IN SCHEMA cdm TO e2e_reader", label = "re-grant e2e_reader"), silent = TRUE), add = TRUE)
  psql("REVOKE SELECT ON cdm.procedure_occurrence FROM e2e_reader", label = "hide procedure_occurrence from e2e_reader")
  h2 <- sr
  h2$label <- "Reader handle 2"
  h2 <- connect_session(h2, "omop_data.gibleed_reader")
  p2 <- if (h2$ok) run_probes(h2, list(cohorts = list()), sets = "fixed") else list()
  disconnect_session(h2)
  psql("GRANT SELECT ON cdm.procedure_occurrence TO e2e_reader", label = "show procedure_occurrence again")
  equality_verdict("G20b", "when that user cannot see an unrelated clinical table, the fixed answers are unchanged (one corpus)",
                   compare_probes(S1_PROBES, p2))
  h3 <- sr
  h3$label <- "Reader handle 3"
  h3 <- connect_session(h3, "omop_data.gibleed_reader")
  if (!h3$ok) stop("reader handle 3 cannot connect: ", h3$error)
  psql("REVOKE SELECT ON cdm.person FROM e2e_reader", label = "a transient read failure: person unreadable")
  f1 <- probe_one(h3, "catalog", FIXED_Q$achilles_3, list())
  psql("GRANT SELECT ON cdm.person TO e2e_reader", label = "person readable again")
  f2 <- probe_one(h3, "catalog", FIXED_Q$achilles_3, list())
  f3 <- probe_one(h3, "catalog", FIXED_Q$age_decade, list())
  disconnect_session(h3)
  ref1 <- S1_PROBES$achilles_3$per[[1]]$answer
  during_ok <- !isTRUE(f1$ok) || identical(f1$per[[1]]$answer, ref1)
  after_ok <- isTRUE(f2$ok) && identical(f2$per[[1]]$answer, ref1) && identical(f2$per[[1]]$protection, "fixed_synopsis") &&
    isTRUE(f3$ok) && identical(f3$per[[1]]$answer, S1_PROBES$age_decade$per[[1]]$answer)
  verdict("G20c", if (during_ok && after_ok) "PASS" else "FAIL",
          "a failed read fails only the current request; the same handle then answers as before (no remembered failure)",
          sprintf("during the failure: %s; after: %s (%s); another fixed question after: %s",
                  if (isTRUE(f1$ok)) if (identical(f1$per[[1]]$answer, ref1)) "same answer" else "A DIFFERENT ANSWER" else paste("refused:", last_server_error(f1$error)),
                  if (isTRUE(f2$ok)) if (identical(f2$per[[1]]$answer, ref1)) "same answer" else "a different answer" else paste("refused:", last_server_error(f2$error)),
                  if (isTRUE(f2$ok)) f2$per[[1]]$protection else "-",
                  if (isTRUE(f3$ok)) if (identical(f3$per[[1]]$answer, S1_PROBES$age_decade$per[[1]]$answer)) "same answer" else "a different answer" else "refused"))
})

section("G13", "a coherent snapshot under concurrent loads, with and without connection loss", function() {
  # Expected: while another connection commits "person + condition" in one transaction and removes them again, every
  # answer is the answer of one of the two states (or a whole-request failure), never a third (mixed) one.
  P <- 900000001
  B <- sprintf(paste0("BEGIN; INSERT INTO cdm.person (person_id, gender_concept_id, year_of_birth, race_concept_id, ",
                      "ethnicity_concept_id) VALUES (%.0f, 8532, 1955, 0, 0); INSERT INTO cdm.condition_occurrence ",
                      "(condition_occurrence_id, person_id, condition_concept_id, condition_start_date, condition_type_concept_id) ",
                      "VALUES (%.0f, %.0f, 192671, DATE '2010-05-05', 32020); COMMIT;"), P, P, P)
  A <- sprintf(paste0("BEGIN; DELETE FROM cdm.condition_occurrence WHERE condition_occurrence_id = %.0f; DELETE FROM ",
                      "cdm.person WHERE person_id = %.0f; COMMIT;"), P, P)
  on.exit(try(psql(A, label = "state A (cleanup)"), silent = TRUE), add = TRUE)
  psql(A, label = "state A")
  refA <- S1_PROBES$achilles_3$per[[1]]$answer
  psql(B, label = "state B (reference)")
  sb <- open_session("G13 state B reference")
  pb <- if (sb$ok) probe_one(sb, "catalog", FIXED_Q$achilles_3, list()) else list(ok = FALSE, error = sb$error)
  close_session(sb)
  psql(A, label = "state A")
  if (!isTRUE(pb$ok)) stop("no state B reference: ", pb$error)
  refB <- pb$per[[1]]$answer
  say("G13 references: A ", substr(refA, 1, 10), ", B ", substr(refB, 1, 10))
  toggle <- function(seconds, kill_every) {
    script <- paste0('end=$((SECONDS+', seconds, ')); i=0; while [ $SECONDS -lt $end ]; do ',
                     'psql -q -U omop -d "$DB" -c "$B" >/dev/null 2>&1; sleep 0.05; ',
                     'psql -q -U omop -d "$DB" -c "$A" >/dev/null 2>&1; sleep 0.05; i=$((i+1)); ',
                     'if [ "$K" -gt 0 ] && [ $((i % K)) -eq 0 ]; then psql -q -U omop -d "$DB" -c "SELECT pg_terminate_backend(pid) ',
                     'FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND datname = current_database() AND backend_type = ',
                     '\'client backend\' AND application_name <> \'psql\'" >/dev/null 2>&1; fi; done; ',
                     'psql -q -U omop -d "$DB" -c "$A" >/dev/null 2>&1; echo toggles=$i')
    f <- tempfile(fileext = ".log")
    system2("docker", c("exec", "-e", shQuote(paste0("A=", A)), "-e", shQuote(paste0("B=", B)), "-e", paste0("DB=", CDM_DB_NAME),
                        "-e", paste0("K=", kill_every), "omopdb", "bash", "-c", shQuote(script)), wait = FALSE, stdout = f, stderr = f)
    f
  }
  sample_run <- function(tag, seconds, kill_every) {
    s <- open_session(paste("G13", tag), servers = c("C1", "C2", "C3"))
    on.exit(close_session(s))
    if (!s$ok) stop("cannot connect: ", s$error)
    log <- toggle(seconds, kill_every)
    t_end <- Sys.time() + seconds - 3
    got <- character(0)
    errs <- character(0)
    while (Sys.time() < t_end) {
      h <- s
      h$label <- paste("G13", tag, "handle")
      h <- connect_session(h)
      for (hh in list(h, s)) {
        if (!isTRUE(hh$ok)) next
        r <- capture_ds(paste("G13", tag, "achilles.3"), raw_run(hh, "dsomop:achilles.3"))
        if (r$ok) got <- c(got, vapply(r$value, function(x) md5(canon(answer_of(x))), "")) else errs <- c(errs, r$error)
      }
      disconnect_session(h)
    }
    Sys.sleep(4)
    toggles <- paste(readLines(log, warn = FALSE), collapse = " ")
    cls <- ifelse(got == refA, "A", ifelse(got == refB, "B", "OTHER"))
    list(n = length(got), A = sum(cls == "A"), B = sum(cls == "B"), other = sum(cls == "OTHER"), errors = length(errs),
         crash = sum(!vapply(errs, plain_error, logical(1))), toggles = toggles,
         example_error = if (length(errs)) last_server_error(errs[[1]]) else "")
  }
  r1 <- sample_run("loads", 60, 0)
  verdict("G13a", if (r1$other == 0L && r1$n >= 10L && r1$crash == 0L) "PASS" else "FAIL",
          "under concurrent atomic loads every answer is one coherent state's (A or B) or a whole-request failure",
          sprintf("%d answers: %d state A, %d state B, %d MIXED; %d failed requests (%d crash-like)%s; %s", r1$n, r1$A, r1$B, r1$other,
                  r1$errors, r1$crash, if (nzchar(r1$example_error)) paste0(" e.g. ", r1$example_error) else "", r1$toggles))
  r2 <- sample_run("loads + connection loss", 40, 15)
  verdict("G13b", if (r2$other == 0L && r2$crash == 0L) "PASS" else "FAIL",
          "with database connections killed during the loads, answers are still one state's or a whole-request failure",
          sprintf("%d answers: %d state A, %d state B, %d MIXED; %d failed requests (%d crash-like)%s; %s", r2$n, r2$A, r2$B, r2$other,
                  r2$errors, r2$crash, if (nzchar(r2$example_error)) paste0(" e.g. ", r2$example_error) else "", r2$toggles))
  psql(A, label = "state A")
  s <- open_session("G13 after")
  pa <- if (s$ok) probe_one(s, "catalog", FIXED_Q$achilles_3, list()) else list(ok = FALSE)
  close_session(s)
  verdict("G13 after", if (isTRUE(pa$ok) && identical(pa$per[[1]]$answer, refA)) "PASS" else "FAIL",
          "after the loads stop, a new session gets state A's answer again", if (isTRUE(pa$ok)) "checked" else "failed")
})

section("G14", "NA pooling policies over two independent sites (GiBleed and a 150-person copy)", function() {
  # Expected: with one site's protected effect NA, strict pooling gives no pooled effect (with a message) and
  # pooled_only_ok pools the other site with "Dropped server(s) with suppressed per-site estimate".
  s <- open_session("G14 two sites", servers = c("Ethiopia", "Small"),
                    resource = c(Ethiopia = RES, Small = "omop_data.gibleed_small"))
  on.exit(close_session(s))
  if (!s$ok) stop("the two sites cannot connect: ", s$error)
  obj <- make_objects(s, prepared = NULL, loader = FALSE)
  arms <- unname(obj$cohorts[c("T", "C")])
  found <- NULL
  for (cand in list(list(model_type = "poisson", tar = TAR730), list(model_type = "cox", tar = TAR730),
                    list(model_type = "poisson", tar = TAR365))) {
    params <- c(list(outcome_concept_id = "192671", model_type = cand$model_type), cand$tar)
    r <- capture_ds(paste("G14 per-site effect,", cand$model_type, cand$tar$tar_end_offset), raw_run(s, "dsomop:cm.effect_estimate", params, arms))
    if (!r$ok) next
    fin <- vapply(r$value, function(df) is.data.frame(df) && any(is.finite(suppressWarnings(as.numeric(df$estimate)))), logical(1))
    say("finite per-site estimate: ", paste(names(fin), fin, collapse = ", "))
    if (isTRUE(fin[["Ethiopia"]]) && !isTRUE(fin[["Small"]])) { found <- params; break }
  }
  if (is.null(found)) {
    verdict("G14", "INFO", "NA pooling policies", "no candidate gave a finite GiBleed estimate and an NA small-site estimate (pattern not produced)")
    return(invisible())
  }
  st <- capture_ds("G14 strict", ds.omop.analysis.run("dsomop:cm.effect_estimate", params = found, cohort = arms,
                                                       pooling_policy = "strict", symbol = s$symbol, conns = s$conns))
  ok_only <- capture_ds("G14 pooled_only_ok", ds.omop.analysis.run("dsomop:cm.effect_estimate", params = found, cohort = arms,
                                                                    pooling_policy = "pooled_only_ok", symbol = s$symbol, conns = s$conns))
  pooled_est <- g_pooled_effect
  strict_ok <- (!st$ok && plain_error(st$error)) || (st$ok && !any(is.finite(pooled_est(st))))
  only_ok <- ok_only$ok && any(is.finite(pooled_est(ok_only))) && any(grepl("Dropped server", ok_only$value$meta$warnings))
  verdict("G14a strict", if (strict_ok) "PASS" else "FAIL", "strict pooling with one NA site gives no pooled effect, with a plain message",
          if (st$ok) paste0("pooled estimate ", paste(pooled_est(st), collapse = "/"), "; warnings: ", squash(st$value$meta$warnings, 300)) else st$error)
  verdict("G14b pooled_only_ok", if (only_ok) "PASS" else "FAIL", "pooled_only_ok pools the finite site and names the dropped one",
          if (ok_only$ok) paste0("pooled estimate ", paste(pooled_est(ok_only), collapse = "/"), "; warnings: ", squash(ok_only$value$meta$warnings, 300)) else ok_only$error)
})

section("G16", "cold and warm first-release latency (GiBleed, and a synthetic CDM of BIG_PERSONS persons)", function() {
  pg_stats <- function(db) {
    Sys.sleep(2)
    x <- psql(paste0("SELECT relname || '|' || seq_scan || '|' || seq_tup_read || '|' || coalesce(idx_scan, 0) || '|' || ",
                     "coalesce(idx_tup_fetch, 0) || '|' || n_live_tup FROM pg_stat_user_tables WHERE schemaname = 'cdm' ORDER BY relname"),
              db = db, label = "pg_stat_user_tables")
    x <- x[grepl("\\|", x)]
    df <- utils::read.table(text = x, sep = "|", col.names = c("table", "seq_scan", "seq_read", "idx_scan", "idx_fetch", "rows"),
                            stringsAsFactors = FALSE)
    df
  }
  measure_db <- function(tag, res, db) {
    st0 <- pg_stats(db)
    s <- open_session(paste("latency", tag), resource = res)
    on.exit(close_session(s))
    if (!s$ok) return(list(error = s$error))
    cold <- probe_one(s, "catalog", FIXED_Q$achilles_3, list())
    st1 <- pg_stats(db)
    warm <- probe_one(s, "catalog", FIXED_Q$achilles_3, list())
    warm2 <- probe_one(s, "catalog", FIXED_Q$age_decade, list())
    close_session(s)
    on.exit(NULL)
    d <- merge(st0, st1, by = "table", suffixes = c(".0", ".1"))
    d$read <- (d$seq_read.1 - d$seq_read.0) + (d$idx_fetch.1 - d$idx_fetch.0)
    d$scans <- (d$seq_scan.1 - d$seq_scan.0) + (d$idx_scan.1 - d$idx_scan.0)
    d <- d[d$scans > 0, c("table", "rows.1", "scans", "read")]
    d <- d[order(-d$read), , drop = FALSE]
    show(paste("tables read by the cold first release on", tag), d)
    s4 <- open_session(paste("latency x4", tag), servers = paste0("L", 1:4), resource = res)
    c4 <- if (s4$ok) capture_ds(paste("latency", tag, "4 concurrent cold first releases"), raw_run(s4, "dsomop:achilles.3")) else s4
    close_session(s4)
    plans <- tryCatch(psql(paste0("EXPLAIN (ANALYZE, BUFFERS, TIMING OFF) SELECT COUNT(*), MAX(person_id) FROM cdm.person; ",
                                  "EXPLAIN (ANALYZE, BUFFERS, TIMING OFF) SELECT person_id FROM cdm.person ORDER BY person_id; ",
                                  "EXPLAIN (ANALYZE, BUFFERS, TIMING OFF) SELECT COUNT(*), MAX(condition_occurrence_id) FROM cdm.condition_occurrence;"),
                           db = db, label = "scan plans"), error = function(e) conditionMessage(e))
    writeLines(plans, out_file(paste0("G16-plans-", tag, ".txt")))
    list(cold = cold$secs %||% NA, cold_ok = isTRUE(cold$ok), warm = warm$secs %||% NA, warm2 = warm2$secs %||% NA,
         x4 = if (isTRUE(c4$ok)) c4$secs else NA, x4_ok = isTRUE(c4$ok), tables = d,
         rows = sum(st1$rows), error = if (!isTRUE(cold$ok)) cold$error else "")
  }
  g <- measure_db("gibleed", RES, CDM_DB_NAME)
  verdict("G16a gibleed", if (isTRUE(g$cold_ok)) "INFO" else "FAIL", "first-release latency on GiBleed (2,694 persons)",
          sprintf("cold %s s, warm %s s, warm other question %s s, 4 concurrent cold %s s; CDM rows %s; tables read by the cold release: %s",
                  g$cold, g$warm, g$warm2, g$x4, g$rows, paste(utils::head(paste0(g$tables$table, ":", g$tables$read), 12), collapse = ", ")))
  if (!isTRUE(INFO$big)) {
    verdict("G16b big", "INFO", "first-release latency on a large synthetic CDM", "not run (no omopbig database: BIG_PERSONS = 0 or upgrade path)")
    return(invisible())
  }
  gen <- admin_handle_eval(paste0('local({ ', HANDLE_CODE, '
    ns <- asNamespace("dsOMOP")
    accelerated <- exists("C_dsomop_person_hmac", ns, inherits = FALSE) &&
      !is.null(.Call(get("C_dsomop_person_hmac", ns), "public-build-probe", raw(32)))
    list(hash_acceleration = accelerated,
         snapshot_seconds = system.time(dsOMOP:::.dsomopWithReadSnapshot(h, dsOMOP:::.dsomopDpMembershipHash(h)))[["elapsed"]]) })'), resource = "omop_data.gibleed_big")
  b <- measure_db("big", "omop_data.gibleed_big", "omopbig")
  ok <- isTRUE(b$cold_ok) && is.finite(b$cold) && b$cold <= 60 && is.finite(b$warm) && b$warm <= 15 && isTRUE(b$x4_ok) && b$x4 <= 120
  verdict("G16b big", if (ok) "PASS" else "FAIL",
          sprintf("first-release latency on %s synthetic persons: cold <= 60 s, warm <= 15 s, 4 concurrent cold <= 120 s", format(BIG_PERSONS, big.mark = ",")),
          sprintf("cold %s s, warm %s s, warm other question %s s, 4 concurrent cold %s s; generation snapshot alone on Rock %s s; hash acceleration %s; CDM rows %s; tables read by the cold release: %s%s",
                  b$cold, b$warm, b$warm2, b$x4, if (is.list(gen)) gen$snapshot_seconds else paste(gen, collapse = " "),
                  if (is.list(gen)) isTRUE(gen$hash_acceleration) else FALSE, b$rows,
                  paste(utils::head(paste0(b$tables$table, ":", b$tables$read), 12), collapse = ", "),
                  if (nzchar(b$error %||% "")) paste("; error", squash(b$error, 300)) else ""))
})

section("G3c4", "a Rock restart: the root persists and every answer is the same", function() {
  log_before <- rock_log()
  writeLines(log_before, out_file("rock-Rserve-before-restart.log"))
  st0 <- state_files()
  t0 <- Sys.time()
  out <- tryCatch(system2("docker", c("restart", ROCK), stdout = TRUE, stderr = TRUE), error = function(e) conditionMessage(e))
  say("docker restart ", ROCK, ": ", paste(out, collapse = " "))
  up <- FALSE
  for (i in 1:60) {
    Sys.sleep(5)
    v <- rock_eval("1 + 1")
    if (!inherits(v, "rock_error") && identical(as.numeric(v), 2)) { up <- TRUE; break }
  }
  say("Rock answers again after ", round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), " s: ", up)
  if (!up) stop("Rock did not come back after the restart")
  st1 <- state_files()
  same_root <- identical(root_line(st0), root_line(st1)) && length(root_line(st1)) == 1L
  s <- open_session("S6 after restart")
  if (!s$ok) stop("S6 cannot connect: ", s$error)
  stv <- capture_ds("S6: omopDpStatusDS()", raw_status(s))
  key_same <- stv$ok && identical(stv$value[[1]]$noise_key_id, S1_STATUS$noise_key_id)
  obj <- make_objects(s)
  p <- run_probes(s, obj)
  show("S6 probes", probe_table(p))
  INFO$timing$S6 <<- c(first = first_fixed_secs(p), repeat_secs = probe_one(s, "catalog", FIXED_Q[[1]], obj)$secs %||% NA)
  created_after <- sum(grepl(ROOT_CREATED_RE, g_new_log_lines(log_before, rock_log())))
  equality_verdict("G3c4", "after a Rock restart every answer equals the reference session's",
                   compare_probes(S1_PROBES, p), compare_probes(S1_PROBES, p, "full"))
  verdict("G3c4 root", if (same_root && key_same && created_after == 0L) "PASS" else "FAIL",
          "the noise root survives the restart (same file, same key id, no new root)",
          sprintf("root file before [%s] after [%s]; key id same: %s; root-creation lines in the new Rserve.log: %d; tools_mode now %s",
                  paste(root_line(st0), collapse = " "), paste(root_line(st1), collapse = " "), key_same, created_after,
                  if (stv$ok) stv$value[[1]]$tools_mode else "?"))
  INFO$s6 <<- s
})

section("G7", "the combined dsBase + dsOMOP method profile (recorded, never claimed safe)", function() {
  s <- INFO$s6
  on.exit(close_session(s))
  if (is.null(s) || !isTRUE(s$ok)) stop("no S6 session")
  agg <- dsadmin.get_methods(O, type = "aggregate")
  asg <- dsadmin.get_methods(O, type = "assign")
  show("published methods by package", table(c(agg$package, asg$package), useNA = "ifany"))
  base_agg <- agg$name[!is.na(agg$package) & agg$package == "dsBase"]
  overlap <- intersect(c(agg$name[agg$package %in% "dsBase"], asg$name[asg$package %in% "dsBase"]),
                       c(agg$name[agg$package %in% "dsOMOP"], asg$name[asg$package %in% "dsOMOP"]))
  exact <- intersect(base_agg, c("meanDS", "meanSdGpDS", "quantileMeanDS", "tableDS", "table1DDS", "table2DDS", "glmDS1",
                                 "glmDS2", "glmSLMADS2", "corDS", "covDS", "varDS", "histogramDS1", "histogramDS2", "rangeDS",
                                 "lengthDS", "numNaDS", "dimDS", "densityGridDS", "heatmapPlotDS", "scatterPlotDS", "kurtosisDS1",
                                 "skewnessDS1", "lmerSLMADS2", "glmerSLMADS2"))
  opts <- tryCatch(dsadmin.get_options(O), error = function(e) NULL)
  nf <- if (is.data.frame(opts)) opts[grepl("nfilter", opts$name), c("name", "value"), drop = FALSE] else NULL
  show("nfilter options in the combined profile", nf)
  ds_set <- capture_ds("S6: dsBase listDisclosureSettingsDS()", DSI::datashield.aggregate(s$conns, quote(listDisclosureSettingsDS())))
  om_set <- capture_ds("S6: ds.omop.disclosure.settings()", ds.omop.disclosure.settings(symbol = s$symbol, conns = s$conns))
  if (ds_set$ok) show("dsBase disclosure settings", ds_set$value)
  if (om_set$ok) show("dsOMOP disclosure settings", om_set$value)
  demo <- capture_ds("S6: recipe_execute(demographics -> G_demo6)", recipe_execute(omop_recipe(
    variables = list(omop_variable_age(), omop_variable_sex()), outputs = omop_output(name = "demo", type = "wide")),
    out = c(demo = "G_demo6"), symbol = s$symbol, conns = s$conns))
  mean_r <- if (demo$ok && "meanDS" %in% base_agg) {
    capture_ds("S6: dsBase meanDS(G_demo6$age) on a dsOMOP plan output", DSI::datashield.aggregate(s$conns, "meanDS(G_demo6$age)"))
  } else NULL
  verdict("G7", "INFO", "combined profile: dsBase methods next to dsOMOP's give exact statistics dsOMOP does not protect",
          sprintf("dsBase %s: %d aggregate + %d assign methods published next to dsOMOP's %d + %d; shared names: %s; exact dsBase aggregates enabled: %s; nfilter options: %s; dsBase meanDS on a dsOMOP table: %s",
                  rock_pkg_version("dsBase"), length(base_agg), sum(asg$package %in% "dsBase"), sum(agg$package %in% "dsOMOP"),
                  sum(asg$package %in% "dsOMOP"), if (length(overlap)) paste(overlap, collapse = ", ") else "none",
                  paste(exact, collapse = ", "), if (is.data.frame(nf)) paste(nf$name, nf$value, sep = "=", collapse = ", ") else "?",
                  if (is.null(mean_r)) "not run" else if (mean_r$ok) paste("returned", squash(capture.output(str(mean_r$value[[1]])), 200)) else paste("refused:", squash(mean_r$error, 200))))
})

AUDIT <- character(0)
section("G8", "audit lines in Rock's Rserve.log", function() {
  before <- if (file.exists(out_file("rock-Rserve-before-restart.log"))) readLines(out_file("rock-Rserve-before-restart.log")) else character(0)
  now <- rock_log()
  writeLines(now, out_file("rock-Rserve-after-restart.log"))
  lines <- unique(c(before, now))
  audit <- grep("^\\[dsomop-audit\\] ", lines, value = TRUE)
  when <- as.POSIXct(sub("^\\[dsomop-audit\\] (\\S+) .*", "\\1", audit), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  g <- audit[!is.na(when) & when >= G_START - 5]
  AUDIT <<- g
  writeLines(g, out_file("G-audit-lines.txt"))
  methods <- sub("^.* method=(\\S+) .*$", "\\1", g)
  show("audit lines since G started, by method", sort(table(methods), decreasing = TRUE))
  rel <- grep("method=omopDpReleaseDS ", g, value = TRUE)
  released <- sum(grepl("\"outcome\":\"released\"", rel))
  refused <- sum(grepl("\"outcome\":\"refused\"", rel))
  leaks <- g[g_private_hex(g)]
  gen_fail <- grep("\\[dsomop-dp-generation\\]", lines, value = TRUE)
  show("sample audit lines", utils::head(rel, 6))
  ok <- length(g) > 0L && released > 0L && refused > 0L && length(leaks) == 0L
  verdict("G8", if (ok) "PASS" else "FAIL",
          "audit lines reach Rock's log: typed releases released and refused, generic fields only",
          sprintf("%d audit lines since G started (%s); omopDpReleaseDS: %d released, %d refused; lines with long hex values: %d%s; generation-failure lines (G20 provokes one): %d%s",
                  length(g), paste(names(table(methods)), table(methods), sep = "=", collapse = ", "), released, refused,
                  length(leaks), if (length(leaks)) paste0(" e.g. ", squash(leaks[1], 300)) else "",
                  length(gen_fail), if (length(gen_fail)) paste0(" e.g. ", squash(gen_fail[1], 300)) else ""))
})

section("G18", "no private fingerprint, map or support in DSI success, error, status or audit payloads", function() {
  name_re <- paste0("fingerprint|person_token|token_map|release_person|person_map|contribution_map|membership_digest|",
                    "support_count|exact_support|generation_id|noise_root|root_key|secret")
  hits <- character(0)
  hex_paths <- character(0)
  raws <- 0L
  walk <- function(x, path) {
    if (is.raw(x)) { raws <<- raws + 1L; return(invisible()) }
    at <- attributes(x)
    for (a in setdiff(names(at), c("names", "row.names", "class", "dim", "dimnames", "levels", "tzone"))) walk(at[[a]], paste0(path, "@", a))
    if (is.list(x)) {
      nm <- names(x) %||% rep("", length(x))
      for (i in seq_along(x)) {
        p <- paste0(path, "$", if (nzchar(nm[[i]])) nm[[i]] else i)
        if (nzchar(nm[[i]]) && grepl(name_re, nm[[i]], ignore.case = TRUE) && length(x[[i]]) && !all(is.na(unlist(x[[i]])))) hits <<- c(hits, p)
        walk(x[[i]], p)
      }
    } else if (is.character(x) && any(grepl("[0-9a-f]{64}", x))) hex_paths <<- c(hex_paths, sub("\\$[0-9]+", "$#", path))
    invisible()
  }
  for (i in seq_along(OBJS)) walk(OBJS[[i]], paste0("obj", i))
  small <- ERRS[grepl("\\b(only |just )?[12] (person|persons|people|patient|patients|subject|subjects|record|records)\\b", ERRS, ignore.case = TRUE)]
  err_hex <- ERRS[grepl("[0-9a-f]{40,}", ERRS)]
  audit_hex <- AUDIT[g_private_hex(AUDIT)]
  public <- c("snapshot_id", "sql_sha256")
  odd_hex <- unique(hex_paths[!grepl(paste0("\\$(", paste(public, collapse = "|"), ")$"), hex_paths)])
  ok <- !length(hits) && !raws && !length(small) && !length(err_hex) && !length(audit_hex)
  verdict("G18", if (ok) "PASS" else "FAIL",
          "no private fingerprint, map or support in what the analyst received (successes, errors, status) or in the audit log",
          sprintf("%d received objects, %d error texts, %d audit lines; private-looking fields with values: %s; raw vectors: %d; small exact supports in errors: %s; long hex in errors: %d; in audit lines: %d",
                  length(OBJS), length(ERRS), length(AUDIT), if (length(hits)) paste(utils::head(unique(hits), 8), collapse = ", ") else "none",
                  raws, if (length(small)) squash(small[1], 200) else "none", length(err_hex), length(audit_hex)))
  verdict("G18 hex", "INFO", "where 64-hex values appear in what the analyst received (public labels expected)",
          if (length(odd_hex)) paste(utils::head(odd_hex, 15), collapse = ", ") else "only public labels (snapshot_id, sql_sha256) or none")
})

section("G22", "automatic vocabulary levels, their limit and model copies on a synthetic answer vocabulary (2.10.7)", function() {
  if (utils::packageVersion("dsOMOPClient") < "2.10.7") {
    verdict("G22", "INFO", "automatic vocabulary levels (dsOMOP 2.10.7)", "not run: the candidate client predates 2.10.7")
    return(invisible())
  }
  # omopauto: GiBleed's CDM plus a synthetic vocabulary E2EAuto whose answer classes hold 1,000, 5,000 and 14,000
  # concepts. Questions Q1-Q3 each have 1,000 people answering with 200 distinct answers of one class (more observed
  # levels than nfilter.levels.max); Q4 has 30 distinct answers of the 1,000 class.
  psql("CREATE DATABASE omopauto", db = "postgres", label = "create omopauto")
  copy <- suppressWarnings(system2("docker", c("exec", "omopdb", "bash", "-o", "pipefail", "-c",
    shQuote(paste0("pg_dump -U omop -d ", CDM_DB_NAME, " --schema=cdm | psql -v ON_ERROR_STOP=1 -q -U omop -d omopauto"))),
    stdout = TRUE, stderr = TRUE))
  if (!identical(as.integer(attr(copy, "status") %||% 0L), 0L)) stop("copying the CDM into omopauto failed: ", squash(copy, 300))
  psql(paste(
    "INSERT INTO cdm.vocabulary (vocabulary_id, vocabulary_name, vocabulary_reference, vocabulary_version, vocabulary_concept_id)",
    "VALUES ('E2EAuto', 'E2E synthetic answers', 'e2e', 'v1', 0);",
    "INSERT INTO cdm.concept (concept_id, concept_name, domain_id, vocabulary_id, concept_class_id, standard_concept,",
    "  concept_code, valid_start_date, valid_end_date, invalid_reason)",
    "SELECT 2100000000 + g, 'E2E answer ' || g, 'Observation', 'E2EAuto',",
    "  CASE WHEN g <= 1000 THEN 'Answer1k' WHEN g <= 6000 THEN 'Answer5k' ELSE 'Answer14k' END,",
    "  'S', 'A' || g, DATE '2000-01-01', DATE '2099-12-31', NULL FROM generate_series(1, 20000) g;",
    "INSERT INTO cdm.concept (concept_id, concept_name, domain_id, vocabulary_id, concept_class_id, standard_concept,",
    "  concept_code, valid_start_date, valid_end_date, invalid_reason)",
    "SELECT 2100100000 + q, 'E2E question ' || q, 'Observation', 'E2EAuto', 'Question', 'S', 'Q' || q,",
    "  DATE '2000-01-01', DATE '2099-12-31', NULL FROM generate_series(1, 4) q;",
    "INSERT INTO cdm.observation (observation_id, person_id, observation_concept_id, observation_date,",
    "  observation_type_concept_id, value_as_concept_id)",
    "SELECT 900000000 + q * 10000 + p.i, p.person_id, 2100100000 + q, p.d, 38000280,",
    "  2100000000 + CASE q WHEN 1 THEN 1 + (p.i % 200) WHEN 2 THEN 1001 + (p.i % 200) WHEN 3 THEN 6001 + (p.i % 200)",
    "  ELSE 1 + (p.i % 30) END",
    "FROM (SELECT person_id, d, row_number() OVER (ORDER BY person_id) AS i FROM",
    "  (SELECT DISTINCT ON (person_id) person_id, observation_period_start_date AS d FROM cdm.observation_period",
    "   ORDER BY person_id, observation_period_start_date) op) p, generate_series(1, 4) q WHERE p.i <= 1000;",
    "ANALYZE;"), db = "omopauto", label = "synthetic answer vocabulary and observations")
  capture("opal.resource_create(o, \"omop_data\", \"gibleed_auto\", ...)",
          opal.resource_create(O, "omop_data", "gibleed_auto", "omop+dbi:postgresql://omopdb:5432/omopauto?cdm_schema=cdm",
                               format = "omop.dbi.db", identity = "omop", secret = Sys.getenv("OMOPDB_PW")))
  capture("opal.resource_perm_add(o, \"omop_data\", \"gibleed_auto\", \"analyst\", \"view\")",
          opal.resource_perm_add(O, "omop_data", "gibleed_auto", subject = "analyst", type = "user", permission = "view"))
  question <- function(q) omop_variable(event = omop_event("observation", name = paste0("q", q),
                                                           concepts = omop_concept_set(2100100000L + q)),
                                        reducer = omop_reduce("first_value", value = "value_as_concept_id"))
  run <- function(s, q, out, spec = NULL) {
    v <- question(q)
    if (!is.null(spec)) v <- omop_category(v, spec)
    r <- omop_recipe(variables = list(v), outputs = omop_output(name = "auto", type = "wide"),
                     options = list(translate_concepts = FALSE))
    res <- capture_ds(sprintf("%s: recipe_execute(Q%d -> %s)", s$label, q, out),
                      recipe_execute(r, out = c(auto = out), symbol = s$symbol, conns = s$conns))
    book <- if (res$ok) tryCatch(recipe_codebook(res$value)[[1L]]$columns, error = function(e) NULL) else NULL
    lv <- if (!is.null(book)) book$levels[[match(paste0("q", q, "_first_value"), book$name)]] else NULL
    list(ok = res$ok, error = res$error, secs = res$secs, levels = length(lv$keys %||% lv$labels))
  }
  sites <- c("SiteA", "SiteB")
  s <- open_session("G22 default limit", servers = sites, resource = "omop_data.gibleed_auto")
  on.exit(close_session(s), add = TRUE)
  if (!isTRUE(s$ok)) stop("no G22 session: ", s$error)
  q1 <- run(s, 1L, "G_auto1k")
  verdict("G22a", if (q1$ok && q1$levels == 1000L) "PASS" else "FAIL",
          "200 observed answers of a 1,000-answer class publish with that class declared automatically, at every site",
          sprintf("published: %s; levels: %d; %.1f s; %s", q1$ok, q1$levels, q1$secs, if (!q1$ok) last_server_error(q1$error) else ""))
  q2 <- run(s, 2L, "G_auto5k")
  verdict("G22a2", if (q2$ok && q2$levels == 5000L) "PASS" else "FAIL",
          "a 5,000-answer class is within the default limit (10,000) and publishes the same way",
          sprintf("published: %s; levels: %d; %.1f s; %s", q2$ok, q2$levels, q2$secs, if (!q2$ok) last_server_error(q2$error) else ""))
  q3 <- run(s, 3L, "G_auto14k")
  msg <- q3$error %||% ""
  verdict("G22b", if (!q3$ok && grepl("dsomop.auto_declared_levels_max", msg, fixed = TRUE) && plain_error(msg) &&
                      !grepl("[0-9]+ (levels|rows|persons|concepts)", msg)) "PASS" else "FAIL",
          "a 14,000-answer class is longer than the default limit: refused, naming dsomop.auto_declared_levels_max, without counts",
          squash(last_server_error(msg), 600))
  keys <- paste0("concept:", 2100000000L + 1:1000)
  q4 <- run(s, 4L, "G_auto_declared", omop_category_spec(levels = keys))
  dl <- capture_ds("G22: ds.omop.drop_empty_levels(G_auto_declared -> G_auto_model)",
                   ds.omop.drop_empty_levels("G_auto_declared", newobj = "G_auto_model", symbol = s$symbol, conns = s$conns))
  kept <- if (dl$ok) dl$value$kept[dl$value$column == "q4_first_value"] else NA_integer_
  lv <- capture_ds("G22: dsBaseClient::ds.levels(G_auto_model$q4_first_value)",
                   dsBaseClient::ds.levels("G_auto_model$q4_first_value", datasources = s$conns))
  n_lv <- if (lv$ok) unique(vapply(lv$value, function(x) length(x$Levels %||% x[[1L]]), 1L)) else NA_integer_
  blocked <- capture_ds("G22: ds.omop.drop_empty_levels(G_auto1k -> G_auto1k_model)",
                        ds.omop.drop_empty_levels("G_auto1k", newobj = "G_auto1k_model", symbol = s$symbol, conns = s$conns))
  status1k <- if (blocked$ok) blocked$value$status[blocked$value$column == "q1_first_value"] else ""
  verdict("G22c", if (q4$ok && q4$levels == 1000L && dl$ok && identical(kept, 30L) && identical(n_lv, 30L) &&
                      blocked$ok && grepl("DataSHIELD level rule", status1k)) "PASS" else "FAIL",
          "a model copy keeps only the levels that hold a value at some site; levels in use over the rule are kept",
          sprintf("declared %d; kept %s; dsBase levels %s; 200 answers in use: %s", q4$levels, kept, paste(n_lv, collapse = "/"),
                  if (blocked$ok) status1k else last_server_error(blocked$error)))
  close_session(s)
  # The limit is practical, not a disclosure control: measure longer lists end to end.
  set_option("dsomop.auto_declared_levels_max", "20000")
  on.exit(rm_option("dsomop.auto_declared_levels_max"), add = TRUE)
  s2 <- open_session("G22 raised limit", servers = sites, resource = "omop_data.gibleed_auto")
  on.exit(close_session(s2), add = TRUE)
  if (!isTRUE(s2$ok)) stop("no G22 raised-limit session: ", s2$error)
  q3b <- run(s2, 3L, "G_auto14k_raised")
  verdict("G22d", if (q3b$ok && q3b$levels == 14000L) "PASS" else "FAIL",
          "with the server option raised, 14,000 declared levels publish identically at every site",
          sprintf("14k: %s, %d levels, %.1f s; %s", q3b$ok, q3b$levels, q3b$secs, if (!q3b$ok) last_server_error(q3b$error) else ""))
  verdict("G22e", "INFO", "end-to-end publication time by declared list length (two connections, translate_concepts = FALSE)",
          sprintf("1,000 levels %.1f s; 5,000 levels %.1f s; 14,000 levels %.1f s", q1$secs, q2$secs, q3b$secs))
})

section("G23", "adaptive hierarchy levels, fingerprint transport and verbs on published outputs (2.10.8)", function() {
  if (utils::packageVersion("dsOMOPClient") < "2.10.8") {
    verdict("G23", "INFO", "adaptive levels and fingerprints (dsOMOP 2.10.8)", "not run: the candidate client predates 2.10.8")
    return(invisible())
  }
  if (!identical(psql_value("SELECT count(*) FROM pg_database WHERE datname = 'omopauto'", db = "postgres"), "1"))
    stop("G23 needs the omopauto database that G22 builds")
  # A hierarchy E2EHier: root, 5 groups, 50 subgroups (10 per group), 5,000 leaves (100 per subgroup), all answers of
  # question Q5; 1,000 people answer with 60 leaves spread over subgroups 1-6.
  psql(paste(
    "INSERT INTO cdm.vocabulary (vocabulary_id, vocabulary_name, vocabulary_reference, vocabulary_version, vocabulary_concept_id)",
    "VALUES ('E2EHier', 'E2E synthetic hierarchy', 'e2e', 'v1', 0);",
    "INSERT INTO cdm.concept (concept_id, concept_name, domain_id, vocabulary_id, concept_class_id, standard_concept,",
    "  concept_code, valid_start_date, valid_end_date, invalid_reason)",
    "SELECT id, 'E2E finding ' || id, 'Observation', 'E2EHier', 'Answer', 'S', 'H' || id, DATE '2000-01-01', DATE '2099-12-31', NULL",
    "FROM (SELECT 2100200000 AS id UNION ALL SELECT 2100200000 + g FROM generate_series(1, 5) g",
    "      UNION ALL SELECT 2100200100 + s FROM generate_series(0, 49) s",
    "      UNION ALL SELECT 2100201000 + l FROM generate_series(0, 4999) l) ids;",
    "INSERT INTO cdm.concept (concept_id, concept_name, domain_id, vocabulary_id, concept_class_id, standard_concept,",
    "  concept_code, valid_start_date, valid_end_date, invalid_reason)",
    "VALUES (2100100005, 'E2E question 5', 'Observation', 'E2EAuto', 'Question', 'S', 'Q5', DATE '2000-01-01', DATE '2099-12-31', NULL);",
    "INSERT INTO cdm.concept_ancestor (ancestor_concept_id, descendant_concept_id, min_levels_of_separation, max_levels_of_separation)",
    "SELECT concept_id, concept_id, 0, 0 FROM cdm.concept WHERE vocabulary_id = 'E2EHier'",
    "UNION ALL SELECT 2100200000, 2100200000 + g, 1, 1 FROM generate_series(1, 5) g",
    "UNION ALL SELECT 2100200000, 2100200100 + s, 2, 2 FROM generate_series(0, 49) s",
    "UNION ALL SELECT 2100200000, 2100201000 + l, 3, 3 FROM generate_series(0, 4999) l",
    "UNION ALL SELECT 2100200001 + s / 10, 2100200100 + s, 1, 1 FROM generate_series(0, 49) s",
    "UNION ALL SELECT 2100200001 + l / 1000, 2100201000 + l, 2, 2 FROM generate_series(0, 4999) l",
    "UNION ALL SELECT 2100200100 + l / 100, 2100201000 + l, 1, 1 FROM generate_series(0, 4999) l;",
    "INSERT INTO cdm.observation (observation_id, person_id, observation_concept_id, observation_date,",
    "  observation_type_concept_id, value_as_concept_id)",
    "SELECT 950000000 + p.i, p.person_id, 2100100005, p.d, 38000280, 2100201000 + ((p.i % 60) / 10) * 100 + (p.i % 10)",
    "FROM (SELECT person_id, d, row_number() OVER (ORDER BY person_id) AS i FROM",
    "  (SELECT DISTINCT ON (person_id) person_id, observation_period_start_date AS d FROM cdm.observation_period",
    "   ORDER BY person_id, observation_period_start_date) op) p WHERE p.i <= 1000;",
    "ANALYZE;"), db = "omopauto", label = "synthetic hierarchy E2EHier and question Q5")
  question <- function(q) omop_variable(event = omop_event("observation", name = paste0("q", q),
                                                           concepts = omop_concept_set(2100100000L + q)),
                                        reducer = omop_reduce("first_value", value = "value_as_concept_id"))
  run <- function(s, q, out) {
    r <- omop_recipe(variables = list(question(q)), outputs = omop_output(name = "auto", type = "wide"),
                     options = list(translate_concepts = FALSE))
    res <- capture_ds(sprintf("%s: recipe_execute(Q%d -> %s)", s$label, q, out),
                      recipe_execute(r, out = c(auto = out), symbol = s$symbol, conns = s$conns))
    book <- if (res$ok) tryCatch(recipe_codebook(res$value)[[1L]]$columns, error = function(e) NULL) else NULL
    lv <- if (!is.null(book)) book$levels[[match(paste0("q", q, "_first_value"), book$name)]] else NULL
    list(ok = res$ok, error = res$error, secs = res$secs, keys = as.character(unlist(lv$keys %||% lv$labels)))
  }
  s <- open_session("G23", servers = c("SiteA", "SiteB"), resource = "omop_data.gibleed_auto")
  on.exit(close_session(s), add = TRUE)
  if (!isTRUE(s$ok)) stop("no G23 session: ", s$error)
  q5 <- run(s, 5L, "G_adaptive")
  verdict("G23a", if (q5$ok && length(q5$keys) == 606L) "PASS" else "FAIL",
          "60 observed answers in 6 subgroups of a 5,056-concept hierarchy publish with those subgroups' 606 concepts",
          sprintf("published: %s; levels: %d (the whole kind holds 5,056); %.1f s; %s", q5$ok, length(q5$keys), q5$secs,
                  if (!q5$ok) last_server_error(q5$error) else ""))
  fast <- run(s, 2L, "G_fp_fast")
  options(dsomop.fingerprint_levels = FALSE)
  full <- run(s, 2L, "G_fp_full")
  options(dsomop.fingerprint_levels = NULL)
  verdict("G23b", if (fast$ok && full$ok && length(fast$keys) == 5000L && identical(fast$keys, full$keys)) "PASS" else "FAIL",
          "a 5,000-concept list shared by both connections publishes from fingerprints with the levels of the full transport",
          sprintf("fingerprints %s in %.1f s; full %s in %.1f s; identical levels: %s", fast$ok, fast$secs, full$ok, full$secs,
                  identical(fast$keys, full$keys)))
  verdict("G23d", "INFO", "publication time of 5,000 automatic levels, fingerprints versus full transport (two connections)",
          sprintf("fingerprints %.1f s; full %.1f s", fast$secs, full$secs))
  f <- capture_ds("G23: ds.omop.filter(G_adaptive -> G_adaptive_f)",
                  ds.omop.filter("G_adaptive", expr = omop_where(!is.na(q5_first_value)), newobj = "G_adaptive_f",
                                 symbol = s$symbol, conns = s$conns))
  b <- capture_ds("G23: ds.omop.bind_rows(G_adaptive, G_adaptive_f -> G_adaptive_b)",
                  ds.omop.bind_rows("G_adaptive", "G_adaptive_f", newobj = "G_adaptive_b", symbol = s$symbol, conns = s$conns))
  dims <- if (b$ok) capture_ds("G23: dsBaseClient::ds.dim(G_adaptive, G_adaptive_f, G_adaptive_b)",
    list(src = dsBaseClient::ds.dim("G_adaptive", type = "split", datasources = s$conns),
         kept = dsBaseClient::ds.dim("G_adaptive_f", type = "split", datasources = s$conns),
         out = dsBaseClient::ds.dim("G_adaptive_b", type = "split", datasources = s$conns))) else NULL
  # ds.dim names its answers after the object: compare the sites by position. Only the people who answered Q5 are
  # kept by the filter, so the stack holds the source's rows plus the kept ones.
  rows <- if (!is.null(dims) && dims$ok) mapply(function(src, kept, out)
    identical(as.numeric(out[[1L]]), as.numeric(src[[1L]]) + as.numeric(kept[[1L]])) && as.numeric(kept[[1L]]) == 1000,
    dims$value$src, dims$value$kept, dims$value$out) else FALSE
  # Level reports on the results read the rows they keep or stack.
  levels_of <- function(x) lapply(DSI::datashield.aggregate(s$conns, call("omopFactorLevelsDS", as.symbol(x))),
                                  function(r) list(unsafe = r$unsafe, levels = r$levels$q5_first_value))
  reports <- if (f$ok && b$ok) capture_ds("G23: omopFactorLevelsDS(G_adaptive, G_adaptive_f, G_adaptive_b)",
    lapply(c("G_adaptive", "G_adaptive_f", "G_adaptive_b"), levels_of)) else NULL
  same <- !is.null(reports) && reports$ok && identical(reports$value[[2L]], reports$value[[1L]]) &&
    identical(reports$value[[3L]], reports$value[[1L]])
  verdict("G23c", if (f$ok && b$ok && length(rows) && all(rows) && same) "PASS" else "FAIL",
          "filter and bind_rows work on a reconciled recipe output, and level reports read their rows (failed before 2.10.8)",
          sprintf("filter: %s; bind_rows: %s; filter keeps the 1,000 answers and the stack holds both: %s; level reports equal the source's: %s; %s",
                  f$ok, b$ok, paste(rows, collapse = "/"), same,
                  paste(c(if (!f$ok) last_server_error(f$error), if (!b$ok) last_server_error(b$error),
                          if (!is.null(reports) && !reports$ok) last_server_error(reports$error)), collapse = " | ")))
})

section("G3b", "how long the automatic data generation takes on this CDM", function() {
  g <- INFO$admin_generation
  tm <- INFO$timing
  verdict("G3b", "INFO", "generation derivation time on GiBleed (PostgreSQL 16)",
          sprintf("on Rock: snapshot %s s, whole derivation %s s over %s/%s tables present; analyst view, first fixed question of a session vs its repeat: %s",
                  if (is.list(g)) g$snapshot_seconds else "?", if (is.list(g)) g$generation_seconds else "?",
                  if (is.list(g)) g$tables_present else "?", if (is.list(g)) g$tables else "?",
                  paste(names(tm), vapply(tm, function(x) paste0(x[["first"]], " s vs ", x[["repeat_secs"]], " s"), ""), sep = ": ", collapse = "; ")))
})

section("G-cleanup", "remove the saved workspace", function() {
  if (!isTRUE(INFO$ws_saved)) return(invisible())
  conns <- analyst_login()
  on.exit(try(DSI::datashield.logout(conns), silent = TRUE))
  capture(paste0("DSI::datashield.workspace_rm(conns, \"", WS, "\")"), DSI::datashield.workspace_rm(conns, WS))
})

# ======================================================================================================================
tab <- write_verdicts("G")
v <- out_file("V-verdicts.csv")
if (file.exists(v)) {
  vt <- utils::read.csv(v, stringsAsFactors = FALSE)
  for (i in seq_len(nrow(vt))) summary_line("[", E2E_PATH, "] (from the upgrade step) V ", vt$id[i], " ", vt$status[i], ": ", vt$title[i])
  tab <- rbind(tab, transform(vt, id = paste0("V ", vt$id)))
  utils::write.csv(tab, out_file("G-verdicts.csv"), row.names = FALSE)
}
counts <- table(factor(tab$status, levels = c("PASS", "FAIL", "INFO", "ERROR")))
summary_line(sprintf("[%s] G: %d checks: PASS %d, FAIL %d, INFO %d, ERROR %d (%s min)", E2E_PATH, nrow(tab), counts[["PASS"]],
                     counts[["FAIL"]], counts[["INFO"]], counts[["ERROR"]],
                     round(as.numeric(difftime(Sys.time(), G_START, units = "mins")), 1)))
try(opal.logout(O), silent = TRUE)
if (counts[["FAIL"]] + counts[["ERROR"]] > 0L) quit(save = "no", status = 1)
