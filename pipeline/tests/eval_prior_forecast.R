#!/usr/bin/env Rscript
# Out-of-sample evaluation of the needle's PRE-ELECTION prior on past Utah cycles.
#   UTEL_RAW_DIR=<shared raw cache> Rscript pipeline/tests/eval_prior_forecast.R
#
# For each past contest the prior is rebuilt from information available before that election only:
#   fundamentals = previous presidential two-party result re-aggregated to that cycle's districts (same precinct
#   formula as needle_prior), plus the damped generic-ballot shift (needle_env_shift). No historical Utah polls
#   exist in the repo, so the poll-blend half of the House prior cannot be back-tested.
# The prior's spread is reproduced with a closed form calibrated against the production pre-stage output in the
# 2026 needle.json (RMSE 0.009 on margin quantiles); see `prior_dist()`.
#
# Outputs (pipeline/tests/): eval_prior_contests.csv, eval_prior_summary.csv, eval_prior_calibration.csv
suppressPackageStartupMessages(library(sf))
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
for (f in c("history_ut_export", "legis_pres24", "model_needle")) {
  source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))
}
p <- needle_params()
out_dir <- file.path(project_root(), "pipeline", "tests")

# ---- environment: national House margin (D - R, points) of each baseline year, and final generic-ballot averages ---
# Approximate values (election results from memory of the official national House vote; final generic-ballot averages
# from memory of FiveThirtyEight/RCP). The shift is damped and capped at 0.3 logit, so a few points of error here move
# a district by well under 1 pt of share; the evaluation also reports the no-environment variant.
env_tbl <- tribble(
  ~year , ~base_year , ~nat_margin_base , ~generic_now ,
   2018 ,       2016 , -1.1             ,  7.3         ,
   2020 ,       2016 , -1.1             ,  6.8         ,
   2022 ,       2020 ,  3.1             , -1.2         ,
   2024 ,       2020 ,  3.1             ,  0.0
) |>
  mutate(
    env = pmin(
      pmax(
        p$env_elasticity * ((generic_now - nat_margin_base) / 200) / 0.25,
        -p$env_cap
      ),
      p$env_cap
    )
  )

# ---- spread of the prior ----------------------------------------------------------------------------------------
# Production prior: logit(share) ~ N(logit(m), (sd / slope)^2 + extra^2) with slope ~ 1.02 m (1 - m); the extra term
# is the late-ballot misfit and county noise that needle_simulate adds on top. Fit to the 2026 pre-stage needle.json.
prior_sd_logit <- \(m, sd_nom) sqrt((sd_nom / (1.02 * m * (1 - m)))^2 + 0.184^2)
margin_q <- \(m, sd_nom, q, other = p$other_prior) {
  (2 * plogis(qlogis(m) + qnorm(q) * prior_sd_logit(m, sd_nom)) - 1) *
    (1 - other)
}
win_prob <- \(m, sd_nom, cap = c(0.01, 0.99)) {
  pmin(pmax(pnorm(qlogis(m) / prior_sd_logit(m, sd_nom)), cap[1]), cap[2])
}

# ---- weighted-unit baselines ------------------------------------------------------------------------------------
state <- readRDS(raw_dir("geo", "build_geo_state.rds"))
blocks <- state$blocks |>
  select(geoid20, county_fips, vap, cd2012, cd2022, unit2016, unit2020)
leg_blocks <- legis_block_districts()

vest_pres <- \(yr) {
  v <- readRDS(raw_dir("geo", str_c("vest_", yr, ".rds"))) |>
    sf::st_drop_geometry()
  d <- v |> select(unit_id, matches("^G\\d\\dPRE[RD]"))
  tibble(
    unit = d$unit_id,
    rep = d |> select(matches("^G\\d\\dPRER")) |> pull(1),
    dem = d |> select(matches("^G\\d\\dPRED")) |> pull(1)
  )
}
pres16 <- vest_pres(2016)
pres20 <- vest_pres(2020)

# units of (plan district, precinct) with VAP-share weights
units_from_blocks <- function(plan, unit_col, pres) {
  plan |>
    filter(!is.na(district)) |>
    summarise(vap = sum(vap), .by = c(district, unit)) |>
    mutate(share = vap / sum(vap) |> pmax(1e-9), .by = unit) |>
    inner_join(pres, by = "unit") |>
    transmute(district, dem = dem * share, rep = rep * share)
}

cd_units <- \(plan_col, unit_col, pres) {
  blocks |>
    transmute(district = .data[[plan_col]], unit = .data[[unit_col]], vap) |>
    units_from_blocks(unit_col, pres)
}
leg_units <- \(chamber, unit_col, pres) {
  leg_blocks |>
    filter(chamber == !!chamber) |>
    inner_join(
      blocks |> select(geoid20, unit = all_of(unit_col)),
      by = "geoid20"
    ) |>
    units_from_blocks(unit_col, pres)
}

# same formula as needle_prior(): vote-weighted mean of the precinct two-party share, shifted by `env` on the logit scale
fundamentals <- \(units, env) {
  units |>
    mutate(b = (dem + 1) / (dem + rep + 2), w = dem + rep) |>
    summarise(
      m_env = sum(w * plogis(qlogis(b) + env)) / sum(w),
      m_raw = sum(w * b) / sum(w),
      pres_votes = sum(w),
      .by = district
    )
}

# ---- 2018 / 2020 legislature: previous-presidential baseline on the OLD maps ---------------------------------
# No old-map polygons are on disk, but the 2016 OpenElections precinct file lists each precinct under its 2016 House
# and Senate district (the map was constant 2012-2021) next to its presidential votes.
oe <- \(file) {
  read_csv(
    raw_dir("openelections", file),
    show_col_types = FALSE,
    col_types = cols(.default = col_character())
  )
}
oe16 <- oe("20161108__ut__general__precinct.csv") |>
  mutate(votes = suppressWarnings(as.integer(votes)))
pres_oe16 <- oe16 |>
  filter(office == "President") |>
  summarise(
    dem = sum(
      votes[str_detect(candidate, regex("clinton", ignore_case = TRUE))],
      na.rm = TRUE
    ),
    rep = sum(
      votes[str_detect(candidate, regex("trump", ignore_case = TRUE))],
      na.rm = TRUE
    ),
    .by = c(county, precinct)
  )
# `file` supplies the precinct -> district link (the 2016 file for seats up in 2016; the 2018 file for 2018 Senate seats,
# which were not on the 2016 ballot); presidential votes are matched by county + precinct name.
link16 <- \(chamber, file = "20161108__ut__general__precinct.csv") {
  oe(file) |>
    mutate(votes = suppressWarnings(as.integer(votes))) |>
    filter(str_detect(office, regex(str_c("state ", chamber), ignore_case = TRUE)), !is.na(district)) |>
    summarise(lv = sum(votes, na.rm = TRUE), .by = c(county, precinct, district)) |>
    mutate(district = as.integer(district), share = lv / sum(lv), .by = c(county, precinct)) |>
    filter(!is.na(share)) |>
    inner_join(pres_oe16, by = c("county", "precinct")) |>
    transmute(district, dem = dem * share, rep = rep * share)
}

# ---- actual results ---------------------------------------------------------------------------------------------
party_group <- \(x) {
  case_when(
    str_detect(str_to_lower(coalesce(x, "")), "^(dem)") ~ "D",
    str_detect(str_to_lower(coalesce(x, "")), "^(rep)") ~ "R",
    .default = "O"
  )
}

# long table: year, chamber, district, candidate, party group, votes
house_actual <- \(yr) {
  s <- read_json(
    data_dir("results", str_c(yr, "-general"), "summary.json"),
    simplifyVector = FALSE
  )
  s$contests |>
    keep(\(c) str_detect(c$contest_id, "^us-house")) |>
    map(\(c) {
      tibble(
        year = yr,
        chamber = "us-house",
        district = as.integer(str_extract(c$contest_id, "\\d+")),
        candidate = map_chr(c$candidates, "name"),
        grp = party_group(map_chr(c$candidates, \(x) {
          x$party %||% NA_character_
        })),
        votes = map_dbl(c$candidates, "votes")
      )
    }) |>
    list_rbind()
}

oe_leg_actual <- \(file, yr) {
  oe(file) |>
    mutate(votes = suppressWarnings(as.integer(votes))) |>
    filter(
      str_detect(office, regex("state (house|senate)", ignore_case = TRUE)),
      !is.na(district),
      !is.na(votes)
    ) |>
    transmute(
      year = yr,
      chamber = if_else(
        str_detect(str_to_lower(office), "senate"),
        "state-senate",
        "state-house"
      ),
      district = suppressWarnings(as.integer(district)),
      candidate = str_squish(candidate),
      grp = party_group(party),
      votes
    ) |>
    filter(
      !is.na(district),
      !str_detect(candidate, regex("write", ignore_case = TRUE))
    ) |>
    summarise(
      votes = sum(votes),
      .by = c(year, chamber, district, candidate, grp)
    )
}

medsl22 <- read_tsv(
  raw_dir("medsl", "2022-ut-precinct-general.tab"),
  col_types = cols(.default = col_character()),
  quote = "\"",
  progress = FALSE
) |>
  filter(
    mode == "TOTAL",
    office %in% c("STATE HOUSE", "STATE SENATE"),
    writein != "TRUE"
  ) |>
  transmute(
    year = 2022,
    chamber = if_else(office == "STATE HOUSE", "state-house", "state-senate"),
    district = suppressWarnings(as.integer(district)),
    candidate = str_squish(candidate),
    grp = party_group(party_simplified),
    votes = suppressWarnings(as.integer(votes))
  ) |>
  filter(!is.na(district), !is.na(votes)) |>
  summarise(
    votes = sum(votes),
    .by = c(year, chamber, district, candidate, grp)
  )

tabs24 <- ut_export_contest_tables(raw_dir(
  "results",
  "export-general11052024.json"
))
leg24 <- tabs24$meta |>
  filter(str_detect(name, "^State (House|Senate) \\d+")) |>
  inner_join(tabs24$state, by = "item_id") |>
  transmute(
    year = 2024,
    chamber = if_else(str_detect(name, "House"), "state-house", "state-senate"),
    district = as.integer(str_extract(name, "(?<=(House|Senate) )\\d+")),
    candidate = str_squish(option),
    grp = party_group(party),
    votes = as.numeric(state_votes)
  ) |>
  filter(!str_detect(candidate, regex("write", ignore_case = TRUE)))

actual_long <- bind_rows(
  map(c(2016, 2018, 2020, 2022, 2024), house_actual) |> list_rbind(),
  oe_leg_actual("20161108__ut__general__precinct.csv", 2016),
  oe_leg_actual("20181106__ut__general__precinct.csv", 2018),
  oe_leg_actual("20201103__ut__general__precinct.csv", 2020),
  medsl22,
  leg24
)

# one row per contest. D = the Democrat; if there is none, the strongest non-Republican stands in as the production
# pick_pair() does ("other_vs_r").
contest_tbl <- actual_long |>
  filter(votes > 0 | grp != "O") |>
  summarise(
    total = sum(votes),
    d = sum(votes[grp == "D"]),
    r = sum(votes[grp == "R"]),
    o_top = max(c(0, votes[grp == "O"])),
    o_all = sum(votes[grp == "O"]),
    n_cand = n(),
    has_d = any(grp == "D"),
    has_r = any(grp == "R"),
    .by = c(year, chamber, district)
  ) |>
  mutate(
    kind = case_when(
      has_d & has_r ~ "d_vs_r",
      has_r & !has_d & o_top > 0 ~ "other_vs_r",
      .default = "unopposed_or_other"
    ),
    a = if_else(kind == "other_vs_r", o_top, d),
    other_share = (total - a - r) / total
  ) |>
  filter(kind %in% c("d_vs_r", "other_vs_r"), a + r > 0) |>
  mutate(
    actual_two_party = a / (a + r),
    actual_margin = (a - r) / total
  )

# ---- incumbency: a candidate who won the same chamber's previous cycle(s) and is on the ballot again -----------------
# Name key = last name + first initial (suffixes dropped). House seats: winners two years earlier; Senate: two or four.
name_key <- \(x) {
  s <- x |>
    str_to_lower() |>
    str_remove_all("\\b(jr|sr|ii|iii|iv)\\b") |>
    str_replace_all("[^a-z ]", " ") |>
    str_squish()
  str_c(word(s, -1), "_", str_sub(word(s, 1), 1, 1))
}
cands <- actual_long |>
  filter(chamber != "us-house" | TRUE) |>
  mutate(key = name_key(candidate))
winners <- cands |>
  slice_max(votes, n = 1, by = c(year, chamber, district), with_ties = FALSE) |>
  select(year, chamber, key)
inc_tbl <- cands |>
  mutate(prev_years = map2(chamber, year, \(ch, y) if (ch == "state-senate") c(y - 2, y - 4) else y - 2)) |>
  mutate(
    is_inc = pmap_lgl(list(chamber, key, prev_years), \(ch, k, py) any(winners$chamber == ch & winners$key == k & winners$year %in% py))
  ) |>
  filter(is_inc, votes > 0) |>
  summarise(inc = str_c(sort(unique(grp)), collapse = ""), .by = c(year, chamber, district))

# ---- baselines per (year, chamber) ------------------------------------------------------------------------------
env_of <- \(yr, use_env) if (use_env) env_tbl$env[env_tbl$year == yr] else 0

baseline_units <- list(
  `2018|us-house` = cd_units("cd2012", "unit2016", pres16),
  `2020|us-house` = cd_units("cd2012", "unit2016", pres16),
  `2022|us-house` = cd_units("cd2022", "unit2020", pres20),
  `2024|us-house` = cd_units("cd2022", "unit2020", pres20),
  `2018|state-house` = link16("house"),
  `2020|state-house` = link16("house"),
  `2018|state-senate` = link16("senate", "20181106__ut__general__precinct.csv"),
  `2020|state-senate` = link16("senate"),
  `2022|state-house` = leg_units("house", "unit2020", pres20),
  `2024|state-house` = leg_units("house", "unit2020", pres20),
  `2022|state-senate` = leg_units("senate", "unit2020", pres20),
  `2024|state-senate` = leg_units("senate", "unit2020", pres20)
)

prior_tbl <- imap(baseline_units, \(u, key) {
  parts <- str_split_1(key, "\\|")
  yr <- as.numeric(parts[1])
  fundamentals(u, env_of(yr, TRUE)) |>
    left_join(
      fundamentals(u, 0) |> select(district, m_noenv = m_env),
      by = "district"
    ) |>
    mutate(year = yr, chamber = parts[2])
}) |>
  list_rbind()

# ---- previous same-district result (naive baseline) ---------------------------------------------------------------
prev_map <- tribble(
  ~chamber       , ~year , ~prev_year ,
  "us-house"     ,  2018 ,       2016 ,
  "us-house"     ,  2020 ,       2018 ,
  "us-house"     ,  2024 ,       2022 ,
  "state-house"  ,  2018 ,       2016 ,
  "state-house"  ,  2020 ,       2018 ,
  "state-house"  ,  2024 ,       2022 ,
  "state-senate" ,  2020 ,       2016
)
prev_tbl <- contest_tbl |>
  filter(kind == "d_vs_r") |>
  select(
    chamber,
    prev_year = year,
    district,
    prev_two_party = actual_two_party
  ) |>
  inner_join(prev_map, by = c("chamber", "prev_year")) |>
  select(chamber, year, district, prev_two_party)

# ---- assemble --------------------------------------------------------------------------------------------------------
sd_nom <- \(chamber) {
  if_else(chamber == "us-house", p$fundamentals_sd_house, p$fundamentals_sd_leg)
}
contests <- contest_tbl |>
  filter(year >= 2018) |>
  inner_join(prior_tbl, by = c("year", "chamber", "district")) |>
  left_join(prev_tbl, by = c("chamber", "year", "district")) |>
  left_join(inc_tbl, by = c("year", "chamber", "district")) |>
  mutate(inc = case_when(chamber == "state-senate" & year == 2018 ~ "unknown", .default = coalesce(inc, "none"))) |>
  mutate(
    sd_nom = sd_nom(chamber),
    prob_a = win_prob(m_env, sd_nom),
    prob_a_noenv = win_prob(m_noenv, sd_nom),
    pred_margin = margin_q(m_env, sd_nom, 0.5),
    lo50 = margin_q(m_env, sd_nom, 0.25),
    hi50 = margin_q(m_env, sd_nom, 0.75),
    lo90 = margin_q(m_env, sd_nom, 0.05),
    hi90 = margin_q(m_env, sd_nom, 0.95),
    a_wins = as.numeric(actual_margin > 0),
    err_margin = actual_margin - pred_margin,
    err_share = actual_two_party - m_env,
    err_share_noenv = actual_two_party - m_noenv,
    cover50 = actual_margin >= lo50 & actual_margin <= hi50,
    cover90 = actual_margin >= lo90 & actual_margin <= hi90,
    favourite_wrong = (m_env > 0.5) != (actual_two_party > 0.5),
    prev_wrong = (prev_two_party > 0.5) != (actual_two_party > 0.5)
  ) |>
  arrange(year, chamber, district) |>
  select(-has_d, -has_r, -n_cand)

write_csv(
  contests |> mutate(across(where(is.double), \(x) round(x, 5))),
  file.path(out_dir, "eval_prior_contests.csv")
)

# ---- metrics -------------------------------------------------------------------------------------------------------------
brier <- \(p, y) mean((p - y)^2)
logloss <- \(p, y) -mean(y * log(p) + (1 - y) * log(1 - p))
summarise_group <- \(d) {
  d |>
    summarise(
      n = n(),
      mae_margin = mean(abs(err_margin)),
      bias_margin = mean(err_margin),
      mae_share = mean(abs(err_share)),
      mae_share_noenv = mean(abs(err_share_noenv)),
      mae_share_prev = mean(
        abs(actual_two_party - prev_two_party),
        na.rm = TRUE
      ),
      n_prev = sum(!is.na(prev_two_party)),
      bias_share = mean(err_share),
      rmse_share = sqrt(mean(err_share^2)),
      cover50 = mean(cover50),
      cover90 = mean(cover90),
      brier = brier(prob_a, a_wins),
      brier_noenv = brier(prob_a_noenv, a_wins),
      brier_coin = brier(0.5, a_wins),
      logloss = logloss(prob_a, a_wins),
      wrong_favourites = sum(favourite_wrong),
      wrong_prev = sum(prev_wrong, na.rm = TRUE),
      d_wins = sum(a_wins),
      mean_other_share = mean(other_share),
      .groups = "drop"
    )
}
slice_defs <- list(
  all = \(d) d |> filter(kind == "d_vs_r") |> mutate(grp = "all D-vs-R"),
  by_chamber = \(d) d |> filter(kind == "d_vs_r") |> mutate(grp = chamber),
  by_year = \(d) d |> filter(kind == "d_vs_r") |> mutate(grp = str_c(year)),
  by_chamber_year = \(d) {
    d |> filter(kind == "d_vs_r") |> mutate(grp = str_c(chamber, " ", year))
  },
  other = \(d) {
    d |>
      filter(kind == "other_vs_r") |>
      mutate(grp = str_c("non-D challenger vs R (", chamber, ")"))
  },
  competitive = \(d) {
    d |>
      filter(kind == "d_vs_r", between(m_env, 0.3, 0.7)) |>
      mutate(grp = "D-vs-R, prior D share 30-70%")
  }
)
summary_tbl <- imap(slice_defs, \(f, nm) {
  f(contests) |>
    group_by(grp) |>
    group_modify(\(d, k) summarise_group(d)) |>
    ungroup() |>
    mutate(slice = nm, .before = 1)
}) |>
  list_rbind() |>
  mutate(across(where(is.double), \(x) round(x, 4)))
write_csv(summary_tbl, file.path(out_dir, "eval_prior_summary.csv"))

cal_breaks <- c(0, 0.011, 0.05, 0.2, 0.4, 0.6, 0.8, 0.95, 0.989, 1)
calibration <- contests |>
  filter(kind == "d_vs_r") |>
  mutate(bin = cut(prob_a, cal_breaks, include.lowest = TRUE)) |>
  summarise(
    n = n(),
    mean_pred = mean(prob_a),
    observed = mean(a_wins),
    mean_pred_share = mean(m_env),
    .by = bin
  ) |>
  arrange(bin) |>
  mutate(across(where(is.double), \(x) round(x, 4)))
write_csv(calibration, file.path(out_dir, "eval_prior_calibration.csv"))

print(env_tbl)
print(
  summary_tbl |>
    filter(
      slice %in% c("all", "by_chamber", "by_year", "other", "competitive")
    ),
  n = 40,
  width = 250
)
print(calibration)
