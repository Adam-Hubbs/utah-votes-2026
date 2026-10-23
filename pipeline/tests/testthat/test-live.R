root <- Sys.getenv("UTEL_ROOT", unset = normalizePath(file.path(testthat::test_path(), "..", "..", "..")))
Sys.setenv(UTEL_ROOT = root)
source(file.path(root, "pipeline", "R", "utils.R"))
for (f in c("live_api", "model_expected", "live_normalize")) source(file.path(root, "pipeline", "R", str_c(f, ".R")))

test_that("ballot names become canonical ids", {
  x <- parse_ballot_name(c("BABAK \"BOBBY\" DARVISH", "ELIAS HENRY MONTGOMERY", "BEN MCADAMS", "Write-in", "\"CJ\" CHRISTINA HERNANDEZ", "J. LOWRY SNOW"))
  expect_equal(x$candidate_id, c("bobby-darvish", "elias-montgomery", "ben-mcadams", "write-in", "cj-hernandez", "lowry-snow"))
  expect_equal(x$display_name[3], "Ben McAdams")
  expect_equal(x$display_name[5], "CJ Hernandez")
})

test_that("contest names map to contest ids", {
  x <- classify_contest(c(
    "U.S. House District 3", "Constitutional Amendment B", "STATE SENATE DISTRICT 6", "State House District 23 (Multi-County)",
    "State School Board District 7 (2-Year Term)", "Shall JILL M. POHLMAN be retained in the office of Justice of the Supreme Court of Utah?",
    "COUNTY SHERIFF", "DAVIS COUNTY JUSTICE COURT JOHN CARL YNCHAUSTI"
  ))
  expect_equal(x$contest_id, c("us-house-3", "amendment-b", "state-senate-6", "state-house-23", "school-board-7", "retention-jill-m-pohlman", NA, NA))
})

counties_fixture <- function(counted, final = FALSE, remaining = NA_real_) {
  tibble(
    fips = utah_counties$fips, registered = 20000 * seq_len(29) / 3 + 2000,
    prior_turnout = 0.65, counted = counted, final = final, remaining = remaining
  ) |>
    mutate(fixed = final | !is.na(remaining))
}

test_that("model never expects fewer ballots than counted and honours overrides", {
  set.seed(1)
  base <- counties_fixture(0)
  counted <- round(base$registered * 0.65 * 0.6)
  cty <- counties_fixture(counted)
  cty$final[1] <- TRUE
  cty$fixed[1] <- TRUE
  cty$remaining[2] <- 100
  cty$fixed[2] <- TRUE
  p <- model_defaults()
  p$draws <- 800L
  fit <- fit_expected_ballots(cty, 2, p, seed = 3)
  expect_true(all(sweep(fit$T, 2, counted, `-`) >= -1e-6))
  expect_equal(unique(fit$T[, 1]), counted[1])
  expect_lt(sd(fit$T[, 2]), 10)
  s <- summarise_draws(fit$T, counted)
  expect_true(all(s$pct_expected <= 1 & s$pct_expected_lo <= s$pct_expected & s$pct_expected <= s$pct_expected_hi))
})

test_that("uncounted counties fall back to the prior", {
  cty <- counties_fixture(0)
  p <- model_defaults()
  p$draws <- 500L
  fit <- fit_expected_ballots(cty, 0, p, seed = 1)
  expect_equal(median(fit$T[, "49035"]) / cty$registered[cty$fips == "49035"], 0.65, tolerance = 0.1)
})

test_that("winners are only marked once results are official", {
  path <- file.path(Sys.getenv("UTEL_RAW_DIR", file.path(root, "pipeline", "raw")), "live", "exp2026.json")
  skip_if_not(file.exists(path))
  parsed <- parse_export(jsonlite::fromJSON(path, simplifyVector = FALSE))
  cands <- read_candidates()
  any_winner <- \(r) any(map_lgl(r$summary$contests, \(c) any(map_lgl(c$candidates, "winner"))))
  expect_false(any_winner(build_results(parsed, cands, cfg = live_config())))
})

test_that("auto_winners takes top seats and refuses ties at the cutoff", {
  rows <- tibble(candidate_id = c("a", "b", "c"), votes = c(50, 30, 30))
  expect_equal(auto_winners(rows, 1), "a")
  expect_equal(auto_winners(rows, 2), character())
  expect_equal(auto_winners(rows[1:2, ], 2), c("a", "b"))
  expect_equal(auto_winners(tibble(candidate_id = c("yes", "no"), votes = c(49, 51)), 1), "no")
  expect_equal(auto_winners(tibble(candidate_id = "a", votes = 0), 1), character())
})
