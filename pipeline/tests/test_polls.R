# Run: Rscript pipeline/tests/test_polls.R
suppressPackageStartupMessages(library(testthat))
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
r_dir <- file.path(dirname(normalizePath(script_file)), "..", "R")
source(file.path(r_dir, "utils.R"))
walk(c("polls_load.R", "polls_utah.R", "polls_average.R", "polls_build.R"), \(f) source(file.path(r_dir, f)))
cfg <- yaml::read_yaml(file.path(project_root(), "pipeline", "config", "polls.yml"))

synthetic <- tribble(
  ~question_id, ~pollster, ~end_date, ~sample_size, ~numeric_grade, ~partisan, ~internal, ~candidate_id, ~name, ~party, ~pct,
  "q1", "A", as.Date("2026-10-01"), 500L, NA, NA, FALSE, "d", "Dee", "DEM", 45,
  "q1", "A", as.Date("2026-10-01"), 500L, NA, NA, FALSE, "r", "Arr", "REP", 40,
  "q2", "B", as.Date("2026-10-10"), 800L, 2, NA, FALSE, "d", "Dee", "DEM", 50,
  "q2", "B", as.Date("2026-10-10"), 800L, 2, NA, FALSE, "r", "Arr", "REP", 38,
  "q3", "C", as.Date("2026-10-15"), 400L, NA, "REP", FALSE, "d", "Dee", "DEM", 41,
  "q3", "C", as.Date("2026-10-15"), 400L, NA, "REP", FALSE, "r", "Arr", "REP", 47
)
as_of <- as.Date("2026-10-20")

test_that("candidate averages lie within the range of the polls", {
  avg <- average_candidates(synthetic, as_of, cfg$state_average)
  ranges <- synthetic |> summarise(min_pct = min(pct), max_pct = max(pct), .by = candidate_id)
  checked <- avg |> inner_join(ranges, by = "candidate_id")
  expect_true(all(checked$avg >= checked$min_pct - 1e-9 & checked$avg <= checked$max_pct + 1e-9))
  expect_true(all(avg$lo <= avg$avg & avg$avg <= avg$hi))
})

test_that("margin average lies within the range of poll margins", {
  m <- average_margin(synthetic, as_of, cfg$state_average)
  gaps <- c(-5, -12, 6)
  expect_gte(m$margin, min(gaps))
  expect_lte(m$margin, max(gaps))
})

test_that("a single poll is returned unchanged and gets the uncertainty floor", {
  one <- filter(synthetic, question_id == "q1")
  avg <- average_candidates(one, as_of, cfg$state_average)
  expect_equal(avg$avg[avg$candidate_id == "d"], 45)
  expect_gte(min(avg$hi - avg$avg), cfg$state_average$floor_halfwidth_candidate - 1e-9)
  expect_equal(unique(avg$n_polls), 1)
})

test_that("weights: recency halves at the half-life and same-pollster share is sub-additive", {
  base <- tibble(
    pollster = "A", end_date = as.Date("2026-10-01"), sample_size = 600L,
    numeric_grade = NA_real_, partisan = NA_character_, internal = FALSE
  )
  w <- poll_weights(base, as.Date("2026-10-22"), 21, 600, 0.5)
  expect_equal(w$w_recency, 0.5)
  two <- bind_rows(base, base)
  w2 <- poll_weights(two, as.Date("2026-10-22"), 21, 600, 0.5)
  expect_equal(sum(w2$w), sqrt(2) * w$w, tolerance = 1e-9)
  partisan <- mutate(base, partisan = "DEM")
  expect_equal(poll_weights(partisan, as.Date("2026-10-22"), 21, 600, 0.5)$w, w$w * 0.5)
})

test_that("weighted mean equals manual computation", {
  avg <- average_candidates(synthetic, as_of, cfg$state_average)
  w <- poll_weights(
    distinct(synthetic, question_id, pollster, end_date, sample_size, numeric_grade, partisan, internal),
    as_of, 21, 600, 0.5
  )
  manual <- sum(w$w * c(45, 50, 41)) / sum(w$w)
  expect_equal(avg$avg[avg$candidate_id == "d"], manual, tolerance = 1e-9)
})

test_that("Utah contest ids come from seat_number, not seat_name", {
  expect_equal(nyt_contest_id("U.S. House", "Third Congressional Election", "3"), "us-house-3")
  expect_equal(nyt_candidate_id("Don't know", "Don't know"), "undecided")
  expect_equal(nyt_candidate_id("McAdams", "Ben McAdams"), "ben-mcadams")
})

test_that("published averages are consistent with the published polls", {
  polls <- jsonlite::read_json(data_dir("polls", "polls.json"), simplifyVector = FALSE)
  avgs <- jsonlite::read_json(data_dir("polls", "averages.json"), simplifyVector = FALSE)
  general <- keep(polls, \(p) p$stage == "general")
  for (cid in names(avgs$contests)) {
    these <- keep(general, \(p) p$contest_id == cid)
    for (cand in avgs$contests[[cid]]$latest) {
      pcts <- these |>
        map(\(p) keep(p$results, \(r) r$candidate_id == cand$candidate_id)) |>
        list_flatten() |>
        map_dbl(\(r) r$pct)
      expect_gte(cand$avg, min(pcts) - 0.05)
      expect_lte(cand$avg, max(pcts) + 0.05)
    }
  }
})
