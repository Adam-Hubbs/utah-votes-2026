# Parser for the Utah Enhanced Voting media export (electionresults.utah.gov/cdn/results/...).

ut_export_url <- \(path) str_c("https://electionresults.utah.gov/cdn/results/", path)

ut_export_contest_tables <- function(path) {
  x <- jsonlite::read_json(path)
  items <- x$results$ballotItems

  contest_meta <- items |>
    map(\(b) tibble(item_id = b$id, name = str_squish(b$name), contest_type = b$contestType)) |>
    list_rbind()

  local_rows <- x$localResults |>
    map(\(l) {
      fips <- county_fips_from_name(l$name)
      l$ballotItems |>
        map(\(b) {
          b$ballotOptions |>
            map(\(o) {
              pr <- o$precinctResults %||% list()
              tibble(
                item_id = b$id,
                county_fips = fips,
                option_id = o$id,
                option = o$name,
                party = o$politicalParty %||% NA_character_,
                county_votes = o$voteCount %||% NA_integer_,
                precinct = map_chr(pr, \(p) p$name),
                votes = map_int(pr, \(p) p$voteCount %||% 0L)
              )
            }) |>
            list_rbind()
        }) |>
        list_rbind()
    }) |>
    list_rbind()

  state_rows <- items |>
    map(\(b) {
      b$ballotOptions |>
        map(\(o) tibble(
          item_id = b$id,
          option_id = o$id,
          option = o$name,
          party = o$politicalParty %||% NA_character_,
          state_votes = o$voteCount %||% NA_integer_
        )) |>
        list_rbind()
    }) |>
    list_rbind()

  list(
    meta = contest_meta,
    local = local_rows,
    state = state_rows,
    election_date = x$electionDate,
    election_name = x$electionName
  )
}
