source("scripts/common.R")
start_log("O-setup")
o <- admin()
# Source fixtures are copied separately: installed R packages do not retain tests/.
for (pkg in c("RSQLite", "RPostgres", "testthat")) {
  if (rock_pkg_version(pkg) == "not installed") dsadmin.install_package(o, pkg)
}
# The password is injected through the authenticated admin channel and never logged.
code <- paste0('Sys.setenv(O_DB_PASSWORD = ', deparse(Sys.getenv("OMOPDB_PW")), '); ',
               'source("/tmp/o-harness/fixtures.R"); o_load_fixtures(); Sys.unsetenv("O_DB_PASSWORD"); TRUE')
stopifnot(isTRUE(opal.execute(o, code)))
for (s in c("reach", "small", "big")) {
  url <- paste0("omop+dbi:postgresql://omopdb:5432/omop?cdm_schema=o_", s,
                "&vocabulary_schema=o_", s, "&results_schema=o_", s)
  if (!paste0("o_", s) %in% opal.resources(o, "omop_data")$name)
    opal.resource_create(o, "omop_data", paste0("o_", s), url, format = "omop.dbi.db",
                         identity = "omop", secret = Sys.getenv("OMOPDB_PW"))
  opal.resource_perm_add(o, "omop_data", paste0("o_", s), subject = "analyst", type = "user", permission = "view")
}
dsadmin.set_option(o, "nfilter.subset", "5")
dsadmin.set_option(o, "dsstaging.base_dir", '"/tmp/o-staging"')
stopifnot(isTRUE(opal.execute(o, 'dir.create("/tmp/o-staging", mode="0700", showWarnings=FALSE); TRUE')))
versions <- opal.execute(o, 'list(R = R.version.string, packages = sapply(c("dsOMOP", "DBI", "RSQLite", "RPostgres", "dsBase"), function(p) as.character(packageVersion(p))), sqlite = RSQLite::rsqliteVersion())')
opal.assign.resource(o, "ores", "omop_data.o_reach")
versions$postgres <- opal.execute(o, 'dsOMOP::omopInitDS("ores"); DBI::dbGetQuery(dsOMOP:::.getHandle("ores")$conn, "SELECT version() AS version")')
jsonlite::write_json(versions, out_file("O-runtime.json"), auto_unbox = TRUE, pretty = TRUE)
opal.logout(o)

if (identical(rock_pkg_version("dsOMOP"), candidate_version())) {
  library(dsOMOPClient)
  birth <- omop_recipe(variables = list(
    omop_variable(name = "year_of_birth", table = "person", column = "year_of_birth"),
    omop_variable(name = "month_of_birth", table = "person", column = "month_of_birth"),
    omop_variable(name = "birth_datetime", table = "person", column = "birth_datetime"),
    age = omop_age(year = 2020), age_group = omop_age(year = 2020, bands = TRUE, age_breaks = c(0,18,19,65))),
    outputs = omop_output("birth", format = "wide", grain = "person"))
  jsonlite::write_json(recipe_to_plan(birth), out_file("birth-plan.json"), auto_unbox = TRUE, null = "null")
  stopifnot(system2("docker", c("cp", out_file("birth-plan.json"),
    paste0(Sys.getenv("ROCK"), ":/tmp/o-harness/birth-plan.json"))) == 0L)
  local <- omop_study(index = omop_event("condition_occurrence", 201820),
                      baseline = list(age = omop_age()), outputs = "baseline")
  jsonlite::write_json(recipe_to_plan(local), out_file("dp-plan.json"), auto_unbox = TRUE, null = "null")
  stopifnot(system2("docker", c("cp", out_file("dp-plan.json"),
    paste0(Sys.getenv("ROCK"), ":/tmp/o-harness/dp-plan.json"))) == 0L)

}
