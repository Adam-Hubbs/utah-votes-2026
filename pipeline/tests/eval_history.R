# County top-of-ticket votes and active registration by election year, shared by the turnout-model evaluation scripts.
# Registration by county is only published for 2022 and 2026 in this repo, so earlier years scale the statewide active-voter
# total (weekly series from vote.utah.gov) by a county share extrapolated from the 2022 -> 2026 trend.
suppressPackageStartupMessages(library(readxl))

# 2016 (precinct file: the county file omits several counties) and 2018 come from OpenElections; 2020 and 2022 from the last Wayback capture of the official site's
# top-of-ticket county table (pipeline/data/timing, built by build_count_timeline.R); 2024 from county_baselines.csv.
votes_top_by_county <- function() {
  oe <- \(file, office, year) {
    read_csv(raw_dir("openelections", file), col_types = cols(.default = "c", votes = "d"), show_col_types = FALSE) |>
      filter(.data$office == .env$office) |>
      summarise(votes = sum(votes, na.rm = TRUE), .by = county) |>
      transmute(county_name = county, votes, year = year)
  }
  wayback <- read_csv(
    file.path(project_root(), "pipeline", "data", "timing", "old_site_raw_contest_county_snapshots.csv"),
    col_types = cols(.default = "c", counted = "d"), show_col_types = FALSE
  ) |>
    filter((election_year == "2020" & contest_id == "399789495") | (election_year == "2022" & contest_id == "451556070")) |>
    slice_max(timestamp, n = 1, by = c(election_year, county)) |>
    transmute(county_name = county, votes = counted, year = as.integer(election_year))
  base <- read_csv(file.path(project_root(), "pipeline", "config", "county_baselines.csv"), col_types = cols(fips = "c"), show_col_types = FALSE)
  bind_rows(
    oe("20161108__ut__general__precinct.csv", "President", 2016L),
    oe("20181106__ut__general__county.csv", "U.S. Senate", 2018L),
    wayback,
    transmute(base, county_name = name, votes = votes_top_2024, year = 2024L)
  ) |>
    mutate(fips = county_fips_from_name(str_replace(county_name, "San Pete", "Sanpete"))) |>
    summarise(votes = sum(votes), .by = c(year, fips)) |>
    filter(!is.na(fips))
}

statewide_active <- function() {
  weekly <- \(year) {
    x <- read_excel(raw_dir("timing", "reg", str_c(year, ".xlsx")), col_names = FALSE, .name_repair = "minimal") |> suppressMessages()
    if (year == 2016) {
      dates <- x[[1]][!is.na(suppressWarnings(as.numeric(x[[1]])))] |> as.numeric()
      total <- x[[ncol(x)]][which(x[[1]] == "Active")] |> as.numeric()
      return(tibble(date = as.Date(dates, origin = "1899-12-30"), active = total))
    }
    dates <- x[1, -(1:2)] |> unlist() |> as.numeric()
    total <- x[which(x[[2]] == "Total Active Voters")[1], -(1:2)] |> unlist() |> as.numeric()
    tibble(date = as.Date(dates, origin = "1899-12-30"), active = total) |> filter(!is.na(date), !is.na(active))
  }
  map(c(2016L, 2018L, 2020L, 2022L, 2024L), \(y) weekly(y) |> mutate(year = y)) |>
    list_rbind() |>
    mutate(election = as.Date(str_c(year, "-11-01"))) |>
    filter(date <= election) |>
    slice_max(date, n = 1, by = year) |>
    select(year, reg_date = date, active_statewide = active)
}

county_registration_by_year <- function() {
  base <- read_csv(file.path(project_root(), "pipeline", "config", "county_baselines.csv"), col_types = cols(fips = "c"), show_col_types = FALSE)
  share22 <- base$registered_2022 / sum(base$registered_2022)
  share26 <- base$registered_2026 / sum(base$registered_2026)
  tot <- statewide_active()
  crossing(year = c(2016L, 2018L, 2020L, 2022L, 2024L), tibble(fips = base$fips, s22 = share22, s26 = share26)) |>
    mutate(share = pmax(s22 + (year - 2022) / 4 * (s26 - s22), 1e-5)) |>
    mutate(share = share / sum(share), .by = year) |>
    left_join(tot, by = "year") |>
    mutate(registered = if_else(year == 2022L, base$registered_2022[match(fips, base$fips)], share * active_statewide)) |>
    select(year, fips, registered)
}

county_history <- function() {
  votes_top_by_county() |>
    inner_join(county_registration_by_year(), by = c("year", "fips")) |>
    mutate(turnout = votes / registered)
}
