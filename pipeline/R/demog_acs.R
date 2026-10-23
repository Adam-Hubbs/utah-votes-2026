# ACS 5-year table-based summary file. The Census API now rejects keyless requests, so the bulk
# files (no key needed) are the source; the Utah rows are cached as small CSVs.
acs_year <- 2024L
acs_base <- "https://www2.census.gov/programs-surveys/acs/summary_file/2024/table-based-SF"
acs_tables <- c("b01001", "b01002", "b01003", "b03002", "b15003", "b19001", "b19013")
acs_geo_pattern <- "^(0400000|0500000|1500000|5001900)US49"

acs_download <- function(url, dest) {
  if (!file.exists(dest)) {
    message("Downloading ", url)
    httr2::request(url) |>
      httr2::req_user_agent("utah-elections-pipeline") |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_timeout(1800) |>
      httr2::req_perform(path = dest)
  }
  dest
}

read_delim_filtered <- function(path, pattern, id_col) {
  read_delim_chunked(
    path,
    callback = DataFrameCallback$new(\(x, pos) filter(x, str_detect(.data[[id_col]], pattern))),
    delim = "|",
    chunk_size = 200000,
    col_types = cols(.default = "c"),
    progress = FALSE
  )
}

acs_geos_ut <- function() {
  cache <- raw_dir("acs2024", "ut_geos.csv")
  if (file.exists(cache)) return(read_csv(cache, col_types = cols(.default = "c")))
  src <- acs_download(str_glue("{acs_base}/documentation/Geos{acs_year}5YR.txt"), raw_dir("acs2024", "Geos20245YR.txt"))
  geos <- read_delim_filtered(src, acs_geo_pattern, "GEO_ID") |>
    select(GEO_ID, SUMLEVEL, STUSAB, COUNTY, CDCURR, TRACT, BLKGRP, NAME)
  write_csv(geos, cache)
  geos
}

acs_table_ut <- function(table) {
  cache <- raw_dir("acs2024", str_glue("ut_{table}.csv"))
  if (file.exists(cache)) return(read_csv(cache, col_types = cols(.default = "c")))
  src <- acs_download(
    str_glue("{acs_base}/data/5YRData/acsdt5y{acs_year}-{table}.dat"),
    raw_dir("acs2024", str_glue("acsdt5y{acs_year}-{table}.dat"))
  )
  ut <- read_delim_filtered(src, acs_geo_pattern, "GEO_ID") |>
    select(GEO_ID, contains("_E"))
  write_csv(ut, cache)
  ut
}

acs_wide_ut <- function() {
  acs_tables |>
    map(\(t) acs_table_ut(t) |> mutate(across(-GEO_ID, \(x) suppressWarnings(as.numeric(x))))) |>
    reduce(full_join, by = "GEO_ID")
}

# Grouped-data median by linear interpolation inside the bin that holds the 50th percentile.
median_from_bins <- function(counts, lower, upper) {
  total <- sum(counts)
  if (is.na(total) || total <= 0) return(NA_real_)
  cum <- cumsum(counts)
  i <- which(cum >= total / 2)[1]
  prev <- if (i == 1) 0 else cum[i - 1]
  lower[i] + (total / 2 - prev) / counts[i] * (upper[i] - lower[i])
}

age_bins <- tibble(
  lower = c(0, 5, 10, 15, 18, 20, 21, 22, 25, 30, 35, 40, 45, 50, 55, 60, 62, 65, 67, 70, 75, 80, 85),
  upper = c(5, 10, 15, 18, 20, 21, 22, 25, 30, 35, 40, 45, 50, 55, 60, 62, 65, 67, 70, 75, 80, 85, 100),
  male = sprintf("B01001_E%03d", 3:25),
  female = sprintf("B01001_E%03d", 27:49)
)

income_bins <- tibble(
  lower = c(0, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 75, 100, 125, 150, 200) * 1000,
  upper = c(10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 75, 100, 125, 150, 200, 250) * 1000,
  col = sprintf("B19001_E%03d", 2:17)
)

# `wide` has one row per geography with raw ACS estimate columns. `published_medians` keeps
# the Census-published medians (valid for real ACS geographies); otherwise bin interpolation is used.
acs_measures <- function(wide, published_medians = TRUE) {
  under_18 <- wide |> select(all_of(c(age_bins$male[1:4], age_bins$female[1:4]))) |> rowSums()
  over_65 <- wide |> select(all_of(c(age_bins$male[18:23], age_bins$female[18:23]))) |> rowSums()
  bach <- wide |> select(B15003_E022, B15003_E023, B15003_E024, B15003_E025) |> rowSums()

  age_counts <- map2(age_bins$male, age_bins$female, \(m, f) wide[[m]] + wide[[f]]) |> reduce(cbind)
  inc_counts <- wide |> select(all_of(income_bins$col)) |> as.matrix()
  interp_age <- map_dbl(seq_len(nrow(wide)), \(i) median_from_bins(age_counts[i, ], age_bins$lower, age_bins$upper))
  interp_inc <- map_dbl(seq_len(nrow(wide)), \(i) median_from_bins(inc_counts[i, ], income_bins$lower, income_bins$upper))

  tibble(
    GEO_ID = wide$GEO_ID,
    population = wide$B01003_E001,
    households = wide$B19001_E001,
    median_age = if (published_medians) wide$B01002_E001 else interp_age,
    median_hh_income = if (published_medians) wide$B19013_E001 else interp_inc,
    median_age_interp = interp_age,
    median_hh_income_interp = interp_inc,
    pct_white_nh = wide$B03002_E003 / wide$B03002_E001,
    pct_black = wide$B03002_E004 / wide$B03002_E001,
    pct_asian = wide$B03002_E006 / wide$B03002_E001,
    pct_hispanic = wide$B03002_E012 / wide$B03002_E001,
    pct_bachelors_plus = bach / wide$B15003_E001,
    pct_under_18 = under_18 / wide$B01001_E001,
    pct_65_plus = over_65 / wide$B01001_E001
  )
}
