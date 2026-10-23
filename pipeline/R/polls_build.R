method_text <- function(cfg) {
  s <- cfg$state_average
  str_glue(
    "Weighted mean of general-election polls ending on or before each date. Weight = 0.5^(age_days/{s$half_life_days}) ",
    "x sqrt(sample_size/{s$reference_sample}) x quality (0.5 + NYT numeric_grade/3, 1 if unrated) ",
    "x {s$partisan_penalty} if partisan-sponsored or internal, divided by sqrt(k) where k is the recency-weighted ",
    "number of polls from the same pollster. One question per poll (likely voters preferred over registered over all adults). ",
    "Undecided / someone else / would not vote are excluded from the mean, so shares do not sum to 100. ",
    "Band = 95% interval: sqrt(sampling variance of the weighted mean, design effect {s$design_effect} + ",
    "({s$house_sd_candidate} pt house/non-sampling SD)^2 / effective number of polls), floored at +/-{s$floor_halfwidth_candidate} pts ",
    "when there are {s$floor_max_polls} or fewer polls (margin: SD {s$house_sd_margin}, floor +/-{s$floor_halfwidth_margin}). ",
    "Margin = REP minus DEM average, in points (positive = Republican lead). With n_polls = 1 the average is that poll."
  )
}

one_question_per_poll <- function(rows) {
  rows |>
    mutate(pop_rank = match(population, c("lv", "rv", "a"), nomatch = 4L)) |>
    filter(pop_rank == min(pop_rank), .by = c(poll_id, contest_id)) |>
    filter(question_id == first(sort(question_id)), .by = c(poll_id, contest_id)) |>
    select(-pop_rank)
}

state_series <- function(polls, today, cfg) {
  dates <- seq(min(polls$end_date), max(today, min(polls$end_date)), by = "day")
  cands <- map(dates, \(d) average_candidates(polls, d, cfg) |> mutate(date = d)) |> list_rbind()
  margins <- map(dates, \(d) average_margin(polls, d, cfg) |> mutate(date = d)) |> list_rbind()
  list(candidates = cands, margins = margins)
}

round_pts <- \(x) round(x, 1)

build_state_averages <- function(general_rows, today, cfg) {
  sa <- cfg$state_average
  rows <- general_rows |>
    filter(stage == "general", !hypothetical, !candidate_id %in% non_candidate_ids, !is.na(pct)) |>
    mutate(sample_size = coalesce(sample_size, as.integer(sa$reference_sample))) |>
    one_question_per_poll()

  contests <- rows |>
    pull(contest_id) |>
    unique() |>
    sort() |>
    set_names() |>
    map(\(cid) {
      polls <- filter(rows, contest_id == cid)
      s <- state_series(polls, today, sa)
      latest <- filter(s$candidates, date == max(date)) |> arrange(desc(avg))
      m_latest <- filter(s$margins, date == max(date))
      list(
        n_polls = max(latest$n_polls),
        n_pollsters = n_distinct(polls$pollster),
        last_poll_date = max(polls$end_date),
        latest = latest |>
          transmute(candidate_id, name, party, avg = round_pts(avg), lo = round_pts(lo), hi = round_pts(hi)),
        margin = if (nrow(m_latest) == 1) {
          list(value = round_pts(m_latest$margin), lo = round_pts(m_latest$lo), hi = round_pts(m_latest$hi))
        },
        series = s$candidates |>
          transmute(date, candidate_id, avg = round_pts(avg), lo = round_pts(lo), hi = round_pts(hi)),
        margin_series = s$margins |>
          transmute(date, margin = round_pts(margin), lo = round_pts(lo), hi = round_pts(hi))
      )
    })
  list(updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), method = as.character(method_text(cfg)), contests = contests)
}

pick_generic_rows <- function(house) {
  house |>
    filter(
      state == "US", stage == "general", cycle == 2026L, !hypothetical,
      party %in% c("DEM", "REP"), is.na(subpopulation), !is.na(pct)
    ) |>
    mutate(
      contest_id = "generic-ballot",
      candidate_id = str_to_lower(party),
      name = party,
      sample_size = coalesce(sample_size, 1000L)
    ) |>
    one_question_per_poll() |>
    filter(n_distinct(party) == 2, .by = question_id)
}

build_national <- function(house, approval_avg, today, cfg) {
  na <- cfg$national_average
  gen <- pick_generic_rows(house)
  dates <- seq(as.Date(na$series_start), today, by = "day")
  ncfg <- list(
    half_life_days = na$half_life_days, reference_sample = na$reference_sample,
    partisan_penalty = na$partisan_penalty, design_effect = na$design_effect,
    house_sd_candidate = na$house_sd_margin, house_sd_margin = na$house_sd_margin,
    floor_halfwidth_candidate = 0, floor_halfwidth_margin = 0, floor_max_polls = 0
  )
  daily <- map(dates, \(d) {
    window <- filter(gen, end_date > d - na$max_age_days)
    if (n_distinct(window$question_id) == 0) return(NULL)
    avg <- average_candidates(window, d, ncfg)
    mar <- average_margin(window, d, ncfg)
    if (is.null(avg) || is.null(mar)) return(NULL)
    tibble(
      date = d,
      DEM = avg$avg[avg$candidate_id == "dem"],
      REP = avg$avg[avg$candidate_id == "rep"],
      margin = mar$margin, margin_lo = mar$lo, margin_hi = mar$hi, n_polls = mar$n_polls
    )
  }) |> list_rbind()

  approval <- approval_avg |>
    mutate(date = as.Date(date), pct = as.numeric(pct)) |>
    filter(str_detect(answer, regex("^(approve|disapprove)$", ignore_case = TRUE))) |>
    mutate(answer = str_to_lower(answer)) |>
    summarise(pct = mean(pct), .by = c(date, answer)) |>
    pivot_wider(names_from = answer, values_from = pct) |>
    arrange(date) |>
    transmute(date, approve = round_pts(approve), disapprove = round_pts(disapprove))

  last <- slice_tail(daily, n = 1)
  list(
    generic_ballot = list(
      method = as.character(str_glue(
        "Same weighting as state averages but half-life {na$half_life_days} days, reference sample {na$reference_sample}, ",
        "polls older than {na$max_age_days} days dropped. Generic congressional ballot, general stage, 2026 cycle, ",
        "full-sample questions only. DEM and REP are mean shares (points); margin = REP minus DEM; ",
        "lo/hi is a 95% band (sampling + {na$house_sd_margin} pt house SD)."
      )),
      series = daily |> transmute(date, DEM = round_pts(DEM), REP = round_pts(REP), margin = round_pts(margin)),
      latest = list(
        date = last$date, DEM = round_pts(last$DEM), REP = round_pts(last$REP), margin = round_pts(last$margin),
        margin_lo = round_pts(last$margin_lo), margin_hi = round_pts(last$margin_hi), n_polls = last$n_polls
      )
    ),
    approval = list(
      source = "New York Times Trump approval average (president-averages.csv)",
      series = approval,
      latest = slice_tail(approval, n = 1) |> as.list()
    )
  )
}
