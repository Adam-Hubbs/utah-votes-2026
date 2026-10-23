#!/usr/bin/env Rscript
# Re-runs the needle on already-written results (writes needle.json). scrape_live.R and the simulator call run_needle() directly.
#   Rscript pipeline/scripts/model_needle.R [results_dir_name]
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
for (f in c("live_api", "model_expected", "live_normalize", "model_needle")) source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))
args <- commandArgs(trailingOnly = TRUE)
election <- if (length(args) >= 1) args[1] else ELECTION_ID
dir <- data_dir("results", election, "summary.json") |> dirname()
run_needle(dir, election)
