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
p_fit <- modifyList(model_defaults(), list(m0 = pre$m0, m_inf = 0.99, tau_hours = pre$tau_hours))
band_dep <- band(model_defaults())
band_fit <- band(p_fit)

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
facts <- list(
  n_pace = nrow(pace), n_early = nrow(early),
  early_below_median = sum(early$pit < 0.5), early_outside90 = sum(early$frac < early$lo90 | early$frac > early$hi90),
  fit_m0 = pre$m0, fit_tau = pre$tau_hours, fit_rmse = pre$rmse
)

data <- list(
  pace = pace, band_dep = band_dep, band_fit = band_fit, cobs = cobs, disp = disp, a_state = a_state,
  a_sum = a_sum |> filter(group == "all counties"),
  a_sum_size = a_sum |> filter(group != "all counties"),
  a_oracle = a_orc |> mutate(ape = abs(median / truth - 1), c90 = truth >= lo90 & truth <= hi90, c50 = truth >= lo50 & truth <= hi50) |>
    summarise(wmape = sum(abs(median - truth)) / sum(truth), mape = mean(ape), c90 = mean(c90), c50 = mean(c50), width90 = mean((hi90 - lo90) / truth), .by = c(year, prev)),
  a_cty = a_cty |> filter(year %in% c(2022, 2024)) |> select(year, prev, fips, registered, truth, median, lo90, hi90),
  warp_h = bind_rows(warp_h, warp_h_ex), warp_cty = warp_cty, real_state = real_state, real_cty = real_cty, facts = facts,
  inventory = tm("county_count_timeline_all_series.csv") |> summarise(snapshots = n_distinct(timestamp_utc), counties = n_distinct(county_fips), rows = n(), hmin = min(as.numeric(hours_since_close)), hmax = max(as.numeric(hours_since_close)), .by = c(election_id, source))
)
json <- jsonlite::toJSON(data, auto_unbox = TRUE, na = "null", digits = 5, dataframe = "rows")
tpl <- read_file(file.path(project_root(), "pipeline", "tests", "report", "turnout_report_template.html"))
write_file(str_replace(tpl, fixed("/*__DATA__*/null"), json), out_path)
message("Wrote ", out_path)
