#!/usr/bin/env Rscript
# Classifies precinct polygons with no votes in a statewide contest, per historical vintage.
#   a_no_residents : no 2020 voting-age population in the polygon (legitimately empty)
#   c_combined     : populated, no votes, and a same-prefix neighbour in the county has more votes than residents,
#                    i.e. the clerk very likely counted these voters with that precinct
#   d_other        : populated with no votes and no such neighbour (group quarters, tiny areas, unexplained)
# Ballot areas no reported name matched (matched: false) are published for coverage only and are excluded here.
# Failed name matches (b) cannot be blank polygons (polygons are built from matches); they show up as reported
# precincts with votes but no polygon, counted separately as b_unmatched_votes.
#   UTEL_RAW_DIR=... Rscript pipeline/tests/diagnose_blank_precincts.R
suppressPackageStartupMessages(library(sf))
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
for (f in c("geo_sources", "history_ut_export", "history_medsl")) source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))

state <- readRDS(raw_dir("geo", "build_geo_state.rds"))
statewide <- c(`2016` = "president", `2018` = "us-senate", `2020` = "president", `2022` = "us-senate", `2024` = "president")

classify_year <- \(yr) {
  contest <- read_json(data_dir("results", str_c(yr, "-general"), "contests", str_c(statewide[[yr]], ".json")))
  rows <- tibble(precinct_id = map_chr(contest$precincts, "precinct_id"), total = map_dbl(contest$precincts, "total"))
  polys <- read_json(data_dir("geo", str_c("precincts_", yr, ".topo.json")))$objects$precincts$geometries |>
    map(\(g) as_tibble(g$properties[c("precinct_id", "county_fips", "name", "vap")]) |> mutate(open_area = isFALSE(g$properties$matched))) |>
    list_rbind() |>
    filter(!open_area) |>
    left_join(rows, by = "precinct_id") |>
    mutate(
      total = coalesce(total, 0),
      prefix = str_extract(name, "^[A-Za-z]+"),
      absorbs = total > vap & vap > 0
    )
  absorbers <- polys |> filter(absorbs) |> distinct(county_fips, prefix)
  polys |>
    mutate(has_absorber = paste(county_fips, prefix) %in% paste(absorbers$county_fips, absorbers$prefix)) |>
    filter(total == 0) |>
    mutate(category = case_when(
      vap == 0 ~ "a_no_residents",
      has_absorber ~ "c_combined",
      .default = "d_other"
    )) |>
    summarise(polygons = n(), vap = sum(vap), .by = category) |>
    mutate(year = yr, total_polygons = nrow(polys))
}

unmatched <- \(votes, members) {
  votes |>
    anti_join(members, by = c("county_fips", "precinct")) |>
    summarise(b_unmatched_precincts = n(), b_unmatched_votes = sum(votes))
}
t24 <- ut_export_contest_tables(raw_dir("results", "export-general11052024.json"))
v24 <- t24$local |> filter(item_id == "State-1") |> summarise(votes = sum(votes), .by = c(county_fips, precinct))
v22 <- medsl_2022_long() |> filter(office == "US SENATE") |> summarise(votes = sum(votes), .by = c(county_fips, precinct))

map(names(statewide), classify_year) |>
  list_rbind() |>
  pivot_wider(names_from = category, values_from = c(polygons, vap), values_fill = 0) |>
  print(width = Inf)
cat("\n2024 "); print(unmatched(v24, state$reported_clusters_2024))
cat("2022 "); print(unmatched(v22, state$reported_clusters_2022))
