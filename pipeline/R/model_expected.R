POLLS_CLOSE_UTC <- as.POSIXct("2026-11-04 03:00:00", tz = "UTC")

# Share of ballots that show up as a vote in the best-voted contest (amendments/retention have a few
# percent undervote). Counted ballots are inferred from contest totals because the API's ballotsCast
# is not reliable for county rows.
VOTE_PER_BALLOT <- 0.97

model_defaults <- function() {
  list(
    draws = 4000L,
    sigma_delta = 0.6, # scale of the statewide turnout shift, logit scale
    df_delta = 3, # Student-t df: Utah midterm turnout swings between cycles (2018 surge) are far heavier-tailed than a normal
    df_eta = 3, # same for the statewide pace shift
    mu_delta = 0.10, # 2026 is expected to run a bit hotter than 2022 (new map, high-profile House race)
    sigma_eps = 0.17, # county-specific turnout deviation for large counties, logit scale
    sigma_eps_small = 0.6, # extra deviation scale for small counties: sd_c = sqrt(sigma_eps^2 + (this / sqrt(registered/1000))^2)
    sigma_eta = 0.7, # scale of statewide uncertainty in count completeness at poll close, logit scale
    sigma_eta_late = 0.5, # same scale once counting has converged (late ballots are mostly cures, so pace matters less)
    tau_eta_hours = 24, # how fast the pace uncertainty decays towards sigma_eta_late
    m0 = 0.62, # prior mean fraction of final ballots counted at the first post-8pm drop
    m_inf = 0.975, # fraction counted once only cures/provisionals are outstanding
    tau_hours = 22,
    likelihood_power = 0.35, # tempers the county likelihood: counties are not independent draws of the statewide shift/pace (shared processing, shared vote-method mix)
    returned_valid = 0.97, # share of returned ballots that end up counted
    concentration = 12, # Beta concentration of a county's counted fraction around the stage mean (counties differ a lot in processing speed)
    remaining_sd = 0.05, # relative sd of an officially reported "ballots remaining"
    grid_range = 6, # statewide grids span +-6 scale units to cover the t tails
    grid_delta = 49L,
    grid_eta = 41L,
    grid_eps = 31L
  )
}

stage_mean <- function(hours, p = model_defaults()) {
  h <- pmax(hours, 0)
  p$m_inf - (p$m_inf - p$m0) * exp(-h / p$tau_hours)
}

eta_scale <- function(hours, p = model_defaults()) {
  p$sigma_eta_late + (p$sigma_eta - p$sigma_eta_late) * exp(-pmax(hours, 0) / p$tau_eta_hours)
}

read_remaining_overrides <- function(
  path = file.path(
    project_root(),
    "pipeline",
    "config",
    "remaining_ballots.csv"
  )
) {
  empty <- tibble(fips = character(), remaining = numeric(), final = logical())
  if (!file.exists(path)) return(empty)
  read_csv(
    path,
    col_types = cols(
      fips = col_character(),
      remaining = col_double(),
      .default = col_character()
    ),
    comment = "#"
  ) |>
    filter(
      !is.na(fips),
      !is.na(remaining) |
        tolower(coalesce(final, "")) %in% c("true", "yes", "1")
    ) |>
    mutate(final = tolower(coalesce(final, "")) %in% c("true", "yes", "1")) |>
    select(fips, remaining, final)
}

# Optional pre-election ballots-returned counts by county (fips, returned). No official per-county feed is known to exist,
# so the file is absent by default; when present, returned ballots (net of a few percent rejected) lower-bound T_c.
read_ballots_returned <- function(
  path = file.path(project_root(), "pipeline", "config", "ballots_returned.csv")
) {
  empty <- tibble(fips = character(), returned = numeric())
  if (!file.exists(path)) return(empty)
  read_csv(path, col_types = cols(fips = col_character(), returned = col_double(), .default = col_character()), comment = "#", show_col_types = FALSE) |>
    filter(!is.na(fips), !is.na(returned)) |>
    select(fips, returned)
}

# Posterior over county eventual ballots T_c. Works on a 2-D grid for the two statewide latent
# parameters (turnout shift delta, completeness shift eta) with the county deviation eps_c integrated out
# on a 1-D grid, then draws joint samples. Everything is vectorized; ~1s for 4000 draws x 29 counties.
fit_expected_ballots <- function(
  counties,
  hours,
  p = model_defaults(),
  seed = NULL
) {
  if (!is.null(seed)) set.seed(seed)
  counties <- add_eps_sd(counties, p)
  if (!"returned" %in% names(counties)) counties$returned <- NA_real_
  counties$floor <- coalesce(counties$returned, 0) * p$returned_valid
  n <- nrow(counties)
  D <- p$draws
  m_base <- qlogis(stage_mean(hours, p))
  eps_grid <- seq(-3.5, 3.5, length.out = p$grid_eps)
  eps_w <- dnorm(eps_grid)
  eps_w <- eps_w / sum(eps_w)
  dgrid <- seq(-p$grid_range, p$grid_range, length.out = p$grid_delta)
  egrid <- seq(-p$grid_range, p$grid_range, length.out = p$grid_eta)
  grid <- expand_grid(zd = dgrid, ze = egrid)
  delta_g <- p$mu_delta + p$sigma_delta * grid$zd
  sd_eta <- eta_scale(hours, p)
  eta_g <- sd_eta * grid$ze
  logprior_g <- dt(grid$zd, p$df_delta, log = TRUE) + dt(grid$ze, p$df_eta, log = TRUE)

  informative <- counties$counted > 0 & !counties$fixed
  loglik_grid <- rep(0, nrow(grid))
  for (i in which(informative)) {
    loglik_grid <- loglik_grid +
      log_marginal_county(
        counties[i, ],
        delta_g,
        eta_g,
        m_base,
        eps_grid,
        eps_w,
        p
      )
  }
  lw <- logprior_g + p$likelihood_power * loglik_grid
  w <- exp(lw - max(lw))
  w <- w / sum(w)
  idx <- sample.int(nrow(grid), D, replace = TRUE, prob = w)
  # jitter inside the cell so draws are continuous rather than 961 repeated points
  step_d <- p$sigma_delta * (dgrid[2] - dgrid[1])
  step_e <- sd_eta * (egrid[2] - egrid[1])
  delta_d <- delta_g[idx] + runif(D, -0.5, 0.5) * step_d
  eta_d <- eta_g[idx] + runif(D, -0.5, 0.5) * step_e

  T_draws <- matrix(NA_real_, nrow = D, ncol = n)
  for (i in seq_len(n)) {
    row <- counties[i, ]
    mu_logit <- qlogis(row$prior_turnout) + delta_d
    T_draws[, i] <- if (row$final) {
      rep(row$counted, D)
    } else if (!is.na(row$remaining)) {
      row$counted + row$remaining * exp(rnorm(D, 0, p$remaining_sd))
    } else {
      sample_county_total(row, mu_logit, eta_d, m_base, eps_grid, p)
    }
  }
  colnames(T_draws) <- counties$fips
  list(T = T_draws, delta = delta_d, eta = eta_d)
}

# Small counties' turnout moves around much more between elections than the big urban ones.
add_eps_sd <- function(counties, p) {
  counties |>
    mutate(eps_sd = sqrt(p$sigma_eps^2 + (p$sigma_eps_small / sqrt(pmax(registered, 100) / 1000))^2))
}

log_marginal_county <- function(
  row,
  delta_g,
  eta_g,
  m_base,
  eps_grid,
  eps_w,
  p
) {
  mu <- qlogis(row$prior_turnout) + delta_g
  m <- plogis(m_base + eta_g)
  k <- p$concentration
  lt <- outer(mu, row$eps_sd * eps_grid, `+`)
  total <- row$registered * plogis(lt)
  f <- row$counted / total
  dens <- exp(dbeta(f, m * k, (1 - m) * k, log = TRUE)) / total
  dens[!is.finite(dens) | total < row$floor] <- 0
  log(pmax(as.vector(dens %*% eps_w), 1e-300))
}

sample_county_total <- function(row, mu_logit, eta_d, m_base, eps_grid, p) {
  D <- length(mu_logit)
  eps_sd <- row$eps_sd
  if (row$counted <= 0) {
    return(pmax(row$registered * plogis(mu_logit + eps_sd * rnorm(D)), row$floor))
  }
  m <- plogis(m_base + eta_d)
  k <- p$concentration
  lt <- outer(mu_logit, eps_sd * eps_grid, `+`)
  total <- row$registered * plogis(lt)
  f <- row$counted / total
  dens <- exp(dbeta(f, m * k, (1 - m) * k, log = TRUE)) /
    total *
    matrix(dnorm(eps_grid), D, length(eps_grid), byrow = TRUE)
  dens[!is.finite(dens) | total < row$floor] <- 0
  # Rows with no mass (county far outside any plausible fraction) fall back to the nearest feasible total.
  dead <- rowSums(dens) <= 0
  dens[dead, ] <- 1
  cum <- dens / rowSums(dens)
  cum <- t(apply(cum, 1, cumsum))
  u <- runif(D)
  j <- pmin(rowSums(cum < u) + 1L, length(eps_grid))
  step <- eps_sd * (eps_grid[2] - eps_grid[1])
  eps <- eps_sd * eps_grid[j] + runif(D, -0.5, 0.5) * step
  tot <- row$registered * plogis(mu_logit + eps)
  pmax(tot, row$counted * 1.001, row$floor)
}

summarise_draws <- function(T_draws, counted, lo = 0.05, hi = 0.95) {
  q <- \(x, pr) as.numeric(quantile(x, pr, names = FALSE))
  tibble(
    fips = colnames(T_draws),
    counted = counted,
    expected_median = map_dbl(
      seq_len(ncol(T_draws)),
      \(i) q(T_draws[, i], 0.5)
    ),
    expected_lo = map_dbl(seq_len(ncol(T_draws)), \(i) q(T_draws[, i], lo)),
    expected_hi = map_dbl(seq_len(ncol(T_draws)), \(i) q(T_draws[, i], hi))
  ) |>
    mutate(
      pct_expected = if_else(
        expected_median > 0,
        pmin(counted / expected_median, 1),
        0
      ),
      pct_expected_lo = if_else(
        expected_hi > 0,
        pmin(counted / expected_hi, 1),
        0
      ),
      pct_expected_hi = if_else(
        expected_lo > 0,
        pmin(counted / expected_lo, 1),
        0
      )
    )
}

# Contest-level completeness: scale each county's expected ballots by that county's observed (or
# imputed, for counties with nothing counted) contest participation rate and compare draw-by-draw.
contest_reporting <- function(T_draws, county_tbl) {
  tbl <- county_tbl |>
    mutate(row = match(fips, colnames(T_draws))) |>
    filter(!is.na(row))
  votes <- sum(tbl$votes)
  if (votes <= 0 || nrow(tbl) == 0) {
    return(list(pct_expected = 0, pct_expected_lo = 0, pct_expected_hi = 0))
  }
  seen <- tbl$counted > 0 & tbl$votes > 0
  rho_ref <- sum(tbl$votes[seen]) / sum((tbl$counted * tbl$share)[seen])
  rho <- if_else(
    tbl$counted > 0,
    tbl$votes / pmax(tbl$counted, 1),
    rho_ref * tbl$share
  )
  E <- T_draws[, tbl$row, drop = FALSE] %*% rho
  pct <- pmin(votes / as.numeric(E), 1)
  q <- quantile(pct, c(0.05, 0.5, 0.95), names = FALSE)
  list(pct_expected = q[2], pct_expected_lo = q[1], pct_expected_hi = q[3])
}

# Orchestrates model.json + pct_expected propagation for one results directory.
run_expected_vote_model <- function(
  results_dir,
  election_id,
  now = Sys.time(),
  seed = 2026,
  is_official = FALSE,
  registered_override = NULL,
  p = model_defaults()
) {
  if (exists("live_config")) p <- utils::modifyList(p, live_config()$model %||% list())
  rd <- \(...) file.path(results_dir, ...)
  summary_path <- rd("summary.json")
  contest_files <- list.files(
    rd("contests"),
    pattern = "\\.json$",
    full.names = TRUE
  )
  if (!file.exists(summary_path) || length(contest_files) == 0)
    stop("No results to model in ", results_dir)

  contests <- map(
    contest_files,
    \(f) jsonlite::read_json(f, simplifyVector = FALSE)
  ) |>
    set_names(path_ext_remove_base(contest_files))
  base <- read_csv(
    file.path(project_root(), "pipeline", "config", "county_baselines.csv"),
    col_types = cols(fips = col_character(), .default = col_guess()),
    show_col_types = FALSE
  )
  overrides <- read_remaining_overrides()
  if (!is.null(registered_override) && sum(registered_override$registered) > 1e6) {
    base <- base |>
      left_join(registered_override, by = "fips") |>
      mutate(registered_2026 = coalesce(registered, registered_2026)) |>
      select(-registered)
  }

  county_rows <- contests |>
    map(
      \(ct)
        map(
          ct$counties,
          \(r) tibble(fips = r$fips, counted = r$ballots_counted %||% 0)
        )
    ) |>
    list_flatten() |>
    list_rbind() |>
    summarise(counted = max(counted), .by = fips)

  cty <- base |>
    left_join(county_rows, by = "fips") |>
    left_join(overrides, by = "fips") |>
    left_join(read_ballots_returned(), by = "fips") |>
    mutate(
      counted = coalesce(counted, 0),
      registered = registered_2026,
      prior_turnout = pmin(pmax(turnout_2022, 0.3), 0.9),
      final = coalesce(final, FALSE) | is_official,
      fixed = final | !is.na(remaining)
    )
  # turnout_2022 was measured against 2022 registration; the prior is a rate so it carries over directly.

  hours <- as.numeric(difftime(now, POLLS_CLOSE_UTC, units = "hours"))
  fit <- fit_expected_ballots(cty, hours, p, seed)
  by_county <- summarise_draws(fit$T, cty$counted) |>
    left_join(
      select(cty, fips, name, registered, remaining, final),
      by = "fips"
    ) |>
    mutate(
      source = case_when(
        final ~ "final",
        !is.na(remaining) ~ "reported_remaining",
        .default = "model"
      )
    )

  state_T <- rowSums(fit$T)
  sq <- quantile(state_T, c(0.05, 0.5, 0.95), names = FALSE)
  counted_total <- sum(cty$counted)
  statewide <- list(
    counted = counted_total,
    expected_median = round(sq[2]),
    expected_lo = round(sq[1]),
    expected_hi = round(sq[3]),
    pct_expected = if_else(sq[2] > 0, min(counted_total / sq[2], 1), 0),
    pct_expected_lo = if_else(sq[3] > 0, min(counted_total / sq[3], 1), 0),
    pct_expected_hi = if_else(sq[1] > 0, min(counted_total / sq[1], 1), 0)
  )

  old <- if (file.exists(rd("model.json")))
    jsonlite::read_json(rd("model.json"), simplifyVector = FALSE) else
    list(history = list())
  now_iso <- format(as.POSIXct(now, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
  hist <- old$history %||% list()
  last <- if (length(hist) > 0) hist[[length(hist)]] else NULL
  if (is.null(last) || last$counted != counted_total) {
    hist <- c(
      hist,
      list(list(
        t = now_iso,
        counted = counted_total,
        expected_median = statewide$expected_median
      ))
    )
  }

  model <- list(
    updated_at = now_iso,
    draws = p$draws,
    method = str_c(
      "Bayesian expected-ballots model. Eventual county ballots = active registered voters x turnout, with turnout ",
      "centred on the county's 2022 midterm rate plus a heavy-tailed (Student-t) statewide shift and county deviations (logit scale). ",
      "The counted fraction of each county follows a Beta whose mean rises with hours since the 8pm MT poll close, ",
      "with a heavy-tailed statewide pace shift whose uncertainty shrinks as counting converges, so early counts can be explained ",
      "by either high turnout or fast pace. County likelihood is tempered for dependence between counties. Posterior by grid integration + Monte Carlo (",
      p$draws,
      " draws), ",
      "so counties inform each other. County 'ballots remaining' overrides, when present, replace the model."
    ),
    statewide = statewide,
    counties = by_county |>
      select(
        fips,
        registered,
        counted,
        expected_median,
        expected_lo,
        expected_hi,
        pct_expected,
        pct_expected_lo,
        pct_expected_hi,
        source
      ) |>
      mutate(across(c(expected_median, expected_lo, expected_hi), round)) |>
      transpose_rows(),
    history = hist
  )
  write_json_file(model, rd("model.json"))

  # propagate to contests
  county_pct <- by_county |>
    select(
      fips,
      expected_median,
      pct_expected,
      pct_expected_lo,
      pct_expected_hi
    ) |>
    set_names(c("fips", "exp", "p", "plo", "phi"))
  contest_summ <- map(names(contests), \(id) {
    ct <- contests[[id]]
    tbl <- map(
      ct$counties,
      \(r)
        tibble(
          fips = r$fips,
          votes = r$total %||% 0,
          counted = r$ballots_counted %||% 0,
          share = r$ballot_share %||% 1
        )
    ) |>
      list_rbind()
    contest_reporting(fit$T, tbl)
  }) |>
    set_names(names(contests))

  for (id in names(contests)) {
    ct <- contests[[id]]
    ct$counties <- map(ct$counties, \(r) {
      m <- filter(county_pct, fips == r$fips)
      if (nrow(m) == 1) {
        r$expected_ballots <- round(m$exp)
        r$pct_expected <- m$p
        r$pct_expected_lo <- m$plo
        r$pct_expected_hi <- m$phi
      }
      r
    })
    write_json_file(ct, contest_files[match(id, names(contests))])
  }

  sm <- jsonlite::read_json(summary_path, simplifyVector = FALSE)
  sm$turnout <- list(
    ballots_counted = counted_total,
    registered = sum(cty$registered),
    expected_ballots = statewide$expected_median,
    expected_lo = statewide$expected_lo,
    expected_hi = statewide$expected_hi,
    pct_expected = statewide$pct_expected
  )
  sm$contests <- map(sm$contests, \(c) {
    r <- contest_summ[[c$contest_id]]
    if (!is.null(r))
      c$reporting[c(
        "pct_expected",
        "pct_expected_lo",
        "pct_expected_hi"
      )] <- r[c("pct_expected", "pct_expected_lo", "pct_expected_hi")]
    c
  })
  write_json_file(sm, summary_path)
  invisible(model)
}

path_ext_remove_base <- function(paths) {
  basename(paths) |> str_remove("\\.json$")
}

transpose_rows <- function(df) {
  pmap(df, \(...) list(...))
}

write_json_file <- function(x, path) {
  jsonlite::write_json(
    x,
    path,
    auto_unbox = TRUE,
    null = "null",
    na = "null",
    digits = NA,
    pretty = FALSE
  )
  invisible(path)
}
