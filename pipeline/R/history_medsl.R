# MEDSL (MIT Election Data + Science Lab) precinct returns for Utah 2022 from Harvard Dataverse.

medsl_2022_url <- "https://dataverse.harvard.edu/api/access/datafile/10855134"

medsl_junk <- regex(
  "^(total votes|total votes cast|over ?votes|under ?votes|contest totals?|not assigned|write-?in.*|ballots cast.*|registered.*)$",
  ignore_case = TRUE
)

medsl_2022_long <- function() {
  path <- download_cached(medsl_2022_url, raw_dir("medsl", "2022-ut-precinct-general.tab"))
  read_tsv(path, col_types = cols(.default = col_character()), quote = "\"", progress = FALSE) |>
    filter(mode == "TOTAL", office %in% c("US SENATE", "US HOUSE", "STATE TREASURER", "STATE AUDITOR", "STATE CONSTITUTIONAL AMENDMENT")) |>
    filter(!str_detect(candidate, medsl_junk), !is.na(candidate)) |>
    transmute(
      county_fips = county_fips,
      precinct = str_squish(precinct),
      office,
      district = as.integer(district),
      candidate = str_squish(candidate),
      party = party_simplified,
      votes = coalesce(as.integer(votes), 0L)
    ) |>
    summarise(votes = sum(votes), .by = c(county_fips, precinct, office, district, candidate, party))
}
