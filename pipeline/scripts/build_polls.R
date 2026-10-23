#!/usr/bin/env Rscript
# Usage: Rscript pipeline/scripts/build_polls.R   (env: POLLS_BASE_URL, optional)
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
r_dir <- file.path(dirname(normalizePath(script_file)), "..", "R")
source(file.path(r_dir, "utils.R"))
walk(c("polls_load.R", "polls_utah.R", "polls_average.R", "polls_build.R"), \(f) source(file.path(r_dir, f)))

cfg <- jsonlite::read_json(file.path(project_root(), "pipeline", "config", "polls.json"))
today <- as.Date(Sys.getenv("POLLS_TODAY", unset = format(Sys.Date())))

house <- read_poll_csv("house.csv", poll_required_cols) |> prep_poll_rows()
rows <- load_house_like_polls()
approval_avg <- read_poll_csv("president-averages.csv", averages_required_cols)
# Validate the approval poll file too, even though the NYT average is what we publish.
invisible(read_poll_csv("president.csv", approval_required_cols))

utah <- utah_poll_rows(rows, cfg)
polls_json <- build_polls_json(utah)
write_polls_json(polls_json, "polls.json")
message("polls.json: ", nrow(polls_json), " Utah poll questions")

averages <- build_state_averages(utah, today, cfg)
write_polls_json(averages, "averages.json")
message("averages.json: ", length(averages$contests), " contests")

national <- build_national(house, approval_avg, today, cfg)
write_polls_json(national, "national.json")
message("national.json written")
