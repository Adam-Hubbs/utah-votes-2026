statewide_contests <- c("president", "us-senate", "governor", "attorney-general", "state-auditor", "state-treasurer")

election_year <- \(election_id) str_sub(election_id, 1, 4)

# Party-group votes for the statewide contests, at county and precinct-unit level.
party_votes <- function(el) {
  cand_party <- el$cands |>
    filter(contest_id %in% statewide_contests) |>
    transmute(contest_id, candidate_id, grp = party_group(party))
  county <- el$county_votes |>
    inner_join(cand_party, by = c("contest_id", "candidate_id")) |>
    summarise(votes = sum(votes), .by = c(contest_id, county_fips, grp))
  unit <- el$unit_votes |>
    inner_join(cand_party, by = c("contest_id", "candidate_id")) |>
    summarise(votes = sum(votes), .by = c(contest_id, unit_id, county_fips, grp))
  list(county = county, unit = unit, election_id = el$meta$election_id, contests = el$contests)
}

# Votes of one election re-aggregated into the districts of `plan_col`.
# Precinct votes are split by block VAP; whatever the precinct files do not cover in a county
# (unmatched precincts, provisional) is spread by VAP over the county's uncovered blocks.
aggregate_to_plan <- function(pv, blocks, plan_col) {
  unit_col <- str_c("unit", election_year(pv$election_id))
  weights <- crosswalk_weights(blocks, unit_col, plan_col) |> rename(unit_id = from, district = to)

  from_units <- pv$unit |>
    inner_join(weights, by = "unit_id", relationship = "many-to-many") |>
    summarise(votes = sum(votes * weight), .by = c(contest_id, district, grp))

  covered <- pv$unit |> summarise(covered = sum(votes), .by = c(contest_id, county_fips, grp))
  residual <- pv$county |>
    left_join(covered, by = c("contest_id", "county_fips", "grp")) |>
    mutate(resid = votes - coalesce(covered, 0)) |>
    filter(resid > 0.5) |>
    select(contest_id, county_fips, grp, resid)

  uncovered_blocks <- blocks |> filter(is.na(.data[[unit_col]]))
  share_src <- bind_rows(
    uncovered_blocks |> mutate(src = 1L),
    blocks |> mutate(src = 2L)
  )
  county_share <- share_src |>
    summarise(vap = sum(vap), pop = sum(pop), .by = c(county_fips, src, all_of(plan_col))) |>
    rename(district = all_of(plan_col)) |>
    mutate(basis = if_else(vap > 0, vap, pop)) |>
    mutate(tot = sum(basis), .by = c(county_fips, src)) |>
    filter(tot > 0) |>
    mutate(share = basis / tot) |>
    select(county_fips, src, district, share)
  has_uncovered <- county_share |> filter(src == 1L) |> distinct(county_fips) |> pull(county_fips)
  share_pick <- county_share |>
    filter(if_else(county_fips %in% has_uncovered, src == 1L, src == 2L)) |>
    select(county_fips, district, share)

  from_resid <- residual |>
    inner_join(share_pick, by = "county_fips", relationship = "many-to-many") |>
    summarise(votes = sum(resid * share), .by = c(contest_id, district, grp))

  bind_rows(from_units, from_resid) |>
    summarise(votes = sum(votes), .by = c(contest_id, district, grp)) |>
    mutate(election_id = pv$election_id)
}

ensure_party_cols <- function(x) {
  for (p in c("REP", "DEM", "OTH")) if (!p %in% names(x)) x[[p]] <- 0
  x
}

baseline_json <- function(agg, contest_names) {
  wide <- agg |>
    pivot_wider(names_from = grp, values_from = votes, values_fill = 0) |>
    ensure_party_cols() |>
    mutate(
      total = REP + DEM + OTH,
      margin = if_else(total > 0, (REP - DEM) / total, NA_real_)
    )
  wide |>
    left_join(contest_names, by = c("election_id", "contest_id")) |>
    arrange(district, desc(election_id), match(contest_id, statewide_contests)) |>
    group_split(district) |>
    set_names(map_chr(group_split(wide |> arrange(district), district), \(g) as.character(g$district[[1]]))) |>
    map(\(g) pmap(g, \(election_id, contest_id, name, REP, DEM, OTH, total, margin, ...) list(
      election_id = election_id, contest_id = contest_id, name = name,
      votes = list(REP = round(REP), DEM = round(DEM), OTH = round(OTH)),
      total = round(total), margin = round(margin, 4),
      note = if (DEM == 0 && REP > 0) "No Democratic candidate on the ballot" else NA_character_
    )))
}

county_trend_rows <- function(pv, contest_names) {
  pv$county |>
    pivot_wider(names_from = grp, values_from = votes, values_fill = 0) |>
    ensure_party_cols() |>
    mutate(
      election_id = pv$election_id,
      total = REP + DEM + OTH,
      margin = (REP - DEM) / total,
      two_party_margin = if_else(DEM > 0, (REP - DEM) / (REP + DEM), NA_real_)
    ) |>
    left_join(contest_names, by = c("election_id", "contest_id"))
}
