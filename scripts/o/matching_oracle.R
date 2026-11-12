# Independent frozen WS-0 reference sampler, copied with only the seed parameterized.
# Source SHA256: b13e1a304656b41f08c0a3557e77d1b5a2100dd961363f1cff5cd9be85cfb593
# This file calls base R/SQL and SHA256, never the dsOMOP matching compiler.
o_matching_oracle <- function(conn, seed) {
  q <- function(sql) DBI::dbGetQuery(conn, sql)
  D <- function(x) as.Date(x)
  iso <- function(x) format(as.Date(x), "%Y-%m-%d")
  IDENTITY <- c("row_id", "cohort_row_id", "person_id")
  FIXTURE_KEYS <- c("person_id", "index_date", "index_key")
  write_expected <- function(dir, outputs, invariants, notes = NULL) list(outputs = outputs)
frame_out <- function(name, df, released, oracle_only = character(0)) {
  rownames(df) <- NULL
  comparison <- setdiff(names(df), c(FIXTURE_KEYS, oracle_only))
  stopifnot(all(comparison %in% released), all(IDENTITY %in% released))
  list(name = name, n_persons = length(unique(df$person_id)), released_columns = released,
       comparison_columns = comparison, oracle_only = oracle_only, columns = names(df), rows = df)
}
wide_cols <- function(vars) c(IDENTITY, vars)
SURV_COLS <- c(IDENTITY, "outcome_name", "event", "entry_days_from_index", "exit_days_from_index", "follow_up_days")
REC_EVENT_COLS <- c(IDENTITY, "outcome_name", "event", "event_number", "outcome_event_number", "event_days_from_index",
                    "entry_days_from_index", "exit_days_from_index")
REC_RISK_COLS <- c(IDENTITY, "entry_days_from_index", "exit_days_from_index", "follow_up_days")
PANEL_BASE <- c(IDENTITY, "period_start_days", "period_end_days", "days")

# ---- fixture accessors --------------------------------------------------------
persons <- q("SELECT person_id, gender_concept_id, year_of_birth FROM person")
ops_all <- q("SELECT person_id, observation_period_id, observation_period_start_date AS s, observation_period_end_date AS e FROM observation_period")
descendants <- function(ids) {
  rows <- q(paste0("SELECT descendant_concept_id FROM concept_ancestor WHERE ancestor_concept_id IN (",
                   paste(ids, collapse = ","), ")"))$descendant_concept_id
  unique(c(as.integer(ids), as.integer(rows)))
}
idlist <- function(ids) paste(ids, collapse = ",")
cohort_episodes <- function(cid, coverage = "unique") {
  ep <- q(paste0("SELECT subject_id AS person_id, cohort_start_date AS index_date, cohort_end_date AS end_date ",
                 "FROM cohort WHERE cohort_definition_id = ", cid, " ORDER BY subject_id, cohort_start_date, cohort_end_date"))
  if (identical(coverage, "unique")) {
    # unique / drop / drop: an index date covered by zero or several periods is dropped
    keep <- vapply(seq_len(nrow(ep)), function(i) !is.null(covering(ep$person_id[i], ep$index_date[i])), logical(1))
    ep <- ep[keep, , drop = FALSE]
  }
  ep
}
person_yob <- function(pid) persons$year_of_birth[match(pid, persons$person_id)]
person_sex <- function(pid) ifelse(persons$gender_concept_id[match(pid, persons$person_id)] == 8532L, "F", "M")
annual_age <- function(pid, date) {
  yob <- person_yob(pid); age <- as.integer(format(as.Date(date), "%Y")) - yob
  age[!is.na(age) & age < 0] <- NA_integer_
  age
}
# unique-coverage lookup: the single observation period containing `date`, else NA
covering <- function(pid, date) {
  o <- ops_all[ops_all$person_id == pid & ops_all$s <= date & ops_all$e >= date, , drop = FALSE]
  if (nrow(o) == 1L) o else NULL
}

{
  mi_ids <- descendants(4329847L); dm_ids <- descendants(201820L)
  mi <- q(paste0("SELECT condition_occurrence_id AS id, person_id, condition_start_date AS d FROM condition_occurrence WHERE condition_concept_id IN (",
                 idlist(mi_ids), ") ORDER BY person_id, condition_start_date, condition_occurrence_id"))
  deaths <- q("SELECT person_id, death_date AS d FROM death")
  dm <- q(paste0("SELECT person_id, condition_start_date AS d FROM condition_occurrence WHERE condition_concept_id IN (", idlist(dm_ids), ")"))
  # cases: first eligible MI per person (observed >= 365 before it, unique coverage)
  cases <- list()
  for (pid in unique(mi$person_id)) {
    r <- mi[mi$person_id == pid, , drop = FALSE]
    for (k in seq_len(nrow(r))) {
      cov <- covering(pid, r$d[k]); if (is.null(cov)) next
      if (D(cov$s) > D(r$d[k]) - 365L) next
      cases[[length(cases) + 1L]] <- list(pid = pid, t = D(r$d[k]), key = as.character(r$id[k])); break
    }
  }
  f <- function(tag, text = NULL) {
    bytes <- if (is.null(text)) raw(0) else charToRaw(enc2utf8(as.character(text))); n <- length(bytes)
    c(as.raw(tag), as.raw(c(bitwAnd(bitwShiftR(n, 24L), 255L), bitwAnd(bitwShiftR(n, 16L), 255L), bitwAnd(bitwShiftR(n, 8L), 255L), bitwAnd(n, 255L))), bytes)
  }
  hash_pair <- function(seed, case, control) {
    E <- c(f(0x02, "dsomop-match-v1"), f(0x01, seed), f(0x02, "cases"), f(0x01, case$pid), f(0x03, iso(case$t)), f(0x03, iso(case$t)),
           f(0x02, "mi"), f(0x02, case$key), f(0x01, control))
    paste(as.character(openssl::sha256(E)))
  }
  strata_of <- function(pid, t) {
    yob <- person_yob(pid); age <- as.integer(format(t, "%Y")) - yob
    list(sex = person_sex(pid), band = if (is.na(age)) NA_integer_ else age %/% 5L, year = as.integer(format(t, "%Y")),
         dm = any(D(dm$d[dm$person_id == pid]) <= t - 1L))
  }
  ord_cases <- order(vapply(cases, function(c) as.integer(c$t), 1), vapply(cases, function(c) c$pid, 1))
  cases <- cases[ord_cases]
  rows <- list(); set_id <- 0L
  for (case in cases) {
    set_id <- set_id + 1L; t <- case$t; cs <- strata_of(case$pid, t)
    pool <- integer(0)
    for (k in persons$person_id) {
      if (k == case$pid) next
      cov <- covering(k, iso(t)); if (is.null(cov) || D(cov$s) > t - 365L) next
      dd <- D(deaths$d[deaths$person_id == k]); if (length(dd) && dd[1] < t) next
      if (any(D(mi$d[mi$person_id == k]) <= t)) next
      ks <- strata_of(k, t)
      if (is.na(cs$band) || is.na(ks$band)) next
      if (ks$sex != cs$sex || ks$band != cs$band || ks$year != cs$year || ks$dm != cs$dm) next
      pool <- c(pool, k)
    }
    N <- length(pool); m <- min(4L, N)
    chosen <- if (N > 0L) { hs <- vapply(pool, function(k) hash_pair(seed, case, k), ""); pool[order(hs, pool)][seq_len(m)] } else integer(0)
    stat <- function(pid, is_case, w) {
      has_statin <- nrow(q(paste0("SELECT 1 FROM drug_exposure WHERE person_id = ", pid, " AND drug_concept_id IN (", idlist(descendants(1539403L)),
                                  ") AND drug_exposure_start_date >= '", iso(t - 365L), "' AND drug_exposure_start_date <= '", iso(t - 1L), "'"))) > 0L
      data.frame(person_id = pid, index_date = iso(t), set_id = set_id, is_case = is_case, w = w,
                 age = annual_age(pid, t), sex = person_sex(pid), statin_365 = as.integer(has_statin), n_eligible = N, stringsAsFactors = FALSE)
    }
    rows[[length(rows) + 1L]] <- stat(case$pid, 1L, 1)
    for (k in chosen) rows[[length(rows) + 1L]] <- stat(k, 0L, N / m)
  }
  write_expected("10-matching", list(cc_table = frame_out("cc_table", do.call(rbind, rows),
                 wide_cols(c("set_id", "is_case", "w", "age", "sex", "statin_365")), oracle_only = "n_eligible")),
                 c("cases: first MI per person with >= 365 observed days before it (unique coverage); same-time outcomes exclude controls",
                   "controls ordered by the SHA-256 of the published encoding; m = min(4, N); w = N/m; a zero-control case is kept (1012)",
                   "set_id = rank of the case in (t, identity) order"),
                 notes = "n_eligible (the private pool size N) is an oracle-only audit field, never a released column")
}

}
