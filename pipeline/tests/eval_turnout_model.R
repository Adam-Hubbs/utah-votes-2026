#!/usr/bin/env Rscript
# Evaluates the expected-vote model (pipeline/R/model_expected.R) against real history.
#   Rscript pipeline/tests/eval_turnout_model.R
# Writes CSVs to pipeline/tests/eval_turnout/. Needs pipeline/data/timing (build_count_timeline.R) and the shared raw cache.
#
# Part A  pre-election prior: predict each county's eventual top-of-ticket votes from registration x last comparable cycle.
# Part B  pace curve: where do real statewide completion fractions fall in the model's predictive distribution of m(h)?
# Part C  live replay: real county vectors (2020 +97h, 2022 +22h) and "transplants" (a real county completion pattern applied
#         to another year's true totals) pushed through fit_expected_ballots().
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
source(file.path(project_root(), "pipeline", "R", "model_expected.R"))
source(file.path(project_root(), "pipeline", "tests", "eval_history.R"))

OUT <- file.path(project_root(), "pipeline", "tests", "eval_turnout")
dir.create(OUT, showWarnings = FALSE)
TIMING <- file.path(project_root(), "pipeline", "data", "timing")
set.seed(2026)
DRAWS <- 4000L

q_draws <- \(m, pr) apply(m, 2, quantile, probs = pr, names = FALSE) |> t()

hist <- county_history() |> arrange(year, fips)
size_group <- \(registered) {
  cut(
    registered,
    c(0, 10000, 50000, Inf),
    c("small (<10k reg.)", "mid (10-50k)", "large (>50k)")
  )
}

# ---- Part A ---------------------------------------------------------------------------------------------------------
pairs <- tribble(
  ~year , ~prev , ~kind                          ,
  2018L , 2016L , "presidential -> midterm"      ,
  2020L , 2016L , "presidential -> presidential" ,
  2022L , 2018L , "midterm -> midterm"           ,
  2024L , 2020L , "presidential -> presidential" ,
  2022L , 2020L , "presidential -> midterm (same roll definition)" ,
  2024L , 2022L , "midterm -> presidential (same roll definition)"
)

prior_eval <- \(year, prev, kind, mu_delta = NULL, sigma_delta = NULL) {
  cur <- filter(hist, year == .env$year)
  old <- filter(hist, year == prev) |> select(fips, turnout_prev = turnout)
  cty <- left_join(cur, old, by = "fips") |>
    mutate(
      prior_turnout = pmin(
        pmax(
          coalesce(
            turnout_prev,
            weighted.mean(turnout_prev, registered, na.rm = TRUE)
          ),
          0.3
        ),
        0.9
      ),
      counted = 0,
      final = FALSE,
      remaining = NA_real_,
      fixed = FALSE
    )
  p <- model_defaults()
  p$draws <- DRAWS
  if (!is.null(mu_delta)) {
    p$mu_delta <- mu_delta
  }
  if (!is.null(sigma_delta)) {
    p$sigma_delta <- sigma_delta
  }
  fit <- fit_expected_ballots(cty, 0, p)
  qs <- q_draws(fit$T, c(0.05, 0.25, 0.5, 0.75, 0.95))
  st <- quantile(rowSums(fit$T), c(0.05, 0.25, 0.5, 0.75, 0.95), names = FALSE)
  total <- \(a) sum(cty$registered * plogis(qlogis(cty$prior_turnout) + a))
  realized_delta <- uniroot(\(a) total(a) - sum(cty$votes), c(-3, 3))$root
  list(
    county = cty |>
      transmute(
        year,
        prev,
        kind,
        fips,
        registered,
        truth = votes,
        lo90 = qs[, 1],
        lo50 = qs[, 2],
        median = qs[, 3],
        hi50 = qs[, 4],
        hi90 = qs[, 5],
        eps_sd = add_eps_sd(cty, p)$eps_sd,
        resid_logit = qlogis(votes / registered) -
          qlogis(prior_turnout) -
          realized_delta
      ),
    state = tibble(
      year,
      prev,
      kind,
      truth = sum(cty$votes),
      lo90 = st[1],
      lo50 = st[2],
      median = st[3],
      hi50 = st[4],
      hi90 = st[5],
      realized_delta,
      delta_percentile = mean(fit$delta <= realized_delta)
    )
  )
}

a_main <- pmap(pairs, \(year, prev, kind) prior_eval(year, prev, kind))
a_county <- map(a_main, "county") |> list_rbind()
a_state <- map(a_main, "state") |> list_rbind()
write_csv(a_county, file.path(OUT, "prior_county.csv"))
write_csv(a_state, file.path(OUT, "prior_statewide.csv"))

prior_summary <- a_county |>
  mutate(
    ape = abs(median / truth - 1),
    cover90 = truth >= lo90 & truth <= hi90,
    cover50 = truth >= lo50 & truth <= hi50,
    z_resid = resid_logit / eps_sd,
    group = size_group(registered)
  ) |>
  summarise(
    wmape = sum(abs(median - truth)) / sum(truth),
    median_ape = median(ape),
    mean_ape = mean(ape),
    cover90 = mean(cover90),
    cover50 = mean(cover50),
    sd_resid_logit = sd(resid_logit),
    sd_z = sd(z_resid),
    .by = c(year, prev, kind, group)
  ) |>
  bind_rows(
    a_county |>
      mutate(
        ape = abs(median / truth - 1),
        cover90 = truth >= lo90 & truth <= hi90,
        cover50 = truth >= lo50 & truth <= hi50,
        z_resid = resid_logit / eps_sd,
        group = factor("all counties")
      ) |>
      summarise(
        wmape = sum(abs(median - truth)) / sum(truth),
        median_ape = median(ape),
        mean_ape = mean(ape),
        cover90 = mean(cover90),
        cover50 = mean(cover50),
        sd_resid_logit = sd(resid_logit),
        sd_z = sd(z_resid),
        .by = c(year, prev, kind, group)
      )
  )
write_csv(prior_summary, file.path(OUT, "prior_summary.csv"))

# Same prior but with the statewide shift known (isolates the county-pattern part of the error).
a_oracle <- pmap(pairs, \(year, prev, kind) {
  d <- a_state$realized_delta[a_state$year == year & a_state$prev == prev]
  prior_eval(year, prev, kind, mu_delta = d, sigma_delta = 0.01)$county |>
    mutate(scenario = "oracle statewide shift")
}) |>
  list_rbind()
write_csv(a_oracle, file.path(OUT, "prior_county_oracle_shift.csv"))

# ---- observed completion fractions (statewide and county) ------------------------------------------------------------
close_utc <- c(
  `2016` = "2016-11-09 03:00:00",
  `2018` = "2018-11-07 03:00:00",
  `2020` = "2020-11-04 03:00:00",
  `2022` = "2022-11-09 03:00:00",
  `2025` = "2025-11-05 03:00:00"
) |>
  as.POSIXct(tz = "UTC")
hours_since <- \(ts, year) {
  as.numeric(difftime(
    as.POSIXct(ts, format = "%Y%m%d%H%M%S", tz = "UTC"),
    close_utc[as.character(year)],
    units = "hours"
  ))
}

sw <- read_csv(
  file.path(TIMING, "old_site_statewide_snapshots.csv"),
  col_types = cols(.default = "c", counted = "d"),
  show_col_types = FALSE
)
cc <- read_csv(
  file.path(TIMING, "old_site_raw_contest_county_snapshots.csv"),
  col_types = cols(.default = "c", counted = "d"),
  show_col_types = FALSE
)
top_contests <- tribble(
  ~election_year , ~contest_id ,
  "2016"         , "300000"    ,
  "2018"         , "300000"    ,
  "2020"         , "399789495" ,
  "2022"         , "451556070"
)
sw_top <- sw |>
  semi_join(top_contests, by = c("election_year", "contest_id")) |>
  summarise(total = sum(counted), .by = c(election_year, timestamp)) |>
  filter(total > 0)
cc_state <- cc |>
  semi_join(top_contests, by = c("election_year", "contest_id")) |>
  summarise(total = sum(counted), n = n(), .by = c(election_year, timestamp)) |>
  filter(n >= 25, total > 0) |>
  select(-n)

finals <- hist |>
  summarise(final = sum(votes), .by = year) |>
  mutate(election_year = as.character(year))
# 2016 / 2018 finals come from the history table; the 2016 statewide page gives the certified-looking figure
pace_points <- bind_rows(
  sw_top |> mutate(source = "statewide page"),
  cc_state |> mutate(source = "county table (29 counties)"),
  cc |>
    filter(election_year == "2018", contest_id == "306950") |>
    summarise(total = sum(counted), .by = c(election_year, timestamp)) |>
    mutate(source = "county table, Proposition 2 (2018)"),
  cc |>
    filter(election_year == "2016", contest_id == "300000") |>
    summarise(total = sum(counted), .by = c(election_year, timestamp)) |>
    mutate(source = "county table (29 counties)")
) |>
  distinct(election_year, timestamp, total, .keep_all = TRUE) |>
  left_join(select(finals, election_year, final), by = "election_year") |>
  mutate(
    year = as.integer(election_year),
    hours = hours_since(timestamp, year),
    frac = total / final,
    pre_hb300 = TRUE
  ) |>
  filter(hours > 0, frac < 1.02) |>
  arrange(year, hours)

export25 <- read_csv(
  file.path(TIMING, "county_count_timeline_all_series.csv"),
  col_types = cols(
    .default = "c",
    counted = "d",
    final_counted = "d",
    hours_since_close = "d",
    frac_of_final = "d"
  ),
  show_col_types = FALSE
) |>
  filter(
    election_id == "2025-general",
    hours_since_close > 0,
    hours_since_close < 100
  )
pace25 <- export25 |>
  summarise(
    total = sum(counted),
    final = sum(final_counted),
    hours = first(hours_since_close),
    .by = timestamp_utc
  ) |>
  transmute(
    election_year = "2025",
    year = 2025L,
    timestamp = timestamp_utc,
    total,
    final,
    hours,
    frac = total / final,
    source = "municipal export, sum of votes in 26 counties",
    pre_hb300 = FALSE
  )
pace_points <- bind_rows(pace_points, pace25)

# Model-implied distribution of the statewide completed fraction at h, with the true county totals as weights.
pace_predictive <- \(h, weights, p = model_defaults(), n = 20000) {
  eta <- eta_scale(h, p) * rt(n, p$df_eta)
  m <- plogis(qlogis(stage_mean(h, p)) + eta)
  f <- map_dbl(seq_len(n), \(i) {
    sum(
      weights *
        rbeta(
          length(weights),
          m[i] * p$concentration,
          (1 - m[i]) * p$concentration
        )
    ) /
      sum(weights)
  })
  c(
    lo90 = quantile(f, 0.05),
    lo50 = quantile(f, 0.25),
    median = quantile(f, 0.5),
    hi50 = quantile(f, 0.75),
    hi90 = quantile(f, 0.95)
  ) |>
    set_names(c("lo90", "lo50", "median", "hi50", "hi90")) |>
    as.list() |>
    as_tibble() |>
    mutate(pit_fun = list(sort(f)))
}
w_for <- \(year) {
  hist$votes[hist$year == min(year, 2024L)] |>
    (\(v) if (length(v) == 0) hist$votes[hist$year == 2022L] else v)()
}
pace_points <- pace_points |>
  mutate(
    pred = map2(hours, year, \(h, y) pace_predictive(h, w_for(y), n = 5000))
  ) |>
  unnest(pred) |>
  mutate(
    pit = map2_dbl(frac, pit_fun, \(f, s) mean(s <= f)),
    model_m = stage_mean(hours)
  ) |>
  select(-pit_fun)
write_csv(
  pace_points |> select(-election_year),
  file.path(OUT, "pace_points.csv")
)

# Fit alternatives by least squares on the pre-HB 300 points (one point per election and ~day to avoid duplicate pages).
fit_curve <- \(d) {
  d <- d |>
    mutate(day = round(hours / 6)) |>
    distinct(year, day, .keep_all = TRUE)
  o <- optim(
    c(0.6, 0.98, 30),
    \(par) {
      sum((par[2] - (par[2] - par[1]) * exp(-d$hours / par[3]) - d$frac)^2)
    },
    method = "L-BFGS-B",
    lower = c(0.2, 0.9, 3),
    upper = c(0.9, 1, 400)
  )
  tibble(
    m0 = o$par[1],
    m_inf = o$par[2],
    tau_hours = o$par[3],
    rmse = sqrt(o$value / nrow(d)),
    n = nrow(d)
  )
}
curve_fit <- bind_rows(
  fit_curve(filter(pace_points, pre_hb300)) |>
    mutate(set = "2016-2022 statewide (pre HB 300)"),
  fit_curve(filter(pace_points, year %in% c(2020, 2022))) |>
    mutate(set = "2020 + 2022 only")
)
write_csv(curve_fit, file.path(OUT, "pace_curve_fit.csv"))

# County dispersion and size dependence of completion at a given moment.
county_obs <- bind_rows(
  cc |>
    semi_join(top_contests, by = c("election_year", "contest_id")) |>
    mutate(
      fips = county_fips_from_name(county),
      year = as.integer(election_year),
      hours = hours_since(timestamp, year)
    ) |>
    left_join(
      select(hist, year, fips, final = votes, registered),
      by = c("year", "fips")
    ) |>
    transmute(
      year,
      hours,
      fips,
      frac = counted / final,
      registered,
      source = "county table"
    ),
  export25 |>
    mutate(fips = county_fips_from_name(county)) |>
    left_join(
      filter(hist, year == 2024) |> select(fips, registered),
      by = "fips"
    ) |>
    transmute(
      year = 2025L,
      hours = hours_since_close,
      fips,
      frac = frac_of_final,
      registered,
      source = "municipal export"
    )
) |>
  filter(hours > 0, hours < 200, !is.na(frac), frac > 0, frac < 1) |>
  mutate(n = n(), .by = c(year, hours)) |>
  filter(n >= 20)
dispersion <- county_obs |>
  summarise(
    mean_frac = mean(frac),
    weighted_frac = weighted.mean(frac, registered),
    sd_logit = sd(qlogis(pmin(pmax(frac, 0.01), 0.995))),
    k_implied = mean_frac * (1 - mean_frac) / var(frac) - 1,
    slope_logit_on_log_size = coef(lm(
      qlogis(pmin(pmax(frac, 0.01), 0.995)) ~ log(registered / 10000)
    ))[2],
    n = n(),
    .by = c(year, hours, source)
  )
write_csv(dispersion, file.path(OUT, "county_pace_dispersion.csv"))
write_csv(county_obs, file.path(OUT, "county_pace_observed.csv"))

# ---- Part C: replays ------------------------------------------------------------------------------------------------
build_replay_inputs <- \(year, counted_by_fips, prior_year) {
  cur <- filter(hist, year == .env$year)
  old <- filter(hist, year == prior_year) |> select(fips, turnout_prev = turnout)
  left_join(cur, old, by = "fips") |>
    left_join(counted_by_fips, by = "fips") |>
    mutate(
      counted = coalesce(counted, 0),
      prior_turnout = pmin(pmax(turnout_prev, 0.3), 0.9),
      final = FALSE, remaining = NA_real_, fixed = FALSE
    )
}

replay <- \(cty, hours, label, p = model_defaults(), mu_delta = NULL) {
  p$draws <- DRAWS
  if (!is.null(mu_delta)) p$mu_delta <- mu_delta
  fit <- fit_expected_ballots(cty, hours, p)
  qs <- q_draws(fit$T, c(0.05, 0.25, 0.5, 0.75, 0.95))
  st <- quantile(rowSums(fit$T), c(0.05, 0.25, 0.5, 0.75, 0.95), names = FALSE)
  bind_rows(
    tibble(level = "county", fips = cty$fips, registered = cty$registered, counted = cty$counted, truth = cty$votes, lo90 = qs[, 1], lo50 = qs[, 2], median = qs[, 3], hi50 = qs[, 4], hi90 = qs[, 5]),
    tibble(level = "state", fips = "49", registered = sum(cty$registered), counted = sum(cty$counted), truth = sum(cty$votes), lo90 = st[1], lo50 = st[2], median = st[3], hi50 = st[4], hi90 = st[5])
  ) |>
    mutate(label = label, hours = hours, frac_counted = counted / truth)
}

realized_delta <- \(year, prior_year) a_state$realized_delta[a_state$year == year & a_state$prev == prior_year]

# "before" is the model as deployed until 2026-10-23; "after" is model_defaults(). Others are candidates for the recalibration.
OLD <- list(m_inf = 0.975, tau_hours = 22, concentration = 12, pace_size_slope = 0, sigma_eps = 0.17, sigma_eps_small = 0.6, sigma_eta = 0.7, sigma_eta_late = 0.5, likelihood_power = 0.35)
ALL_SETS <- list(
  before = OLD,
  after = list(),
  after_slope0.3 = list(pace_size_slope = 0.3),
  after_slope0.75 = list(pace_size_slope = 0.75),
  after_tau50 = list(tau_hours = 50),
  after_tau95 = list(tau_hours = 95),
  after_k4 = list(concentration = 4),
  slower_pace_only = modifyList(OLD, list(m_inf = 0.99, tau_hours = 70)),
  size_slope_only = modifyList(OLD, list(pace_size_slope = 0.5)),
  k6_only = modifyList(OLD, list(concentration = 6)),
  cand_A = list(pace_size_slope = 0.6),
  cand_B = list(pace_size_slope = 0.6, sigma_eta = 0.9, sigma_eta_late = 0.6),
  cand_C = list(pace_size_slope = 0.6, sigma_eta = 0.9, sigma_eta_late = 0.6, sigma_eps = 0.22, sigma_eps_small = 0.7),
  cand_D = list(pace_size_slope = 0.6, sigma_eta = 0.9, sigma_eta_late = 0.6, sigma_eps = 0.22, sigma_eps_small = 0.7, concentration = 5),
  cand_E = list(pace_size_slope = 0.6, sigma_eta = 0.9, sigma_eta_late = 0.6, sigma_eps = 0.22, sigma_eps_small = 0.7, likelihood_power = 0.25)
)
SET_NAMES <- strsplit(Sys.getenv("UTEL_EVAL_SETS", "before,after"), ",")[[1]]
PARAM_SETS <- ALL_SETS[SET_NAMES]
OUT_TAG <- Sys.getenv("UTEL_EVAL_TAG", "")
PRIOR_PAIRS <- tribble(~year, ~prior_year, 2018L, 2016L, 2020L, 2016L, 2022L, 2020L, 2024L, 2022L)

# real county vectors (the only ones in the archive: 2022 +22h and 2020 +97h)
real_vec <- \(year, contest_id, ts) {
  cc |>
    filter(election_year == as.character(year), contest_id == .env$contest_id, timestamp == ts) |>
    transmute(fips = county_fips_from_name(county), counted)
}
first_ts <- \(year, contest_id, from, to) {
  cc |> filter(election_year == as.character(year), contest_id == .env$contest_id, timestamp > from, timestamp < to) |> distinct(timestamp) |> arrange(timestamp) |> pull() |> first()
}
real_runs <- tribble(
  ~year , ~prior_year , ~contest_id , ~from , ~to ,
  2022L , 2020L , "451556070" , "20221109030000" , "20221112000000" ,
  2022L , 2018L , "451556070" , "20221109030000" , "20221112000000" ,
  2020L , 2016L , "399789495" , "20201104030000" , "20201110000000"
) |>
  mutate(ts = pmap_chr(list(year, contest_id, from, to), first_ts), hours = hours_since(ts, year))

replay_real <- map(names(PARAM_SETS), \(nm) {
  p <- modifyList(model_defaults(), PARAM_SETS[[nm]])
  pmap(real_runs, \(year, prior_year, contest_id, from, to, ts, hours) {
    cty <- build_replay_inputs(year, real_vec(year, contest_id, ts), prior_year)
    bind_rows(
      replay(cty, hours, "as deployed prior", p = p),
      replay(cty, hours, "prior centred on true shift", p = p, mu_delta = realized_delta(year, prior_year))
    ) |>
      mutate(year = year, prior_year = prior_year, params = nm)
  }) |>
    list_rbind()
}) |>
  list_rbind() |>
  mutate(kind = "real county vector")

# "Warped" replays: a real county completion pattern (logit fraction of final, with its size gradient) is shifted so that
# the statewide weighted fraction follows the empirical pre-HB 300 curve, then applied to other years' true county totals.
emp <- curve_fit |> filter(str_detect(set, "pre HB 300"))
emp_curve <- \(h) emp$m_inf - (emp$m_inf - emp$m0) * exp(-h / emp$tau_hours)
patterns <- bind_rows(
  county_obs |> filter(year == 2022, hours > 20, hours < 25) |> transmute(pattern = "2022 +22h", fips, frac),
  county_obs |> filter(year == 2020, hours > 90, hours < 100) |> transmute(pattern = "2020 +97h", fips, frac),
  county_obs |> filter(year == 2025, hours > 15, hours < 25) |> transmute(pattern = "2025 +19h", fips, frac)
)
fill_pattern <- \(pat) {
  d <- left_join(tibble(fips = unique(hist$fips)), pat, by = "fips") |>
    left_join(filter(hist, year == 2022) |> select(fips, registered), by = "fips") |>
    mutate(logit_f = qlogis(pmin(pmax(frac, 0.02), 0.995)))
  fit <- lm(logit_f ~ log(registered), data = d)
  d |> mutate(logit_f = coalesce(logit_f, predict(fit, newdata = pick(everything()))))
}
warp_fracs <- \(pat, truth, target) {
  f <- \(shift) plogis(pat$logit_f + shift)
  shift <- uniroot(\(s) sum(truth * f(s)) / sum(truth) - target, c(-8, 8))$root
  pmin(f(shift), 0.995)
}
WARP_HOURS <- c(3, 6, 12, 24, 36, 48, 72, 120)
warp_runs <- expand_grid(pattern = unique(patterns$pattern), PRIOR_PAIRS, hours = WARP_HOURS) |>
  filter(!(pattern == "2022 +22h" & year == 2022L), !(pattern == "2020 +97h" & year == 2020L))

replay_warp <- expand_grid(nm = names(PARAM_SETS), centred = c(FALSE, TRUE)) |>
  pmap(\(nm, centred) {
    p <- modifyList(model_defaults(), PARAM_SETS[[nm]])
    pmap(warp_runs, \(pattern, year, prior_year, hours) {
      pat <- patterns |> filter(pattern == .env$pattern) |> fill_pattern()
      base <- build_replay_inputs(year, tibble(fips = character(), counted = numeric()), prior_year)
      f <- warp_fracs(left_join(base, pat, by = "fips"), base$votes, emp_curve(hours))
      cty <- build_replay_inputs(year, tibble(fips = base$fips, counted = round(base$votes * f)), prior_year)
      replay(cty, hours, str_c(pattern, " pattern, ", year, " totals"), p = p, mu_delta = if (centred) realized_delta(year, prior_year)) |>
        mutate(year = year, pattern = pattern, params = nm, prior = if_else(centred, "prior centred on true shift", "as deployed prior"))
    }) |>
      list_rbind()
  }) |>
  list_rbind() |>
  mutate(kind = "warped real pattern")
write_csv(replay_real, file.path(OUT, str_c("replays_real", OUT_TAG, ".csv")))
write_csv(replay_warp, file.path(OUT, str_c("replays_warped", OUT_TAG, ".csv")))

# ---- console summary ------------------------------------------------------------------------------------------------
options(width = 200)
cat("\n== Part A: statewide prior ==\n")
print(
  a_state |>
    mutate(
      err_pct = 100 * (median / truth - 1),
      covered90 = truth >= lo90 & truth <= hi90,
      width90_pct = 100 * (hi90 - lo90) / truth
    ) |>
    select(
      year,
      prev,
      kind,
      truth,
      median,
      err_pct,
      covered90,
      width90_pct,
      realized_delta,
      delta_percentile
    )
)
cat("\n== Part A: county summary (all counties) ==\n")
print(prior_summary |> filter(group == "all counties"))
cat("\n== Part B: pace points ==\n")
print(
  pace_points |> select(year, source, hours, frac, model_m, lo90, hi90, pit),
  n = 60
)
print(curve_fit)
cat("\n== Dispersion ==\n")
print(dispersion)
cat("\n== Part C summary (real vectors, statewide) ==\n")
print(replay_real |> filter(level == "state") |> mutate(err_pct = 100 * (median / truth - 1), cover50 = truth >= lo50 & truth <= hi50, cover90 = truth >= lo90 & truth <= hi90, width_pct = 100 * (hi90 - lo90) / truth) |> select(year, label, params, hours, frac_counted, err_pct, cover50, cover90, width_pct))
cat("\n== Part C summary (warped, statewide, by params and hours) ==\n")
print(replay_warp |> filter(level == "state") |> mutate(err = median / truth - 1, cover50 = truth >= lo50 & truth <= hi50, cover90 = truth >= lo90 & truth <= hi90, width = (hi90 - lo90) / truth) |> summarise(mape = mean(abs(err)), bias = mean(err), cover50 = mean(cover50), cover90 = mean(cover90), width = mean(width), n = n(), .by = c(prior, params, hours)) |> arrange(prior, params, hours), n = 60)
