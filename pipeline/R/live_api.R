library(httr2)

EV_BASE <- "https://electionresults.utah.gov"
EV_UA <- "utah-elections-site/0.1 (static results mirror; contact adam@y2analytics.com)"

ev_request <- function(url, timeout = 60) {
  request(url) |>
    req_user_agent(EV_UA) |>
    req_timeout(timeout) |>
    req_retry(
      max_tries = 4,
      backoff = \(i) 2^i,
      is_transient = \(r) resp_status(r) %in% c(429, 500, 502, 503, 504)
    )
}

ev_get_json <- function(url, timeout = 60) {
  ev_request(url, timeout) |>
    req_perform() |>
    resp_body_json(simplifyVector = FALSE)
}

ev_election_id <- function(default = "General11032026") {
  Sys.getenv("UTEL_ELECTION_ID", unset = default)
}

ev_export_url <- function(election_id = ev_election_id()) {
  str_c(EV_BASE, "/cdn/results/Utah/export-", election_id, ".json")
}

ev_data_url <- function(
  election_id = ev_election_id(),
  jurisdiction = "Utah",
  endpoint = "data"
) {
  str_c(
    EV_BASE,
    "/results/public/api/elections/",
    jurisdiction,
    "/",
    election_id,
    "/",
    endpoint
  )
}

# Cheap HEAD request so unchanged exports are never re-downloaded.
ev_export_etag <- function(url = ev_export_url()) {
  resp <- ev_request(url, timeout = 20) |>
    req_method("HEAD") |>
    req_error(is_error = \(r) FALSE) |>
    req_perform()
  list(
    status = resp_status(resp),
    etag = resp_header(resp, "etag"),
    last_modified = resp_header(resp, "last-modified")
  )
}

ev_download_export <- function(
  url = ev_export_url(),
  dest = raw_dir("live", "export-latest.json")
) {
  ev_request(url, timeout = 180) |> req_perform(path = dest)
  dest
}

connectivity_check <- function() {
  targets <- c(
    jurisdiction = str_c(EV_BASE, "/results/public/api/jurisdictions/Utah"),
    data = ev_data_url(),
    export = ev_export_url()
  )
  results <- map2(names(targets), targets, \(nm, u) {
    out <- tryCatch(
      {
        resp <- ev_request(u, timeout = 20) |>
          req_method(if_else(nm == "export", "HEAD", "GET")) |>
          req_error(is_error = \(r) FALSE) |>
          req_perform()
        tibble(
          target = nm,
          status = resp_status(resp),
          ok = resp_status(resp) < 400
        )
      },
      error = \(e) tibble(target = nm, status = NA_integer_, ok = FALSE)
    )
    out
  }) |>
    list_rbind()
  for (i in seq_len(nrow(results))) {
    message(sprintf(
      "[connectivity] %-12s status=%s %s",
      results$target[i],
      results$status[i],
      if_else(results$ok[i], "OK", "FAILED")
    ))
  }
  results
}

# 2026 judges are the only statewide-style contests identified by a sentence, so the regex is kept here
# next to the other name parsing helpers.
RETENTION_RE <- regex(
  "^Shall (.+?) be retained in the office of (.+?)\\??$",
  ignore_case = TRUE
)

title_name <- function(x) {
  x |>
    str_to_lower() |>
    str_to_title() |>
    str_replace_all(
      "\\bMc([a-z])",
      \(m) str_c("Mc", str_to_upper(str_sub(m, 3, 3)))
    ) |>
    str_replace_all("\\bMac(?=[A-Z])", "Mac") |>
    str_replace_all(
      "\\bO'([a-z])",
      \(m) str_c("O'", str_to_upper(str_sub(m, 3, 3)))
    ) |>
    str_replace_all("\\b(Ii|Iii|Iv)\\b", \(m) str_to_upper(m)) |>
    str_replace_all("\\bJr\\b", "Jr.") |>
    str_replace_all("\\b(Of|The|And)\\b", \(m) str_to_lower(m))
}

# Maps a raw ballot-item name to the canonical contest identity; NA contest_id means "not a state-level
# contest" (county commission, municipal justice court, school districts, ...), which the site ignores.
classify_contest <- function(name, contest_type = NA_character_) {
  nm <- str_squish(name)
  tibble(raw = nm) |>
    mutate(
      num = str_extract(nm, "(?<=\\b)\\d+(?=\\b|\\s*\\()") |> as.integer(),
      amend = str_match(
        nm,
        regex("^Constitutional Amendment ([A-Z])\\b", ignore_case = TRUE)
      )[, 2],
      retention = str_detect(nm, RETENTION_RE),
      kind = case_when(
        str_detect(nm, regex("^U\\.?S\\.? House", ignore_case = TRUE)) ~
          "us-house",
        !is.na(amend) ~ "amendment",
        str_detect(nm, regex("^(Utah )?State House", ignore_case = TRUE)) ~
          "state-house",
        str_detect(nm, regex("^(Utah )?State Senate", ignore_case = TRUE)) ~
          "state-senate",
        str_detect(nm, regex("^(Utah )?State School Board", ignore_case = TRUE)) ~
          "school-board",
        retention ~ "retention",
        .default = NA_character_
      )
    ) |>
    mutate(
      judge = if_else(
        retention,
        str_match(nm, RETENTION_RE)[, 2],
        NA_character_
      ),
      court = if_else(
        retention,
        str_match(nm, RETENTION_RE)[, 3],
        NA_character_
      ),
      contest_id = case_when(
        kind %in% c("us-house", "state-house", "state-senate", "school-board") ~
          str_c(kind, "-", num),
        kind == "amendment" ~ str_c("amendment-", str_to_lower(amend)),
        kind == "retention" ~ str_c("retention-", slugify(judge)),
        .default = NA_character_
      ),
      display = case_when(
        kind == "us-house" ~ str_c("U.S. House District ", num),
        kind == "amendment" ~ str_c("Constitutional Amendment ", amend),
        kind == "state-house" ~ str_c("Utah House District ", num),
        kind == "state-senate" ~ str_c("Utah Senate District ", num),
        kind == "school-board" ~ str_c("State School Board District ", num),
        kind == "retention" ~
          str_c(
            "Retain ",
            if_else(
              str_detect(court, regex("Supreme Court", ignore_case = TRUE)),
              "Justice ",
              "Judge "
            ),
            title_name(judge),
            "?"
          ),
        .default = NA_character_
      ),
      measure = kind %in% c("amendment", "retention")
    ) |>
    select(contest_id, kind, district = num, display, measure, judge, court)
}

# Candidate id/display rules: strip middle names/initials/suffixes; a quoted nickname replaces the first name.
parse_ballot_name <- function(ballot_name) {
  raw <- str_squish(ballot_name)
  nick <- str_match(raw, "[\"“]([^\"”]+)[\"”]")[, 2]
  clean <- raw |>
    str_remove_all("[\"“”]") |>
    str_replace("^[A-Za-z]{1,2},\\s+", "") |>
    str_remove_all(regex("[,.]?\\s+(JR|SR|II|III|IV)\\.?$", ignore_case = TRUE))
  toks <- str_split(str_remove_all(clean, "\\."), "\\s+")
  first <- map_chr(toks, \(t) t[1])
  last <- map_chr(toks, \(t) t[length(t)])
  first <- if_else(!is.na(nick), nick, first)
  # "J. LOWRY SNOW" style: a lone initial is not a usable first name
  first <- if_else(str_length(first) == 1 & map_int(toks, length) > 2, map_chr(toks, \(t) t[2]), first)
  tibble(
    ballot_name = raw,
    first = first,
    last = last,
    display_name = title_name(str_c(first, " ", last)) |>
      str_replace_all("\\b(Cj|Jr|Tj|Dj|Aj|Jd|Jb)\\b", \(m) str_to_upper(m)),
    candidate_id = slugify(str_c(first, " ", last))
  ) |>
    mutate(
      is_write_in = str_detect(raw, regex("^write[- ]?in", ignore_case = TRUE)),
      display_name = if_else(is_write_in, "Write-in", display_name),
      candidate_id = if_else(is_write_in, "write-in", candidate_id)
    ) |>
    select(-is_write_in)
}

PARTY_PREFIXES <- c(REP = "REP", DEM = "DEM", FWD = "FWD", CON = "CON", LIB = "LIB", IAP = "IAP", UUP = "UUP", GRN = "GRN", UNA = "UNA")

# County-only legislative contests print the party as a name prefix ("DEM JARED NEAL").
split_party_prefix <- function(ballot_name) {
  m <- str_match(ballot_name, "^(REP|DEM|FWD|CON|LIB|IAP|UUP|GRN|UNA)\\s+(.+)$")
  tibble(ballot_name = coalesce(m[, 3], ballot_name), prefix_party = m[, 2])
}

party_from_text <- function(x) {
  recode_values(
    str_to_lower(str_squish(x)) |> str_remove("\\s+party$"),
    from = c("republican", "democratic", "libertarian", "constitution", "independent american", "unaffiliated", "nonpartisan", "forward", "forward party", "green", "united utah"),
    to = c("REP", "DEM", "LIB", "CON", "IAP", "UNA", "UNA", "FWD", "FWD", "GRN", "UUP"),
    default = if_else(is.na(x) | x == "", NA_character_, "OTH")
  )
}

as_int0 <- function(x) {
  v <- suppressWarnings(as.numeric(x %||% 0))
  if_else(is.na(v), 0, v)
}

# Flattens the Enhanced Voting media export for state-level contests only. Returns one row per
# county x contest x option, plus a precinct-level table. `keep_precincts = FALSE` skips the heavy part.
parse_export <- function(j, keep_precincts = TRUE) {
  stopifnot(is.list(j), !is.null(j$localResults), length(j$localResults) > 0)
  county_tbl <- map(j$localResults, \(lr) {
    items <- lr$ballotItems %||% list()
    cls <- classify_contest(map_chr(items, \(b) b$name %||% ""))
    keep <- which(!is.na(cls$contest_id))
    fips <- county_fips_from_name(lr$name)
    if (is.na(fips)) stop("Unrecognized county name in export: ", lr$name)
    map(keep, \(i) {
      b <- items[[i]]
      opts <- b$ballotOptions %||% list()
      list(
        opt = tibble(
          fips = fips,
          county = normalize_county_name(lr$name),
          contest_id = cls$contest_id[i],
          raw_name = str_squish(b$name),
          option_id = map_chr(opts, \(o) as.character(o$id %||% NA)),
          ballot_name = map_chr(opts, \(o) str_squish(o$name %||% "")),
          party_raw = map_chr(opts, \(o) o$politicalParty %||% NA_character_),
          option_order = map_int(opts, \(o) as.integer(o$ballotOrder %||% NA)),
          votes = map_dbl(opts, \(o) as_int0(o$voteCount)),
          precincts_total = as_int0(b$precinctsParticipating),
          precincts_reporting = as_int0(b$precinctsReporting)
        ),
        prec = if (keep_precincts) {
          map2(opts, seq_along(opts), \(o, k) {
            pr <- o$precinctResults %||% list()
            if (length(pr) == 0) return(NULL)
            tibble(
              fips = fips,
              contest_id = cls$contest_id[i],
              ballot_name = split_party_prefix(str_squish(o$name %||% ""))$ballot_name,
              precinct_name = map_chr(pr, \(p) p$name %||% NA_character_),
              votes = map_dbl(pr, \(p) as_int0(p$voteCount)),
              status = map_chr(pr, \(p) p$reportingStatus %||% NA_character_)
            )
          }) |>
            list_rbind()
        } else {
          NULL
        }
      )
    })
  }) |>
    list_flatten()
  list(
    classes = j$localResults |>
      map(
        \(lr)
          classify_contest(map_chr(
            lr$ballotItems %||% list(),
            \(b) b$name %||% ""
          )) |>
            mutate(
              raw = map_chr(
                lr$ballotItems %||% list(),
                \(b) str_squish(b$name %||% "")
              )
            )
      ) |>
      list_rbind() |>
      filter(!is.na(contest_id)) |>
      distinct(contest_id, .keep_all = TRUE),
    options = map(county_tbl, "opt") |>
      list_rbind() |>
      mutate(
        pp = split_party_prefix(ballot_name),
        ballot_name = pp$ballot_name,
        party = coalesce(party_from_text(party_raw), pp$prefix_party)
      ) |>
      select(-pp),
    precincts = map(county_tbl, "prec") |> list_rbind(),
    created_at = j$createdAt %||% NA_character_
  )
}

parse_state_data <- function(d) {
  winners <- tryCatch(parse_official_winners(d), error = \(e) tibble(contest_id = character(), ballot_name = character()))
  e <- d$election %||% list()
  list(
    as_of = e$asOf %||% NA_character_,
    last_updated = e$lastUpdated %||% NA_character_,
    official = isTRUE(e$isOfficialResults),
    winners = winners,
    next_update_at = e$nextUpdateAt %||% NA_character_,
    ballots_cast = as_int0(e$ballotsCast),
    registered = d$voterRegistration |>
      map(
        \(v)
          tibble(
            county = normalize_county_name(
              v$localityName[[1]]$text %||% NA_character_
            ),
            active = as_int0(v$activeVoters),
            inactive = as_int0(v$inactiveVoters)
          )
      ) |>
      list_rbind()
  )
}

# The export only carries precinct detail; election-level metadata lives in /data. A failure there is
# not fatal because the export alone is enough to publish votes.
fetch_state_data <- function(election_id = ev_election_id()) {
  tryCatch(
    parse_state_data(ev_get_json(ev_data_url(election_id))),
    error = \(e) {
      message("[scrape] /data unavailable: ", conditionMessage(e))
      NULL
    }
  )
}

ev_text <- function(x) x[[1]]$text %||% NA_character_

parse_county_data <- function(d, county_name) {
  fips <- county_fips_from_name(county_name)
  items <- d$ballotItems %||% list()
  cls <- classify_contest(map_chr(items, \(b) ev_text(b$name)))
  map(which(!is.na(cls$contest_id)), \(i) {
    b <- items[[i]]
    opts <- b$summaryResults$ballotOptions %||% list()
    tibble(
      fips = fips,
      county = normalize_county_name(county_name),
      contest_id = cls$contest_id[i],
      raw_name = str_squish(ev_text(b$name)),
      option_id = map_chr(opts, \(o) o$id %||% NA_character_),
      ballot_name = map_chr(opts, \(o) str_squish(ev_text(o$name))),
      party_raw = map_chr(opts, \(o) o$party$name[[1]]$text %||% NA_character_),
      option_order = seq_along(opts),
      votes = map_dbl(opts, \(o) as_int0(o$voteCount)),
      precincts_total = as_int0(b$reportingStatus$totalUnits),
      precincts_reporting = as_int0(b$reportingStatus$reportingUnits)
    )
  }) |>
    list_rbind()
}

# Fallback when the media export is unavailable: one /data call per county (no precinct detail).
fetch_fallback_parsed <- function(election_id = ev_election_id()) {
  jur <- ev_get_json(str_c(EV_BASE, "/results/public/api/jurisdictions/Utah"))
  kids <- jur$childLocalities |>
    map(\(k) tibble(short = k$shortName, name = ev_text(k$name))) |>
    list_rbind()
  options <- map2(kids$short, kids$name, \(s, nm) {
    parse_county_data(ev_get_json(ev_data_url(election_id, s)), nm)
  }) |>
    list_rbind() |>
    mutate(
      pp = split_party_prefix(ballot_name),
      ballot_name = pp$ballot_name,
      party = coalesce(party_from_text(party_raw), pp$prefix_party)
    ) |>
    select(-pp)
  classes <- options |>
    distinct(contest_id, raw_name) |>
    mutate(cls = classify_contest(raw_name)) |>
    unnest(cls, names_sep = "_") |>
    transmute(contest_id, kind = cls_kind, district = cls_district, display = cls_display, measure = cls_measure, judge = cls_judge, court = cls_court, raw = raw_name) |>
    distinct(contest_id, .keep_all = TRUE)
  list(classes = classes, options = options, precincts = NULL, created_at = NA_character_)
}

# Official winners (isWinner) are only trusted from the statewide /data once the election is certified.
parse_official_winners <- function(d) {
  items <- d$ballotItems %||% list()
  cls <- classify_contest(map_chr(items, \(b) ev_text(b$name)))
  map(which(!is.na(cls$contest_id)), \(i) {
    opts <- items[[i]]$summaryResults$ballotOptions %||% list()
    win <- keep(opts, \(o) isTRUE(o$isWinner))
    if (length(win) == 0) return(NULL)
    tibble(contest_id = cls$contest_id[i], ballot_name = map_chr(win, \(o) str_squish(ev_text(o$name))))
  }) |>
    list_rbind()
}
