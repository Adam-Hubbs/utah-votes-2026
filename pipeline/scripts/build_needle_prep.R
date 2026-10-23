#!/usr/bin/env Rscript
# Precinct-level 2024 presidential baseline re-expressed on the 2026 precincts (via the block crosswalk).
# Output: pipeline/config/needle_baseline_2026.csv, committed so the election-night runner needs no raw cache.
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
for (f in c("live_api", "live_normalize", "model_expected", "live_sim")) source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))

state <- readRDS(raw_dir("geo", "build_geo_state.rds"))
cw <- read_json(data_dir("history", "crosswalks", "precinct_2024_to_precinct_2026.json"))$weights |>
  imap(\(w, from) tibble(from = from, to = names(w), weight = as.numeric(w))) |>
  list_rbind()

source(file.path(project_root(), "pipeline", "R", "history_ut_export.R"))
tabs <- ut_export_contest_tables(raw_dir("results", "export-general11052024.json"))
pres_id <- tabs$meta |> filter(str_detect(name, regex("president", ignore_case = TRUE))) |> pull(item_id) |> first()
opt <- tabs$state |>
  filter(item_id == pres_id) |>
  transmute(option_id, side = case_when(
    str_detect(option, regex("trump", ignore_case = TRUE)) ~ "rep",
    str_detect(option, regex("harris", ignore_case = TRUE)) ~ "dem",
    .default = "oth"
  ))
lean <- tabs$local |>
  filter(item_id == pres_id) |>
  inner_join(opt, by = "option_id") |>
  summarise(
    dem = sum(votes[side == "dem"]), rep = sum(votes[side == "rep"]), total = sum(votes),
    .by = c(county_fips, precinct)
  ) |>
  mutate(precinct_id = precinct_key(county_fips, precinct)) |>
  select(precinct_id, dem, rep, total)
members <- state$reported_clusters_2024 |>
  mutate(precinct_id = precinct_key(county_fips, precinct)) |>
  left_join(lean, by = "precinct_id") |>
  summarise(dem = sum(dem, na.rm = TRUE), rep = sum(rep, na.rm = TRUE), total = sum(total, na.rm = TRUE), .by = unit_id)

base <- cw |>
  inner_join(members, by = c("from" = "unit_id")) |>
  summarise(dem24 = sum(dem * weight), rep24 = sum(rep * weight), total24 = sum(total * weight), .by = to) |>
  rename(precinct_id = to)

reported <- read_csv(file.path(project_root(), "pipeline", "config", "precincts_2026_reported.csv"), col_types = cols(.default = col_character())) |>
  mutate(precinct_id = precinct_key(county_fips, precinct))
out <- reported |>
  select(precinct_id, county_fips) |>
  left_join(base, by = "precinct_id") |>
  mutate(
    dem24 = round(dem24, 1),
    rep24 = round(rep24, 1),
    total24 = round(total24, 1),
    has_baseline = !is.na(total24) & (dem24 + rep24) > 0
  )
cat("precincts:", nrow(out), " with baseline:", sum(out$has_baseline), "\n")
out |>
  summarise(n = n(), with_baseline = sum(has_baseline), votes24 = sum(total24, na.rm = TRUE), .by = county_fips) |>
  arrange(county_fips) |>
  print(n = 30)
cat("statewide baseline D/R/total:", sum(out$dem24, na.rm = TRUE), sum(out$rep24, na.rm = TRUE), sum(out$total24, na.rm = TRUE), "\n")
write_csv(out, file.path(project_root(), "pipeline", "config", "needle_baseline_2026.csv"), na = "")
