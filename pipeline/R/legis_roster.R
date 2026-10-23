# Legislator roster (le.utah.gov) and the seat table seeded from it.

LEG_ROSTER_URL <- "https://le.utah.gov/data/legislators.json"

LEG_SENATE_UP_2026 <- c(1, 5, 6, 7, 9, 11, 12, 13, 14, 18, 19, 20, 21, 23, 28)

fetch_legislator_roster <- function(force = FALSE) {
  path <- raw_dir("legislature", "legislators.json")
  if (force || !file.exists(path)) {
    download.file(LEG_ROSTER_URL, path, mode = "wb", quiet = TRUE)
  }
  read_json(path, simplifyVector = TRUE)$legislators |>
    as_tibble() |>
    transmute(
      chamber = if_else(house == "H", "house", "senate"),
      district = as.integer(district),
      holder = formatName,
      holder_party = case_when(party == "R" ~ "REP", party == "D" ~ "DEM", party == "F" ~ "FWD", .default = party),
      holder_since = serviceStart
    )
}

last_name_pattern <- function(holder) {
  holder |>
    str_remove(",?\\s+(Jr\\.?|Sr\\.?|II|III)$") |>
    word(-1) |>
    str_c("\\b", x = _, "\\b") |>
    regex(ignore_case = TRUE)
}

# Candidates that appear on the 2026 ballot, from the scraped summary (state-house / state-senate offices).
ballot_candidates <- function(summary) {
  summary$contests |>
    keep(\(c) c$office %in% c("state-house", "state-senate")) |>
    map(\(c) {
      tibble(
        chamber = str_remove(c$office, "state-"),
        district = as.integer(c$district),
        name = map_chr(c$candidates, "name"),
        party = map_chr(c$candidates, \(x) x$party %||% NA_character_)
      )
    }) |>
    list_rbind()
}

seed_legislature_seats <- function(summary) {
  roster <- fetch_legislator_roster()
  cands <- ballot_candidates(summary)
  seats <- bind_rows(
    tibble(chamber = "house", district = 1:75),
    tibble(chamber = "senate", district = 1:29)
  ) |>
    left_join(roster, by = c("chamber", "district"))

  running <- seats |>
    filter(!is.na(holder)) |>
    left_join(cands, by = c("chamber", "district"), relationship = "many-to-many") |>
    summarise(
      incumbent_running = any(str_detect(name, last_name_pattern(first(holder))) & !is.na(name)),
      .by = c(chamber, district)
    )

  # Members who hold one seat but appear on the ballot for a different one (e.g. House member running for Senate).
  moving <- seats |>
    filter(!is.na(holder)) |>
    cross_join(cands |> rename(c_chamber = chamber, c_district = district)) |>
    filter(
      str_detect(name, last_name_pattern(holder)),
      str_detect(name, regex(str_c("\\b", word(holder, 1), "\\b"), ignore_case = TRUE)),
      chamber != c_chamber | district != c_district
    ) |>
    transmute(chamber, district, running_for = str_c(c_chamber, "-", c_district))

  contested <- cands |>
    filter(name != "Write-in") |>
    summarise(n_candidates = n(), .by = c(chamber, district))

  seats |>
    left_join(running, by = c("chamber", "district")) |>
    left_join(contested, by = c("chamber", "district")) |>
    left_join(moving, by = c("chamber", "district")) |>
    mutate(
      vacant = is.na(holder),
      up_2026 = chamber == "house" | district %in% LEG_SENATE_UP_2026,
      on_ballot_data = !is.na(n_candidates),
      incumbent_running = if_else(up_2026 & on_ballot_data & !vacant, incumbent_running, NA),
      uncontested = if_else(on_ballot_data, n_candidates < 2, NA)
    ) |>
    select(chamber, district, holder, holder_party, holder_since, vacant, up_2026, incumbent_running, running_for, uncontested) |>
    arrange(chamber, district) |>
    mutate(source = "le.utah.gov/data/legislators.json; candidates from results/2026-general/summary.json", note = "")
}
