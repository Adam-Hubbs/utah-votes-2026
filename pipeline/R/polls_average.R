# Weight of each poll as of `as_of`. Rows need: pollster, end_date, sample_size, numeric_grade, partisan, internal.
poll_weights <- function(polls, as_of, half_life, reference_sample, partisan_penalty) {
  polls |>
    mutate(
      w_recency = 0.5^(as.numeric(as_of - end_date) / half_life),
      w_size = sqrt(coalesce(sample_size, reference_sample) / reference_sample),
      # Grades are on a 0-3 scale; unrated pollsters get the neutral 1.0.
      w_quality = if_else(is.na(numeric_grade), 1, 0.5 + pmin(pmax(numeric_grade, 0), 3) / 3),
      w_partisan = if_else(!is.na(partisan) | internal, partisan_penalty, 1),
      w_base = w_recency * w_size * w_quality * w_partisan
    ) |>
    mutate(
      # Effective number of polls from this pollster (recency-aware); their combined weight grows
      # only with its square root, so a pollster that polls often cannot dominate.
      k_eff = sum(w_recency) / max(w_recency),
      w = w_base / sqrt(k_eff),
      .by = pollster
    )
}

# One row per (poll question, candidate). `margin_pair` picks the two candidates whose gap is reported.
average_candidates <- function(polls, as_of, cfg) {
  active <- polls |> filter(end_date <= as_of)
  if (nrow(active) == 0) return(NULL)
  weighted <- poll_weights(
    distinct(active, question_id, pollster, end_date, sample_size, numeric_grade, partisan, internal),
    as_of, cfg$half_life_days, cfg$reference_sample, cfg$partisan_penalty
  )
  n_eff_polls <- sum(weighted$w)^2 / sum(weighted$w^2)
  n_polls <- nrow(weighted)

  active |>
    inner_join(select(weighted, question_id, w), by = "question_id") |>
    summarise(
      avg = sum(w * pct) / sum(w),
      var_sampling = sum(w^2 * cfg$design_effect * (pct / 100) * (1 - pct / 100) / sample_size * 1e4) / sum(w)^2,
      .by = c(candidate_id, name, party)
    ) |>
    mutate(
      n_polls = n_polls,
      half = 1.96 * sqrt(var_sampling + cfg$house_sd_candidate^2 / n_eff_polls),
      half = if_else(n_polls <= cfg$floor_max_polls, pmax(half, cfg$floor_halfwidth_candidate), half),
      lo = pmax(avg - half, 0),
      hi = pmin(avg + half, 100)
    ) |>
    select(candidate_id, name, party, avg, lo, hi, n_polls)
}

# Gap between the two major-party candidates (REP minus DEM, points).
average_margin <- function(polls, as_of, cfg) {
  active <- polls |> filter(end_date <= as_of)
  both <- active |>
    filter(party %in% c("REP", "DEM")) |>
    summarise(
      rep = sum(pct[party == "REP"]),
      dem = sum(pct[party == "DEM"]),
      has_both = any(party == "REP") && any(party == "DEM"),
      .by = c(question_id)
    ) |>
    filter(has_both)
  if (nrow(both) == 0) return(NULL)
  meta <- active |>
    distinct(question_id, pollster, end_date, sample_size, numeric_grade, partisan, internal) |>
    semi_join(both, by = "question_id")
  weighted <- poll_weights(meta, as_of, cfg$half_life_days, cfg$reference_sample, cfg$partisan_penalty) |>
    inner_join(both, by = "question_id") |>
    mutate(
      diff = rep - dem,
      # Multinomial variance of a difference of shares: pR(1-pR) + pD(1-pD) + 2 pR pD.
      var_s = cfg$design_effect * ((rep / 100) * (1 - rep / 100) + (dem / 100) * (1 - dem / 100) + 2 * rep * dem / 1e4) / sample_size * 1e4
    )
  n_eff_polls <- sum(weighted$w)^2 / sum(weighted$w^2)
  n_polls <- nrow(weighted)
  margin <- sum(weighted$w * weighted$diff) / sum(weighted$w)
  var_sampling <- sum(weighted$w^2 * weighted$var_s) / sum(weighted$w)^2
  half <- 1.96 * sqrt(var_sampling + cfg$house_sd_margin^2 / n_eff_polls)
  half <- if_else(n_polls <= cfg$floor_max_polls, pmax(half, cfg$floor_halfwidth_margin), half)
  tibble(margin = margin, lo = margin - half, hi = margin + half, n_polls = n_polls)
}
