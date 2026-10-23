#!/usr/bin/env Rscript
# The adopted specification uses the presidential baseline WITHOUT the generic-ballot shift: no historical generic-ballot data is
# available in the repo, and the typed-in values in eval_prior_forecast.R are used only for the diagnostic 'with environment' variants.
# Diagnoses the legislative pre-election prior (bias vs the presidential baseline, incumbency, non-Democratic
# challengers, generic-ballot shift) and back-tests a corrected specification with leave-one-year-out validation.
#   Rscript pipeline/tests/eval_legislative_spec.R      (needs eval_prior_contests.csv from eval_prior_forecast.R)
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
out_dir <- file.path(project_root(), "pipeline", "tests")
options(width = 200)

d <- read_csv(
  file.path(out_dir, "eval_prior_contests.csv"),
  show_col_types = FALSE
) |>
  filter(chamber != "us-house") |>
  mutate(
    y = qlogis(pmin(pmax(actual_two_party, 0.005), 0.995)),
    x = qlogis(m_noenv),
    x_env = qlogis(m_env),
    nonD = as.numeric(kind == "other_vs_r"),
    # incumbency from the point of view of the challenger-side candidate "a": +1 own-side incumbent, -1 Republican incumbent
    inc_R = as.numeric(str_detect(inc, "R")),
    inc_a = as.numeric(if_else(
      kind == "d_vs_r",
      str_detect(inc, "D"),
      str_detect(inc, "O")
    )),
    senate = as.numeric(chamber == "state-senate"),
    env_l = x_env - x
  )
known <- d |> filter(inc != "unknown")

section <- \(x) cat("\n====", x, "====\n")

section(
  "1. Bias of the presidential baseline (share of two-party vote for the D/challenger side, actual - predicted)"
)
bias_tbl <- d |>
  filter(kind == "d_vs_r") |>
  summarise(
    n = n(),
    bias_noenv = mean(err_share_noenv),
    bias_env = mean(err_share),
    mae_noenv = mean(abs(err_share_noenv)),
    mae_env = mean(abs(err_share)),
    .by = year
  ) |>
  arrange(year)
print(bias_tbl)
print(
  d |>
    filter(kind == "d_vs_r") |>
    summarise(
      n = n(),
      bias_noenv = mean(err_share_noenv),
      bias_env = mean(err_share),
      mae_noenv = mean(abs(err_share_noenv)),
      mae_env = mean(abs(err_share))
    )
)
bin_tbl <- d |>
  filter(kind == "d_vs_r") |>
  mutate(bin = cut(m_noenv, c(0, 0.2, 0.3, 0.4, 0.5, 0.6, 1))) |>
  summarise(
    n = n(),
    bias = mean(err_share_noenv),
    mae = mean(abs(err_share_noenv)),
    .by = bin
  ) |>
  arrange(bin)
print(bin_tbl)

section(
  "2. Incumbency (D-vs-R contests, bias vs baseline in share points, by who is the incumbent)"
)
inc_tbl <- known |>
  filter(kind == "d_vs_r") |>
  mutate(
    inc_group = case_when(
      str_detect(inc, "R") & !str_detect(inc, "D") ~ "R incumbent",
      str_detect(inc, "D") & !str_detect(inc, "R") ~ "D incumbent",
      inc == "none" ~ "open / none",
      .default = "both"
    )
  ) |>
  summarise(
    n = n(),
    bias_noenv = mean(err_share_noenv),
    sd = sd(err_share_noenv),
    .by = inc_group
  )
print(inc_tbl)

section(
  "3. Non-Democratic challengers vs Republican (actual challenger two-party share vs the Democratic baseline)"
)
nd <- d |> filter(kind == "other_vs_r")
print(
  nd |>
    summarise(
      n = n(),
      mean_baseline = mean(m_noenv),
      mean_actual = mean(actual_two_party),
      bias = mean(err_share_noenv),
      mae = mean(abs(err_share_noenv)),
      wins = sum(a_wins),
      max_actual = max(actual_two_party),
      max_baseline = max(m_noenv),
      .by = year
    )
)
print(
  nd |>
    summarise(
      n = n(),
      mean_baseline = mean(m_noenv),
      mean_actual = mean(actual_two_party),
      bias = mean(err_share_noenv),
      wins = sum(a_wins)
    )
)
print(
  nd |>
    arrange(desc(actual_two_party)) |>
    select(year, chamber, district, m_noenv, actual_two_party, a_wins, inc) |>
    head(8) |>
    mutate(across(where(is.double), \(x) round(x, 3)))
)

section(
  "4. Generic-ballot shift: does adding it reduce error? (D-vs-R, all legislative)"
)
env_check <- d |>
  filter(kind == "d_vs_r") |>
  summarise(
    env_logit = mean(x_env - x),
    actual_minus_noenv = mean(err_share_noenv),
    actual_minus_env = mean(err_share),
    mae_noenv = mean(abs(err_share_noenv)),
    mae_env = mean(abs(err_share)),
    .by = year
  ) |>
  arrange(year)
print(env_check)

section(
  "5. Regression: logit(actual share) on logit(baseline), incumbency and challenger type"
)
fit_full <- lm(y ~ x + inc_R + inc_a + nonD + senate, data = known)
print(summary(fit_full)$coefficients |> round(3))
cat("resid sd (logit):", round(sigma(fit_full), 3), "\n")
fit_slope <- lm(y ~ x, data = known |> filter(kind == "d_vs_r"))
print(round(coef(fit_slope), 3))

res <- known |> mutate(r = resid(fit_full))
print(res |> mutate(bin = cut(m_noenv, c(0, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 1))) |> summarise(n = n(), sd_logit = sd(r), sd_share = sd(actual_two_party - m_noenv), .by = bin) |> arrange(bin))
print(res |> arrange(desc(abs(r))) |> select(year, chamber, district, kind, m_noenv, actual_two_party, inc, r) |> head(8) |> mutate(across(where(is.double), \(x) round(x, 3))))

section("6. Leave-one-year-out back-test of specifications")
# Specifications for the mean of logit(share); residual sd taken from the training years, probabilities from a t(6) so tails stay honest.
specs <- list(
  production = NULL,
  offset_only = \(tr) lm(y - x ~ 1, data = tr),
  slope = \(tr) lm(y ~ x, data = tr),
  slope_inc = \(tr) lm(y ~ x + inc_R + inc_a, data = tr),
  proposed = \(tr) lm(y ~ x + inc_R + inc_a + nonD, data = tr),
  proposed_senate = \(tr) lm(y ~ x + inc_R + inc_a + nonD + senate, data = tr),
  proposed_plus_env = \(tr) lm(y ~ x + inc_R + inc_a + nonD + env_l, data = tr),
  proposed_on_env_baseline = \(tr) lm(y ~ x_env + inc_R + inc_a + nonD, data = tr)
)
t_df <- 6
evaluate_spec <- function(name, fit_fn) {
  yrs <- sort(unique(known$year))
  map(yrs, \(yr) {
    tr <- known |> filter(year != yr)
    te <- known |> filter(year == yr)
    if (name == "production") {
      return(
        te |>
          mutate(
            spec = name,
            p = prob_a,
            mu = qlogis(m_env),
            sdl = NA_real_,
            lo90s = lo90,
            hi90s = hi90
          )
      )
    }
    f <- fit_fn(tr)
    mu <- predict(f, te) + (if (name == "offset_only") te$x else 0)
    sd_kind <- tr |>
      mutate(r = resid(f)) |>
      summarise(sd_r = mad(r), .by = nonD)
    s <- te |>
      left_join(sd_kind, by = "nonD") |>
      pull(sd_r) |>
      (\(v) v * 1.1)()
    scale <- s * sqrt((t_df - 2) / t_df)
    p <- pmin(pmax(pt(mu / scale, t_df), 0.01), 0.99)
    q <- \(pp) (2 * plogis(mu + scale * qt(pp, t_df)) - 1) * (1 - 0.04)
    te |>
      mutate(
        spec = name,
        p = p,
        mu = mu,
        sdl = s,
        lo90s = q(0.05),
        hi90s = q(0.95),
        lo50s = q(0.25),
        hi50s = q(0.75)
      )
  }) |>
    list_rbind()
}
cv <- imap(specs, \(f, nm) evaluate_spec(nm, f)) |> list_rbind()
score <- \(g) {
  g |>
    summarise(
      n = n(),
      mae_share = mean(abs(
        actual_two_party - if_else(spec == "production", m_env, plogis(mu))
      )),
      bias_share = mean(
        actual_two_party - if_else(spec == "production", m_env, plogis(mu))
      ),
      brier = mean((p - a_wins)^2),
      logloss = -mean(a_wins * log(p) + (1 - a_wins) * log(1 - p)),
      wrong_fav = sum((p > 0.5) != (a_wins == 1)),
      exp_wrong = sum(pmin(p, 1 - p)),
      cover90 = mean(actual_margin >= lo90s & actual_margin <= hi90s),
      .by = spec
    )
}
cv_all <- cv |> filter(kind == "d_vs_r") |> score() |> mutate(set = "D-vs-R")
cv_nd <- cv |>
  filter(kind == "other_vs_r") |>
  score() |>
  mutate(set = "non-D challenger")
cv_comp <- cv |>
  filter(kind == "d_vs_r", between(m_noenv, 0.3, 0.7)) |>
  score() |>
  mutate(set = "D-vs-R, baseline 30-70%")
cv_tbl <- bind_rows(cv_all, cv_comp, cv_nd) |>
  mutate(across(where(is.double), \(x) round(x, 4)))
print(cv_tbl)
write_csv(cv_tbl, file.path(out_dir, "eval_legislative_spec_cv.csv"))

cal_breaks <- c(0, 0.011, 0.05, 0.2, 0.4, 0.6, 0.8, 0.95, 0.989, 1)
cal <- cv |>
  filter(spec %in% c("production", "proposed")) |>
  mutate(bin = cut(p, cal_breaks, include.lowest = TRUE)) |>
  summarise(
    n = n(),
    mean_pred = mean(p),
    observed = mean(a_wins),
    .by = c(spec, bin)
  ) |>
  arrange(spec, bin) |>
  mutate(across(where(is.double), \(x) round(x, 4)))
print(cal, n = 40)
write_csv(cal, file.path(out_dir, "eval_legislative_spec_calibration.csv"))

section(
  "7. Final corrected coefficients (all four cycles) and 2026 implied corrections"
)
fit_final <- lm(y ~ x + inc_R + inc_a + nonD, data = known)
print(round(summary(fit_final)$coefficients, 3))
cat("sigma:", round(sigma(fit_final), 3), "\n")
print(known |> mutate(r = resid(fit_final)) |> summarise(n = n(), sd_resid = sd(r), mad_resid = mad(r), .by = nonD))
section("8. Win rates of close seats (baseline 40-60%) by incumbent party")
print(known |> filter(kind == "d_vs_r", between(m_noenv, 0.4, 0.6)) |> mutate(inc_group = case_when(str_detect(inc, "R") & !str_detect(inc, "D") ~ "R incumbent", str_detect(inc, "D") & !str_detect(inc, "R") ~ "D incumbent", .default = "open / both")) |> summarise(n = n(), d_wins = sum(a_wins), mean_baseline = mean(m_noenv), mean_actual = mean(actual_two_party), .by = inc_group))
section("9. Residual mean by year (proposed spec without env) vs env shift")
print(known |> mutate(r = resid(fit_final)) |> summarise(mean_resid = mean(r), env_l = mean(env_l), n = n(), .by = year) |> arrange(year))
print(cv_tbl |> filter(set != "non-D challenger") |> select(spec, set, mae_share, brier, logloss, wrong_fav, exp_wrong, cover90), n = 30)
write_csv(
  tibble(
    term = names(coef(fit_final)),
    estimate = coef(fit_final),
    sigma = sigma(fit_final),
    n = nrow(known)
  ),
  file.path(out_dir, "eval_legislative_spec_coefs.csv")
)
write_csv(bias_tbl, file.path(out_dir, "eval_legislative_bias_by_year.csv"))
write_csv(env_check, file.path(out_dir, "eval_legislative_env_check.csv"))
write_csv(inc_tbl, file.path(out_dir, "eval_legislative_incumbency.csv"))

section("10. Gaussian total prior sd (logit) as the needle would use it: calibration vs width, leave-one-year-out means")
sd_grid <- crossing(sd_dvr = c(0.2, 0.25, 0.3, 0.35, 0.45), sd_nd = c(0.45, 0.6))
grid_scores <- sd_grid |>
  mutate(
    res = map2(sd_dvr, sd_nd, \(sd_a, sd_b) {
      cv |>
        filter(spec == "proposed") |>
        mutate(sdl_g = if_else(nonD == 1, sd_b, sd_a), p_g = pmin(pmax(pnorm(mu / sdl_g), 0.01), 0.99)) |>
        summarise(
          brier = mean((p_g - a_wins)^2),
          logloss = -mean(a_wins * log(p_g) + (1 - a_wins) * log(1 - p_g)),
          mid_bin_pred = mean(p_g[between(p_g, 0.2, 0.8)]),
          mid_bin_obs = mean(a_wins[between(p_g, 0.2, 0.8)]),
          mid_n = sum(between(p_g, 0.2, 0.8)),
          wrong_fav = sum((p_g > 0.5) != (a_wins == 1))
        )
    })
  ) |>
  unnest(res) |>
  mutate(across(where(is.double), \(x) round(x, 4)))
print(grid_scores)
write_csv(grid_scores, file.path(out_dir, "eval_legislative_spec_sd_grid.csv"))
