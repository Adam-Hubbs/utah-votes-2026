#!/usr/bin/env Rscript
# Re-runs the expected-vote model on already-written results (writes model.json, pct_expected*, summary turnout).
#   Rscript pipeline/scripts/model_expected_vote.R [results_dir_name] [--hours-after-close H]
# scrape_live.R calls the same function after every scrape; this entry point is for manual re-runs
# (e.g. after editing pipeline/config/remaining_ballots.csv).
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
for (f in c("live_api", "model_expected", "live_normalize")) source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))

args <- commandArgs(trailingOnly = TRUE)
positional <- args[!str_starts(args, "--") & !(seq_along(args) %in% (match("--hours-after-close", args) + 1))]
election <- if (length(positional) >= 1) positional[1] else ELECTION_ID
h <- args[match("--hours-after-close", args) + 1]
now <- if (is.na(h)) Sys.time() else POLLS_CLOSE_UTC + as.numeric(h) * 3600
dir <- data_dir("results", election, "summary.json") |> dirname()
state <- fetch_state_data()
reg <- if (!is.null(state) && nrow(state$registered) > 0) {
  state$registered |> transmute(fips = county_fips_from_name(county), registered = active)
}
run_expected_vote_model(dir, election, now = now, registered_override = reg)
message("Model written to ", file.path(dir, "model.json"))
