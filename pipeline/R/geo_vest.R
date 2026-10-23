# VEST precinct shapefiles with results (Harvard Dataverse, Election Science collections) for 2016/2018/2020.

vest_files <- c("2016" = 11595839, "2018" = 11595847, "2020" = 11595849)

vest_precincts <- function(year) {
  year <- as.character(year)
  cache <- raw_dir("geo", str_c("vest_", year, ".rds"))
  if (file.exists(cache)) return(readRDS(cache))

  zip <- download_cached(
    str_c("https://dataverse.harvard.edu/api/access/datafile/", vest_files[[year]]),
    raw_dir("vest", str_c("ut_", year, ".zip"))
  )
  dir <- dirname(raw_dir("vest", str_c("ut_", year), "x"))
  unzip(zip, exdir = dir)
  shp <- sf::st_read(file.path(dir, str_c("ut_", year, ".shp")), quiet = TRUE) |> to_proj()

  out <- shp |>
    mutate(
      county_fips = sprintf("49%03d", COUNTYID * 2L - 1L),
      precinct = PRECINCT,
      precinct_id = precinct_key(county_fips, PRECINCT)
    ) |>
    select(-COUNTYID, -COUNTY, -PRECINCT)

  # VEST occasionally repeats a precinct code; those rows are parts of one precinct.
  vote_cols <- names(out)[str_detect(names(out), "^G[0-9]{2}")]
  out <- out |>
    group_by(precinct_id, county_fips, precinct) |>
    summarise(
      name = first(NAME),
      across(all_of(vote_cols), \(x) sum(x, na.rm = TRUE)),
      geometry = sf::st_union(geometry),
      .groups = "drop"
    ) |>
    mutate(unit_id = precinct_id)
  saveRDS(out, cache)
  out
}
