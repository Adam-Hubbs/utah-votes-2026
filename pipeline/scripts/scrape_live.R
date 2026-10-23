#!/usr/bin/env Rscript
# Election-night scraper. See pipeline/docs/live.md.
#   Rscript pipeline/scripts/scrape_live.R                      one live scrape (+ model)
#   Rscript pipeline/scripts/scrape_live.R --force              ignore the unchanged-export shortcut
#   Rscript pipeline/scripts/scrape_live.R --simulate 0.45 --seed 1
#   Rscript pipeline/scripts/scrape_live.R --simulate-sequence [--seed 1] [--steps 5]
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
for (f in c("live_api", "model_expected", "model_needle", "live_normalize", "live_scrape", "live_sim")) {
  source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))
}

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
seed <- as.integer(arg_value("--seed", "1"))

if ("--simulate-sequence" %in% args) {
  phis <- c(0.55, 0.65, 0.75, 0.83, 0.9, 0.94, 0.97, 0.985)
  hours <- c(0.4, 1, 2.5, 5, 10, 20, 40, 80)
  steps <- as.integer(arg_value("--steps", as.character(length(phis))))
  run_simulation(phis = phis[seq_len(steps)], hours = hours[seq_len(steps)], seed = seed)
} else if ("--simulate" %in% args) {
  run_simulation(as.numeric(arg_value("--simulate", "0.45")), seed = seed)
} else {
  status <- tryCatch(
    scrape_once(force = "--force" %in% args),
    error = \(e) {
      message("[scrape] FAILED: ", conditionMessage(e))
      quit(status = 1)
    }
  )
}
