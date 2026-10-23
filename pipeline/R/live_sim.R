# Election-night simulator: invents plausible precinct results for every 2026 contest from 2024 partisanship
# and the 2026 House polls, then reveals them progressively. Used to demo the front end; never touches live data.

lean_2024 <- function() {
  cache <- raw_dir("live", "lean2024.rds")
  if (file.exists(cache)) return(readRDS(cache))
  path <- raw_dir("live", "export-general11052024.json")
  if (!file.exists(path)) {
    ev_request(
      "https://electionresults.utah.gov/cdn/results/Utah/export-general11052024.json",
      180
    ) |>
      req_perform(path = path)
  }
  j <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  out <- j$localResults |>
    map(\(lr) {
      fips <- county_fips_from_name(lr$name)
      b <- keep(
        lr$ballotItems,
        \(b) str_detect(b$name, regex("president", ignore_case = TRUE))
      )[[1]]
      map(b$ballotOptions, \(o) {
        pr <- o$precinctResults %||% list()
        tibble(
          fips = fips,
          precinct_name = map_chr(pr, \(p) p$name),
          party = party_from_text(o$politicalParty),
          votes = map_dbl(pr, \(p) as_int0(p$voteCount))
        )
      }) |>
        list_rbind()
    }) |>
    list_rbind() |>
    summarise(
      dem = sum(votes[party %in% "DEM"]),
      rep = sum(votes[party %in% "REP"]),
      total = sum(votes),
      .by = c(fips, precinct_name)
    ) |>
    mutate(precinct_id = precinct_key(fips, precinct_name))
  saveRDS(out, cache)
  out
}

house_poll_targets <- function() {
  read_csv(
    file.path(project_root(), "polls", "house.csv"),
    show_col_types = FALSE,
    progress = FALSE
  ) |>
    filter(state == "UT", stage == "general", party != "NONE") |>
    mutate(pct = pct / sum(pct), .by = c(poll_id, seat_number)) |>
    summarise(share = mean(pct), .by = c(seat_number, party, candidate_name)) |>
    mutate(
      candidate_id = slugify(candidate_name),
      contest_id = str_c("us-house-", seat_number)
    )
}

# Sequential conditional binomials: vectorized multinomial over precincts.
multinomial_rows <- function(n, probs) {
  k <- ncol(probs)
  out <- matrix(0, nrow(probs), k)
  left <- n
  remaining <- rep(1, nrow(probs))
  for (j in seq_len(k - 1)) {
    pj <- pmin(pmax(probs[, j] / pmax(remaining, 1e-12), 0), 1)
    out[, j] <- rbinom(nrow(probs), left, pj)
    left <- left - out[, j]
    remaining <- remaining - probs[, j]
  }
  out[, k] <- left
  out
}

sim_truth <- function(parsed, candidates, seed, delta_true = 0.15) {
  set.seed(seed)
  base <- read_csv(
    file.path(project_root(), "pipeline", "config", "county_baselines.csv"),
    col_types = cols(fips = col_character()),
    show_col_types = FALSE
  )
  lean <- lean_2024()
  opts <- attach_candidates(parsed$options, parsed$classes, candidates) |>
    distinct(
      contest_id,
      ballot_name,
      candidate_id,
      party,
      option_order,
      measure,
      kind
    )
  prec <- parsed$precincts
  if (is.null(prec) || nrow(prec) == 0)
    stop("Simulation needs precinct lists from the export.")
  universe <- prec |>
    distinct(fips, precinct_name) |>
    mutate(precinct_id = precinct_key(fips, precinct_name)) |>
    left_join(select(lean, precinct_id, dem, rep, total), by = "precinct_id")
  pool <- lean |> filter(dem + rep > 0)
  universe <- universe |>
    mutate(row = row_number()) |>
    group_split(fips) |>
    map(\(g) {
      miss <- is.na(g$dem) | (g$dem + g$rep) == 0
      src <- pool |> filter(fips == g$fips[1])
      if (any(miss) && nrow(src) > 0) {
        draw <- src[sample.int(nrow(src), sum(miss), replace = TRUE), ]
        g$dem[miss] <- draw$dem
        g$rep[miss] <- draw$rep
        g$total[miss] <- draw$total
      }
      g
    }) |>
    list_rbind() |>
    mutate(
      dem = coalesce(dem, 0),
      rep = coalesce(rep, 0),
      total = coalesce(total, 100),
      lean = qlogis(pmin(pmax((dem + 0.5) / (dem + rep + 1), 0.03), 0.97)),
      size = pmax(total, 20)
    )
  county_true <- base |>
    mutate(
      T_true = registered_2026 *
        plogis(qlogis(turnout_2022) + delta_true + rnorm(n(), 0, 0.1))
    ) |>
    select(fips, T_true)
  universe <- universe |>
    left_join(county_true, by = "fips") |>
    mutate(ballots = T_true * size / sum(size), .by = fips)

  polls <- house_poll_targets()
  contests <- parsed$classes
  final <- map(contests$contest_id, \(cid) {
    kind <- contests$kind[contests$contest_id == cid]
    ps <- prec |>
      filter(contest_id == cid) |>
      distinct(fips, precinct_name) |>
      left_join(universe, by = c("fips", "precinct_name"))
    o <- opts |> filter(contest_id == cid) |> arrange(option_order)
    if (nrow(ps) == 0 || nrow(o) == 0) return(NULL)
    d_prob <- plogis(ps$lean + rnorm(nrow(ps), 0, 0.12))
    n_vote <- round(ps$ballots * VOTE_PER_BALLOT)
    P <- if (kind == "amendment") {
      pfor <- if (cid == "amendment-a") 0.62 - 0.12 * (d_prob - 0.4) else
        0.45 - 0.35 * (d_prob - 0.4)
      pfor <- pmin(pmax(pfor + rnorm(nrow(ps), 0, 0.03), 0.05), 0.95)
      cbind(pfor, 1 - pfor)[,
        order(match(str_to_lower(o$ballot_name), c("for", "against"))),
        drop = FALSE
      ]
    } else if (kind == "retention") {
      judge <- rnorm(1, 0.78, 0.05)
      py <- pmin(
        pmax(judge - 0.08 * (d_prob - 0.4) + rnorm(nrow(ps), 0, 0.02), 0.3),
        0.97
      )
      cbind(py, 1 - py)[,
        order(match(str_to_lower(o$ballot_name), c("yes", "no"))),
        drop = FALSE
      ]
    } else {
      sim_candidate_probs(cid, kind, o, ps, d_prob, polls)
    }
    votes <- multinomial_rows(n_vote, P)
    tibble(
      contest_id = cid,
      fips = rep(ps$fips, ncol(P)),
      precinct_name = rep(ps$precinct_name, ncol(P)),
      ballot_name = rep(o$ballot_name, each = nrow(ps)),
      final = as.vector(votes)
    )
  }) |>
    list_rbind()
  list(final = final, universe = universe, county_true = county_true)
}

sim_candidate_probs <- function(cid, kind, o, ps, d_prob, polls) {
  n <- nrow(ps)
  k <- nrow(o)
  is_wi <- o$candidate_id == "write-in"
  is_d <- o$party %in% "DEM"
  is_r <- o$party %in% "REP"
  third <- !is_d & !is_r & !is_wi
  poll <- filter(polls, contest_id == cid)
  third_share <- if_else(third, 0.025, 0)
  if (nrow(poll) > 0) {
    matched <- poll$share[match(o$candidate_id, poll$candidate_id)]
    third_share <- if_else(third, coalesce(matched, 0.01), 0)
  }
  if (sum(third_share) > 0.12) third_share <- third_share * 0.12 / sum(third_share)
  tp <- matrix(third_share, n, k, byrow = TRUE) *
    exp(matrix(rnorm(n * k, 0, 0.25), n, k))
  tp[, !third] <- 0
  tp[, is_wi] <- 0.002
  rest <- pmax(1 - rowSums(tp), 0.05)
  target <- if (
    nrow(poll) > 0 && any(poll$party == "DEM") && any(poll$party == "REP")
  ) {
    d <- poll$share[poll$party == "DEM"][1]
    r <- poll$share[poll$party == "REP"][1]
    d / (d + r)
  } else {
    NA_real_
  }
  shift <- if (!is.na(target)) {
    w <- ps$ballots
    f <- \(s) weighted.mean(plogis(qlogis(d_prob) + s), w) - target
    uniroot(f, c(-6, 6))$root
  } else {
    0
  }
  dp <- plogis(qlogis(d_prob) + shift)
  P <- tp
  if (any(is_d) && any(is_r)) {
    P[, is_d] <- rest * dp
    P[, is_r] <- rest * (1 - dp)
  } else if (any(is_d)) {
    P[, is_d] <- rest
  } else if (any(is_r)) {
    P[, is_r] <- rest
  } else {
    P[, which(!is_wi)[1]] <- P[, which(!is_wi)[1]] + rest
  }
  P / rowSums(P)
}

# Reveals the simulated truth at a given pace. `phi` is the target statewide counted fraction.
sim_reveal <- function(
  truth,
  parsed,
  phi,
  seed,
  county_pace,
  county_start,
  precinct_z
) {
  u <- truth$universe
  county <- tibble(
    fips = names(county_pace),
    a = county_pace,
    start = county_start[names(county_pace)]
  )
  f_c <- county |>
    mutate(f = if_else(phi >= start, 1 - (1 - phi)^a, 0)) |>
    select(fips, f)
  r <- u |>
    left_join(f_c, by = "fips") |>
    mutate(
      z = precinct_z[match(precinct_id, names(precinct_z))],
      r = 1 - (1 - f)^exp(z)
    ) |>
    select(fips, precinct_name, r)
  prec <- truth$final |>
    left_join(r, by = c("fips", "precinct_name")) |>
    mutate(votes = round(final * coalesce(r, 0))) |>
    mutate(status = if_else(votes > 0, "Reporting", "Not Reported")) |>
    select(fips, contest_id, ballot_name, precinct_name, votes, status)
  cty_votes <- prec |>
    summarise(votes = sum(votes), .by = c(fips, contest_id, ballot_name))
  options <- parsed$options |>
    select(-votes) |>
    left_join(cty_votes, by = c("fips", "contest_id", "ballot_name")) |>
    mutate(votes = coalesce(votes, 0))
  list(
    classes = parsed$classes,
    options = options,
    precincts = prec,
    created_at = NA_character_
  )
}

sim_hours_for <- function(phi, p = model_defaults()) {
  frac <- (p$m_inf - pmin(phi, p$m_inf - 0.005)) / (p$m_inf - p$m0)
  pmax(-p$tau_hours * log(pmin(frac, 1)), 0.25) + 0.25
}

run_simulation <- function(
  phis,
  hours = NULL,
  seed = 1,
  out_dir = data_dir("results", "2026-sim", "summary.json") |> dirname(),
  parsed = NULL
) {
  cfg <- live_config()
  candidates <- read_candidates()
  parsed <- parsed %||%
    parse_export(jsonlite::fromJSON(
      ev_download_export(dest = raw_dir("live", "export-latest.json")),
      simplifyVector = FALSE
    ))
  message("[sim] building simulated truth (seed ", seed, ")")
  truth <- sim_truth(parsed, candidates, seed)
  set.seed(seed + 1)
  fips <- sort(unique(truth$universe$fips))
  county_pace <- set_names(exp(rnorm(length(fips), 0, 0.3)), fips)
  county_start <- set_names(rbeta(length(fips), 1, 3) * 0.6, fips)
  precinct_z <- set_names(
    rnorm(nrow(truth$universe), 0, 0.3),
    truth$universe$precinct_id
  )
  unlink(out_dir, recursive = TRUE)
  close_time <- POLLS_CLOSE_UTC
  tl <- NULL
  for (phi in phis) {
    h <- if (is.null(hours)) sim_hours_for(phi) else hours[match(phi, phis)]
    now <- close_time + h * 3600
    t_iso <- format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    revealed <- sim_reveal(
      truth,
      parsed,
      phi,
      seed,
      county_pace,
      county_start,
      precinct_z
    )
    res <- build_results(
      revealed,
      candidates,
      tibble(
        contest_id = character(),
        candidate_id = character(),
        called_at = character(),
        by = character()
      ),
      election_id = "2026-sim",
      status = "live",
      as_of = t_iso,
      updated_at = t_iso,
      cfg = cfg
    )
    tl <- update_timeline(file.path(out_dir, "timeline.json"), res, cfg, t_iso)
    staging <- file.path(tempdir(), "sim")
    unlink(staging, recursive = TRUE)
    write_results(res, staging, tl)
    if (file.exists(file.path(out_dir, "model.json")))
      file.copy(
        file.path(out_dir, "model.json"),
        file.path(staging, "model.json"),
        overwrite = TRUE
      )
    run_expected_vote_model(staging, "2026-sim", now = now, seed = seed)
    publish_dir(staging, out_dir)
    mdl <- jsonlite::read_json(file.path(out_dir, "model.json"))
    message(sprintf(
      "[sim] phi=%.2f t=+%.1fh counted=%s expected=%s [%s, %s] truth=%s",
      phi,
      h,
      format(mdl$statewide$counted, big.mark = ","),
      format(mdl$statewide$expected_median, big.mark = ","),
      format(mdl$statewide$expected_lo, big.mark = ","),
      format(mdl$statewide$expected_hi, big.mark = ","),
      format(round(sum(truth$county_true$T_true)), big.mark = ",")
    ))
  }
  invisible(out_dir)
}
