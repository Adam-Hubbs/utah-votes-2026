# 2020 Census blocks (TIGER) with P.L. 94-171 total and voting-age population, as internal points.

blocks_points <- function(force = FALSE) {
  cache <- raw_dir("geo", "blocks2020_points.rds")
  if (!force && file.exists(cache)) return(readRDS(cache))

  tiger_zip <- download_cached(
    "https://www2.census.gov/geo/tiger/TIGER2020/TABBLOCK20/tl_2020_49_tabblock20.zip",
    raw_dir("census", "tl_2020_49_tabblock20.zip")
  )
  pl_zip <- download_cached(
    "https://www2.census.gov/programs-surveys/decennial/2020/data/01-Redistricting_File--PL_94-171/Utah/ut2020.pl.zip",
    raw_dir("census", "ut2020.pl.zip")
  )
  pl_dir <- raw_dir("census", "pl", "x")
  unzip(pl_zip, exdir = dirname(pl_dir), overwrite = FALSE)
  tiger_dir <- dirname(raw_dir("census", "tiger_blocks", "x"))
  unzip(tiger_zip, exdir = tiger_dir, overwrite = FALSE)

  geo <- read_delim(
    file.path(dirname(pl_dir), "utgeo2020.pl"),
    delim = "|", col_names = FALSE, col_types = cols(.default = col_character()),
    col_select = c(X3, X8, X10), progress = FALSE
  ) |>
    rename(sumlev = X3, logrecno = X8, geoid20 = X10) |>
    filter(sumlev == "750")

  pl_col <- \(file) {
    read_delim(
      file.path(dirname(pl_dir), file),
      delim = "|", col_names = FALSE, col_types = cols(.default = col_character()),
      col_select = c(X5, X6), progress = FALSE
    ) |>
      rename(logrecno = X5, value = X6) |>
      mutate(value = as.integer(value))
  }
  pop <- pl_col("ut000012020.pl") |> rename(pop = value)
  vap <- pl_col("ut000022020.pl") |> rename(vap = value)

  tab <- geo |>
    inner_join(pop, by = "logrecno") |>
    inner_join(vap, by = "logrecno") |>
    select(geoid20, pop, vap)

  blocks <- sf::st_read(file.path(tiger_dir, "tl_2020_49_tabblock20.shp"), quiet = TRUE) |>
    select(geoid20 = GEOID20, county_fips = COUNTYFP20) |>
    mutate(county_fips = str_c("49", county_fips)) |>
    sf::st_transform(26912)
  pts <- blocks |>
    sf::st_point_on_surface() |>
    left_join(tab, by = "geoid20") |>
    mutate(across(c(pop, vap), \(x) coalesce(x, 0L)))

  saveRDS(pts, cache)
  pts
}
