tier_rank <- c(exact = 1L, alias = 2L, parent = 3L, abbrev = 4L, approx = 5L)

vista_by_id <- function(vista) {
  vista |>
    mutate(county_fips = sprintf("49%03d", CountyID * 2L - 1L)) |>
    group_by(county_fips, vista_id = VistaID) |>
    summarise(geometry = sf::st_union(geometry), .groups = "drop")
}

# Connected components of reported names that were matched onto the same Vista features.
# One UGRC feature may be matched by several reported names (e.g. AMA:U1, AMA:U2, AMA:U3 all fall in
# the single feature 3AMA:U); those become one unit so geometries never overlap.
cluster_reported <- function(matches, votes) {
  edges <- matches |>
    filter(!is.na(vista_id)) |>
    mutate(rank = tier_rank[tier]) |>
    group_by(county_fips, vista_id) |>
    filter(rank == min(rank)) |>
    ungroup() |>
    distinct(county_fips, precinct, vista_id)

  lab <- edges |>
    distinct(county_fips, precinct) |>
    arrange(county_fips, precinct) |>
    mutate(cluster = row_number())

  repeat {
    vmin <- edges |>
      left_join(lab, by = c("county_fips", "precinct")) |>
      summarise(vm = min(cluster), .by = c(county_fips, vista_id))
    nxt <- edges |>
      left_join(vmin, by = c("county_fips", "vista_id")) |>
      summarise(cluster = min(vm), .by = c(county_fips, precinct)) |>
      arrange(county_fips, precinct)
    if (identical(nxt$cluster, lab$cluster)) break
    lab <- nxt
  }

  members <- lab |>
    left_join(votes, by = c("county_fips", "precinct")) |>
    mutate(votes = coalesce(votes, 0L))
  rep_name <- members |>
    arrange(cluster, desc(votes), precinct) |>
    distinct(cluster, .keep_all = TRUE) |>
    transmute(cluster, unit_name = precinct, unit_id = precinct_key(county_fips, precinct))
  members <- members |> left_join(rep_name, by = "cluster")
  vista_units <- edges |>
    left_join(lab, by = c("county_fips", "precinct")) |>
    distinct(county_fips, vista_id, cluster) |>
    left_join(rep_name, by = "cluster")
  list(members = members, vista_units = vista_units)
}

unit_geometry <- function(vista_geom, vista_units) {
  vista_geom |>
    inner_join(vista_units |> select(county_fips, vista_id, unit_id, unit_name), by = c("county_fips", "vista_id")) |>
    group_by(unit_id, county_fips, unit_name) |>
    summarise(geometry = sf::st_union(geometry), .groups = "drop")
}

# Plurality district of a unit by block VAP; units with no people fall back to population, then to the
# district containing the unit's representative point.
plurality_district <- function(units, blocks_tbl, unit_col, district_col, polys) {
  by_pop <- blocks_tbl |>
    filter(!is.na(.data[[unit_col]]), !is.na(.data[[district_col]])) |>
    summarise(vap = sum(vap), pop = sum(pop), .by = c(all_of(unit_col), all_of(district_col))) |>
    rename(unit_id = all_of(unit_col), district = all_of(district_col)) |>
    group_by(unit_id) |>
    arrange(desc(vap), desc(pop), district, .by_group = TRUE) |>
    slice_head(n = 1) |>
    ungroup() |>
    select(unit_id, district)
  fallback <- units |>
    sf::st_point_on_surface() |>
    sf::st_join(polys["district"], join = sf::st_nearest_feature) |>
    sf::st_drop_geometry() |>
    select(unit_id, district_fb = district)
  units |>
    left_join(by_pop, by = "unit_id") |>
    left_join(fallback, by = "unit_id") |>
    mutate(district = coalesce(district, district_fb)) |>
    select(-district_fb)
}

# Shares of source-unit VAP falling in each target unit.
crosswalk_weights <- function(blocks_tbl, from_col, to_col) {
  blocks_tbl |>
    filter(!is.na(.data[[from_col]]), !is.na(.data[[to_col]])) |>
    summarise(vap = sum(vap), pop = sum(pop), .by = c(all_of(from_col), all_of(to_col))) |>
    rename(from = all_of(from_col), to = all_of(to_col)) |>
    mutate(
      basis = if_else(sum(vap) > 0, vap, pop),
      .by = from
    ) |>
    mutate(weight = if_else(sum(basis) > 0, basis / sum(basis), 1 / n()), .by = from) |>
    select(from, to, weight)
}
