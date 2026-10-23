# Election-night "needle": a live probabilistic projection of each contest's FINAL result.
# See ARCHITECTURE.md ("Needle") for the output contract and the method summary.
#
# For contest k with a pair of candidates (a, b) and precincts j in county c:
#   counted votes are exact; remaining votes in j are drawn as
#     logit(share_a,j) = alpha + beta * x_j + eta_c + lambda + lambda_c + eps_j
#   x_j  = logit of the 2024 presidential two-party Democratic share in the 2026 precinct (centred),
#   alpha, beta  prior from polls / fundamentals, updated by counted precincts (Gaussian GLS),
#   eta_c county deviation (shrunk), eps_j precinct deviation (shrunk towards what was counted),
#   lambda, lambda_c  shift of late-counted ballots relative to early ones (not identified from the count).
# Remaining votes per county come from the expected-vote model (lognormal fitted to its 90% interval).

needle_params <- function() {
  list(
    draws = 5000,
    draws_other = 2500,
    chunk_cells = 4e6,
    rho_ballots = 0.7,
    tau_county = 0.12,
    sigma_eps = 0.18,
    sigma_eps_measure = 0.25,
    late_mean = 0,
    late_sd = 0.15,
    late_county_sd = 0.10,
    misfit_sd = 0.08,
    poll_extra_sd = 0.04,
    fundamentals_sd_house = 0.065,
    fundamentals_sd_leg = 0.08,
    env_elasticity = 0.5,
    env_cap = 0.3,
    nat_house_margin_2024 = -2.6,
    measure_alpha_sd = 0.55,
    measure_beta_sd = 0.7,
    other_prior = 0.04,
    other_k = 200,
    leg_heterogeneity = 0.2,
    leg_min_contests = 5,
    missing_baseline_extra_sd = 0.3,
    size_prior_votes = 20
  )
}

logit <- \(p) qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))

needle_stage <- function(votes, pct_expected, final) {
  case_when(
    votes <= 0 ~ "pre",
    final ~ "final",
    pct_expected < 0.05 ~ "early",
    .default = "live"
  )
}

# ---- priors ---------------------------------------------------------------------------------------------

# Shift (logit scale) from the 2024 environment to the current generic ballot, damped for Utah.
needle_env_shift <- function(national, p) {
  latest <- national$generic_ballot$latest
  if (is.null(latest)) return(0)
  now <- latest$DEM - latest$REP
  d_share <- (now - p$nat_house_margin_2024) / 200
  pmin(pmax(p$env_elasticity * d_share / 0.25, -p$env_cap), p$env_cap)
}

# Intercept alpha0 such that the weighted district share equals `target`, and the derivative d share / d alpha.
solve_alpha <- function(x, w, beta, target) {
  f <- \(a) sum(w * plogis(a + beta * x)) / sum(w) - target
  a <- uniroot(f, c(-8, 8))$root
  q <- plogis(a + beta * x)
  list(alpha = a, slope = sum(w * q * (1 - q)) / sum(w))
}

# ---- Gaussian GLS update of (alpha, beta) with a compound-symmetric county effect -------------------------

needle_gls <- function(obs, m0, V0, sigma2, tau2) {
  Lam0 <- solve(V0)
  A <- Lam0
  b <- Lam0 %*% m0
  agg <- NULL
  if (nrow(obs) > 0) {
    agg <- obs |>
      mutate(w = 1 / (sigma2 + v + extra)) |>
      summarise(
        Sw = sum(w),
        Swx = sum(w * x),
        Swxx = sum(w * x * x),
        Swy = sum(w * y),
        Swxy = sum(w * x * y),
        .by = cty
      ) |>
      mutate(k = tau2 / (1 + tau2 * Sw))
    A <- A +
      matrix(
        c(
          sum(agg$Sw - agg$k * agg$Sw^2),
          sum(agg$Swx - agg$k * agg$Sw * agg$Swx),
          sum(agg$Swx - agg$k * agg$Sw * agg$Swx),
          sum(agg$Swxx - agg$k * agg$Swx^2)
        ),
        2,
        2
      )
    b <- b +
      c(
        sum(agg$Swy - agg$k * agg$Sw * agg$Swy),
        sum(agg$Swxy - agg$k * agg$Swx * agg$Swy)
      )
  }
  cov <- solve(A)
  list(mean = as.numeric(cov %*% b), cov = cov, agg = agg)
}

# Posterior fit: two passes so the precinct-level scatter is estimated once enough precincts are in.
needle_fit_theta <- function(obs, m0, V0, sigma0, tau2, vague = FALSE) {
  s2 <- sigma0^2
  fit <- needle_gls(obs, m0, V0, s2, tau2)
  if (nrow(obs) >= 10) {
    ag <- fit$agg
    eta <- ag |>
      mutate(eta = k * (Swy - fit$mean[1] * Sw - fit$mean[2] * Swx)) |>
      select(cty, eta)
    r <- obs |>
      left_join(eta, by = "cty") |>
      mutate(res2 = (y - fit$mean[1] - fit$mean[2] * x - eta)^2 - v)
    est <- pmax(mean(r$res2), 0.05^2)
    n <- nrow(obs)
    s2 <- min(max((30 * sigma0^2 + n * est) / (30 + n), 0.08^2), 0.4^2)
    fit <- needle_gls(obs, m0, V0, s2, tau2)
  }
  fit$sigma2 <- s2
  fit
}

# ---- simulation -------------------------------------------------------------------------------------------

rmvn2 <- function(n, mean, cov) {
  cov <- (cov + t(cov)) / 2
  e <- eigen(cov, symmetric = TRUE)
  root <- e$vectors %*% diag(sqrt(pmax(e$values, 0)))
  sweep(matrix(rnorm(n * 2), n, 2) %*% t(root), 2, mean, "+")
}

needle_simulate <- function(inp, prior, p, n_draws, seed) {
  set.seed(seed)
  pr <- inp$prec
  ct <- inp$cty
  P <- nrow(pr)
  C <- nrow(ct)
  tau2 <- p$tau_county^2
  sigma0 <- if (inp$type == "measure") p$sigma_eps_measure else p$sigma_eps

  obs <- pr |>
    filter(va + vb > 0) |>
    transmute(
      cty,
      x,
      pt = (va + 0.5) / (va + vb + 1),
      y = qlogis(pt),
      v = 1 / ((va + vb + 1) * pt * (1 - pt)),
      extra = if_else(miss, p$missing_baseline_extra_sd^2, 0),
      pid
    )
  has_obs <- nrow(obs) > 0
  m0 <- c(prior$alpha, prior$beta)
  V0 <- diag(c(prior$sd_alpha_early^2, prior$sd_beta^2))
  fit <- needle_fit_theta(obs, m0, V0, sigma0, tau2)
  sigma2 <- fit$sigma2
  agg <- fit$agg

  Sw <- Swx <- Swy <- numeric(C)
  if (has_obs) {
    Sw[agg$cty] <- agg$Sw
    Swx[agg$cty] <- agg$Swx
    Swy[agg$cty] <- agg$Swy
  }
  k_c <- tau2 / (1 + tau2 * Sw)

  # per-precinct constants
  cidx <- pr$cty
  kappa <- rep(0, P)
  y_j <- rep(0, P)
  if (has_obs) {
    pos <- match(obs$pid, pr$pid)
    kappa[pos] <- sigma2 / (sigma2 + obs$v + obs$extra)
    y_j[pos] <- obs$y
  }
  counted_j <- pr$va + pr$vb + pr$vo
  wfrac <- pr$w / ave_sum(pr$w, cidx, C)
  Ind <- matrix(0, P, C)
  Ind[cbind(seq_len(P), cidx)] <- 1

  # other-candidate share of the remaining votes, shrunk from county to contest level
  C_c <- ct$C
  O_c <- as.numeric(rowsum_vec(pr$vo, cidx, C))
  o_tot <- (sum(pr$vo) + p$other_k * prior$other) / (sum(counted_j) + p$other_k)
  o_c <- (O_c + p$other_k * o_tot) / (C_c + p$other_k)
  o_j <- o_c[cidx]

  # The regression fits unweighted logits, which need not reproduce the vote-weighted totals already counted.
  # Offset each county (and, for counties with nothing counted, the vote-weighted average offset) so it does.
  delta_c <- rep(0, C)
  if (has_obs) {
    eta_hat <- k_c * (Swy - fit$mean[1] * Sw - fit$mean[2] * Swx)
    m_j <- fit$mean[1] + fit$mean[2] * pr$x + eta_hat[cidx]
    m_j <- m_j + kappa * (y_j - m_j)
    n2 <- pr$va + pr$vb
    d_c <- map_dbl(seq_len(C), \(c) {
      ix <- which(cidx == c & n2 > 0)
      if (length(ix) == 0) return(NA_real_)
      f <- \(d) sum(n2[ix] * plogis(m_j[ix] + d)) - sum(pr$va[ix])
      tryCatch(uniroot(f, c(-4, 4))$root, error = \(e) NA_real_)
    })
    w_c <- rowsum_vec(n2, cidx, C)
    ok <- !is.na(d_c)
    d_bar <- if (any(ok)) weighted.mean(d_c[ok], w_c[ok] + 1e-9) else 0
    delta_c <- if_else(ok, d_c, d_bar)
  }

  th <- rmvn2(n_draws, fit$mean, fit$cov)
  alpha <- th[, 1]
  beta <- th[, 2]
  lam <- rnorm(n_draws, p$late_mean, sqrt(p$late_sd^2 + p$misfit_sd^2))

  eta_mean <- (matrix(Swy, n_draws, C, byrow = TRUE) - outer(alpha, Sw) - outer(beta, Swx)) *
    rep(k_c, each = n_draws)
  eta <- eta_mean +
    matrix(rnorm(n_draws * C), n_draws, C) * rep(sqrt(k_c), each = n_draws)
  lamc <- matrix(rnorm(n_draws * C, 0, p$late_county_sd), n_draws, C)

  sdlog <- ct$sdlog
  kap_c <- ct$kappa
  chunk <- max(200L, as.integer(floor(p$chunk_cells / max(P, 1))))
  starts <- seq(1L, n_draws, by = chunk)
  parts <- map(starts, \(s0) {
    idx <- s0:min(s0 + chunk - 1L, n_draws)
    n <- length(idx)
    z0 <- rnorm(n)
    Z <- sqrt(p$rho_ballots) *
      z0 +
      sqrt(1 - p$rho_ballots) * matrix(rnorm(n * C), n, C)
    Tm <- exp(
      rep(log(ct$med), each = n) +
        Z * rep(sdlog, each = n)
    )
    Tm <- pmax(Tm, rep(ct$B, each = n))
    Tm[, ct$final] <- matrix(ct$B[ct$final], n, sum(ct$final), byrow = TRUE)
    Vf <- Tm * rep(kap_c, each = n)
    Rem_c <- pmax(Vf - rep(C_c, each = n), 0)

    t_j <- Vf[, cidx, drop = FALSE] * rep(wfrac, each = n)
    # a precinct's own count says how big it is: trust it in proportion to how much of it is in
    pace_j <- Vf[, cidx, drop = FALSE] / rep(pmax(C_c, 1)[cidx], each = n)
    lam_j <- rep(counted_j / (counted_j + p$size_prior_votes), each = n)
    size_j <- lam_j * pace_j * rep(counted_j, each = n) + (1 - lam_j) * t_j
    rem0 <- pmax(size_j - rep(counted_j, each = n), 0.02 * size_j)
    S0 <- pmax(rem0 %*% Ind, 1e-9)
    rem <- rem0 * (Rem_c / S0)[, cidx, drop = FALSE]

    a <- alpha[idx]
    b <- beta[idx]
    eta_j <- eta[idx, , drop = FALSE][, cidx, drop = FALSE]
    base <- a + outer(b, pr$x) + eta_j + rep(delta_c[cidx], each = n)
    eps_mean <- rep(kappa, each = n) *
      (rep(y_j, each = n) - base)
    eps_sd <- rep(sqrt(sigma2 * (1 - kappa)), each = n)
    L0 <- base +
      lam[idx] +
      lamc[idx, , drop = FALSE][, cidx, drop = FALSE] +
      eps_mean
    # second-order correction so independent precinct noise does not pull the expected vote share towards 50%
    L <- L0 + 0.5 * eps_sd^2 * (2 * plogis(L0) - 1) + eps_sd * matrix(rnorm(n * P), n, P)
    s <- plogis(L)
    keep <- 1 - rep(o_j, each = n)
    ra <- rem * keep * s
    rb <- rem * keep * (1 - s)
    ro <- rem * (1 - keep)
    tibble(
      A = sum(pr$va) + rowSums(ra),
      B = sum(pr$vb) + rowSums(rb),
      O = sum(pr$vo) + rowSums(ro)
    )
  }) |>
    list_rbind()
  list(draws = parts, theta = fit, sigma_eps = sqrt(sigma2))
}

ave_sum <- \(x, g, C) as.numeric(rowsum_vec(x, g, C))[g]
rowsum_vec <- \(x, g, C) {
  out <- numeric(C)
  s <- tapply(x, g, sum)
  out[as.integer(names(s))] <- as.numeric(s)
  out
}

q_at <- \(x, p) unname(quantile(x, p, names = FALSE))

needle_summarise <- function(draws, ids, cap = c(0.01, 0.99)) {
  tot <- draws$A + draws$B + draws$O
  m <- (draws$A - draws$B) / tot
  pa_raw <- mean(draws$A > draws$B) + 0.5 * mean(draws$A == draws$B)
  pa <- min(max(pa_raw, cap[1]), cap[2])
  q <- \(x)
    list(
      median = q_at(x, 0.5),
      lo50 = q_at(x, 0.25),
      hi50 = q_at(x, 0.75),
      lo90 = q_at(x, 0.05),
      hi90 = q_at(x, 0.95)
    )
  sh <- \(x)
    list(median = q_at(x, 0.5), lo90 = q_at(x, 0.05), hi90 = q_at(x, 0.95))
  list(
    prob = set_names(list(pa, 1 - pa), ids[1:2]),
    prob_raw = pa_raw,
    capped = pa_raw > cap[2] || pa_raw < cap[1],
    margin = q(m),
    shares = list(
      a = sh(draws$A / tot),
      b = sh(draws$B / tot),
      other = sh(draws$O / tot)
    ) |>
      set_names(c(ids[1], ids[2], "other"))
  )
}

# ---- contest assembly --------------------------------------------------------------------------------------

needle_baseline <- function() {
  read_csv(
    file.path(project_root(), "pipeline", "config", "needle_baseline_2026.csv"),
    col_types = cols(
      .default = col_double(),
      precinct_id = col_character(),
      county_fips = col_character(),
      has_baseline = col_logical()
    ),
    show_col_types = FALSE
  ) |>
    mutate(
      b = if_else(has_baseline, (dem24 + 1) / (dem24 + rep24 + 2), NA_real_),
      w = if_else(has_baseline, total24, NA_real_)
    ) |>
    select(precinct_id, b, w)
}

pick_pair <- function(cands, type) {
  if (type == "measure") {
    ids <- cands$candidate_id
    a <- intersect(c("for", "yes"), ids)[1]
    b <- intersect(c("against", "no"), ids)[1]
    return(list(ids = c(a, b), partisan = FALSE, kind = "measure"))
  }
  real <- cands |> filter(candidate_id != "write-in")
  d <- real |> filter(party == "DEM")
  r <- real |> filter(party == "REP")
  if (nrow(d) > 0 && nrow(r) > 0)
    return(list(
      ids = c(d$candidate_id[1], r$candidate_id[1]),
      partisan = TRUE,
      kind = "dr"
    ))
  if (nrow(r) > 0 && nrow(real) >= 2) {
    o <- real |> filter(party != "REP")
    return(list(
      ids = c(o$candidate_id[1], r$candidate_id[1]),
      partisan = TRUE,
      kind = "other_vs_r"
    ))
  }
  if (nrow(real) >= 2)
    return(list(
      ids = real$candidate_id[1:2],
      partisan = FALSE,
      kind = "unknown"
    ))
  NULL
}

# Everything one contest needs: precinct table, county table, prior.
needle_contest_inputs <- function(ct, sm, model, baseline, polls, env, p) {
  type <- sm$type
  cands <- map(
    sm$candidates,
    \(c)
      tibble(candidate_id = c$candidate_id, party = c$party %||% NA_character_)
  ) |>
    list_rbind()
  pair <- pick_pair(cands, type)
  if (is.null(pair) || is.na(pair$ids[1]) || is.na(pair$ids[2])) return(NULL)
  ids <- pair$ids

  cty_rows <- ct$counties |>
    map(
      \(r)
        tibble(fips = r$fips, C = r$total %||% 0, share = r$ballot_share %||% 1)
    ) |>
    list_rbind()
  mc <- model$counties |>
    map(
      \(r)
        tibble(
          fips = r$fips,
          B = r$counted,
          med = r$expected_median,
          lo = r$expected_lo,
          hi = r$expected_hi,
          source = r$source
        )
    ) |>
    list_rbind()
  cty <- cty_rows |>
    inner_join(mc, by = "fips") |>
    mutate(
      final = source == "final",
      sdlog = pmax(log(pmax(hi, 1) / pmax(lo, 1)) / (2 * 1.645), 0.002),
      med = pmax(med, B),
      kappa = if_else(C > 0 & B > 0, C / B, share * VOTE_PER_BALLOT)
    )
  if (nrow(cty) == 0) return(NULL)

  vote_of <- \(id) map_dbl(ct$precincts, \(r) as.numeric(r$votes[[id]] %||% 0))
  prec <- tibble(
    pid = map_chr(ct$precincts, "precinct_id"),
    va = vote_of(ids[1]),
    vb = vote_of(ids[2]),
    vo = map_dbl(ct$precincts, \(r) as.numeric(r$total %||% 0)) - va - vb
  ) |>
    mutate(fips = str_sub(pid, 1, 5)) |>
    left_join(baseline, by = c("pid" = "precinct_id")) |>
    mutate(cty = match(fips, cty$fips)) |>
    filter(!is.na(cty))
  if (nrow(prec) == 0) return(NULL)

  z <- logit(prec$b)
  if (pair$partisan) z <- z + env
  zbar <- weighted.mean(z, coalesce(prec$w, 0) + 1e-6, na.rm = TRUE)
  prec <- prec |>
    mutate(z = z, miss = is.na(z))
  zc <- prec |> summarise(zc = mean(z, na.rm = TRUE), .by = cty)
  prec <- prec |>
    left_join(zc, by = "cty") |>
    mutate(
      z = coalesce(z, zc, zbar),
      w0 = coalesce(w, NA_real_)
    ) |>
    mutate(
      w = coalesce(w0, median(w0, na.rm = TRUE), 1) |> pmax(1),
      w = if_else(miss & is.na(w0), pmax(median(w0, na.rm = TRUE), 1) * 0.3, w)
    )
  if (!pair$partisan) prec$z <- zbar
  zbar <- weighted.mean(prec$z, prec$w)
  prec <- prec |>
    mutate(x = z - zbar) |>
    select(pid, fips, cty, va, vb, vo, x, z, w, miss)

  prior <- needle_prior(ids, pair, type, prec, sm, polls, p)
  list(
    type = type,
    ids = ids,
    pair = pair,
    prec = prec,
    cty = cty |> select(fips, C, B, med, sdlog, final, kappa),
    prior = prior
  )
}

needle_prior <- function(ids, pair, type, prec, sm, polls, p) {
  other <- if (type == "measure") 0 else p$other_prior
  if (type == "measure") {
    return(list(
      alpha = 0,
      beta = 0,
      sd_alpha = p$measure_alpha_sd,
      sd_beta = p$measure_beta_sd,
      other = 0,
      share = 0.5,
      source = "uninformative prior around 50%"
    ))
  }
  contest_id <- sm$contest_id
  pol <- polls[[contest_id]]$latest
  m_f <- sum(prec$w * plogis(prec$x + weighted.mean(prec$z, prec$w))) /
    sum(prec$w)
  if (!pair$partisan) {
    return(list(
      alpha = qlogis(0.3),
      beta = 0.3,
      sd_alpha = 0.6,
      sd_beta = 0.4,
      other = other,
      share = 0.3,
      source = "default for a non-major-party challenger"
    ))
  }
  sd_f <- if_else(
    str_starts(contest_id, "us-house"),
    p$fundamentals_sd_house,
    p$fundamentals_sd_leg
  )
  m <- m_f
  s <- sd_f
  src <- "fundamentals"
  if (!is.null(pol)) {
    get <- \(id) keep(pol, \(r) r$candidate_id == id)[[1]]
    ra <- tryCatch(get(ids[1]), error = \(e) NULL)
    rb <- tryCatch(get(ids[2]), error = \(e) NULL)
    if (!is.null(ra) && !is.null(rb)) {
      m_p <- ra$avg / (ra$avg + rb$avg)
      band <- ((ra$hi - ra$lo) + (rb$hi - rb$lo)) / 2 / (2 * 1.96) / 100
      s_p <- sqrt(
        (band / (ra$avg + rb$avg) * 100 / 2)^2 + p$poll_extra_sd^2 + 0.03^2
      )
      s_p <- max(s_p, 0.045)
      w_p <- 1 / s_p^2
      w_f <- 1 / sd_f^2
      m <- (m_p * w_p + m_f * w_f) / (w_p + w_f)
      s <- sqrt(1 / (w_p + w_f))
      src <- "poll average blended with 2024 fundamentals"
      other <- max(0, 1 - (ra$avg + rb$avg) / 100)
      other <- max(other, 0.01)
      other <- min(other, 0.2)
    }
  }
  sol <- solve_alpha(prec$x, prec$w, 1, m)
  list(
    alpha = sol$alpha,
    beta = 1,
    sd_alpha = s / sol$slope,
    sd_beta = 0.25,
    other = other,
    share = m,
    source = src
  )
}

# Partition the prior on the final intercept into the early-ballot intercept (see header comment).
needle_prior_early <- function(prior, f, p) {
  sd_e <- sqrt(max(prior$sd_alpha^2 - (1 - f)^2 * p$late_sd^2, 0.05^2))
  prior$sd_alpha_early <- sd_e
  prior
}

# Result list for one contest from its inputs.
needle_run_contest <- function(inp, f, p, n_draws, seed, alpha_shift = NULL) {
  inp$prior <- needle_prior_early(inp$prior, f, p)
  if (!is.null(alpha_shift)) {
    inp$prior$alpha <- alpha_shift$alpha
    inp$prior$sd_alpha_early <- alpha_shift$sd
  }
  sim <- needle_simulate(inp, inp$prior, p, n_draws, seed)
  list(sim = sim, summary = needle_summarise(sim$draws, inp$ids))
}

# Stage 1 estimate of how far counted precincts sit from the fundamentals-based intercept (data only).
needle_swing_estimate <- function(inp, p) {
  pr <- inp$prec
  obs <- pr |>
    filter(va + vb > 0) |>
    transmute(
      cty,
      x,
      pt = (va + 0.5) / (va + vb + 1),
      y = qlogis(pt),
      v = 1 / ((va + vb + 1) * pt * (1 - pt)),
      extra = if_else(miss, p$missing_baseline_extra_sd^2, 0)
    )
  if (nrow(obs) < 5) return(NULL)
  m0 <- c(inp$prior$alpha, inp$prior$beta)
  V0 <- diag(c(10^2, 0.05^2))
  fit <- needle_fit_theta(obs, m0, V0, p$sigma_eps, p$tau_county^2)
  list(delta = fit$mean[1] - inp$prior$alpha, var = fit$cov[1, 1])
}

# ---- driver ---------------------------------------------------------------------------------------------------

needle_read_json <- \(path)
  if (file.exists(path)) jsonlite::read_json(path, simplifyVector = FALSE) else
    NULL

round_list <- \(x, d = 4) {
  if (is.list(x)) map(x, round_list, d = d) else if (is.numeric(x))
    round(x, d) else x
}

run_needle <- function(
  dir,
  election_id,
  now = Sys.time(),
  seed = 20261103,
  history = TRUE,
  params = needle_params()
) {
  t0 <- Sys.time()
  p <- params
  summary <- needle_read_json(file.path(dir, "summary.json"))
  model <- needle_read_json(file.path(dir, "model.json"))
  if (is.null(summary) || is.null(model)) {
    message("[needle] summary/model missing; skipped")
    return(invisible(NULL))
  }
  baseline <- needle_baseline()
  polls <- needle_read_json(data_dir("polls", "averages.json"))$contests %||%
    list()
  national <- needle_read_json(data_dir("polls", "national.json"))
  env <- needle_env_shift(national, p)
  old <- needle_read_json(file.path(dir, "needle.json"))
  now_iso <- format(as.POSIXct(now, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")
  final_all <- identical(summary$status, "final")

  items <- keep(
    summary$contests,
    \(c)
      c$type %in%
        c("candidate", "measure") &&
        (str_detect(
          c$contest_id,
          "^(us-house|amendment|state-house|state-senate)"
        ))
  )
  inputs <- map(items, \(sm) {
    ct <- needle_read_json(file.path(
      dir,
      "contests",
      str_c(sm$contest_id, ".json")
    ))
    if (is.null(ct) || length(ct$precincts) == 0) return(NULL)
    needle_contest_inputs(ct, sm, model, baseline, polls, env, p)
  }) |>
    set_names(map_chr(items, "contest_id"))
  keep_ids <- names(compact(inputs))
  inputs <- compact(inputs)
  items <- items[match(keep_ids, map_chr(items, "contest_id"))] |>
    set_names(keep_ids)
  fs <- map_dbl(items, \(sm) sm$reporting$pct_expected %||% 0)

  # statewide swing shared by the legislative contests (leave-one-out so a contest never informs its own prior)
  is_leg <- str_detect(keep_ids, "^state-")
  swing <- map(inputs[is_leg], \(i) {
    i$prior <- needle_prior_early(i$prior, 0.5, p)
    if (sum(i$prec$va + i$prec$vb) < 200) return(NULL)
    needle_swing_estimate(i, p)
  })
  swing_tbl <- swing |>
    compact() |>
    imap(\(s, id) tibble(id = id, delta = s$delta, var = s$var)) |>
    list_rbind()

  results <- imap(inputs, \(inp, id) {
    shift <- NULL
    if (str_detect(id, "^state-") && nrow(swing_tbl) > 0) {
      oth <- swing_tbl |> filter(id != !!id)
      if (nrow(oth) >= p$leg_min_contests) {
        w <- 1 / (oth$var + p$leg_heterogeneity^2)
        pooled <- sum(w * oth$delta) / sum(w)
        pooled_var <- 1 / sum(w)
        pr0 <- needle_prior_early(inp$prior, fs[[id]], p)
        shift <- list(
          alpha = pr0$alpha + pooled,
          sd = min(sqrt(pooled_var + p$leg_heterogeneity^2), pr0$sd_alpha_early)
        )
      }
    }
    needle_run_contest(
      inp,
      fs[[id]],
      p,
      if_else(isTRUE(items[[id]]$featured), as.integer(p$draws), as.integer(p$draws_other)),
      seed + sum(utf8ToInt(id)),
      shift
    )
  })

  finals_ok <- final_all ||
    (all(map_lgl(model$counties, \(c) c$source == "final")))
  contests <- imap(results, \(r, id) {
    sm <- items[[id]]
    inp <- inputs[[id]]
    s <- r$summary
    votes <- sm$total_votes %||% 0
    f <- fs[[id]]
    stage <- needle_stage(votes, f, finals_ok && f >= 0.99)
    prev <- old$contests[[id]]
    hist <- prev$history %||% list()
    featured <- isTRUE(sm$featured)
    if (history && featured && stage != "pre") {
      last <- if (length(hist) > 0) hist[[length(hist)]] else NULL
      if (is.null(last) || !identical(last$t, now_iso)) {
        pt <- list(
          t = now_iso,
          pct_expected = f,
          prob = list(),
          margin_median = s$margin$median,
          margin_lo90 = s$margin$lo90,
          margin_hi90 = s$margin$hi90
        )
        pt$prob[[inp$ids[1]]] <- s$prob[[inp$ids[1]]]
        hist <- c(hist, list(pt))
      }
    }
    out <- list(
      stage = stage,
      pct_expected = f,
      pair = as.list(inp$ids),
      prob = s$prob,
      capped = s$capped,
      margin = s$margin,
      shares = s$shares,
      prior = list(share_a = inp$prior$share, source = inp$prior$source),
      scatter_sd = r$sim$sigma_eps
    )
    if (featured) out$history <- if (stage == "pre") list() else hist
    round_list(out)
  })

  needle <- list(
    updated_at = now_iso,
    draws = p$draws,
    draws_other = p$draws_other,
    method = str_c(
      "Monte Carlo projection of the final result. Counted votes are exact; remaining votes per county come from the expected-vote model. ",
      "Remaining ballots' lean = 2024 presidential precinct baseline plus a statewide-in-district swing (prior: poll average blended with ",
      "fundamentals; amendments: wide prior around 50%) updated by counted precincts, county deviations, and an uncertain late-ballot shift ",
      "(sd ",
      p$late_sd,
      " logit). Probabilities are capped at 1% / 99%."
    ),
    environment_shift_logit = round(env, 4),
    contests = contests
  )
  write_json_file(needle, file.path(dir, "needle.json"))
  message(sprintf(
    "[needle] %d contests in %.1fs",
    length(contests),
    as.numeric(difftime(Sys.time(), t0, units = "secs"))
  ))
  invisible(needle)
}
