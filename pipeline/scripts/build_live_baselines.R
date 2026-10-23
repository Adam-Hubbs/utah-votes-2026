#!/usr/bin/env Rscript
# One-off (re-runnable) builder for pipeline/config/county_baselines.csv, the prior inputs of the
# expected-vote model: current registration, 2022 midterm turnout, 2024 presidential totals.
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "live_api.R"))

vr_pdf <- raw_dir("live", "vr_2026_10.pdf")
if (!file.exists(vr_pdf)) {
  download.file(
    "https://vote.utah.gov/wp-content/uploads/2026/10/10.19.2026-Active-Voters-by-County-and-Party.pdf",
    vr_pdf, mode = "wb", quiet = TRUE
  )
}
vr_lines <- system2("pdftotext", c("-layout", shQuote(vr_pdf), "-"), stdout = TRUE)
registered_2026 <- tibble(line = vr_lines) |>
  mutate(
    line = str_remove_all(line, "\\f"),
    voters = str_extract(line, "[0-9,]+\\s*$") |> str_remove_all("[,\\s]") |> as.numeric(),
    county = str_extract(line, "^(Box Elder|Salt Lake|San Juan|[A-Z][a-z]+)(?=\\s{2,})")
  ) |>
  filter(!is.na(county), !is.na(voters)) |>
  summarise(registered_2026 = sum(voters), .by = county) |>
  mutate(fips = county_fips_from_name(county))

dw <- read_tsv("https://datawrapper.dwcdn.net/uHuTJ/1/dataset.csv", show_col_types = FALSE) |>
  transmute(
    fips = county_fips_from_name(County),
    registered_2022 = `Registered Voters`,
    ballots_2022 = `Total Ballots Cast`
  )

exp2024 <- raw_dir("live", "export-general11052024.json")
if (!file.exists(exp2024)) {
  ev_request("https://electionresults.utah.gov/cdn/results/Utah/export-general11052024.json", 180) |>
    req_perform(path = exp2024)
}
j24 <- jsonlite::fromJSON(exp2024, simplifyVector = FALSE)
pres_2024 <- j24$localResults |>
  map(\(lr) {
    b <- keep(lr$ballotItems, \(b) str_detect(b$name, regex("president", ignore_case = TRUE)))[[1]]
    tibble(fips = county_fips_from_name(lr$name), votes_top_2024 = sum(map_dbl(b$ballotOptions, \(o) o$voteCount)))
  }) |>
  list_rbind()

baselines <- utah_counties |>
  select(fips, name) |>
  left_join(select(registered_2026, fips, registered_2026), by = "fips") |>
  left_join(dw, by = "fips") |>
  left_join(pres_2024, by = "fips") |>
  mutate(turnout_2022 = ballots_2022 / registered_2022)

stopifnot(nrow(baselines) == 29, !anyNA(baselines))
write_csv(baselines, file.path(project_root(), "pipeline", "config", "county_baselines.csv"))
print(summarise(baselines, across(where(is.numeric), sum)))
