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

  # Reported names that lost every feature to a better-tier match (e.g. "COV01:X" next to "COV01") belong
  # to the area of the winning unit; their votes are attributed to it.
  vista_cluster <- edges |>
    left_join(lab, by = c("county_fips", "precinct")) |>
    distinct(county_fips, vista_id, cluster)
  orphans <- matches |>
    filter(!is.na(vista_id)) |>
    distinct(county_fips, precinct, vista_id) |>
    anti_join(lab, by = c("county_fips", "precinct")) |>
    inner_join(vista_cluster, by = c("county_fips", "vista_id")) |>
    count(county_fips, precinct, cluster) |>
    arrange(county_fips, precinct, desc(n), cluster) |>
    distinct(county_fips, precinct, .keep_all = TRUE) |>
    select(county_fips, precinct, cluster)
  lab_all <- bind_rows(lab, orphans)

  members <- lab_all |>
    left_join(votes, by = c("county_fips", "precinct")) |>
    mutate(votes = coalesce(votes, 0L))
  rep_name <- members |>
    semi_join(lab, by = c("county_fips", "precinct")) |>
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

# A populated sub-area (e.g. LP01:1) whose reported row has no votes while a sibling sub-area of the same parent
# precinct has them is almost always counted with that sibling by the clerk, so it joins the sibling's unit.
merge_zero_vote_siblings <- function(cl, vista_vap) {
  unit_votes <- cl$members |>
    distinct(county_fips, precinct, unit_id, votes) |>
    summarise(votes = sum(votes), .by = unit_id)
  target <- cl$vista_units |>
    mutate(parent = str_remove(vista_id, ":.*$")) |>
    left_join(unit_votes, by = "unit_id") |>
    left_join(vista_vap, by = c("county_fips", "vista_id")) |>
    group_by(county_fips, parent) |>
    mutate(
      has_sibling_votes = any(votes > 0 & !is.na(votes)),
      best_id = unit_id[which.max(coalesce(votes, 0))],
      best_name = unit_name[which.max(coalesce(votes, 0))]
    ) |>
    ungroup() |>
    filter(coalesce(votes, 0) == 0, coalesce(vap, 0) > 0, has_sibling_votes, str_detect(vista_id, ":"))
  moved <- target |> distinct(old_id = unit_id, new_id = best_id, new_name = best_name)
  # A zero-vote unit spanning several parents moves with the parent that has the most VAP.
  moved <- moved |> distinct(old_id, .keep_all = TRUE)
  remap_id <- \(id) coalesce(moved$new_id[match(id, moved$old_id)], id)
  remap_name <- \(id, nm) coalesce(moved$new_name[match(id, moved$old_id)], nm)
  cl$vista_units <- cl$vista_units |> mutate(unit_name = remap_name(unit_id, unit_name), unit_id = remap_id(unit_id))
  cl$members <- cl$members |> mutate(unit_name = remap_name(unit_id, unit_name), unit_id = remap_id(unit_id))
  cl
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
    mutate(use_vap = sum(vap) > 0, .by = from) |>
    mutate(basis = as.double(if_else(use_vap, vap, pop))) |>
    mutate(has_basis = sum(basis) > 0, .by = from) |>
    mutate(weight = if_else(has_basis, basis / sum(basis), 1 / n()), .by = from) |>
    select(from, to, weight)
}

# Reported precinct names for one election -> units on current UGRC geometry, plus the per-block unit id.
build_reported_vintage <- function(votes, vista, vista_geom, blocks_tbl, plan_polys, plan_col) {
  matches <- match_precincts_to_vista(votes, vista)
  cl <- cluster_reported(matches, votes)
  vista_vap <- blocks_tbl |>
    summarise(vap = sum(vap), .by = vista_key) |>
    separate_wider_delim(vista_key, "|", names = c("county_fips", "vista_id"), too_many = "merge")
  cl <- merge_zero_vote_siblings(cl, vista_vap)
  geom <- unit_geometry(vista_geom, cl$vista_units)
  vista_unit <- cl$vista_units |>
    transmute(vista_key = str_c(county_fips, "|", vista_id), unit = unit_id)
  block_unit <- blocks_tbl |>
    select(vista_key) |>
    left_join(vista_unit, by = "vista_key") |>
    pull(unit)
  tmp <- blocks_tbl
  tmp$unit_tmp <- block_unit
  units <- geom |>
    plurality_district(tmp, "unit_tmp", plan_col, plan_polys) |>
    transmute(precinct_id = unit_id, county_fips, name = unit_name, !!plan_col := district)
  list(matches = matches, members = cl$members, vista_units = cl$vista_units, units = units, block_unit = block_unit)
}
