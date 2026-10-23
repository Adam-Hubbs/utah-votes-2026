#!/usr/bin/env Rscript
# Replays the 2024 general election (2024 districts, official precinct results) through the needle at 25/50/75/90% counted.
#   Rscript pipeline/tests/backtest_needle.R [reps_per_cell] [draws]
# Partial counting: county pace and precinct pace vary; the late-counted ballots of every precinct are shifted
# (logit scale) relative to the early ones so that early + late = the official final result.
# Baselines are a *different* contest of the same election (president for House/legislature/measures,
# governor for president) so precinct-level structure is realistic but the level is not given away.
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
for (f in c(
  "live_api",
  "model_expected",
  "live_normalize",
  "history_ut_export",
  "model_needle"
)) {
  source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))
}

args <- commandArgs(trailingOnly = TRUE)
reps <- as.integer(args[1] %||% 10)
draws <- as.integer(args[2] %||% 2000)
p <- needle_params()
p$draws <- draws

tabs <- ut_export_contest_tables(raw_dir(
  "results",
  "export-general11052024.json"
))
opt <- tabs$state |>
  mutate(
    side = case_when(
      str_detect(str_to_lower(party %||% ""), "^democ") ~ "dem",
      str_detect(str_to_lower(party %||% ""), "^repub") ~ "rep",
      str_to_lower(option) == "for" ~ "for",
      str_to_lower(option) == "against" ~ "against",
      .default = "oth"
    )
  )
# President's party strings differ ("Demo..." / "Repu...") but the same rule applies.
item_votes <- function(item) {
  tabs$local |>
    filter(item_id == item) |>
    inner_join(
      select(opt, item_id, option_id, side),
      by = c("item_id", "option_id")
    ) |>
    summarise(
      a = sum(votes[side %in% c("dem", "for")]),
      b = sum(votes[side %in% c("rep", "against")]),
      o = sum(votes[side == "oth"]),
      .by = c(county_fips, precinct)
    ) |>
    mutate(pid = precinct_key(county_fips, precinct))
}

pres <- item_votes("State-1") |>
  transmute(pid, county_fips, d = a, r = b, tot = a + b + o)
gov <- item_votes("State-7") |> transmute(pid, d = a, r = b)

contest_defs <- bind_rows(
  tibble(id = "president", item = "State-1", kind = "president", base = "gov"),
  tibble(
    id = str_c("us-house-", 1:4),
    item = str_c("State-", 3:6),
    kind = "house",
    base = "pres"
  ),
  tibble(
    id = c("amendment-b", "amendment-c"),
    item = c("State-145", "State-146"),
    kind = "measure",
    base = "pres"
  )
)
leg_meta <- tabs$meta |>
  filter(str_detect(name, "^State (House|Senate)")) |>
  mutate(n = map_int(item_id, \(i) sum(tabs$local$item_id == i)))
leg_pick <- leg_meta |>
  filter(n > 40) |>
  mutate(
    ok = map_lgl(item_id, \(i) {
      s <- filter(opt, item_id == i)
      any(s$side == "dem") && any(s$side == "rep")
    })
  ) |>
  filter(ok) |>
  slice(seq(1, n(), length.out = 12) |> round() |> unique())
contest_defs <- bind_rows(
  contest_defs,
  tibble(
    id = leg_pick$name,
    item = leg_pick$item_id,
    kind = "legislature",
    base = "pres"
  )
)

# ---- truth + baseline for one contest -----------------------------------------------------------------------
prepare_contest <- function(def) {
  tr <- item_votes(def$item) |> filter(a + b + o > 0)
  bl <- if (def$base == "gov") gov else select(pres, pid, d, r)
  county_ballots <- pres |>
    summarise(T = sum(tot) / VOTE_PER_BALLOT, .by = county_fips)
  tr <- tr |>
    left_join(select(pres, pid, w = tot), by = "pid") |>
    left_join(bl, by = "pid") |>
    mutate(miss = is.na(d) | d + r == 0, b0 = (d + 1) / (d + r + 2))
  list(def = def, truth = tr, county_ballots = county_ballots)
}

# ---- reveal --------------------------------------------------------------------------------------------------
solve_early <- function(s, r, lam) {
  lo <- rep(-9, length(s))
  hi <- rep(9, length(s))
  target <- qlogis(pmin(pmax(s, 1e-6), 1 - 1e-6))
  for (i in 1:50) {
    mid <- (lo + hi) / 2
    f <- r * plogis(mid) + (1 - r) * plogis(mid + lam) - plogis(target)
    lo <- if_else(f < 0, mid, lo)
    hi <- if_else(f < 0, hi, mid)
  }
  plogis((lo + hi) / 2)
}

reveal <- function(tr, phi, late_mean, late_sd, late_county_sd) {
  fips <- unique(tr$county_fips)
  a_c <- set_names(exp(rnorm(length(fips), 0, 0.35)), fips)
  start <- set_names(rbeta(length(fips), 1, 4) * 0.5, fips)
  n_tot <- tr$a + tr$b + tr$o
  z <- rnorm(nrow(tr), 0, 0.3)
  frac_for <- \(scale) {
    f_c <- if_else(phi >= start, 1 - (1 - phi)^(a_c * scale), 0)
    1 - (1 - pmin(f_c[match(tr$county_fips, fips)], 0.999))^exp(z)
  }
  g <- \(sc) sum(n_tot * frac_for(sc)) / sum(n_tot) - phi
  sc <- tryCatch(uniroot(g, c(0.05, 20))$root, error = \(e) 1)
  r <- pmin(pmax(frac_for(sc), 0.002), 0.999)
  lam_c <- set_names(rnorm(length(fips), 0, late_county_sd), fips)
  lam <- late_mean + rnorm(1, 0, late_sd) + lam_c[tr$county_fips]
  n2 <- tr$a + tr$b
  s_final <- (tr$a + 0.0) / pmax(n2, 1)
  s_e <- solve_early(s_final, r, lam)
  n_c <- round(r * n2)
  # counted ballots are a random subset of the precinct's ballots, so counted shares carry sampling noise
  ca <- rbinom(length(n_c), n_c, s_e)
  cb <- n_c - ca
  co <- rbinom(length(n_c), tr$o, r)
  tibble(
    ca = pmin(ca, tr$a),
    cb = pmin(pmax(cb, 0), tr$b),
    co = pmin(co, tr$o)
  )
}

# ---- one replicate -------------------------------------------------------------------------------------------
run_rep <- function(pc, phi, scenario, close, seed) {
  set.seed(seed)
  def <- pc$def
  tr <- pc$truth
  if (close) {
    n2 <- tr$a + tr$b
    target <- 0.5 + sample(c(-1, 1), 1) * 0.015
    f <- \(d)
      sum(
        n2 * plogis(qlogis(pmin(pmax(tr$a / pmax(n2, 1), 1e-4), 1 - 1e-4)) + d)
      ) /
        sum(n2) -
        target
    d <- uniroot(f, c(-4, 4))$root
    a_new <- round(
      n2 * plogis(qlogis(pmin(pmax(tr$a / pmax(n2, 1), 1e-4), 1 - 1e-4)) + d)
    )
    tr <- tr |> mutate(a = a_new, b = n2 - a_new)
  }
  late <- if (scenario == "none") c(mean = 0, sd = 0, csd = 0) else if (scenario == "stress")
    c(mean = 0.08 * sample(c(-1, 1), 1), sd = 0.25, csd = 0.15) else
    c(mean = 0, sd = p$late_sd, csd = p$late_county_sd)
  rv <- reveal(tr, phi, late[["mean"]], late[["sd"]], late[["csd"]])
  tr <- bind_cols(tr, rv)
  truth_margin <- (sum(tr$a) - sum(tr$b)) / sum(tr$a + tr$b + tr$o)

  fips_all <- sort(unique(tr$county_fips))
  cty <- tibble(fips = fips_all) |>
    left_join(pc$county_ballots |> rename(fips = county_fips), by = "fips") |>
    left_join(
      tr |>
        summarise(
          C = sum(ca + cb + co),
          V = sum(a + b + o),
          .by = county_fips
        ) |>
        rename(fips = county_fips),
      by = "fips"
    ) |>
    mutate(
      rho = pmin(C / V, 1),
      B = rho * T,
      phi_c = pmax(rho, 0.05),
      s_stated = 0.02 + 0.10 * (1 - phi_c)^1.5,
      s_true = if_else(
        rep(scenario == "stress", n()),
        1.6 * s_stated,
        s_stated
      ),
      med = T * exp(rnorm(n(), 0, s_true)),
      sdlog = s_stated,
      kappa = V / T,
      final = FALSE
    )
  # the model never reports an expected total below what is counted
  cty <- cty |> mutate(med = pmax(med, B * 1.001))

  base_w <- tr |> mutate(z0 = qlogis(b0), w = coalesce(w, 1))
  zc <- base_w |> summarise(zc = mean(z0[!miss]), .by = county_fips)
  base_w <- base_w |>
    left_join(zc, by = "county_fips") |>
    mutate(z = coalesce(if_else(miss, NA_real_, z0), zc, mean(z0[!miss])))
  zbar <- weighted.mean(base_w$z, pmax(base_w$w, 1))
  prec <- tibble(
    pid = base_w$pid,
    fips = base_w$county_fips,
    cty = match(base_w$county_fips, fips_all),
    va = base_w$ca,
    vb = base_w$cb,
    vo = base_w$co,
    x = if (def$kind == "measure") base_w$z - zbar else base_w$z - zbar,
    z = base_w$z,
    w = pmax(base_w$w, 1),
    miss = base_w$miss
  )

  # prior built from the baseline only (never from the truth)
  tr0 <- pc$truth
  if (def$kind == "measure") {
    prior <- list(
      alpha = 0,
      beta = 0,
      sd_alpha = p$measure_alpha_sd,
      sd_beta = p$measure_beta_sd,
      other = 0,
      share = 0.5
    )
  } else {
    sd_f <- case_when(
      def$kind == "president" ~ 0.10,
      def$kind == "house" ~ p$fundamentals_sd_house,
      .default = p$fundamentals_sd_leg
    )
    m_f <- sum(prec$w * plogis(prec$z)) / sum(prec$w)
    sol <- solve_alpha(prec$x, prec$w, 1, m_f)
    prior <- list(
      alpha = sol$alpha,
      beta = 1,
      sd_alpha = sd_f / sol$slope,
      sd_beta = 0.25,
      other = p$other_prior,
      share = m_f
    )
  }
  f <- sum(prec$va + prec$vb + prec$vo) / sum(tr$a + tr$b + tr$o)
  prior <- needle_prior_early(prior, f, p)
  inp <- list(
    type = if_else(def$kind == "measure", "measure", "candidate"),
    ids = c("a", "b"),
    prec = prec,
    cty = cty,
    prior = prior
  )
  sim <- needle_simulate(inp, prior, p, draws, seed + 7)
  sm <- needle_summarise(sim$draws, inp$ids)
  tibble(
    contest = def$id,
    kind = def$kind,
    close = close,
    scenario = scenario,
    phi_target = phi,
    phi = f,
    truth_margin = truth_margin,
    med = sm$margin$median,
    lo50 = sm$margin$lo50,
    hi50 = sm$margin$hi50,
    lo90 = sm$margin$lo90,
    hi90 = sm$margin$hi90,
    cover90 = truth_margin >= sm$margin$lo90 & truth_margin <= sm$margin$hi90,
    cover50 = truth_margin >= sm$margin$lo50 & truth_margin <= sm$margin$hi50,
    prob_a = sm$prob[[1]],
    prob_raw = sm$prob_raw,
    a_wins = as.numeric(truth_margin > 0),
    width90 = sm$margin$hi90 - sm$margin$lo90,
    alpha_hat = sim$theta$mean[1], beta_hat = sim$theta$mean[2], sigma_eps = sim$sigma_eps,
    rem_a_true = (sum(tr$a) - sum(tr$ca)) / (sum(tr$a + tr$b) - sum(tr$ca + tr$cb)),
    rem_a_model = median((sim$draws$A - sum(prec$va)) / (sim$draws$A - sum(prec$va) + sim$draws$B - sum(prec$vb))),
    rem_n_true = sum(tr$a + tr$b + tr$o) - sum(tr$ca + tr$cb + tr$co),
    rem_n_model = median(sim$draws$A + sim$draws$B + sim$draws$O) - sum(prec$va + prec$vb + prec$vo)
  )
}

if (Sys.getenv("BT_STOP") == "1") { print(pres); print(tabs$local |> count(item_id) |> head()); print(prepare_contest(contest_defs[2, ])$truth); quit() }
prepared <- map(
  seq_len(nrow(contest_defs)),
  \(i) prepare_contest(contest_defs[i, ])
) |>
  set_names(contest_defs$id)
grid <- expand_grid(
  contest = contest_defs$id,
  phi = c(0.25, 0.5, 0.75, 0.9),
  scenario = c("base", "stress"),
  rep = seq_len(reps)
) |>
  left_join(select(contest_defs, contest = id, kind), by = "contest") |>
  # close-race variants: only for races whose official margin is not already tiny
  bind_rows(
    expand_grid(
      contest = str_c("us-house-", 1:4),
      phi = c(0.25, 0.5, 0.75, 0.9),
      scenario = c("base", "stress"),
      rep = seq_len(reps)
    ) |>
      mutate(kind = "house", close = TRUE)
  ) |>
  mutate(close = coalesce(close, FALSE), seed = 1000 + row_number())

t0 <- Sys.time()
runs <- pmap(grid, \(contest, phi, scenario, rep, kind, close, seed) {
  if (Sys.getenv("BT_DEBUG") == "1") return(run_rep(prepared[[contest]], phi, scenario, close, seed))
  tryCatch(
    run_rep(prepared[[contest]], phi, scenario, close, seed),
    error = \(e) {
      message("failed: ", contest, " ", conditionMessage(e))
      NULL
    }
  )
}) |>
  list_rbind()
message(
  "backtest: ",
  nrow(runs),
  " runs in ",
  round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1),
  " min"
)

runs <- runs |> mutate(pct_counted = str_c(round(phi_target * 100), "%"))
summ <- runs |>
  mutate(
    group = case_when(close ~ "house (close variants)", .default = kind)
  ) |>
  summarise(
    runs = n(),
    cover90 = mean(cover90),
    cover50 = mean(cover50),
    brier = mean((prob_a - a_wins)^2),
    brier_uncapped = mean((prob_raw - a_wins)^2),
    mean_width90 = mean(width90),
    mean_abs_err = mean(abs(med - truth_margin)),
    .by = c(scenario, group, phi_target)
  ) |>
  bind_rows(
    runs |>
      summarise(
        runs = n(),
        cover90 = mean(cover90),
        cover50 = mean(cover50),
        brier = mean((prob_a - a_wins)^2),
        brier_uncapped = mean((prob_raw - a_wins)^2),
        mean_width90 = mean(width90),
        mean_abs_err = mean(abs(med - truth_margin)),
        .by = c(scenario, phi_target)
      ) |>
      mutate(group = "all")
  ) |>
  arrange(scenario, group, phi_target) |>
  mutate(across(where(is.numeric), \(x) round(x, 4)))
write_csv(
  summ,
  file.path(project_root(), "pipeline", "tests", "backtest_needle_results.csv")
)
write_csv(
  runs |> mutate(across(where(is.numeric), \(x) round(x, 4))),
  file.path(project_root(), "pipeline", "tests", "backtest_needle_runs.csv")
)
print(summ |> filter(group == "all"), n = 20)
print(summ |> filter(scenario == "base"), n = 60)
