senate_max_poll_age_days <- 120
tracker_count <- 8

load_senate_config <- function() {
  cfg_dir <- file.path(project_root(), "pipeline", "config")
  list(
    races = read_csv(file.path(cfg_dir, "national_senate.csv"), col_types = cols(.default = "c")) |>
      mutate(special = special == "true", open = open == "true"),
    candidates = read_csv(file.path(cfg_dir, "national_senate_candidates.csv"), col_types = cols(.default = "c")) |>
      mutate(main_opponent = main_opponent == "true", poll_name = coalesce(poll_name, name)),
    meta = read_json(file.path(cfg_dir, "national_meta.json"), simplifyVector = FALSE)
  )
}

senate_poll_rows <- function(candidates, states) {
  read_poll_csv("senate.csv", poll_required_cols) |>
    prep_poll_rows() |>
    filter(state %in% states, cycle == 2026L, stage == "general", !hypothetical, is.na(subpopulation), !is.na(pct)) |>
    inner_join(
      select(candidates, state, nominee = name, nominee_party = party, main_opponent, poll_name),
      by = c("state", "candidate_name" = "poll_name")
    ) |>
    mutate(
      contest_id = str_c("senate-", state),
      candidate_id = slugify(nominee),
      name = nominee,
      party = nominee_party,
      sample_size = coalesce(sample_size, 600L)
    ) |>
    one_question_per_poll() |>
    filter(any(party == "REP") && (any(main_opponent) || any(party == "DEM")), .by = question_id)
}

# The margin compares the Republican with the main opponent, which is an independent where the Democrat withdrew.
margin_rows <- function(rows) {
  rows |>
    mutate(has_main = any(main_opponent), .by = state) |>
    filter(!has_main | main_opponent | party == "REP") |>
    mutate(party = if_else(main_opponent, "DEM", party))
}

state_poll_average <- function(polls, today, sa, with_series) {
  latest <- average_candidates(polls, today, sa)
  if (is.null(latest)) return(NULL)
  m <- average_margin(margin_rows(polls), today, sa)
  list(
    n_polls = max(latest$n_polls),
    last_poll_date = max(polls$end_date),
    latest = latest |>
      arrange(desc(avg)) |>
      transmute(candidate_id, name, party, avg = round_pts(avg), lo = round_pts(lo), hi = round_pts(hi)),
    margin = if (!is.null(m) && nrow(m) == 1) {
      list(value = round_pts(m$margin), lo = round_pts(m$lo), hi = round_pts(m$hi))
    },
    series = if (with_series) {
      state_series(polls, today, sa)$candidates |>
        transmute(date, candidate_id, avg = round_pts(avg), lo = round_pts(lo), hi = round_pts(hi))
    }
  )
}

rating_score <- function(label) {
  base <- str_remove(label, " \\(flip\\)$")
  case_when(
    is.na(base) ~ NA_real_,
    base %in% c("Tossup", "Toss-up") ~ 0,
    str_detect(base, "^Tilt") ~ if_else(str_ends(base, "R"), 0.5, -0.5),
    str_detect(base, "^Lean") ~ if_else(str_ends(base, "R"), 1, -1),
    str_detect(base, "^Likely") ~ if_else(str_ends(base, "R"), 2, -2),
    .default = if_else(str_ends(base, "R"), 3, -3)
  )
}

read_calls <- function(file = "national_calls.csv") {
  path <- file.path(project_root(), "pipeline", "config", file)
  calls <- read_csv(path, col_types = cols(.default = "c"), show_col_types = FALSE) |>
    mutate(across(everything(), \(x) na_if(str_squish(x), "")))
  bad <- calls |> filter(!winner_party %in% c("DEM", "REP", "IND") | !chamber %in% c("senate", "house"))
  if (nrow(bad) > 0) {
    stop("Invalid rows in ", file, " (chamber must be senate|house, winner_party DEM|REP|IND): ", str_c(bad$state, bad$district, collapse = ", "), call. = FALSE)
  }
  calls
}

call_record <- function(calls) {
  calls |>
    transmute(
      state, district = suppressWarnings(as.integer(district)),
      winner_party, winner_name, called_at, called_by, note
    )
}

party_tally <- function(called, total) {
  counts <- called |> count(winner_party) |> deframe()
  get <- \(p) as.integer(counts[p] |> unname() |> (\(v) if (is.na(v)) 0L else v)())
  list(DEM_won = get("DEM"), REP_won = get("REP"), IND_won = get("IND"), uncalled = total - nrow(called))
}

build_senate <- function(cfg, calls, today, sa) {
  rows <- senate_poll_rows(cfg$candidates, cfg$races$state) |>
    filter(end_date >= today - senate_max_poll_age_days, end_date <= today)

  senate_calls <- calls |> filter(chamber == "senate")
  averages <- cfg$races$state |>
    set_names() |>
    map(\(s) {
      polls <- filter(rows, state == s)
      if (nrow(polls) == 0) return(NULL)
      state_poll_average(polls, today, sa, with_series = FALSE)
    })

  scores <- cfg$races |>
    mutate(
      score = rowMeans(cbind(rating_score(cook), rating_score(sabato), rating_score(inside))),
      n_polls = map_int(state, \(s) averages[[s]]$n_polls %||% 0L)
    )
  tracker_states <- scores |>
    filter(n_polls > 0) |>
    arrange(abs(score), desc(n_polls)) |>
    slice_head(n = tracker_count) |>
    pull(state)

  tracker <- tracker_states |>
    set_names(\(s) str_c("senate-", s)) |>
    map(\(s) state_poll_average(filter(rows, state == s), today, sa, with_series = TRUE))
  tracker_polls <- rows |>
    filter(state %in% tracker_states) |>
    arrange(desc(end_date), poll_id, question_id) |>
    select(poll_id, question_id, contest_id, stage, pollster, sponsor = sponsors, start_date, end_date,
           sample_size, population, partisan, internal, url, numeric_grade, hypothetical, candidate_id, name, party, pct) |>
    nest(results = c(candidate_id, name, party, pct), .by = c(poll_id, question_id, contest_id, stage, pollster, sponsor, start_date, end_date,
           sample_size, population, partisan, internal, url, numeric_grade, hypothetical)) |>
    mutate(results = map(results, \(r) r |> arrange(desc(pct)) |> mutate(pct = round(pct, 1))))

  races <- cfg$races |>
    pmap(\(state, state_name, special, incumbent, incumbent_party, open, status_note, cook, sabato, inside) {
      call <- senate_calls |> filter(.data$state == .env$state) |> slice_head(n = 1)
      list(
        state = state, state_name = state_name, special = special,
        incumbent = incumbent, incumbent_party = incumbent_party, open = open, status_note = status_note,
        candidates = cfg$candidates |> filter(.data$state == .env$state) |> transmute(name, party),
        poll_avg = averages[[state]] |> (\(a) if (is.null(a)) list(n_polls = 0L, latest = list(), margin = NULL) else list_modify(a, series = zap()))(),
        ratings = list(cook = cook, sabato = sabato, inside = inside),
        tracker = str_c("senate-", state) %in% names(tracker),
        call = if (nrow(call) == 1) as.list(call[c("winner_party", "winner_name", "called_at", "called_by")])
      )
    })

  list(
    senate = list(
      updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      composition = cfg$meta$senate$composition,
      composition_source = cfg$meta$senate$composition_source,
      ratings_sources = cfg$meta$senate$ratings_sources,
      ratings_via = cfg$meta$senate$ratings_via,
      poll_method = as.character(method_text(list(state_average = sa))),
      poll_note = str_glue("Polls from the New York Times poll database, general-election matchups between the nominees only, last {senate_max_poll_age_days} days."),
      races = races,
      tally = party_tally(senate_calls, nrow(cfg$races))
    ),
    tracker = list(updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), polls = tracker_polls, averages = tracker)
  )
}

build_house <- function(meta, calls) {
  house_calls <- calls |> filter(chamber == "house")
  ratings <- read_csv(file.path(project_root(), "pipeline", "config", "national_house_ratings.csv"), show_col_types = FALSE)
  generic <- read_json(data_dir("polls", "national.json"), simplifyVector = FALSE)$generic_ballot$latest

  list(
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    composition = c(meta$house$composition, list(source = meta$house$composition_source)),
    ratings_tally = list(
      via = "Wikipedia: 2026 United States House of Representatives election ratings",
      url = ratings$url[1],
      sources = ratings |>
        nest(counts = c(label, n), .by = c(source, as_of)) |>
        pmap(\(source, as_of, counts) list(id = source, as_of = as_of, counts = deframe(counts) |> as.list()))
    ),
    generic_ballot = generic,
    calls = call_record(house_calls) |> select(-note) |> transpose_rows(),
    tally = party_tally(house_calls, 435L)
  )
}

transpose_rows <- function(df) pmap(df, list)
