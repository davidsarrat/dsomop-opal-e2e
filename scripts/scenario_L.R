# Scenario L (experiment): which characters in published factor labels break dsBase's table, summary and levels on a
# real Opal/Rock. Each case publishes GiBleed's gender with a label map whose two labels carry the characters, then
# runs dsBaseClient::ds.table(), ds.summary() and ds.levels() and dsOMOP's ds.omop.table() on it. Verdicts are INFO.
source("scripts/common.R")
suppressPackageStartupMessages(library(dsOMOPClient))
source("scripts/g_lib.R")
start_log("scenario-L")
assert_candidate_server()
cases <- list(
  comma = c("Male,a", "Female,a"), colon = c("Male:a", "Female:a"), semicolon = c("Male;a", "Female;a"),
  hash = c("Male#a", "Female#a"), ampersand = c("Male&a", "Female&a"), exclamation = c("Male!", "Female!"),
  tilde = c("Male~a", "Female~a"), caret = c("Male^a", "Female^a"), plus = c("Male+a", "Female+a"),
  parenthesis = c("Male(a)", "Female(a)"), accent_e = c("Mal\u00e9", "Femal\u00e9"), enye = c("Ma\u00f1a", "Fe\u00f1a"),
  umlaut = c("M\u00fcller", "F\u00fcller"), sharp_s = c("Ma\u00dfe", "Fe\u00dfe"), cjk = c("\u7537", "\u5973"),
  unicode_dash = c("Male\u2013a", "Female\u2013a"), nbsp = c("Male\u00a0a", "Female\u00a0a"), tab = c("Male\ta", "Female\ta"),
  underscore_digit = c("_1male", "_2female"), dot_start = c(".male", ".female"), hyphen_start = c("-male", "-female"),
  digits = c("123", "456"), mixed_safe = c("Male-adult_1.a", "Female-adult_2.b"))
s <- open_session("L")
if (!isTRUE(s$ok)) stop("no L session: ", s$error)
for (case in names(cases)) section(paste0("L-", case), paste("labels with", case), function() {
  labels <- cases[[case]]
  gender <- omop_variable(name = "gender", table = "person", column = "gender_concept_id", type = "categorical",
                          format = "raw", labels = setNames(labels, c("8507", "8532")))
  sym <- paste0("L_", case)
  r <- omop_recipe(variables = list(gender), outputs = omop_output(name = "lab", type = "wide"))
  pub <- capture_ds(sprintf("L %s: recipe_execute", case), recipe_execute(r, out = c(lab = sym), symbol = s$symbol, conns = s$conns))
  if (!pub$ok) { verdict(paste0("L-", case), "INFO", paste("labels with", case), paste("publication refused:", last_server_error(pub$error))); return(invisible()) }
  col <- paste0(sym, "$gender")
  tab <- capture_ds(sprintf("L %s: ds.table", case), dsBaseClient::ds.table(rvar = col, datasources = s$conns))
  tab_ok <- tab$ok && identical(tab$value$validity.message, "Data in all studies were valid")
  tab_names <- if (tab_ok) paste(dimnames(tab$value$output.list$TABLES.COMBINED_all.sources_counts)[[1L]], collapse = " | ") else ""
  smy <- capture_ds(sprintf("L %s: ds.summary", case), dsBaseClient::ds.summary(col, datasources = s$conns))
  smy_ok <- smy$ok && is.list(smy$value[[1L]])
  lev <- capture_ds(sprintf("L %s: ds.levels", case), dsBaseClient::ds.levels(col, datasources = s$conns))
  lev_names <- if (lev$ok) paste(unlist(lev$value[[1L]]$Levels), collapse = " | ") else ""
  omt <- capture_ds(sprintf("L %s: ds.omop.table", case), ds.omop.table(sym, "gender", conns = s$conns))
  verdict(paste0("L-", case), "INFO", paste("labels with", case),
          sprintf("labels [%s]; ds.table %s%s; ds.summary %s%s; ds.levels %s [%s]; ds.omop.table %s%s",
                  paste(labels, collapse = " | "),
                  if (tab_ok) "OK" else "FAILED", if (tab_ok) paste0(" [", tab_names, "]") else paste0(": ", squash(c(tab$error, tab$value$validity.message), 200)),
                  if (smy_ok) "OK" else "FAILED", if (smy_ok) "" else paste0(": ", squash(c(smy$error, unlist(smy$value)), 200)),
                  if (lev$ok) "OK" else "FAILED", lev_names,
                  if (omt$ok) "OK" else "FAILED", if (omt$ok) paste0(" [", paste(names(omt$value), collapse = " | "), "]") else paste0(": ", squash(omt$error, 200))))
})
close_session(s)
tab <- write_verdicts("L")
summary_line(sprintf("[%s] L: %d label cases", E2E_PATH, nrow(tab)))
