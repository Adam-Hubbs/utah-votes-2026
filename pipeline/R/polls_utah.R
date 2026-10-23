non_candidate_ids <- c("undecided", "someone-else", "would-not-vote")

nyt_contest_id <- function(office_type, seat_name, seat_number) {
  # seat_name is unreliable (e.g. "Third Congressional Election"), so districts come from seat_number.
  case_when(
    office_type == "U.S. House" & !is.na(seat_number) ~ str_c("us-house-", seat_number),
    office_type == "U.S. Senate" ~ "us-senate",
    office_type == "Governor" ~ "governor",
    .default = slugify(coalesce(seat_name, office_type))
  )
}

nyt_candidate_id <- function(answer, candidate_name) {
  name <- coalesce(candidate_name, answer)
  case_when(
    str_detect(name, regex("^(don.t know|not sure|undecided|no opinion|depends)", ignore_case = TRUE)) ~ "undecided",
    str_detect(name, regex("^(someone else|other|neither|none|does not matter)", ignore_case = TRUE)) ~ "someone-else",
    str_detect(name, regex("^would not vote", ignore_case = TRUE)) ~ "would-not-vote",
    .default = slugify(name)
  )
}

apply_text_fixes <- function(x, fixes) {
  reduce2(names(fixes), unlist(fixes), \(acc, from, to) str_replace_all(acc, fixed(from), to), .init = x)
}

utah_poll_rows <- function(rows, cfg) {
  rows |>
    filter(state == cfg$state, cycle == cfg$cycle) |>
    mutate(
      contest_id = nyt_contest_id(office_type, seat_name, seat_number),
      candidate_id = nyt_candidate_id(answer, candidate_name),
      party = if_else(candidate_id %in% non_candidate_ids | party %in% c("NONE", ""), NA_character_, party),
      name = case_when(
        candidate_id == "undecided" ~ "Don't know",
        candidate_id == "someone-else" ~ "Someone else",
        candidate_id == "would-not-vote" ~ "Would not vote",
        .default = coalesce(candidate_name, answer)
      ),
      sponsors = apply_text_fixes(sponsors, cfg$text_fixes)
    )
}

build_polls_json <- function(utah_rows) {
  utah_rows |>
    arrange(desc(end_date), poll_id, question_id) |>
    select(
      poll_id, question_id, contest_id, stage, pollster, sponsor = sponsors, start_date, end_date,
      sample_size, population, partisan, internal, url, numeric_grade, hypothetical,
      candidate_id, name, party, pct
    ) |>
    nest(
      results = c(candidate_id, name, party, pct),
      .by = c(
        poll_id, question_id, contest_id, stage, pollster, sponsor, start_date, end_date,
        sample_size, population, partisan, internal, url, numeric_grade, hypothetical
      )
    ) |>
    mutate(results = map(results, \(r) r |> arrange(desc(pct)) |> mutate(pct = round(pct, 1))))
}
