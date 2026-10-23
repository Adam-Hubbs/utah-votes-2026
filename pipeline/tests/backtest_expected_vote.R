#!/usr/bin/env Rscript
# Back-test of the expected-ballots model. Truth comes from real county totals (2022 ballots, 2024 top-of-ticket
# votes). The counted-fraction process used to generate fake election nights is deliberately different from the
# model's own Beta assumption (logit-normal county noise, uniform statewide pace), so coverage is an honest check.
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "model_expected.R"))

args <- commandArgs(trailingOnly = TRUE)
n_rep <- if (length(args) >= 1) as.integer(args[1]) else 40L
base <- read_csv(file.path(project_root(), "pipeline", "config", "county_baselines.csv"), col_types = cols(fips = col_character()), show_col_types = FALSE)

# The statewide level of the prior is set to truth +/- 0.2 logit (about one prior sd) so the test isolates
# county-pattern transfer plus a plausible statewide miss.
make_scenario <- function(registered, truth, pattern, miss) {
  w <- registered
  lvl <- weighted.mean(qlogis(truth / registered), w)
  prior_lvl <- weighted.mean(qlogis(pattern), w)
  tibble(
    fips = base$fips, registered = registered, truth = truth,
    prior_turnout = plogis(qlogis(pattern) - prior_lvl + lvl + miss - model_defaults()$mu_delta)
  )
}
scenarios <- list(
  sim_2022_from_2024_pattern_miss_plus = make_scenario(
    base$registered_2022, base$ballots_2022, base$votes_top_2024 / VOTE_PER_BALLOT / base$registered_2026, 0.2
  ),
  sim_2024_from_2022_pattern_miss_minus = make_scenario(
    base$registered_2026, base$votes_top_2024 / VOTE_PER_BALLOT, base$turnout_2022, -0.2
  ),
  # Closest to 2026 itself: a same-type (midterm) pattern with county noise of 0.15 logit and a 0.2 statewide miss.
  midterm_like_2022_noisy_pattern = make_scenario(
    base$registered_2022, base$ballots_2022,
    plogis(qlogis(base$ballots_2022 / base$registered_2022) + rnorm(nrow(base), 0, 0.15)), 0.2
  )
)

# Production-style prior (raw 2022 rates) against a 2018-style surge (+25 % ballots vs 2022) and a collapse (-25 %).
make_shift_scenario <- function(mult) {
  prior <- pmin(pmax(base$turnout_2022, 0.3), 0.9)
  total <- \(a) sum(base$registered_2026 * plogis(qlogis(prior) + a))
  shift <- uniroot(\(a) total(a) - mult * total(0), c(-2, 2))$root
  tibble(
    fips = base$fips, registered = base$registered_2026, prior_turnout = prior,
    truth = base$registered_2026 * plogis(qlogis(prior) + shift + rnorm(nrow(base), 0, 0.1))
  )
}
scenarios$surge_2018_style_plus25 <- make_shift_scenario(1.25)
scenarios$slump_minus25 <- make_shift_scenario(0.75)

stage_hours <- c(first_drop = 1, next_morning = 14, day_two = 36)

simulate_counted <- function(truth, stage) {
  n <- length(truth)
  g <- runif(1, 0.50, 0.85)
  f1 <- pmin(g * exp(rnorm(n, 0, 0.18)), 0.97)
  f <- switch(stage,
    first_drop = f1,
    next_morning = 1 - (1 - f1) * runif(n, 0.35, 0.6),
    day_two = 1 - (1 - f1) * runif(n, 0.10, 0.30)
  )
  round(truth * f)
}

one_rep <- function(sc, stage, p) {
  counted <- simulate_counted(sc$truth, stage)
  cty <- sc |> mutate(counted = counted, final = FALSE, remaining = NA_real_, fixed = FALSE)
  fit <- fit_expected_ballots(cty, stage_hours[[stage]], p)
  s <- summarise_draws(fit$T, counted) |> left_join(select(sc, fips, truth), by = "fips")
  st <- quantile(rowSums(fit$T), c(0.05, 0.5, 0.95), names = FALSE)
  tibble(
    cover_county = mean(s$truth >= s$expected_lo & s$truth <= s$expected_hi),
    cover_state = as.numeric(sum(sc$truth) >= st[1] & sum(sc$truth) <= st[3]),
    mape_state = abs(st[2] / sum(sc$truth) - 1),
    width_state = (st[3] - st[1]) / sum(sc$truth),
    width_county = mean((s$expected_hi - s$expected_lo) / s$truth),
    frac_counted = sum(counted) / sum(sc$truth)
  )
}

set.seed(2026)
p <- model_defaults()
overrides <- Sys.getenv("UTEL_MODEL_OVERRIDES", "")
if (nzchar(overrides)) p <- modifyList(p, eval(parse(text = str_c("list(", overrides, ")"))))
p$draws <- 1500L
res <- expand_grid(scenario = names(scenarios), stage = names(stage_hours), rep = seq_len(n_rep)) |>
  mutate(out = pmap(list(scenario, stage), \(scenario, stage, ...) one_rep(scenarios[[scenario]], stage, p))) |>
  unnest(out)

report <- res |>
  summarise(
    across(c(cover_county, cover_state, mape_state, width_state, width_county, frac_counted), mean),
    .by = c(scenario, stage)
  ) |>
  mutate(across(where(is.numeric), \(x) round(x, 3)))
print(report, n = 20, width = Inf)
if (!nzchar(overrides)) write_csv(report, file.path(project_root(), "pipeline", "tests", "backtest_results.csv"))
