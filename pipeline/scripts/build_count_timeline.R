#!/usr/bin/env Rscript
# Builds pipeline/data/timing/county_count_timeline.csv: votes counted per county over time for past Utah elections,
# recovered from Wayback Machine captures. Everything downloaded is cached under $UTEL_RAW_DIR/timing/ and requests are throttled.
#   Rscript pipeline/scripts/build_count_timeline.R
#
# Sources
#  * old_site: electionresults.utah.gov/elections/countyCount/<contest id> (2016-2022). One table per contest with a row per county.
#  * export_2025: electionresults.utah.gov/cdn/results/Utah/export-general11042025.json (sum of votes over all municipal contests per county).
#  * clarity_slc: results.enr.clarityelections.com/UT/Salt_Lake/<id>/<version>/json/sum.json (Salt Lake only; top-of-ticket ballots).
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
suppressPackageStartupMessages({
  library(httr2)
  library(rvest)
})

TIMING_DIR <- raw_dir("timing", "x")
TIMING_DIR <- dirname(TIMING_DIR)
OUT_DIR <- file.path(project_root(), "pipeline", "data", "timing")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Polls close 8 pm Mountain, which is 03:00 UTC the next day in every general-election year here (DST has ended by then).
elections <- tribble(
  ~election_id   , ~year , ~close_utc            ,
  "2016-general" , 2016L , "2016-11-09 03:00:00" ,
  "2018-general" , 2018L , "2018-11-07 03:00:00" ,
  "2020-general" , 2020L , "2020-11-04 03:00:00" ,
  "2022-general" , 2022L , "2022-11-09 03:00:00" ,
  "2025-general" , 2025L , "2025-11-05 03:00:00"
) |>
  mutate(close_utc = as.POSIXct(close_utc, tz = "UTC"))

cache_path <- \(...) {
  p <- file.path(TIMING_DIR, ...)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  p
}

wb_request <- \(url) {
  request(url) |>
    req_user_agent(
      "utah-election-site timing research (adam@y2analytics.com)"
    ) |>
    req_throttle(rate = 40 / 60) |>
    req_timeout(120) |>
    req_retry(max_tries = 5, backoff = \(i) 5 * 2^i, is_transient = \(r) {
      resp_status(r) %in% c(429, 500, 502, 503, 504)
    })
}

# Wayback id_ URLs redirect to the nearest capture; the capture time actually served is in the final URL.
wb_get <- \(ts, url) {
  slug <- str_c(
    ts,
    "_",
    str_replace_all(url, "[^A-Za-z0-9]+", "_") |> str_sub(-120)
  )
  body_path <- cache_path("wb", str_c(slug, ".body"))
  meta_path <- cache_path("wb", str_c(slug, ".ts"))
  if (file.exists(body_path) && file.exists(meta_path)) {
    return(list(ts = read_lines(meta_path), body = read_file(body_path)))
  }
  resp <- tryCatch(
    wb_request(str_c("https://web.archive.org/web/", ts, "id_/", url)) |>
      req_perform(),
    error = \(e) NULL
  )
  if (is.null(resp) || resp_status(resp) != 200) {
    return(NULL)
  }
  body <- resp_body_string(resp)
  if (!nzchar(str_trim(body))) {
    return(NULL)
  }
  served <- str_match(resp$url, "/web/([0-9]{14})")[, 2]
  write_file(body, body_path)
  write_lines(coalesce(served, ts), meta_path)
  list(ts = coalesce(served, ts), body = body)
}

cdx_list <- \(url, from, to) {
  path <- cache_path(
    "cdx",
    str_c(
      str_replace_all(url, "[^A-Za-z0-9]+", "_"),
      "_",
      from,
      "_",
      to,
      ".csv"
    )
  )
  if (file.exists(path)) {
    return(read_csv(
      path,
      col_types = cols(.default = "c"),
      show_col_types = FALSE
    ))
  }
  resp <- wb_request("https://web.archive.org/cdx/search/cdx") |>
    req_url_query(
      url = url,
      from = from,
      to = to,
      output = "json",
      fl = "timestamp,original,statuscode,length",
      filter = "statuscode:200",
      limit = 5000
    ) |>
    req_timeout(280) |>
    req_perform()
  raw <- resp_body_string(resp)
  out <- if (nchar(raw) < 5) {
    tibble(
      timestamp = character(),
      original = character(),
      statuscode = character(),
      length = character()
    )
  } else {
    m <- jsonlite::fromJSON(raw)
    as_tibble(m[-1, , drop = FALSE], .name_repair = "minimal") |>
      set_names(m[1, ])
  }
  write_csv(out, path)
  out
}

ts_to_posix <- \(ts) as.POSIXct(ts, format = "%Y%m%d%H%M%S", tz = "UTC")

# ---- old site ---------------------------------------------------------------------------------------------------
parse_county_count <- \(html) {
  tbl <- read_html(html) |>
    html_element("table") |>
    html_table(header = FALSE)
  contest <- tbl[[2]][1]
  body <- tbl[-(1:2), ] |> filter(!X1 %in% c("Total", ""))
  if (nrow(body) == 0) return(NULL)
  body |>
    mutate(across(-X1, parse_number)) |>
    mutate(counted = rowSums(pick(-X1), na.rm = TRUE)) |>
    select(county = X1, counted) |>
    mutate(contest = contest, n_candidates = ncol(tbl) - 1L)
}

fetch_old_site <- \(year) {
  caps <- cdx_list(
    "electionresults.utah.gov/elections/countyCount/*",
    str_c(year, "1101"),
    str_c(year, "1231")
  ) |>
    filter(!str_detect(original, "%5C|&")) |>
    mutate(contest_id = str_extract(original, "[0-9]+$"))
  cli::cli_alert_info("{year}: {nrow(caps)} countyCount captures")
  caps |>
    mutate(page = map2(timestamp, original, \(ts, u) wb_get(ts, u))) |>
    filter(!map_lgl(page, is.null)) |>
    mutate(
      served_ts = map_chr(page, "ts"),
      tbl = map(page, \(p) {
        tryCatch(parse_county_count(p$body), error = \(e) NULL)
      })
    ) |>
    filter(!map_lgl(tbl, is.null)) |>
    select(contest_id, timestamp = served_ts, tbl) |>
    unnest(tbl) |>
    mutate(county = normalize_county_name(county), election_year = year)
}

# ---- 2025 export --------------------------------------------------------------------------------------------------
parse_export_2025 <- \(json_text) {
  x <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)
  map(x$localResults, \(cty) {
    votes <- map(cty$ballotItems, \(bi) {
      map_dbl(bi$ballotOptions, \(o) o$voteCount %||% 0)
    }) |>
      unlist()
    tibble(county = cty$name, counted = sum(votes, na.rm = TRUE))
  }) |>
    list_rbind()
}

old <- map(c(2016L, 2018L, 2020L, 2022L), fetch_old_site) |> list_rbind()
write_csv(old, file.path(OUT_DIR, "old_site_raw_contest_county_snapshots.csv"))

# ---- old site: county pages (county-wide offices, one number per county and capture) and completion report ------------
parse_county_page <- \(html) {
  doc <- read_html(html)
  races <- doc |> html_elements("div.race-wrapper")
  tibble(
    contest_id = races |> html_attr("id"),
    contest = races |> html_element(".race-title") |> html_text2(),
    counted = races |> map_dbl(\(r) r |> html_elements("tbody tr td:last-child") |> html_text2() |> parse_number() |> sum(na.rm = TRUE))
  )
}

fetch_old_county_pages <- \(year) {
  caps <- cdx_list("electionresults.utah.gov/elections/county/*", str_c(year, "1101"), str_c(year, "1231")) |>
    mutate(county = str_match(original, "/elections/county/([a-zA-Z]+)")[, 2]) |>
    filter(!is.na(county), !county %in% c("0", "change", "click"))
  cli::cli_alert_info("{year}: {nrow(caps)} county-page captures")
  caps |>
    mutate(page = map2(timestamp, original, \(ts, u) wb_get(ts, u))) |>
    filter(!map_lgl(page, is.null)) |>
    mutate(served_ts = map_chr(page, "ts"), tbl = map(page, \(p) tryCatch(parse_county_page(p$body), error = \(e) NULL))) |>
    filter(!map_lgl(tbl, is.null)) |>
    select(county, timestamp = served_ts, tbl) |>
    unnest(tbl) |>
    mutate(county = str_replace_all(county, "([a-z])([A-Z])", "\\1 \\2") |> normalize_county_name(), election_year = year)
}

# One row per county and capture: when the county last released results ("Completed for <date> <time>", Mountain time).
parse_ccr <- \(html) {
  doc <- read_html(html)
  tbl <- doc |> html_element("table") |> html_table(header = FALSE)
  tibble(county = as.character(tbl[[1]]), status = as.character(tbl[[2]]), last_updated = as.character(tbl[[3]])) |>
    filter(county != "County", !is.na(last_updated))
}

fetch_ccr <- \(year) {
  cdx_list("electionresults.utah.gov/elections/ccr", str_c(year, "1101"), str_c(year, "1231")) |>
    mutate(page = map2(timestamp, original, \(ts, u) wb_get(ts, u))) |>
    filter(!map_lgl(page, is.null)) |>
    mutate(served_ts = map_chr(page, "ts"), tbl = map(page, \(p) tryCatch(parse_ccr(p$body), error = \(e) NULL))) |>
    filter(!map_lgl(tbl, is.null)) |>
    select(timestamp = served_ts, tbl) |>
    unnest(tbl) |>
    mutate(election_year = year)
}

years <- c(2016L, 2018L, 2020L, 2022L)
county_pages <- map(years, fetch_old_county_pages) |> list_rbind()
ccr <- map(years, fetch_ccr) |> list_rbind()
write_csv(county_pages, file.path(OUT_DIR, "old_site_county_page_snapshots.csv"))
write_csv(ccr, file.path(OUT_DIR, "old_site_completion_report.csv"))

# ---- Salt Lake County on Clarity (the only Utah Clarity feed the Wayback Machine holds) ------------------------------
fetch_clarity_slc <- \() {
  cdx_list("results.enr.clarityelections.com/UT/Salt_Lake/*", "20201101", "20221231") |>
    filter(str_detect(original, "/(107137|115463)/[0-9]+/json/sum\\.json")) |>
    mutate(page = map2(timestamp, original, \(ts, u) wb_get(ts, u))) |>
    filter(!map_lgl(page, is.null)) |>
    mutate(
      served_ts = map_chr(page, "ts"),
      counted = map_dbl(page, \(p) {
        x <- jsonlite::fromJSON(p$body, simplifyVector = FALSE)
        max(map_dbl(x$Contests, \(c) c$BC %||% 0))
      }),
      county = "Salt Lake",
      contest_id = str_extract(original, "(107137|115463)"),
      contest = "ballots cast (max over contests)",
      election_year = if_else(str_detect(original, "107137"), 2020L, 2022L)
    ) |>
    select(election_year, county, contest_id, contest, timestamp = served_ts, counted) |>
    distinct(election_year, timestamp, .keep_all = TRUE)
}

# ---- 2025 municipal general: sum of votes over every contest in a county ---------------------------------------------
fetch_export_2025 <- \() {
  cdx_list("electionresults.utah.gov/cdn/results/Utah/export-general11042025.json", "20251104", "20260301") |>
    mutate(page = map2(timestamp, original, \(ts, u) wb_get(ts, u))) |>
    filter(!map_lgl(page, is.null)) |>
    mutate(served_ts = map_chr(page, "ts"), tbl = map(page, \(p) parse_export_2025(p$body))) |>
    select(timestamp = served_ts, tbl) |>
    unnest(tbl) |>
    mutate(election_year = 2025L, contest_id = "all-contests", contest = "sum of votes over all municipal contests")
}

# Statewide totals (no county detail): used for the statewide pace curve only.
fetch_old_statewide <- \(year) {
  pages <- c("elections/federal", "elections/statewide", "elections/uscongress/0", "elections/senate/0", "elections/house/0")
  map(pages, \(pg) cdx_list(str_c("electionresults.utah.gov/", pg), str_c(year, "1101"), str_c(year, "1231"))) |>
    list_rbind() |>
    filter(!str_detect(original, "^http://")) |>
    mutate(page = map2(timestamp, original, \(ts, u) wb_get(ts, u))) |>
    filter(!map_lgl(page, is.null)) |>
    mutate(served_ts = map_chr(page, "ts"), tbl = map(page, \(p) tryCatch(parse_county_page(p$body), error = \(e) NULL))) |>
    filter(!map_lgl(tbl, is.null)) |>
    select(page_url = original, timestamp = served_ts, tbl) |>
    unnest(tbl) |>
    mutate(election_year = year)
}
statewide <- map(years, fetch_old_statewide) |> list_rbind()
write_csv(statewide, file.path(OUT_DIR, "old_site_statewide_snapshots.csv"))

clarity <- fetch_clarity_slc()
export25 <- fetch_export_2025()

# ---- assemble -----------------------------------------------------------------------------------------------------
fips_lookup <- utah_counties |> transmute(county = normalize_county_name(name), county_fips = fips)

series <- bind_rows(
  old |> mutate(source = "old_site_countyCount", contest_id = as.character(contest_id)),
  county_pages |> mutate(source = "old_site_county_page"),
  clarity |> mutate(source = "clarity_salt_lake"),
  export25 |> mutate(source = "export_2025_wayback")
) |>
  mutate(
    election_id = str_c(election_year, "-general"),
    timestamp = as.character(timestamp),
    timestamp_utc = ts_to_posix(timestamp),
    county = normalize_county_name(county)
  ) |>
  left_join(fips_lookup, by = "county") |>
  filter(!is.na(county_fips)) |>
  left_join(select(elections, election_id, close_utc), by = "election_id") |>
  mutate(hours_since_close = as.numeric(difftime(timestamp_utc, close_utc, units = "hours"))) |>
  distinct(election_id, source, contest_id, county_fips, timestamp, .keep_all = TRUE) |>
  arrange(election_id, source, contest_id, county_fips, timestamp_utc)

# Series "final" = the last capture of the same contest/county; flagged as certified-like when it was taken 10+ days after close.
series <- series |>
  mutate(
    n_snapshots = n(),
    final_counted = last(counted),
    final_ts = last(timestamp_utc),
    .by = c(election_id, source, contest_id, county_fips)
  ) |>
  mutate(
    final_days_after_close = as.numeric(difftime(final_ts, close_utc, units = "days")),
    frac_of_final = if_else(final_counted > 0, counted / final_counted, NA_real_)
  ) |>
  filter(n_snapshots >= 2, final_counted > 0)

fmt <- \(df) {
  df |>
    transmute(
      election_id, county_fips, county, timestamp_utc = format(timestamp_utc, "%Y-%m-%dT%H:%M:%SZ"),
      hours_since_close = round(hours_since_close, 2), counted, final_counted, frac_of_final = round(frac_of_final, 4), source,
      contest_id, contest, final_days_after_close = round(final_days_after_close, 1),
      final_reliable = final_days_after_close >= 10
    )
}
write_csv(fmt(series), file.path(OUT_DIR, "county_count_timeline_all_series.csv"))

# The headline file keeps, for each election/county/source, the contest with the most votes at the final capture
# (county-wide offices and top-of-ticket races are the best proxy for ballots counted).
main <- series |>
  mutate(rank_final = dense_rank(desc(final_counted)), .by = c(election_id, source, county_fips)) |>
  filter(rank_final == 1)
write_csv(fmt(main), file.path(OUT_DIR, "county_count_timeline.csv"))
cli::cli_alert_success("wrote {nrow(main)} rows ({n_distinct(main$election_id)} elections); all series: {nrow(series)} rows")
