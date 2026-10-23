#!/usr/bin/env Rscript
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
r_dir <- file.path(dirname(normalizePath(script_file)), "..", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "ratings_build.R"))

cfg_dir <- file.path(project_root(), "pipeline", "config")
ratings <- read_csv(file.path(cfg_dir, "ratings.csv"), col_types = cols(.default = "c"))
forecasts <- read_csv(file.path(cfg_dir, "forecasts.csv"), col_types = cols(.default = "c", prob_dem = "d"))
write_site_json(build_ratings_json(ratings, forecasts), "ratings.json")
message("ratings.json written")
