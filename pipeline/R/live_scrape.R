RESULTS_SUBDIR <- c("results", ELECTION_ID)

results_path <- function(...) data_dir(RESULTS_SUBDIR[1], RESULTS_SUBDIR[2], ...)

read_json_safe <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(jsonlite::read_json(path, simplifyVector = FALSE), error = \(e) NULL)
}

# Refuses to publish data that looks like an API hiccup rather than a real update.
validate_update <- function(results, parsed, prev, cfg) {
  n_counties <- n_distinct(parsed$options$fips)
  if (n_counties < 29) stop(sprintf("Only %d counties present in source data (expected 29); refusing to publish.", n_counties))
  if (nrow(parsed$options) == 0) stop("Source data has no contest options; refusing to publish.")
  if (!is.null(prev)) {
    prev_ids <- map_chr(prev$contests, "contest_id")
    missing_ids <- setdiff(prev_ids, names(results$contests))
    if (length(missing_ids) > 0.1 * length(prev_ids)) {
      stop(sprintf("%d of %d previously published contests vanished from source data; schema drift?", length(missing_ids), length(prev_ids)))
    }
    prev_votes <- sum(map_dbl(prev$contests, "total_votes"))
    new_votes <- sum(map_dbl(results$summary$contests, "total_votes"))
    if (prev_votes > 0 && new_votes < (1 - cfg$max_vote_drop_fraction) * prev_votes) {
      stop(sprintf("Total votes fell from %s to %s; refusing to overwrite good data.", prev_votes, new_votes))
    }
  }
  invisible(TRUE)
}

# Reported precinct ids that have votes but no polygon in precincts_2026 would silently vanish from the map, so say so in the log.
report_unjoined_precincts <- function(results) {
  topo <- read_json_safe(data_dir("geo", "precincts_2026.topo.json"))
  if (is.null(topo)) return(invisible(NULL))
  polygon_ids <- map_chr(topo$objects$precincts$geometries, \(g) g$properties$precinct_id)
  unjoined <- results$contests |>
    map(\(x) tibble(precinct_id = map_chr(x$precincts, "precinct_id"), votes = map_dbl(x$precincts, "total"))) |>
    list_rbind() |>
    summarise(votes = sum(votes), .by = precinct_id) |>
    filter(!precinct_id %in% polygon_ids)
  if (nrow(unjoined) > 0) {
    message(sprintf(
      "[scrape] %d reported precincts have no polygon (%s votes): %s",
      nrow(unjoined), format(sum(unjoined$votes), big.mark = ","),
      str_c(head(unjoined$precinct_id, 8), collapse = ", ")
    ))
  }
  invisible(unjoined)
}

winners_to_ids <- function(winners, candidates) {
  if (is.null(winners) || nrow(winners) == 0) return(NULL)
  winners |>
    mutate(key = str_to_upper(ballot_name)) |>
    left_join(transmute(candidates, contest_id, key = str_to_upper(ballot_name), cand = candidate_id), by = c("contest_id", "key")) |>
    mutate(candidate_id = coalesce(cand, if_else(contest_id %in% character(), NA_character_, slugify(ballot_name)))) |>
    mutate(candidate_id = if_else(str_detect(contest_id, "^(amendment|retention)-"), str_to_lower(ballot_name), candidate_id)) |>
    select(contest_id, candidate_id)
}

fetch_parsed <- function() {
  url <- ev_export_url()
  head <- ev_export_etag(url)
  if (head$status == 200 && Sys.getenv("UTEL_FORCE_FALLBACK") != "1") {
    path <- ev_download_export(url)
    parsed <- tryCatch(
      parse_export(jsonlite::fromJSON(path, simplifyVector = FALSE)),
      error = \(e) {
        message("[scrape] export unparsable (", conditionMessage(e), "); falling back to /data")
        NULL
      }
    )
    if (!is.null(parsed)) return(list(parsed = parsed, etag = head$etag, via = "export"))
  } else {
    message("[scrape] export returned HTTP ", head$status, "; falling back to /data endpoints")
  }
  list(parsed = fetch_fallback_parsed(), etag = NA_character_, via = "data")
}

# Manual inputs that change the output without the source changing (candidates, remaining-ballot overrides).
inputs_hash <- function() {
  files <- file.path(project_root(), "pipeline", "config", c("candidates.csv", "remaining_ballots.csv", "live.yml"))
  unname(tools::md5sum(files[file.exists(files)])) |> str_c(collapse = "")
}

scrape_once <- function(force = FALSE, now = Sys.time()) {
  cfg <- live_config()
  conn <- if (Sys.getenv("UTEL_SKIP_CONNCHECK") == "1") tibble(ok = TRUE) else connectivity_check()
  if (!any(conn$ok)) stop("No Utah results endpoint reachable (blocked network?). See pipeline/docs/live.md fallback.")
  dest <- results_path()
  prev <- read_json_safe(file.path(dest, "summary.json"))

  head <- tryCatch(ev_export_etag(), error = \(e) list(status = NA, etag = NA_character_))
  if (!force && !is.null(prev) && !is.na(head$etag) && identical(prev$source_etag, head$etag) && identical(prev$inputs_hash, inputs_hash())) {
    message("[scrape] export unchanged (etag ", head$etag, "); re-running model only")
    refresh_model_only(dest, now)
    return(invisible("unchanged"))
  }

  src <- fetch_parsed()
  state <- fetch_state_data()
  candidates <- read_candidates()
  official <- isTRUE(state$official)
  winners <- if (official) winners_to_ids(state$winners, candidates) else NULL
  t_iso <- format(as.POSIXct(now, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  as_of <- state$as_of %||% t_iso

  results <- build_results(src$parsed, candidates, status = "live", as_of = as_of, official = official, official_winners = winners, updated_at = t_iso, cfg = cfg)
  status <- case_when(official ~ "final", results$max_votes > 0 ~ "live", .default = "pre")
  results$summary$status <- status
  results$summary$source_etag <- src$etag
  results$summary$inputs_hash <- inputs_hash()
  validate_update(results, src$parsed, prev, cfg)
  try(report_unjoined_precincts(results), silent = TRUE)

  staging <- file.path(tempdir(), "live")
  unlink(staging, recursive = TRUE)
  tl <- update_timeline(file.path(dest, "timeline.json"), results, cfg, t_iso)
  write_results(results, staging, if (status == "pre") NULL else tl)
  for (f in c("model.json", "needle.json")) if (file.exists(file.path(dest, f))) file.copy(file.path(dest, f), file.path(staging, f), overwrite = TRUE)
  reg <- if (!is.null(state) && nrow(state$registered) > 0) {
    state$registered |> transmute(fips = county_fips_from_name(county), registered = active) |> filter(!is.na(fips))
  }
  run_expected_vote_model(staging, ELECTION_ID, now = now, is_official = official, registered_override = reg)
  safe_needle(staging, ELECTION_ID, now)
  publish_dir(staging, dest)
  write_site_config(status, featured_ids(results))
  message(sprintf("[scrape] published status=%s via=%s as_of=%s votes=%s", status, src$via, as_of, format(results$max_votes, big.mark = ",")))
  invisible(status)
}

# When only the clock moved (no new export) the pct-expected estimates still drift, so refresh them at most every few minutes.
refresh_model_only <- function(dest, now, min_age_min = 10) {
  model <- read_json_safe(file.path(dest, "model.json"))
  if (is.null(model)) return(invisible(FALSE))
  age <- difftime(now, as.POSIXct(model$updated_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "mins")
  if (as.numeric(age) < min_age_min) return(invisible(FALSE))
  status <- read_json_safe(file.path(dest, "summary.json"))$status
  if (!identical(status, "live")) return(invisible(FALSE))
  run_expected_vote_model(dest, ELECTION_ID, now = now)
  safe_needle(dest, ELECTION_ID, now)
  invisible(TRUE)
}

# The needle is an add-on: a failure must never block publishing the results themselves.
safe_needle <- function(dir, election_id, now) {
  tryCatch(run_needle(dir, election_id, now = now), error = \(e) message("[needle] FAILED: ", conditionMessage(e)))
  invisible(NULL)
}
