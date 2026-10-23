# 2024 presidential result re-aggregated to legislative districts through the 2020-block VAP crosswalk
# (same method as the congressional baselines: block internal point -> district, block -> 2024 precinct).

legis_block_districts <- function() {
  blocks <- readRDS(raw_dir("geo", "blocks2020_points.rds"))
  plans <- list(
    house = raw_dir("geo", "ugrc_UtahHouseDistricts2022to2032.geojson"),
    senate = raw_dir("geo", "ugrc_UtahSenateDistricts2022to2032.geojson")
  )
  plans |>
    imap(\(path, chamber) {
      polys <- sf::st_read(path, quiet = TRUE) |>
        sf::st_transform(sf::st_crs(blocks)) |>
        transmute(district = as.integer(DIST))
      blocks |>
        sf::st_join(polys, join = sf::st_within) |>
        sf::st_drop_geometry() |>
        transmute(geoid20, chamber = chamber, district, vap)
    }) |>
    list_rbind()
}

legis_pres24_margins <- function() {
  state <- readRDS(raw_dir("geo", "build_geo_state.rds"))
  xwalk <- legis_block_districts() |>
    filter(!is.na(district)) |>
    inner_join(state$blocks |> select(geoid20, unit2024), by = "geoid20") |>
    summarise(vap = sum(vap), .by = c(chamber, district, unit2024)) |>
    filter(sum(vap) > 0, .by = unit2024) |>
    mutate(weight = vap / sum(vap), .by = unit2024)

  pres <- read_json(data_dir("results", "2024-general", "contests", "president.json"), simplifyVector = FALSE)
  party <- pres$candidates |> map_chr("party", .default = NA_character_) |> set_names(map_chr(pres$candidates, "candidate_id"))
  # Trump/Harris ids are stable in the 2024 file; third parties only enter the denominator.
  precincts <- pres$precincts |>
    map(\(p) tibble(
      unit2024 = p$precinct_id,
      rep = p$votes[["donald-j-trump"]] %||% 0,
      dem = p$votes[["kamala-d-harris"]] %||% 0,
      total = p$total
    )) |>
    list_rbind()

  matched <- inner_join(xwalk, precincts, by = "unit2024")
  message(sprintf(
    "pres24 crosswalk: %.1f%% of 2024 precinct votes assigned to a legislative district",
    100 * sum(distinct(matched, unit2024, total)$total) / sum(precincts$total)
  ))

  matched |>
    summarise(across(c(rep, dem, total), \(x) sum(x * weight)), .by = c(chamber, district)) |>
    transmute(chamber, district, pres24_rep_pct = rep / total, pres24_dem_pct = dem / total, pres24_margin = (rep - dem) / total)
}
