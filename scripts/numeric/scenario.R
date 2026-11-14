# Shared by real Opal N and the targeted installed DSLite harness check.
# Only aggregate results leave the analyst's session.
run_numeric_scenario <- function(conns, resource = "omop_data.numeric_cdm") {
  dsOMOPClient::ds.omop.connect(resource = resource, symbol = "numeric", conns = conns)
  on.exit(dsOMOPClient::ds.omop.disconnect("numeric", conns = conns), add = TRUE)
  lab <- dsOMOPClient::omop_event("measurement", 3000963L, name = "lab")
  recipe <- dsOMOPClient::omop_recipe(events = list(lab),
    populations = dsOMOPClient::omop_population("p", index = dsOMOPClient::omop_index("lab")),
    variables = list(
      mean_hgb = dsOMOPClient::omop_variable("mean_hgb", event = "lab", reducer = dsOMOPClient::omop_reduce("mean")),
      index_hgb = dsOMOPClient::omop_value_at_index("measurement", 3000963L, unit = 8713L),
      date = dsOMOPClient::omop_date(dsOMOPClient::omop_anchor("lab"))),
    outputs = dsOMOPClient::omop_output("labs", format = "wide", rows = "p", grain = "episode"))
  dsOMOPClient::recipe_execute(recipe, out = c(labs = "NumericLabs"), symbol = "numeric", conns = conns)
  mean <- dsBaseClient::ds.mean("NumericLabs$mean_hgb", type = "combine", datasources = conns)
  quantiles <- dsBaseClient::ds.quantileMean("NumericLabs$mean_hgb", type = "combine", datasources = conns)
  # Frozen independent source oracle: computed from the pinned CSV, never a
  # value read back from a production table to construct its own expectation.
  stopifnot(isTRUE(all.equal(as.numeric(mean$Global.Mean[1L, 1L]), 14.46678571428571, tolerance = 1e-10)))
  stopifnot(isTRUE(all.equal(unname(quantiles),
    c(12.905, 13.1466666666667, 13.785, 14.325, 15.3354166666667, 15.7, 15.92375,
      14.46678571428571), tolerance = 1e-10)))
  dsOMOPClient::recipe_execute(recipe, out = c(labs = "NumericLabsStaged"), symbol = "numeric",
                              conns = conns, output_mode = "staged")
  invisible(list(mean = mean, quantiles = quantiles))
}
