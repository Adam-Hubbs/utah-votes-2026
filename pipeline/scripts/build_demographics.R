#!/usr/bin/env Rscript
# Usage: Rscript pipeline/scripts/build_demographics.R
# Needs: poppler's pdftotext on the PATH (voter registration PDF).
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
r_dir <- file.path(dirname(normalizePath(script_file)), "..", "R")
source(file.path(r_dir, "utils.R"))
walk(c("demog_acs.R", "demog_districts.R", "demog_registration.R"), \(f) source(file.path(r_dir, f)))

source_label <- "ACS 2020–2024 5-year"
wide <- acs_wide_ut()
geos <- acs_geos_ut()
reg <- county_registration()

unit_cols <- c(
  "id", "name", "population", "median_age", "median_hh_income", "pct_white_nh", "pct_hispanic", "pct_asian",
  "pct_black", "pct_bachelors_plus", "pct_under_18", "pct_65_plus", "pct_urban", "median_method"
)

# Rounded, contract-shaped records; `extra` adds per-unit list fields such as registration.
as_units <- function(measures, extra = list()) {
  units <- measures |>
    mutate(
      population = round(population),
      median_age = round(median_age, 1),
      median_hh_income = round(median_hh_income),
      across(c(starts_with("pct_"), -pct_urban), \(v) round(v, 4))
    ) |>
    select(all_of(unit_cols)) |>
    pmap(list)
  imap(units, \(u, i) c(u, map(extra, \(e) e[[i]])))
}

write_units <- function(units, file, source, ...) {
  write_site_json(list(source = source, ...,  units = units), "demographics", file)
}

published <- acs_measures(wide, published_medians = TRUE) |>
  left_join(select(geos, GEO_ID, SUMLEVEL, NAME), by = "GEO_ID") |>
  mutate(pct_urban = NA_real_, median_method = "published")

state_reg <- reg |>
  summarise(across(c(REP, DEM, UNA, OTH, LIB, CON, FWD, GRN, IAP), sum)) |>
  mutate(total = REP + DEM + UNA + OTH, as_of = registration_as_of)

state <- published |> filter(SUMLEVEL == "040") |> mutate(id = "49", name = "Utah")
write_units(as_units(state, list(registration = list(registration_record(state_reg)))), "state.json", source_label)

counties <- published |>
  filter(SUMLEVEL == "050") |>
  mutate(id = str_remove(GEO_ID, "^0500000US"), name = str_remove(NAME, " County, Utah$")) |>
  left_join(reg, by = c("id" = "fips"))
write_units(
  as_units(counties, list(registration = map(seq_len(nrow(counties)), \(i) registration_record(slice(counties, i))))),
  "counties.json", source_label
)

# Old map (2022-2024): Census publishes ACS for the 119th Congress districts directly.
cd2022 <- published |>
  filter(SUMLEVEL == "500") |>
  mutate(id = as.character(as.integer(str_extract(GEO_ID, "[0-9]{2}$"))), name = str_c("District ", id))
write_units(
  as_units(cd2022, list(registration = rep(list(NULL), nrow(cd2022)))),
  "cd2022.json",
  str_c(source_label, " (published for the 119th Congress districts, i.e. the 2022\u20132024 map)")
)

# New map (2026): block-group counts split across districts by 2020 block population.
shares <- bg_district_shares("cd2026")
composition <- district_county_composition("cd2026")
cd2026 <- aggregate_to_districts(wide, shares) |>
  acs_measures(published_medians = FALSE) |>
  mutate(id = GEO_ID, name = str_c("District ", id), pct_urban = NA_real_, median_method = "interpolated_from_bins")
cd2026_counties <- map(cd2026$id, \(d) {
  composition |>
    filter(district == as.integer(d)) |>
    transmute(fips, name = county, share = round(share, 4)) |>
    pmap(list)
})
write_units(
  as_units(cd2026, list(registration = rep(list(NULL), nrow(cd2026)), counties = cd2026_counties)),
  "cd2026.json",
  str_c(source_label, ", allocated to the 2026 court-ordered districts"),
  method = str_c(
    "Each 2020 census block is assigned to a 2026 district by its internal point (UGRC district boundaries, adopted Nov 2025). ",
    "A block group's ACS counts are split across districts in proportion to the 2020 population of its blocks in each district ",
    "(uniform-within-block-group assumption). Counts are summed, then percentages are computed from summed numerators and denominators. ",
    "Medians are approximate: median age and household income are interpolated from the summed age and income-bracket counts. ",
    "Validated by applying the same method to the 2022-2024 districts and comparing with published ACS: population within 0.3%, ",
    "percentages within about 0.3 points, medians within 1%. Voter registration is not published by congressional district."
  )
)
message("demographics written")
