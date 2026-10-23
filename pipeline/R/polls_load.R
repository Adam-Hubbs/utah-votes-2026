poll_required_cols <- c(
  "poll_id", "question_id", "pollster", "sponsors", "numeric_grade", "state",
  "start_date", "end_date", "sample_size", "population", "partisan", "internal",
  "cycle", "office_type", "seat_name", "seat_number", "stage", "party", "pct",
  "answer", "candidate_name", "url"
)
approval_required_cols <- c(
  "poll_id", "question_id", "pollster", "state", "start_date", "end_date",
  "sample_size", "population", "politician", "yes", "no"
)
averages_required_cols <- c("topic", "date", "answer", "pct")

polls_base <- function() {
  base <- Sys.getenv("POLLS_BASE_URL", unset = "")
  if (nzchar(base)) base else file.path(project_root(), "polls")
}

polls_source_path <- function(file, base = polls_base()) {
  if (str_detect(base, "^https?://")) {
    str_c(str_remove(base, "/+$"), "/", file)
  } else {
    file.path(base, file)
  }
}

read_poll_csv <- function(file, required, base = polls_base()) {
  src <- polls_source_path(file, base)
  data <- tryCatch(
    read_csv(src, col_types = cols(.default = "c"), show_col_types = FALSE),
    error = \(e) stop(
      "Could not read poll file '", file, "' from ", src, ": ", conditionMessage(e),
      call. = FALSE
    )
  )
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) {
    stop(
      "Poll file '", file, "' (", src, ") is missing required column(s): ",
      str_c(missing, collapse = ", "), ". Found: ", str_c(names(data), collapse = ", "),
      call. = FALSE
    )
  }
  data
}

parse_poll_date <- function(x) {
  # Two-digit years are parsed explicitly: lubridate would map 2-digit years by its own pivot rule.
  parsed <- as.Date(x, format = "%m/%d/%y")
  alt <- as.Date(x, format = "%Y-%m-%d")
  dplyr::coalesce(parsed, alt)
}

prep_poll_rows <- function(data) {
  data |>
    mutate(
      start_date = parse_poll_date(start_date),
      end_date = parse_poll_date(end_date),
      sample_size = suppressWarnings(as.integer(sample_size)),
      numeric_grade = suppressWarnings(as.numeric(numeric_grade)),
      pct = suppressWarnings(as.numeric(pct)),
      cycle = suppressWarnings(as.integer(cycle)),
      hypothetical = if ("hypothetical" %in% names(data)) {
        coalesce(str_to_upper(hypothetical) == "TRUE", FALSE)
      } else {
        FALSE
      },
      internal = coalesce(str_to_upper(internal) == "TRUE", FALSE)
    )
}

load_house_like_polls <- function(base = polls_base()) {
  c("house.csv", "senate.csv", "governor.csv", "other.csv") |>
    map(\(f) read_poll_csv(f, poll_required_cols, base)) |>
    list_rbind() |>
    prep_poll_rows()
}
