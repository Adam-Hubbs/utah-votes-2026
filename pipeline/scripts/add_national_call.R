#!/usr/bin/env Rscript
# Usage: Rscript pipeline/scripts/add_national_call.R <senate|house> <STATE> <district|-> <DEM|REP|IND> "<winner name>" "<called by>" ["note"]
# Adds or replaces one row in pipeline/config/national_calls.csv, then rebuilds the national JSON.
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
r_dir <- file.path(dirname(normalizePath(script_file)), "..", "R")
source(file.path(r_dir, "utils.R"))

args <- commandArgs(TRUE)
if (length(args) < 6) stop("Need: chamber state district party winner_name called_by [note]", call. = FALSE)
new <- tibble(
  chamber = str_to_lower(args[1]), state = str_to_upper(args[2]),
  district = if_else(args[3] %in% c("-", ""), NA_character_, args[3]),
  winner_party = str_to_upper(args[4]), winner_name = args[5], called_by = args[6],
  called_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  note = if_else(length(args) >= 7, args[7], NA_character_)
)
path <- file.path(project_root(), "pipeline", "config", "national_calls.csv")
calls <- read_csv(path, col_types = cols(.default = "c"), show_col_types = FALSE) |>
  anti_join(new, by = c("chamber", "state", "district")) |>
  bind_rows(new)
write_csv(calls, path, na = "")
system2("Rscript", file.path(dirname(normalizePath(script_file)), "build_national.R"))
