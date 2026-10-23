#!/usr/bin/env Rscript
# Re-summarises pipeline/tests/backtest_needle_runs.csv (no new simulation): coverage, convergence, false confidence.
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
out_dir <- file.path(project_root(), "pipeline", "tests")
runs <- read_csv(file.path(out_dir, "backtest_needle_runs.csv"), show_col_types = FALSE) |>
  mutate(
    group = if_else(close, "house (close variants)", kind),
    leader_a = prob_raw > 0.5,
    wrong = leader_a != (a_wins == 1),
    se = (med - truth_margin) / (width90 / (2 * 1.645)),
    covered_by_p = case_when(prob_raw >= 0.99 | prob_raw <= 0.01 ~ "decided (<=1% / >=99%)", prob_raw >= 0.95 | prob_raw <= 0.05 ~ "confident (95-99%)", .default = "uncertain")
  )

coverage <- runs |>
  summarise(
    n = n(),
    cover50 = mean(cover50),
    cover90 = mean(cover90),
    z_sd = sd(se),
    mae = mean(abs(med - truth_margin)),
    width90 = mean(width90),
    .by = c(scenario, phi_target)
  ) |>
  arrange(scenario, phi_target)
print(coverage)

false_conf <- runs |>
  summarise(
    n = n(),
    wrong_calls = sum(wrong),
    mean_conf = mean(pmax(prob_raw, 1 - prob_raw)),
    .by = c(scenario, close, covered_by_p)
  ) |>
  arrange(scenario, close, covered_by_p)
print(false_conf)

calib <- runs |>
  mutate(bin = cut(prob_a, c(0, 0.011, 0.05, 0.2, 0.4, 0.6, 0.8, 0.95, 0.989, 1), include.lowest = TRUE)) |>
  summarise(n = n(), mean_pred = mean(prob_a), observed = mean(a_wins), .by = c(scenario, bin)) |>
  arrange(scenario, bin)
print(calib, n = 30)

tail_miss <- runs |>
  mutate(miss = !cover90, side = if_else(truth_margin < lo90, "below", "above")) |>
  summarise(miss_rate = mean(miss), below = mean(miss & side == "below"), above = mean(miss & side == "above"), .by = c(scenario, phi_target))
print(tail_miss)

decided <- runs |>
  filter(!close, kind != "legislature" | TRUE) |>
  summarise(share_decided = mean(prob_raw >= 0.99 | prob_raw <= 0.01), share_confident = mean(prob_raw >= 0.95 | prob_raw <= 0.05), .by = c(scenario, group, phi_target))
print(decided, n = 60)

res <- list(coverage = coverage, false_conf = false_conf, calib = calib, tail = tail_miss, decided = decided)
iwalk(res, \(x, nm) write_csv(x |> mutate(across(where(is.double), \(v) round(v, 4))), file.path(out_dir, str_c("eval_live_", nm, ".csv"))))
