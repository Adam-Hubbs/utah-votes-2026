# Run: Rscript pipeline/tests/test_polls_demographics.R (after build_demographics.R)
suppressPackageStartupMessages(library(testthat))
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
source(file.path(dirname(normalizePath(script_file)), "..", "R", "utils.R"))

units <- \(f) read_json(data_dir("demographics", f), simplifyVector = FALSE)$units
state <- units("state.json")[[1]]

test_that("district populations add up to the state total", {
  expect_equal(sum(map_dbl(units("cd2026.json"), "population")), state$population, tolerance = 0.002)
  expect_equal(sum(map_dbl(units("cd2022.json"), "population")), state$population, tolerance = 0.002)
  expect_equal(sum(map_dbl(units("counties.json"), "population")), state$population)
})

test_that("new District 1 is the Salt Lake County based district", {
  d1 <- units("cd2026.json")[[1]]
  expect_equal(d1$counties[[1]]$fips, "49035")
  expect_gt(d1$counties[[1]]$share, 0.95)
})

test_that("shares are proportions and registration reconciles", {
  all_units <- c(units("cd2026.json"), units("counties.json"))
  walk(all_units, \(u) {
    expect_true(all(c(u$pct_white_nh, u$pct_hispanic, u$pct_bachelors_plus, u$pct_under_18, u$pct_65_plus) |> between(0, 1)))
  })
  expect_equal(sum(map_dbl(units("counties.json"), \(u) u$registration$total)), state$registration$total)
})
