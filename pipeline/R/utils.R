suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
  library(jsonlite)
})

project_root <- function() {
  root <- Sys.getenv("UTEL_ROOT", unset = NA)
  if (!is.na(root)) return(normalizePath(root))
  dir <- normalizePath(getwd())
  while (!file.exists(file.path(dir, "ARCHITECTURE.md"))) {
    parent <- dirname(dir)
    if (parent == dir) stop("Could not find project root (ARCHITECTURE.md).")
    dir <- parent
  }
  dir
}

# Raw downloads are shared across git worktrees, so the cache can live outside the repo.
raw_dir <- function(...) {
  base <- Sys.getenv(
    "UTEL_RAW_DIR",
    unset = file.path(project_root(), "pipeline", "raw")
  )
  path <- file.path(base, ...)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}

data_dir <- function(...) {
  path <- file.path(project_root(), "web", "public", "data", ...)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}

write_site_json <- function(x, ...) {
  path <- data_dir(...)
  write_json(
    x,
    path,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    pretty = FALSE
  )
  invisible(path)
}

utah_counties <- tibble(
  name = c(
    "Beaver",
    "Box Elder",
    "Cache",
    "Carbon",
    "Daggett",
    "Davis",
    "Duchesne",
    "Emery",
    "Garfield",
    "Grand",
    "Iron",
    "Juab",
    "Kane",
    "Millard",
    "Morgan",
    "Piute",
    "Rich",
    "Salt Lake",
    "San Juan",
    "Sanpete",
    "Sevier",
    "Summit",
    "Tooele",
    "Uintah",
    "Utah",
    "Wasatch",
    "Washington",
    "Wayne",
    "Weber"
  )
) |>
  mutate(
    county_nbr = sprintf("%02d", row_number()),
    fips = sprintf("49%03d", row_number() * 2L - 1L)
  )

normalize_county_name <- function(x) {
  x |>
    str_replace_all("-", " ") |>
    str_squish() |>
    str_remove(regex("\\s+county(,?\\s*ut(ah)?)?$", ignore_case = TRUE)) |>
    str_to_title()
}

county_fips_from_name <- function(x) {
  tibble(name = normalize_county_name(x)) |>
    left_join(utah_counties, by = "name") |>
    pull(fips)
}

slugify <- function(x) {
  x |>
    str_to_lower() |>
    str_replace_all("[\"'’]", "") |>
    str_replace_all("[^a-z0-9]+", "-") |>
    str_remove_all("^-+|-+$")
}

precinct_key <- function(county_fips, precinct_name) {
  str_c(county_fips, "-", str_to_upper(str_squish(precinct_name)))
}

party_group <- function(party) {
  case_when(
    party == "REP" ~ "REP",
    party == "DEM" ~ "DEM",
    .default = "OTH"
  )
}
