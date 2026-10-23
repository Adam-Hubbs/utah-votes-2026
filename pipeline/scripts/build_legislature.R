#!/usr/bin/env Rscript
# Builds web/public/data/legislature.json and judges.json from the hand-maintained seat/judge tables,
# the scraped 2026 contest list and the 2024 presidential crosswalk.
# --refresh-seats re-seeds pipeline/config/legislature_seats.csv from the le.utah.gov roster (overwrites manual edits).
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "legis_roster.R"))
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "legis_pres24.R"))

seats_csv <- file.path(project_root(), "pipeline", "config", "legislature_seats.csv")
judges_csv <- file.path(project_root(), "pipeline", "config", "judges.csv")
summary <- read_json(data_dir("results", "2026-general", "summary.json"), simplifyVector = FALSE)

if ("--refresh-seats" %in% commandArgs(trailingOnly = TRUE)) {
  write_csv(seed_legislature_seats(summary), seats_csv, na = "")
}

contest_ids <- map_chr(summary$contests, "contest_id")

seats <- read_csv(seats_csv, show_col_types = FALSE, col_types = cols(.default = col_character())) |>
  mutate(
    district = as.integer(district),
    across(c(vacant, up_2026, incumbent_running, uncontested), as.logical)
  ) |>
  left_join(legis_pres24_margins(), by = c("chamber", "district")) |>
  mutate(
    contest_id = str_c("state-", chamber, "-", district),
    contest_id = if_else(contest_id %in% contest_ids & up_2026, contest_id, NA_character_)
  )

count_party <- \(df) {
  df |>
    filter(!is.na(holder_party)) |>
    count(holder_party) |>
    (\(d) set_names(as.list(d$n), d$holder_party))()
}

chamber_block <- function(ch, seats_total, majority, supermajority) {
  s <- seats |> filter(chamber == ch)
  list(
    seats = seats_total,
    majority = majority,
    supermajority = supermajority,
    current = count_party(s),
    holdovers = count_party(filter(s, !up_2026)),
    up_2026 = count_party(filter(s, up_2026)),
    vacant = sum(s$vacant),
    seats_list = s |>
      arrange(district) |>
      pmap(\(district, contest_id, holder, holder_party, holder_since, vacant, up_2026, incumbent_running,
             running_for, uncontested, pres24_margin, pres24_rep_pct, pres24_dem_pct, note, ...) {
        list(
          district = district,
          contest_id = contest_id,
          holder = holder,
          holder_party = holder_party,
          holder_since = holder_since,
          vacant = vacant,
          up = up_2026,
          incumbent_running = incumbent_running,
          running_for = running_for,
          uncontested = uncontested,
          pres24_margin = round(pres24_margin, 4),
          note = if (is.na(note) || note == "") NULL else note
        )
      })
  )
}

# Utah Constitution art. VII: veto override needs two thirds of the members of each house.
legislature <- list(
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  roster_source = "le.utah.gov/data/legislators.json (membership as of the seed date); 2024 presidential margin via 2020-block VAP crosswalk",
  chambers = list(
    house = chamber_block("house", 75L, 38L, 50L),
    senate = chamber_block("senate", 29L, 15L, 20L)
  )
)
write_site_json(legislature, "legislature.json")

judges <- read_csv(judges_csv, show_col_types = FALSE, col_types = cols(.default = col_character())) |>
  filter(contest_id %in% contest_ids)
judges_json <- list(
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  jpec_source = first(judges$jpec_source),
  judges = judges |>
    mutate(across(everything(), \(x) na_if(x, ""))) |>
    pmap(\(contest_id, judge, title, court, court_level, jpec_recommendation, jpec_score_summary, jpec_source,
           appointing_governor, appointed_year, ...) {
      list(
        judge = judge, title = title, court = court, court_level = court_level,
        jpec_recommendation = jpec_recommendation, jpec_score_summary = jpec_score_summary,
        appointing_governor = appointing_governor,
        appointed_year = if (is.na(appointed_year)) NULL else as.integer(appointed_year)
      )
    }) |>
    set_names(judges$contest_id)
)
write_site_json(judges_json, "judges.json")
message(sprintf("legislature.json: %d seats; judges.json: %d judges", nrow(seats), nrow(judges)))
