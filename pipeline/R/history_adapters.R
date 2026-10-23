# Source-specific adapters producing the common election representation (see history_common.R).

# ---- Utah official media export (2023+) ------------------------------------------------------------

ut_gov_2024_names <- c(
  "SPENCER J. COX DEIDRE M. HENDERSON" = "Spencer J. Cox",
  "TOMMY WILLIAMS ARCHIE A. WILLIAMS III" = "Tommy Williams",
  "BRIAN SMITH KING REBEKAH CUMMINGS" = "Brian King",
  "J. ROBERT LATHAM BARRY EVAN SHORT" = "J. Robert Latham",
  "TOM TOMENY WILLIAM LANSING TAYLOR" = "Tom Tomeny",
  "PHIL LYMAN NATALIE CLAWSON" = "Phil Lyman",
  "CHARLIE TAUTUAA SYLVIA MIERA FISK" = "Charlie Tautuaa"
)

ut_contest_id <- function(name) {
  n <- str_squish(name)
  case_when(
    n == "U.S. President" ~ "president",
    n == "U.S. Senate" ~ "us-senate",
    str_detect(n, "^U\\.S\\. House [0-9]$") ~ str_c("us-house-", str_extract(n, "[0-9]$")),
    n == "Governor" ~ "governor",
    n == "Attorney General" ~ "attorney-general",
    n == "State Auditor" ~ "state-auditor",
    n == "State Treasurer" ~ "state-treasurer",
    str_detect(n, "^Constitutional Amendment [A-Z]$") ~ str_c("amendment-", str_to_lower(str_extract(n, "[A-Z]$"))),
    .default = NA_character_
  )
}

adapt_ut_export <- function(tables, members, election_id, precinct_geo, cd_plan) {
  contest_map <- tables$meta |>
    mutate(contest_id = ut_contest_id(name)) |>
    filter(!is.na(contest_id)) |>
    select(item_id, contest_id)

  cands <- tables$state |>
    inner_join(contest_map, by = "item_id") |>
    mutate(
      raw = option,
      name = case_when(
        contest_id == "governor" & raw %in% names(ut_gov_2024_names) ~ unname(ut_gov_2024_names[raw]),
        contest_id == "president" ~ pretty_name(str_remove(raw, "\\s*/.*$")),
        .default = pretty_name(raw)
      ),
      party = if_else(str_starts(contest_id, "amendment-"), NA_character_, party_code(party))
    ) |>
    select(contest_id, option_id, name, party) |>
    unique_candidate_ids() |>
    tag_incumbents(election_id)

  option_key <- cands |> select(contest_id, option_id, candidate_id)

  county_votes <- tables$county |>
    inner_join(contest_map, by = "item_id") |>
    inner_join(option_key, by = c("contest_id", "option_id")) |>
    transmute(contest_id, county_fips, candidate_id, votes = as.integer(county_votes))

  unit_lookup <- members |> select(county_fips, precinct, unit_id)
  unit_votes <- tables$local |>
    inner_join(contest_map, by = "item_id") |>
    inner_join(option_key, by = c("contest_id", "option_id")) |>
    inner_join(unit_lookup, by = c("county_fips", "precinct")) |>
    summarise(votes = sum(votes), .by = c(contest_id, unit_id, county_fips, candidate_id))

  contests <- make_contests(unique(contest_map$contest_id)) |>
    arrange(match(contest_id, c("president", "us-senate", "us-house-1", "us-house-2", "us-house-3", "us-house-4", "governor", "attorney-general", "state-auditor", "state-treasurer")), contest_id)

  list(
    meta = list(
      election_id = election_id, name = tables$election_name, date = tables$election_date,
      precinct_geo = precinct_geo, cd_plan = cd_plan, source = "electionresults.utah.gov",
      updated_at = NA_character_
    ),
    contests = contests,
    cands = cands |> select(contest_id, candidate_id, name, party, incumbent),
    county_votes = county_votes,
    unit_votes = unit_votes
  )
}

# ---- MEDSL 2022 ----------------------------------------------------------------------------------------

medsl_party_override <- c("EVAN MCMULLIN" = "UNA", "TOMMY WILLIAMS" = "IAP", "JAMES ARTHUR HANSEN" = "LIB")

adapt_medsl_2022 <- function(long, members) {
  long <- long |>
    mutate(
      contest_id = case_when(
        office == "US SENATE" ~ "us-senate",
        office == "US HOUSE" ~ str_c("us-house-", district),
        office == "STATE TREASURER" ~ "state-treasurer",
        .default = NA_character_
      )
    ) |>
    filter(!is.na(contest_id))

  cands <- long |>
    distinct(contest_id, candidate, party) |>
    mutate(
      name = pretty_name(candidate),
      party = coalesce(unname(medsl_party_override[candidate]), party_code(party))
    ) |>
    summarise(party = first(party), .by = c(contest_id, candidate, name)) |>
    unique_candidate_ids() |>
    tag_incumbents("2022-general")

  key <- cands |> select(contest_id, candidate, candidate_id)
  long <- long |> inner_join(key, by = c("contest_id", "candidate"))

  county_votes <- long |>
    summarise(votes = sum(votes), .by = c(contest_id, county_fips, candidate_id))
  unit_votes <- long |>
    inner_join(members |> select(county_fips, precinct, unit_id), by = c("county_fips", "precinct")) |>
    summarise(votes = sum(votes), .by = c(contest_id, unit_id, county_fips, candidate_id))

  list(
    meta = list(
      election_id = "2022-general", name = "2022 General Election", date = "2022-11-08",
      precinct_geo = "precincts_2022", cd_plan = "cd2022", source = "MEDSL precinct returns (Harvard Dataverse)",
      updated_at = NA_character_
    ),
    contests = make_contests(unique(cands$contest_id)) |>
      arrange(match(contest_id, c("us-senate", "us-house-1", "us-house-2", "us-house-3", "us-house-4", "state-treasurer"))),
    cands = cands |> select(contest_id, candidate_id, name, party, incumbent),
    county_votes = county_votes,
    unit_votes = unit_votes
  )
}

# ---- VEST (2016, 2018, 2020) ----------------------------------------------------------------------------

vest_candidates <- tribble(
  ~year, ~code, ~name, ~party,
  2016, "G16PRERTRU", "Donald Trump", "REP",
  2016, "G16PREDCLI", "Hillary Clinton", "DEM",
  2016, "G16PRELJOH", "Gary Johnson", "LIB",
  2016, "G16PRECCAS", "Darrell Castle", "CON",
  2016, "G16PREAGIO", "Rocky Giordani", "IAP",
  2016, "G16PREIMCM", "Evan McMullin", "UNA",
  2016, "G16PREISTE", "Jill Stein", "GRN",
  2016, "G16PREIDEL", "Rocky De La Fuente", "UNA",
  2016, "G16PREIKEN", "Alyson Kennedy", "OTH",
  2016, "G16PREIMOO", "Monica Moorehead", "OTH",
  2016, "G16USSRLEE", "Mike Lee", "REP",
  2016, "G16USSDSNO", "Misty Snow", "DEM",
  2016, "G16USSAFON", "Stoney Fonua", "IAP",
  2016, "G16USSIBAR", "Bill Barron", "UNA",
  2016, "G16GOVRHER", "Gary R. Herbert", "REP",
  2016, "G16GOVDWEI", "Mike Weinholtz", "DEM",
  2016, "G16GOVLKAM", "Brian Kamerath", "LIB",
  2016, "G16GOVASCH", "Superdell Schanze", "IAP",
  2016, "G16ATGRREY", "Sean Reyes", "REP",
  2016, "G16ATGDHAR", "Jon Harper", "DEM",
  2016, "G16ATGLMCC", "W. Andrew McCullough", "LIB",
  2016, "G16ATGAISB", "Michael Isbell", "IAP",
  2016, "G16AUDRDOU", "John Dougall", "REP",
  2016, "G16AUDDMIT", "Mike Mitchell", "DEM",
  2016, "G16AUDAGRE", "Jared Green", "IAP",
  2016, "G16TRERDAM", "David Damschen", "REP",
  2016, "G16TREDHAN", "Neil Hansen", "DEM",
  2016, "G16TRECPRO", "Richard Proctor", "CON",
  2018, "G18USSRROM", "Mitt Romney", "REP",
  2018, "G18USSDWIL", "Jenny Wilson", "DEM",
  2018, "G18USSLBOW", "Craig Bowden", "LIB",
  2018, "G18USSCAAL", "Tim Aalders", "CON",
  2018, "G18USSAMCC", "Reed McCandless", "IAP",
  2020, "G20PRERTRU", "Donald J. Trump", "REP",
  2020, "G20PREDBID", "Joseph R. Biden", "DEM",
  2020, "G20PRELJOR", "Jo Jorgensen", "LIB",
  2020, "G20PREGHAW", "Howie Hawkins", "GRN",
  2020, "G20PRECBLA", "Don Blankenship", "CON",
  2020, "G20PREIWES", "Kanye West", "UNA",
  2020, "G20PREIPIE", "Brock Pierce", "UNA",
  2020, "G20PREIMCH", "Joe McHugh", "UNA",
  2020, "G20PREILAR", "Gloria La Riva", "UNA",
  2020, "G20GOVRCOX", "Spencer J. Cox", "REP",
  2020, "G20GOVDPET", "Chris Peterson", "DEM",
  2020, "G20GOVLCOT", "Daniel Cottam", "LIB",
  2020, "G20GOVADUE", "Greg Duerden", "IAP",
  2020, "G20ATGRREY", "Sean D. Reyes", "REP",
  2020, "G20ATGDSKO", "Greg Skordas", "DEM",
  2020, "G20ATGLBAU", "Rudy J. Bautista", "LIB",
  2020, "G20AUDRDOU", "John Dougall", "REP",
  2020, "G20AUDCOST", "Jeffrey L. Ostler", "CON",
  2020, "G20AUDUFAB", "Brian L. Fabbi", "UUP",
  2020, "G20TRERDAM", "David Damschen", "REP",
  2020, "G20TRELSPE", "Joseph Speciale", "LIB",
  2020, "G20TRECPRO", "Richard Proctor", "CON"
) |>
  mutate(
    office_code = str_sub(code, 4, 6),
    contest_id = case_when(
      office_code == "PRE" ~ "president", office_code == "USS" ~ "us-senate", office_code == "GOV" ~ "governor",
      office_code == "ATG" ~ "attorney-general", office_code == "AUD" ~ "state-auditor", office_code == "TRE" ~ "state-treasurer"
    )
  )

adapt_vest <- function(vest_sf, year) {
  cand_defs <- vest_candidates |> filter(.data$year == !!year)
  tbl <- vest_sf |> sf::st_drop_geometry() |> as_tibble()
  long <- tbl |>
    select(unit_id = precinct_id, county_fips, all_of(cand_defs$code)) |>
    pivot_longer(all_of(cand_defs$code), names_to = "code", values_to = "votes") |>
    mutate(votes = as.integer(votes)) |>
    left_join(cand_defs |> select(code, contest_id, name, party), by = "code")

  election_id <- str_c(year, "-general")
  cands <- cand_defs |>
    transmute(contest_id, name, party, code) |>
    unique_candidate_ids() |>
    tag_incumbents(election_id)
  long <- long |> left_join(cands |> select(code, candidate_id), by = "code")

  list(
    meta = list(
      election_id = election_id, name = str_c(year, " General Election"),
      date = c(`2016` = "2016-11-08", `2018` = "2018-11-06", `2020` = "2020-11-03")[[as.character(year)]],
      precinct_geo = str_c("precincts_", year), cd_plan = "cd2012",
      source = "VEST precinct-level election results (Harvard Dataverse)", updated_at = NA_character_
    ),
    contests = make_contests(unique(cand_defs$contest_id)) |>
      arrange(match(contest_id, c("president", "us-senate", "governor", "attorney-general", "state-auditor", "state-treasurer"))),
    cands = cands |> select(contest_id, candidate_id, name, party, incumbent),
    county_votes = long |> summarise(votes = sum(votes), .by = c(contest_id, county_fips, candidate_id)),
    unit_votes = long |> filter(votes > 0) |> select(contest_id, unit_id, county_fips, candidate_id, votes)
  )
}

# ---- OpenElections U.S. House (county level) --------------------------------------------------------------

house_candidates <- tribble(
  ~year, ~district, ~pattern, ~name, ~party,
  2016, 1, "bishop", "Rob Bishop", "REP",
  2016, 1, "clemens", "Peter Clemens", "DEM",
  2016, 1, "bowden", "Craig Bowden", "LIB",
  2016, 1, "fairbanks", "Chadwick Fairbanks", "UNA",
  2016, 2, "stewart", "Chris Stewart", "REP",
  2016, 2, "albarran", "Charlene Albarran", "DEM",
  2016, 2, "mccollaum", "Paul McCollaum", "CON",
  2016, 3, "chaffetz", "Jason Chaffetz", "REP",
  2016, 3, "tryon", "Stephen Tryon", "DEM",
  2016, 4, "love", "Mia Love", "REP",
  2016, 4, "owens", "Doug Owens", "DEM",
  2016, 4, "simonsen", "Collin Simonsen", "CON",
  2018, 1, "bishop", "Rob Bishop", "REP",
  2018, 1, "castillo", "Lee Castillo", "DEM",
  2018, 1, "eliason", "Eric Eliason", "UUP",
  2018, 1, "davis", "Adam Davis", "GRN",
  2018, 2, "stewart", "Chris Stewart", "REP",
  2018, 2, "ghorbani", "Shireen Ghorbani", "DEM",
  2018, 2, "whipple", "Jeffrey Whipple", "LIB",
  2018, 3, "curtis", "John Curtis", "REP",
  2018, 3, "singer", "James Courage Singer", "DEM",
  2018, 3, "duerden", "Gregory C. Duerden", "IAP",
  2018, 3, "zeidner", "Timothy L. Zeidner", "UUP",
  2018, 4, "love", "Mia B. Love", "REP",
  2018, 4, "mcadams", "Ben McAdams", "DEM",
  2020, 1, "moore", "Blake D. Moore", "REP",
  2020, 1, "parry", "Darren Parry", "DEM",
  2020, 2, "stewart", "Chris Stewart", "REP",
  2020, 2, "weston", "Kael Weston", "DEM",
  2020, 2, "latham", "J. Robert Latham", "LIB",
  2020, 3, "curtis", "John Curtis", "REP",
  2020, 3, "thorpe", "Devin D. Thorpe", "DEM",
  2020, 3, "cummings", "Daniel Clyde Cummings", "CON",
  2020, 3, "mcneill", "Thomas G. McNeill", "UUP",
  2020, 4, "owens", "Burgess Owens", "REP",
  2020, 4, "mcadams", "Ben McAdams", "DEM",
  2020, 4, "molnar", "John Molnar", "LIB",
  2020, 4, "broderick", "Jonia M. Broderick", "UUP"
)

openelections_house <- function(year) {
  file <- c(
    `2016` = "20161108__ut__general__county.csv",
    `2018` = "20181106__ut__general__county.csv",
    `2020` = "20201103__ut__general__precinct.csv"
  )[[as.character(year)]]
  path_in_repo <- str_c(year, "/", file)
  path <- download_cached(
    str_c("https://raw.githubusercontent.com/openelections/openelections-data-ut/master/", path_in_repo),
    raw_dir("openelections", file)
  )
  raw <- read_csv(path, col_types = cols(.default = col_character()), progress = FALSE) |>
    filter(office == "U.S. House") |>
    mutate(
      district = as.integer(district),
      votes = as.integer(str_remove_all(votes, ",") |> replace_values("" ~ "0")),
      county_fips = county_fips_from_name(county |> str_replace("^San Pete$", "Sanpete") |> str_replace("^Salt Lake City$", "Salt Lake"))
    )
  defs <- house_candidates |> filter(.data$year == !!year)
  classified <- raw |>
    mutate(
      key = str_to_lower(candidate),
      pattern = map_chr(key, \(k) {
        hit <- defs$pattern[str_detect(k, defs$pattern)]
        if (length(hit) == 0) NA_character_ else hit[[1]]
      })
    ) |>
    left_join(defs |> transmute(district = as.integer(district), pattern, name, party_std = party), by = c("district", "pattern")) |>
    filter(!is.na(name))
  classified |>
    select(-party) |>
    rename(party = party_std) |>
    summarise(votes = sum(votes), .by = c(district, county_fips, name, party))
}

adapt_house_county <- function(year, el) {
  hv <- openelections_house(year)
  cands <- hv |>
    distinct(district, name, party) |>
    mutate(contest_id = str_c("us-house-", district)) |>
    select(contest_id, name, party) |>
    unique_candidate_ids() |>
    tag_incumbents(str_c(year, "-general"))
  cv <- hv |>
    mutate(contest_id = str_c("us-house-", district)) |>
    inner_join(cands |> select(contest_id, name, candidate_id), by = c("contest_id", "name")) |>
    select(contest_id, county_fips, candidate_id, votes)
  el$contests <- bind_rows(el$contests, make_contests(unique(cands$contest_id))) |>
    arrange(match(contest_id, c("president", "us-senate", "us-house-1", "us-house-2", "us-house-3", "us-house-4", "governor", "attorney-general", "state-auditor", "state-treasurer")))
  el$cands <- bind_rows(el$cands, cands |> select(contest_id, candidate_id, name, party, incumbent))
  el$county_votes <- bind_rows(el$county_votes, cv)
  el
}
