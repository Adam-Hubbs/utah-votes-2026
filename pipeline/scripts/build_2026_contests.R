#!/usr/bin/env Rscript
# Builds candidates.csv/json and the zero-vote "pre" results from the published ballot structure.
# Usage: Rscript pipeline/scripts/build_2026_contests.R [--refresh-candidates]
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
for (f in c("live_api", "live_normalize", "model_expected", "live_scrape")) source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))

args <- commandArgs(trailingOnly = TRUE)
cfg <- live_config()
export_path <- ev_download_export(dest = raw_dir("live", "export-latest.json"))
j <- jsonlite::fromJSON(export_path, simplifyVector = FALSE)
parsed <- parse_export(j)

cand_path <- file.path(project_root(), "pipeline", "config", "candidates.csv")
existing <- if (file.exists(cand_path)) read_candidates() else NULL
if (is.null(existing) || "--refresh-candidates" %in% args) {
  candidates <- generate_candidates(parsed, existing)
  write_csv(candidates, cand_path, na = "")
  message("Wrote ", nrow(candidates), " candidates to candidates.csv")
}
candidates <- read_candidates()
write_site_json(candidates_json(candidates), "candidates.json")

results <- build_results(parsed, candidates, read_calls(), status = "pre", as_of = j$createdAt, cfg = cfg)
results$summary$source_etag <- ev_export_etag()$etag
results$summary$inputs_hash <- inputs_hash()
staging <- file.path(tempdir(), "pre")
write_results(results, staging)
run_expected_vote_model(staging, ELECTION_ID, now = Sys.time())
publish_dir(staging, data_dir("results", ELECTION_ID, "summary.json") |> dirname())
write_site_config("pre", featured_ids(results))
message("Pre-election results written: ", length(results$contests), " contests")
