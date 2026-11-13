# Administrator setup: the analyst (DataSHIELD "use"), project omop_data (no database) and its resources.
source("scripts/common.R")
start_log("admin-setup")
o <- admin()
say("Opal version: ", o$version)
# Current Opal ships with "R package management" off: the DataSHIELD package install answers 403 until an
# administrator allows it (Administration > General settings), here through the endpoint the UI uses.
conf0 <- tryCatch(opal.get(o, "system", "conf", "general"), error = function(e) list(error = conditionMessage(e)))
show("general configuration before", conf0)
conf <- conf0
for (i in 1:6) {
  capture("opal.put(o, \"system\", \"conf\", \"general\", \"_rPackage\")", opal.put(o, "system", "conf", "general", "_rPackage"))
  conf <- tryCatch(opal.get(o, "system", "conf", "general"), error = function(e) list(error = conditionMessage(e)))
  if (isTRUE(conf$allowRPackageManagement)) break
  Sys.sleep(10)
}
show("general configuration after", conf)
summary_line("[", E2E_PATH, "] Opal ", o$version, ": allowRPackageManagement on a fresh Opal = ", conf0$allowRPackageManagement,
             "; after the administrator enables it = ", conf$allowRPackageManagement)
show("DataSHIELD profiles", tryCatch(dsadmin.profiles(o), error = function(e) conditionMessage(e)))
show("default profile", tryCatch(str(dsadmin.profile(o, "default")), error = function(e) conditionMessage(e)))

capture("oadmin.user_add(o, \"analyst\")", oadmin.user_add(o, "analyst", password = Sys.getenv("ANALYST_PW")))
capture("dsadmin.perm_add(o, \"analyst\", \"user\", \"use\")", dsadmin.perm_add(o, "analyst", "user", "use"))
capture("opal.project_create(o, \"omop_data\")", opal.project_create(o, "omop_data"))

# 2.x: the URL dsOMOP 2.10.0's inst/resources/resource.js asResource() builds for a PostgreSQL type.
enc <- function(x) utils::URLencode(as.character(x), reserved = TRUE)
v2_url <- function(host, port, database, cdm_schema = NULL, vocabulary_schema = NULL, results_schema = NULL,
                   sslmode = NULL) {
  q <- character(0)
  add <- function(k, v) if (!is.null(v) && nzchar(as.character(v))) q <<- c(q, paste0(k, "=", enc(v)))
  add("cdm_schema", cdm_schema)
  add("vocabulary_schema", vocabulary_schema)
  add("results_schema", results_schema)
  add("sslmode", sslmode)
  paste0("omop+dbi:postgresql://", host, ":", port, "/", enc(database),
         if (length(q)) paste0("?", paste(q, collapse = "&")) else "")
}
# 1.x: the URL dsOMOP 1.1.1's resource.js builds (driver://host:port/db[//dsomop::/schema:X][/vocabulary_schema:Y]).
v1_url <- function(host, port, db, schema = NULL, vocabulary_schema = NULL) {
  u <- paste0("postgresql://", host, ":", port, "/", db)
  if (!is.null(schema) || !is.null(vocabulary_schema)) {
    u <- paste0(u, "//dsomop::")
    if (!is.null(schema)) u <- paste0(u, "/schema:", schema)
    if (!is.null(vocabulary_schema)) u <- paste0(u, "/vocabulary_schema:", vocabulary_schema)
  }
  u
}
db <- Sys.getenv("CDM_DB", "omop53")
say("CDM database behind the resources: ", db, " (gibleed_asshipped always uses omop, cdm_version as shipped)")
resources <- list(
  # What the 2.10.0 form produces when the administrator leaves "TLS mode" empty.
  gibleed = list(url = v2_url("omopdb", 5432, db, cdm_schema = "cdm"), format = "omop.dbi.db"),
  # 2.x without a CDM schema, on a database whose only CDM schema is cdm (not public): discovery must find it.
  gibleed_noschema = list(url = v2_url("omopdb", 5432, "omopone"), format = "omop.dbi.db"),
  gibleed_tls_disable = list(url = v2_url("omopdb", 5432, db, cdm_schema = "cdm", sslmode = "disable"),
                             format = "omop.dbi.db"),
  # GiBleed exactly as OHDSI ships it (cdm_source.cdm_version "v5.3.1"), TLS mode empty.
  # The immutable 2.10.1 server predates patch-version normalization.
  gibleed_legacy = list(url = v2_url("omopdb", 5432, "omop53", cdm_schema = "cdm"), format = "omop.dbi.db"),
  gibleed_asshipped = list(url = v2_url("omopdb", 5432, "omop", cdm_schema = "cdm"), format = "omop.dbi.db"),
  gibleed_v1 = list(url = v1_url("omopdb", 5432, db, "cdm", "cdm"), format = "omop.cdm.db"),
  gibleed_v1_vocab = list(url = v1_url("omopdb", 5432, db, "cdm2", "vocab"), format = "omop.cdm.db"),
  gibleed_v1_schemaonly = list(url = v1_url("omopdb", 5432, db, "cdm"), format = "omop.cdm.db"),
  gibleed_v1_plain = list(url = v1_url("omopdb", 5432, "omoppub"), format = "omop.cdm.db"),
  # Scenario G: a small independent site (GiBleed's first 150 persons) and the same CDM read by a second, read-only
  # database user.
  gibleed_small = list(url = v2_url("omopdb", 5432, "omopsmall", cdm_schema = "cdm"), format = "omop.dbi.db"),
  gibleed_reader = list(url = v2_url("omopdb", 5432, db, cdm_schema = "cdm"), format = "omop.dbi.db",
                        identity = "e2e_reader", secret_env = "READER_PW")
)
for (name in names(resources)) {
  r <- resources[[name]]
  say(sprintf("resource %-22s format %-12s url %s", name, r$format, r$url))
  capture(paste0("opal.resource_create(o, \"omop_data\", \"", name, "\", ...)"),
          opal.resource_create(o, "omop_data", name, r$url, format = r$format,
                               identity = r$identity %||% "omop", secret = Sys.getenv(r$secret_env %||% "OMOPDB_PW")))
  capture(paste0("opal.resource_perm_add(o, \"omop_data\", \"", name, "\", \"analyst\", permission = \"view\")"),
          opal.resource_perm_add(o, "omop_data", name, subject = "analyst", type = "user", permission = "view"))
}
show("Rock as Opal's R sessions see it", rock_eval('list(libPaths = .libPaths(), user = Sys.info()[["user"]], R = R.version.string, packages = { ip <- installed.packages(); p <- c("dsBase", "resourcer", "DBI", "RPostgres", "RPostgreSQL", "RSQLite", "R6", "jsonlite", "filelock", "openssl", "remotes", "dsOMOP"); stats::setNames(ifelse(p %in% rownames(ip), ip[match(p, rownames(ip)), "Version"], "-"), p) })'))
show("resources", tryCatch(opal.resources(o, "omop_data")[, c("name", "url", "format")], error = function(e) conditionMessage(e)))
opal.logout(o)
