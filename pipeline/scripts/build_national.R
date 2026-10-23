#!/usr/bin/env Rscript
# Usage: Rscript pipeline/scripts/build_national.R [--sim]   (env: POLLS_BASE_URL, POLLS_TODAY optional)
# --sim reads pipeline/config/national_calls_sim.csv and writes web/public/data/national/sim/ for ?sim=1 previews.
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
r_dir <- file.path(dirname(normalizePath(script_file)), "..", "R")
source(file.path(r_dir, "utils.R"))
walk(c("polls_load.R", "polls_utah.R", "polls_average.R", "polls_build.R", "national_build.R"), \(f) source(file.path(r_dir, f)))

sim <- "--sim" %in% commandArgs(TRUE)
today <- as.Date(Sys.getenv("POLLS_TODAY", unset = format(Sys.Date())))
polls_cfg <- read_json(file.path(project_root(), "pipeline", "config", "polls.json"))
cfg <- load_senate_config()
calls <- read_calls(if (sim) "national_calls_sim.csv" else "national_calls.csv")

# Rewrites only when the content changed apart from the timestamp, so the election-night loop does not commit noise.
write_national_json <- function(x, file) {
  path <- do.call(data_dir, as.list(c("national", if (sim) "sim", file)))
  tmp <- tempfile(fileext = ".json")
  write_json(x, tmp, auto_unbox = TRUE, null = "null", na = "null", digits = NA, pretty = FALSE)
  strip_stamp <- \(p) str_replace_all(read_file(p), '"updated_at":"[^"]*"', '"updated_at":""')
  if (file.exists(path) && identical(strip_stamp(path), strip_stamp(tmp))) return(invisible(path))
  file.copy(tmp, path, overwrite = TRUE)
  invisible(path)
}

senate <- build_senate(cfg, calls, today, polls_cfg$state_average)
write_national_json(senate$senate, "senate.json")
write_national_json(senate$tracker, "senate_polls.json")
write_national_json(build_house(cfg$meta, calls), "house.json")
message(
  "national: ", length(senate$senate$races), " Senate races, ",
  sum(map_lgl(senate$senate$races, \(r) r$poll_avg$n_polls > 0)), " with polls, ",
  length(senate$tracker$averages), " tracker races",
  if (sim) " (sim)"
)
