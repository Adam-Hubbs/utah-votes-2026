#!/usr/bin/env Rscript
# Historical election results, cross-plan baselines and county trends. Needs build_geo.R to have run
# (it leaves the block assignments and reported-name matches in the raw cache).
# Rscript pipeline/scripts/build_history.R

suppressPackageStartupMessages(library(sf))
source("pipeline/R/utils.R")
for (f in c("geo_sources", "geo_layers", "geo_precincts", "history_ut_export", "history_medsl", "history_common", "history_adapters", "history_baselines")) {
  source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))
}

state <- readRDS(raw_dir("geo", "build_geo_state.rds"))
blocks <- state$blocks

# ---- elections ---------------------------------------------------------------------------------------
tables_2024 <- download_cached(
  ut_export_url("Utah/export-general11052024.json"),
  raw_dir("results", "export-general11052024.json")
) |>
  ut_export_contest_tables()
el_2024 <- adapt_ut_export(tables_2024, state$reported_clusters_2024, "2024-general", "precincts_2024", "cd2022")
el_2024$meta$updated_at <- tables_2024$created_at

el_2022 <- adapt_medsl_2022(medsl_2022_long(), state$reported_clusters_2022)
el_2022$meta$updated_at <- "2022-12-01T00:00:00Z"

vest_els <- map(c(2020, 2018, 2016), \(yr) {
  adapt_vest(readRDS(raw_dir("geo", str_c("vest_", yr, ".rds"))), yr) |>
    adapt_house_county(yr, el = _)
})
vest_els <- map(vest_els, \(el) {
  el$meta$updated_at <- str_c(el$meta$date, "T00:00:00Z")
  el
})

elections <- c(list(el_2024, el_2022), vest_els)

# ---- checks and outputs ------------------------------------------------------------------------------
statewide_check <- map(elections, \(el) {
  el$county_votes |>
    summarise(votes = sum(votes), .by = c(contest_id, candidate_id)) |>
    left_join(el$cands, by = c("contest_id", "candidate_id")) |>
    mutate(election_id = el$meta$election_id)
}) |>
  list_rbind()
if (any(is.na(statewide_check$name))) stop("candidate join failed")

walk(elections, \(el) {
  stopifnot(!anyNA(el$county_votes$county_fips))
  write_election(el)
})

index <- list(
  elections = elections |>
    map(\(el) list(
      election_id = el$meta$election_id,
      name = el$meta$name,
      date = el$meta$date,
      status = "final",
      precinct_geo = el$meta$precinct_geo,
      cd_plan = el$meta$cd_plan,
      contests = pmap(el$contests, \(contest_id, name, office, ...) list(contest_id = contest_id, name = name, office = office))
    )) |>
    (\(x) x[order(map_chr(x, "date"), decreasing = TRUE)])()
)
write_site_json(index, "results", "index.json")

# ---- baselines and trends -----------------------------------------------------------------------------
contest_names <- elections |>
  map(\(el) {
    el$contests |>
      filter(contest_id %in% statewide_contests) |>
      transmute(election_id = el$meta$election_id, contest_id, name = str_c(election_year(el$meta$election_id), " ", name))
  }) |>
  list_rbind()

pvs <- map(elections, party_votes)
pvs <- keep(pvs, \(pv) nrow(pv$unit) > 0)

baseline_plan <- \(plan_col) {
  pvs |>
    map(aggregate_to_plan, blocks = blocks, plan_col = plan_col) |>
    list_rbind()
}
agg_2026 <- baseline_plan("cd2026")
agg_2022 <- baseline_plan("cd2022")

method <- "2020-block VAP-weighted precinct-to-district crosswalk; votes outside matched precincts spread over uncovered blocks by VAP"
write_site_json(
  list(method = method, districts = baseline_json(agg_2026, contest_names)),
  "history", "cd2026_baselines.json"
)
write_site_json(
  list(method = method, districts = baseline_json(agg_2022, contest_names)),
  "history", "cd2022_baselines.json"
)

trends <- map(pvs, county_trend_rows, contest_names = contest_names) |>
  list_rbind() |>
  arrange(county_fips, desc(election_id), match(contest_id, statewide_contests))
write_site_json(
  list(
    margin_definition = "(REP - DEM) / total votes; two_party_margin = (REP - DEM) / (REP + DEM)",
    counties = trends |>
      group_split(county_fips) |>
      set_names(map_chr(group_split(trends, county_fips), \(g) g$county_fips[[1]])) |>
      map(\(g) pmap(g, \(election_id, contest_id, name, REP, DEM, OTH, total, margin, two_party_margin, ...) list(
        election_id = election_id, contest_id = contest_id, name = name,
        votes = list(REP = REP, DEM = DEM, OTH = OTH), total = total,
        margin = round(margin, 4), two_party_margin = round(two_party_margin, 4)
      )))
  ),
  "history", "county_trends.json"
)

# ---- crosswalks ------------------------------------------------------------------------------------------
crosswalk_json <- function(cw) {
  cw |>
    group_split(from) |>
    set_names(map_chr(group_split(cw, from), \(g) g$from[[1]])) |>
    map(\(g) as.list(set_names(round(g$weight, 4), as.character(g$to))))
}
write_site_json(
  list(
    method = "share of source-precinct 2020 voting-age population (P.L. 94-171 blocks, internal point) falling in each target",
    from = "precincts_2024", to = "cd2026",
    weights = crosswalk_json(crosswalk_weights(blocks, "unit2024", "cd2026"))
  ),
  "history", "crosswalks", "precinct_2024_to_cd2026.json"
)
write_site_json(
  list(
    method = "share of source-precinct 2020 voting-age population (P.L. 94-171 blocks, internal point) falling in each target",
    from = "precincts_2024", to = "precincts_2026",
    weights = crosswalk_json(crosswalk_weights(blocks, "unit2024", "unit2026"))
  ),
  "history", "crosswalks", "precinct_2024_to_precinct_2026.json"
)

# ---- match report ------------------------------------------------------------------------------------------
match_rates <- function(election_id, reported_votes, members) {
  reported_votes |>
    left_join(members |> select(county_fips, precinct, unit_id), by = c("county_fips", "precinct")) |>
    summarise(
      precincts = n(), precincts_matched = sum(!is.na(unit_id)),
      votes_matched = sum(votes[!is.na(unit_id)]), votes = sum(votes),
      .by = county_fips
    ) |>
    mutate(
      election_id = election_id, county = county_name(county_fips),
      pct_precincts = round(precincts_matched / precincts, 4),
      pct_votes = round(votes_matched / votes, 4)
    ) |>
    arrange(county_fips)
}
votes_2024 <- tables_2024$local |>
  filter(item_id == "State-1") |>
  summarise(votes = sum(votes), .by = c(county_fips, precinct))
votes_2022 <- medsl_2022_long() |>
  filter(office == "US SENATE") |>
  summarise(votes = sum(votes), .by = c(county_fips, precinct))
rates <- bind_rows(
  match_rates("2024-general", votes_2024, state$reported_clusters_2024),
  match_rates("2022-general", votes_2022, state$reported_clusters_2022)
)
saveRDS(list(rates = rates, agg_2026 = agg_2026, agg_2022 = agg_2022), raw_dir("geo", "build_history_state.rds"))
write_site_json(
  rates |> group_split(election_id) |> set_names(map_chr(group_split(rates, election_id), \(g) g$election_id[[1]])) |>
    map(\(g) list(
      statewide = list(
        pct_precincts = round(sum(g$precincts_matched) / sum(g$precincts), 4),
        pct_votes = round(sum(g$votes_matched) / sum(g$votes), 4)
      ),
      counties = pmap(g, \(county_fips, county, precincts, precincts_matched, votes, votes_matched, pct_precincts, pct_votes, ...) list(
        fips = county_fips, name = county, precincts = precincts, precincts_matched = precincts_matched,
        votes = votes, votes_matched = votes_matched, pct_precincts = pct_precincts, pct_votes = pct_votes
      ))
    )),
  "geo", "match_rates.json"
)
message("history build complete")
