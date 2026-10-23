# Shared representation for historical elections:
#   meta         one-row list: election_id, name, date, precinct_geo, cd_plan, source, updated_at
#   contests     contest_id, name, office, district, type
#   cands        contest_id, candidate_id, name, party
#   county_votes contest_id, county_fips, candidate_id, votes
#   unit_votes   contest_id, unit_id, county_fips, candidate_id, votes   (precinct geometry units)

party_code <- function(x) {
  y <- str_to_lower(coalesce(x, ""))
  case_when(
    str_detect(y, "^rep") ~ "REP",
    str_detect(y, "^dem") ~ "DEM",
    str_detect(y, "^lib|^lbt") ~ "LIB",
    str_detect(y, "^con") ~ "CON",
    str_detect(y, "^gre|^grn") ~ "GRN",
    str_detect(y, "independent american|^iap") ~ "IAP",
    str_detect(y, "^unaff|^una|^ind") ~ "UNA",
    str_detect(y, "united utah|^uup") ~ "UUP",
    str_detect(y, "forward|^fwd") ~ "FWD",
    .default = "OTH"
  )
}

pretty_name <- function(x) {
  x <- str_squish(x)
  shout <- x == str_to_upper(x)
  fixed <- x |>
    str_to_title() |>
    str_replace_all("\\bMc([a-z])", \(m) str_c("Mc", str_to_upper(str_sub(m, 3, 3)))) |>
    str_replace_all("\\bO'([a-z])", \(m) str_c("O'", str_to_upper(str_sub(m, 3, 3)))) |>
    str_replace_all("\\b(Ii|Iii|Iv)\\b", str_to_upper) |>
    str_replace_all("\\bJd\\b", "JD")
  if_else(shout, fixed, x)
}

incumbent_rules <- tribble(
  ~election_id, ~contest_id, ~pattern,
  "2024-general", "us-house-1", "Moore",
  "2024-general", "us-house-2", "Maloy",
  "2024-general", "us-house-3", "Kennedy",
  "2024-general", "us-house-4", "Owens",
  "2024-general", "governor", "Cox",
  "2024-general", "state-treasurer", "Oaks",
  "2022-general", "us-senate", "Lee",
  "2022-general", "us-house-1", "Moore",
  "2022-general", "us-house-2", "Stewart",
  "2022-general", "us-house-3", "Curtis",
  "2022-general", "us-house-4", "Owens",
  "2022-general", "state-treasurer", "Oaks",
  "2020-general", "president", "Trump",
  "2020-general", "attorney-general", "Reyes",
  "2020-general", "state-auditor", "Dougall",
  "2020-general", "state-treasurer", "Damschen",
  "2020-general", "us-house-2", "Stewart",
  "2020-general", "us-house-3", "Curtis",
  "2020-general", "us-house-4", "McAdams",
  "2018-general", "us-house-1", "Bishop",
  "2018-general", "us-house-2", "Stewart",
  "2018-general", "us-house-3", "Curtis",
  "2018-general", "us-house-4", "Love",
  "2016-general", "us-senate", "Lee",
  "2016-general", "governor", "Herbert",
  "2016-general", "attorney-general", "Reyes",
  "2016-general", "state-auditor", "Dougall",
  "2016-general", "state-treasurer", "Damschen",
  "2016-general", "us-house-1", "Bishop",
  "2016-general", "us-house-2", "Stewart",
  "2016-general", "us-house-3", "Chaffetz",
  "2016-general", "us-house-4", "Love"
)

contest_label <- function(contest_id, district = NA_integer_) {
  case_when(
    contest_id == "president" ~ "President",
    contest_id == "us-senate" ~ "U.S. Senate",
    contest_id == "governor" ~ "Governor",
    contest_id == "attorney-general" ~ "Attorney General",
    contest_id == "state-auditor" ~ "State Auditor",
    contest_id == "state-treasurer" ~ "State Treasurer",
    str_starts(contest_id, "us-house-") ~ str_c("U.S. House District ", district),
    str_starts(contest_id, "amendment-") ~ str_c("Constitutional Amendment ", str_to_upper(str_remove(contest_id, "^amendment-"))),
    .default = contest_id
  )
}

make_contests <- function(contest_ids) {
  tibble(contest_id = contest_ids) |>
    mutate(
      district = suppressWarnings(as.integer(str_extract(contest_id, "(?<=us-house-)[0-9]+"))),
      name = contest_label(contest_id, district),
      office = case_when(
        str_starts(contest_id, "us-house-") ~ "us-house",
        str_starts(contest_id, "amendment-") ~ "amendment",
        .default = contest_id
      ),
      type = if_else(office == "amendment", "measure", "candidate")
    )
}

unique_candidate_ids <- function(cands) {
  cands |>
    mutate(base = if_else(name %in% c("For", "Against", "Yes", "No"), str_to_lower(name), slugify(name))) |>
    mutate(candidate_id = if_else(n() > 1, str_c(base, "-", row_number()), base), .by = c(contest_id, base)) |>
    select(-base)
}

tag_incumbents <- function(cands, election_id) {
  rules <- incumbent_rules |> filter(.data$election_id == !!election_id)
  cands |>
    left_join(rules, by = "contest_id") |>
    mutate(incumbent = map2_lgl(name, pattern, \(n, p) !is.na(p) && str_detect(n, p))) |>
    select(-election_id, -pattern)
}

county_name <- \(fips) utah_counties$name[match(fips, utah_counties$fips)]

as_votes <- function(ids, votes) {
  keep <- votes > 0
  as.list(set_names(as.integer(votes[keep]), ids[keep]))
}

write_election <- function(el, out_root = "results") {
  meta <- el$meta
  dir <- file.path(out_root, meta$election_id)

  totals <- el$county_votes |>
    summarise(votes = sum(votes), .by = c(contest_id, candidate_id))
  cand_tbl <- el$cands |>
    left_join(totals, by = c("contest_id", "candidate_id")) |>
    mutate(votes = coalesce(votes, 0L)) |>
    mutate(
      total = sum(votes),
      pct = if_else(total > 0, votes / total, 0),
      winner = votes == max(votes) & votes > 0,
      .by = contest_id
    )

  county_ballots <- el$county_votes |>
    summarise(total = sum(votes), .by = c(contest_id, county_fips)) |>
    summarise(ballots = max(total), .by = county_fips)

  summary_contests <- el$contests |>
    pmap(\(contest_id, name, office, district, type) {
      cs <- cand_tbl |> filter(.data$contest_id == !!contest_id)
      n_counties <- el$county_votes |> filter(.data$contest_id == !!contest_id) |> distinct(county_fips) |> nrow()
      winner_id <- cs$candidate_id[cs$winner][1]
      list(
        contest_id = contest_id,
        name = name,
        office = office,
        district = district,
        type = type,
        featured = contest_id %in% c("president", "us-senate", "governor") || str_starts(contest_id, "us-house-"),
        total_votes = sum(cs$votes),
        candidates = pmap(
          cs |> arrange(desc(votes)),
          \(candidate_id, name, party, incumbent, votes, pct, winner, ...) list(
            candidate_id = candidate_id, name = name, party = party,
            incumbent = incumbent, votes = votes, pct = round(pct, 5), winner = winner
          )
        ),
        reporting = list(
          counties_reporting = n_counties, counties_total = n_counties,
          pct_expected = 1, pct_expected_lo = 1, pct_expected_hi = 1
        ),
        call = if (is.na(winner_id)) NA else list(candidate_id = winner_id, called_at = NA, by = "certified")
      )
    })

  summary <- list(
    election_id = meta$election_id,
    name = meta$name,
    date = meta$date,
    status = "final",
    updated_at = meta$updated_at,
    source = meta$source,
    precinct_geo = meta$precinct_geo,
    cd_plan = meta$cd_plan,
    turnout = list(
      ballots_counted = sum(county_ballots$ballots),
      registered = NA,
      expected_ballots = sum(county_ballots$ballots),
      expected_lo = sum(county_ballots$ballots),
      expected_hi = sum(county_ballots$ballots),
      pct_expected = 1
    ),
    contests = summary_contests
  )
  write_site_json(summary, dir, "summary.json")

  walk(el$contests$contest_id, \(cid) {
    cs <- el$cands |> filter(contest_id == cid)
    cv <- el$county_votes |> filter(contest_id == cid)
    counties <- cv |>
      group_split(county_fips) |>
      map(\(g) {
        tot <- sum(g$votes)
        list(
          fips = g$county_fips[[1]], name = county_name(g$county_fips[[1]]),
          votes = as_votes(g$candidate_id, g$votes), total = tot,
          ballots_counted = tot, expected_ballots = tot, pct_expected = 1,
          pct_expected_lo = 1, pct_expected_hi = 1
        )
      })
    precincts <- el$unit_votes |>
      filter(contest_id == cid) |>
      group_split(unit_id) |>
      map(\(g) list(precinct_id = g$unit_id[[1]], votes = as_votes(g$candidate_id, g$votes), total = sum(g$votes)))
    write_site_json(
      list(
        contest_id = cid, election_id = meta$election_id, updated_at = meta$updated_at,
        candidates = pmap(cs, \(candidate_id, name, party, ...) list(candidate_id = candidate_id, name = name, party = party)),
        counties = counties,
        precincts = precincts
      ),
      dir, "contests", str_c(cid, ".json")
    )
  })
  invisible(summary)
}
