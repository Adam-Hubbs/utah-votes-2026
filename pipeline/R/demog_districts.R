tiger_block_url <- "https://www2.census.gov/geo/tiger/TIGER2020/TABBLOCK20/tl_2020_49_tabblock20.zip"
ugrc_cd_urls <- c(
  cd2026 = "https://opendata.gis.utah.gov/datasets/utah::utah-congressional-districts-2026-to-2032.geojson",
  cd2022 = "https://opendata.gis.utah.gov/datasets/utah::utah-congressional-districts-2022-to-2026.geojson"
)
ugrc_cd_files <- c(
  cd2026 = "ugrc_political_us_congress_districts_2026_to_2032.geojson",
  cd2022 = "ugrc_political_us_congress_districts_2022_to_2026.geojson"
)

# One row per 2020 census block: id, population and internal point.
census_blocks_ut <- function() {
  cache <- raw_dir("census", "ut_blocks_2020.csv")
  if (file.exists(cache)) return(read_csv(cache, col_types = cols(GEOID20 = "c", .default = "d")))
  zip <- raw_dir("census", "tl_2020_49_tabblock20.zip")
  if (!file.exists(zip)) acs_download(tiger_block_url, zip)
  exdir <- tempfile("tabblock")
  dir.create(exdir)
  unzip(zip, files = "tl_2020_49_tabblock20.dbf", exdir = exdir)
  blocks <- sf::st_read(file.path(exdir, "tl_2020_49_tabblock20.dbf"), quiet = TRUE) |>
    as_tibble() |>
    transmute(GEOID20, POP20 = as.numeric(POP20), lon = as.numeric(INTPTLON20), lat = as.numeric(INTPTLAT20))
  write_csv(blocks, cache)
  blocks
}

cd_plan_sf <- function(plan) {
  path <- raw_dir("geo", ugrc_cd_files[[plan]])
  if (!file.exists(path)) stop("Missing ", path, "; download the UGRC congressional district GeoJSON first (", ugrc_cd_urls[[plan]], ")")
  sf::read_sf(path) |>
    transmute(district = as.integer(DISTRICT)) |>
    sf::st_make_valid() |>
    sf::st_transform(4269)
}

# Assign each block to a district by its internal point (nearest district as a fallback for
# points that fall in a sliver gap), then convert to block-group -> district population shares.
bg_district_shares <- function(plan) {
  blocks <- census_blocks_ut()
  pts <- sf::st_as_sf(blocks, coords = c("lon", "lat"), crs = 4269, remove = FALSE)
  districts <- cd_plan_sf(plan)
  hit <- sf::st_intersects(pts, districts)
  idx <- map_int(seq_along(hit), \(i) if (length(hit[[i]]) > 0) hit[[i]][1] else NA_integer_)
  nearest <- sf::st_nearest_feature(pts, districts)
  assigned <- blocks |>
    mutate(district = districts$district[coalesce(idx, nearest)], bg = str_sub(GEOID20, 1, 12))

  assigned |>
    summarise(pop = sum(POP20), n_blocks = n(), .by = c(bg, district)) |>
    mutate(
      wt = if (sum(pop) > 0) pop else as.numeric(n_blocks),
      share = wt / sum(wt),
      .by = bg
    ) |>
    select(bg, district, share)
}

aggregate_to_districts <- function(wide, shares) {
  bg <- wide |>
    filter(str_detect(GEO_ID, "^1500000US")) |>
    mutate(bg = str_remove(GEO_ID, "^1500000US"))
  count_cols <- bg |> select(-GEO_ID, -bg, -any_of(c("B01002_E001", "B19013_E001"))) |> names()
  bg |>
    inner_join(shares, by = "bg", relationship = "many-to-many") |>
    mutate(across(all_of(count_cols), \(x) coalesce(x, 0) * share)) |>
    summarise(across(all_of(count_cols), sum), .by = district) |>
    arrange(district) |>
    mutate(GEO_ID = as.character(district))
}

# Share of each district's 2020 population that lives in each county (for sanity checks and display).
district_county_composition <- function(plan) {
  blocks <- census_blocks_ut()
  pts <- sf::st_as_sf(blocks, coords = c("lon", "lat"), crs = 4269, remove = FALSE)
  districts <- cd_plan_sf(plan)
  hit <- sf::st_intersects(pts, districts)
  idx <- map_int(seq_along(hit), \(i) if (length(hit[[i]]) > 0) hit[[i]][1] else NA_integer_)
  blocks |>
    mutate(district = districts$district[coalesce(idx, sf::st_nearest_feature(pts, districts))], fips = str_sub(GEOID20, 1, 5)) |>
    summarise(pop = sum(POP20), .by = c(district, fips)) |>
    mutate(share = pop / sum(pop), .by = district) |>
    left_join(select(utah_counties, fips, county = name), by = "fips") |>
    arrange(district, desc(share))
}
