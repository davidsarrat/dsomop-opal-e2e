# O6 and O10: real package installation and method publication, not mocked versions.
source("scripts/common.R")
library(dsOMOPClient)
start_log("O-install")
o <- admin()
if (E2E_PATH == "upgrade") {
  r <- install_server(o, Sys.getenv("OLD_REF", "2.10.1"))
  stopifnot(identical(rock_pkg_version("dsOMOP"), "2.10.1"))
  dsadmin.publish_package(o, "dsOMOP")
  c0 <- analyst_login()
  # Connecting remains supported for v1. The native request must refuse before
  # assigning outputs on an old profile; connection setup itself assigns handles.
  r <- capture("O6 connect new client / old server", ds.omop.connect("omop_data.gibleed", conns = c0))
  stopifnot(r$ok)
  before <- DSI::datashield.symbols(c0)
  native <- omop_recipe(variables = list(age = omop_age()),
                        outputs = omop_output("native", format = "wide"))
  r <- capture("O6 native request / old server", recipe_execute(native, out = c(native = "O_refused"), conns = c0))
  stopifnot(!r$ok, grepl("omopPlanStatusDS|omopStagedRevokeDS|operation|publish|publication|Upgrade|language", r$error),
            identical(before, DSI::datashield.symbols(c0)))
  legacy <- omop_recipe(variables = omop_variable_age(year = 2020),
                        outputs = omop_output("legacy", type = "wide"),
                        options = list(translate_concepts = FALSE))
  r <- capture("O6 numeric v1 / old server", recipe_execute(legacy, out = c(legacy = "O_legacy"), conns = c0))
  stopifnot(r$ok)
  ds.omop.disconnect(conns = c0)
  DSI::datashield.logout(c0)
  # Baseline timings are produced by the actual old server, before replacement.
  # The frozen fixture source works with the old server; export before timing.
  source("scripts/o/setup.R", local = new.env(parent = globalenv()))
  opal.assign.resource(o, "ores", "omop_data.o_big")
  baseline <- opal.execute(o, 'source("/tmp/o-harness/performance.R"); o_performance("ores", "baseline")')
  jsonlite::write_json(baseline, out_file("O9-old.json"), auto_unbox = TRUE)
}
install_server(o, server_target())
dsadmin.publish_package(o, "dsOMOP")
stopifnot(identical(rock_pkg_version("dsOMOP"), candidate_version()))
p <- check_publication(o, "O10 methods and Options republished")
stopifnot(length(c(p$missing_aggregate, p$missing_assign, p$wrong_type,
                  p$wrong_function, p$not_exported, p$options_missing)) == 0L)
if (rock_pkg_version("dsBase") == "not installed") dsadmin.install_package(o, "dsBase")
dsadmin.publish_package(o, "dsBase")
# Generic constructors cannot be aggregate methods in the analyst profile.
for (name in c("c", "list")) {
  methods <- dsadmin.get_methods(o, type = "aggregate")
  if (name %in% methods$name) dsadmin.rm_method(o, name, type = "aggregate")
}
opal.logout(o)
dir.create("/tmp/o-old-client", showWarnings = FALSE)
