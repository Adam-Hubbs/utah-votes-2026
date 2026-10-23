#!/usr/bin/env Rscript
# Assembles the self-contained HTML evaluation report from pipeline/tests/eval_turnout/*.csv and the timeline data.
#   Rscript pipeline/tests/build_turnout_report.R <output.html>
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
source(file.path(project_root(), "pipeline", "R", "model_expected.R"))

args <- commandArgs(trailingOnly = TRUE)
out_path <- if (length(args) >= 1) args[1] else file.path(project_root(), "pipeline", "tests", "eval_turnout", "turnout_model_report.html")
ev <- \(f) read_csv(file.path(project_root(), "pipeline", "tests", "eval_turnout", f), show_col_types = FALSE)
tm <- \(f) read_csv(file.path(project_root(), "pipeline", "data", "timing", f), show_col_types = FALSE, col_types = cols(.default = "c"))
set.seed(1)

pace <- ev("pace_points.csv")
fit <- ev("pace_curve_fit.csv")
disp <- ev("county_pace_dispersion.csv")
cobs <- ev("county_pace_observed.csv")
a_state <- ev("prior_statewide.csv")
a_sum <- ev("prior_summary.csv")
a_orc <- ev("prior_county_oracle_shift.csv")
a_cty <- ev("prior_county.csv")
real <- ev("replays_real.csv")
warp <- ev("replays_warped.csv")

# predictive band of the statewide completed fraction under the model, with 2022 county weights
w22 <- read_csv(file.path(project_root(), "pipeline", "config", "county_baselines.csv"), show_col_types = FALSE)$ballots_2022
band <- \(p, hs = exp(seq(log(1), log(1500), length.out = 40))) {
  map(hs, \(h) {
    n <- 3000
    eta <- eta_scale(h, p) * rt(n, p$df_eta)
    m <- plogis(qlogis(stage_mean(h, p)) + eta)
    f <- map_dbl(m, \(mi) sum(w22 * rbeta(length(w22), mi * p$concentration, (1 - mi) * p$concentration)) / sum(w22))
    tibble(h = h, m = stage_mean(h, p), lo = quantile(f, 0.05), hi = quantile(f, 0.95))
  }) |>
    list_rbind()
}
pre <- fit |> filter(str_detect(set, "pre HB"))
OLD <- list(m_inf = 0.975, tau_hours = 22, concentration = 12, pace_size_slope = 0, sigma_eps = 0.17, sigma_eps_small = 0.6, sigma_eta = 0.7, sigma_eta_late = 0.5, likelihood_power = 0.35)
p_old <- modifyList(model_defaults(), OLD)
band_dep <- band(p_old)
band_fit <- band(model_defaults())
# PIT of each observed share under the old model, for the before/after comparison (pace_points.csv holds the new model's)
pit_old <- map2_dbl(pace$hours, pace$frac, \(h, f) {
  n <- 4000
  eta <- eta_scale(h, p_old) * rt(n, p_old$df_eta)
  m <- plogis(qlogis(stage_mean(h, p_old)) + eta)
  sim <- map_dbl(m, \(mi) sum(w22 * rbeta(length(w22), mi * p_old$concentration, (1 - mi) * p_old$concentration)) / sum(w22))
  mean(sim <= f)
})
pace$pit_old <- pit_old
pace$model_m_old <- stage_mean(pace$hours, p_old)
syn_after <- read_csv(file.path(project_root(), "pipeline", "tests", "backtest_results.csv"), show_col_types = FALSE)
syn_before <- read_csv(file.path(project_root(), "pipeline", "tests", "eval_turnout", "backtest_synthetic_before.csv"), show_col_types = FALSE)

state_err <- \(d) d |> filter(level == "state") |> mutate(err = median / truth - 1, c50 = truth >= lo50 & truth <= hi50, c90 = truth >= lo90 & truth <= hi90, width = (hi90 - lo90) / truth)
warp_h <- state_err(warp) |>
  mutate(ex22 = year != 2022) |>
  summarise(mape = mean(abs(err)), bias = mean(err), c50 = mean(c50), c90 = mean(c90), width = mean(width), n = n(), .by = c(prior, params, hours)) |>
  mutate(subset = "all pairs")
warp_h_ex <- state_err(warp) |>
  filter(year != 2022) |>
  summarise(mape = mean(abs(err)), bias = mean(err), c50 = mean(c50), c90 = mean(c90), width = mean(width), n = n(), .by = c(prior, params, hours)) |>
  mutate(subset = "excluding 2022 totals")
warp_cty <- warp |>
  filter(level == "county", hours %in% c(6, 24, 72)) |>
  mutate(group = cut(registered, c(0, 10000, 50000, Inf), c("small", "mid", "large")), err = median / truth - 1) |>
  summarise(bias = mean(err), mape = mean(abs(err)), c90 = mean(truth >= lo90 & truth <= hi90), c50 = mean(truth >= lo50 & truth <= hi50), .by = c(prior, params, hours, group))
real_state <- state_err(real) |> select(year, prior_year, label, params, hours, frac_counted, truth, median, lo90, hi90, err, c50, c90, width)
real_cty <- real |>
  filter(level == "county") |>
  mutate(group = cut(registered, c(0, 10000, 50000, Inf), c("small", "mid", "large")), err = median / truth - 1) |>
  summarise(bias = mean(err), mape = mean(abs(err)), c90 = mean(truth >= lo90 & truth <= hi90), c50 = mean(truth >= lo50 & truth <= hi50), .by = c(year, prior_year, label, params, group))

early <- pace |> filter(hours <= 100)
early_old_below <- sum(early$pit_old < 0.5)
facts <- list(
  n_pace = nrow(pace), n_early = nrow(early),
  early_below_median = early_old_below, early_pit_new_median = median(early$pit), early_pit_old_median = median(early$pit_old), early_outside90 = sum(early$pit_old < 0.05 | early$pit_old > 0.95), early_outside90_new = sum(early$pit < 0.05 | early$pit > 0.95),
  fit_m0 = pre$m0, fit_tau = pre$tau_hours, fit_rmse = pre$rmse
)

data <- list(
  pace = pace, band_dep = band_dep, band_fit = band_fit, cobs = cobs, disp = disp, a_state = a_state,
  a_sum = a_sum |> filter(group == "all counties"),
  a_sum_size = a_sum |> filter(group != "all counties"),
  a_oracle = a_orc |> mutate(ape = abs(median / truth - 1), c90 = truth >= lo90 & truth <= hi90, c50 = truth >= lo50 & truth <= hi50) |>
    summarise(wmape = sum(abs(median - truth)) / sum(truth), mape = mean(ape), c90 = mean(c90), c50 = mean(c50), width90 = mean((hi90 - lo90) / truth), .by = c(year, prev)),
  a_cty = a_cty |> filter(year %in% c(2022, 2024)) |> select(year, prev, fips, registered, truth, median, lo90, hi90),
  warp_h = bind_rows(warp_h, warp_h_ex), warp_cty = warp_cty, real_state = real_state, real_cty = real_cty, facts = facts, syn_after = syn_after, syn_before = syn_before, model_new = model_defaults()[c("m0", "m_inf", "tau_hours", "concentration", "pace_size_slope", "sigma_eta", "sigma_eta_late", "sigma_eps", "sigma_eps_small", "likelihood_power")], model_old = p_old[c("m0", "m_inf", "tau_hours", "concentration", "pace_size_slope", "sigma_eta", "sigma_eta_late", "sigma_eps", "sigma_eps_small", "likelihood_power")],
  inventory = tm("county_count_timeline_all_series.csv") |> summarise(snapshots = n_distinct(timestamp_utc), counties = n_distinct(county_fips), rows = n(), hmin = min(as.numeric(hours_since_close)), hmax = max(as.numeric(hours_since_close)), .by = c(election_id, source))
)
json <- jsonlite::toJSON(data, auto_unbox = TRUE, na = "null", digits = 5, dataframe = "rows")
tpl <- read_file(file.path(project_root(), "pipeline", "tests", "report", "turnout_report_template.html"))
write_file(str_replace(tpl, fixed("/*__DATA__*/null"), json), out_path)
message("Wrote ", out_path)
