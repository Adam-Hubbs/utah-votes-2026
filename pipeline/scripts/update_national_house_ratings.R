#!/usr/bin/env Rscript
# Refreshes pipeline/config/national_house_ratings.csv from Wikipedia's House ratings page.
# Manual step (not part of CI): run it, eyeball the diff, commit. Wikipedia's edit history is the audit trail.
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
r_dir <- file.path(dirname(normalizePath(script_file)), "..", "R")
source(file.path(r_dir, "utils.R"))
source(file.path(r_dir, "national_ratings.R"))

page <- "2026_United_States_House_of_Representatives_election_ratings"
url <- str_glue("https://en.wikipedia.org/w/index.php?title={page}&action=raw")
text <- httr2::request(url) |>
  httr2::req_user_agent("utah-elections-site/0.1 (adam@y2analytics.com)") |>
  httr2::req_perform() |>
  httr2::resp_body_string()

parsed <- parse_house_ratings(text)
stopifnot(all(parsed$totals$tossups == parsed$counts |> filter(label == "Toss-up") |> arrange(match(source, parsed$totals$source)) |> pull(n)))

out <- parsed$counts |>
  mutate(url = str_glue("https://en.wikipedia.org/wiki/{page}")) |>
  arrange(source, label)
write_csv(out, file.path(project_root(), "pipeline", "config", "national_house_ratings.csv"))
print(out, n = 40)
