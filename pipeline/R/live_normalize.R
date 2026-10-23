ELECTION_ID <- "2026-general"
ELECTION_NAME <- "2026 General Election"
ELECTION_DATE <- "2026-11-03"

CONTEST_DESCRIPTIONS <- file.path(project_root(), "pipeline", "config", "measures.json") |>
  read_json() |>
  map(\(m) m$summary)

live_config <- function() {
  path <- file.path(project_root(), "pipeline", "config", "live.yml")
  defaults <- list(
    precinct_kinds = c(
      "us-house",
      "amendment",
      "state-house",
      "state-senate",
      "school-board"
    ),
    featured_kinds = c("us-house", "amendment"),
    timeline_kinds = c("us-house", "amendment"),
    max_vote_drop_fraction = 0.2,
    model = list()
  )
  if (!file.exists(path)) return(defaults)
  utils::modifyList(defaults, yaml::read_yaml(path))
}

read_candidates <- function() {
  read_csv(
    file.path(project_root(), "pipeline", "config", "candidates.csv"),
    col_types = cols(.default = col_character(), incumbent = col_logical()),
    show_col_types = FALSE
  )
}

MEASURE_LABELS <- c(`for` = "For", against = "Against", yes = "Yes", no = "No")

kind_order <- c(
  "us-house",
  "amendment",
  "state-senate",
  "state-house",
  "school-board",
  "retention"
)

# Joins export option rows to canonical candidate identity. Unknown names are never dropped: they get a slug
# and a warning so a late filing/withdrawal cannot silently lose votes.
attach_candidates <- function(options, classes, candidates) {
  opts <- options |>
    left_join(select(classes, contest_id, kind, measure), by = "contest_id") |>
    mutate(key = str_to_upper(ballot_name))
  parsed <- parse_ballot_name(opts$ballot_name) |>
    select(parsed_id = candidate_id, parsed_name = display_name)
  opts <- bind_cols(opts, parsed) |>
    left_join(
      candidates |>
        transmute(
          contest_id,
          key = str_to_upper(ballot_name),
          cand_id = candidate_id,
          cand_name = display_name,
          cand_party = party,
          incumbent
        ),
      by = c("contest_id", "key")
    )
  unknown <- opts |>
    filter(!measure, is.na(cand_id)) |>
    distinct(contest_id, ballot_name)
  if (nrow(unknown) > 0) {
    warning(
      "Candidates missing from candidates.csv: ",
      str_c(unknown$contest_id, ":", unknown$ballot_name, collapse = "; "),
      call. = FALSE
    )
  }
  opts |>
    mutate(
      candidate_id = case_when(
        measure ~ str_to_lower(ballot_name),
        .default = coalesce(cand_id, parsed_id)
      ),
      name = case_when(
        measure ~
          coalesce(
            unname(MEASURE_LABELS[str_to_lower(ballot_name)]),
            str_to_title(ballot_name)
          ),
        .default = coalesce(cand_name, parsed_name)
      ),
      party = if_else(
        measure,
        NA_character_,
        coalesce(cand_party, party, "OTH")
      ),
      incumbent = coalesce(incumbent, FALSE)
    ) |>
    select(-key, -cand_id, -cand_name, -cand_party, -parsed_id, -parsed_name)
}

votes_list <- function(ids, votes) {
  as.list(set_names(votes, ids))
}

# Seats up in a contest (the export's voteFor); absent in the per-county fallback feed, where 1 is the safe default.
contest_seats <- function(options, cid) {
  if (!hasName(options, "vote_for")) return(1L)
  seats <- options |>
    filter(contest_id == cid) |>
    pull(vote_for) |>
    max(na.rm = TRUE)
  if_else(is.finite(seats) && seats >= 1, as.integer(seats), 1L)
}

# Applied only once results are official. Top `seats` vote-getters win; measures and retention are a single
# seat between For/Yes and Against/No, which is the same as clearing 50%. A tie at the cutoff awards nothing.
auto_winners <- function(cand_rows, seats) {
  ranked <- arrange(cand_rows, desc(votes))
  if (nrow(ranked) == 0 || sum(ranked$votes) <= 0) return(character())
  if (nrow(ranked) <= seats) return(ranked$candidate_id)
  if (ranked$votes[seats] == ranked$votes[seats + 1]) return(character())
  ranked$candidate_id[seq_len(seats)]
}

# Builds every output object from parsed options/precincts. Pure function: no I/O, so the same code serves the
# live scrape, the pre-election zero file and the simulator.
build_results <- function(
  parsed,
  candidates,
  election_id = ELECTION_ID,
  status = "pre",
  as_of = NA_character_,
  official = FALSE,
  official_winners = NULL,
  updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  cfg = live_config()
) {
  classes <- parsed$classes
  opts <- attach_candidates(parsed$options, classes, candidates)

  merged <- opts |>
    summarise(
      votes = sum(votes),
      option_order = min(option_order, na.rm = TRUE),
      precincts_total = max(precincts_total),
      .by = c(fips, county, contest_id, candidate_id, name, party, incumbent)
    )

  county_tot <- merged |>
    summarise(
      total = sum(votes),
      precincts_total = max(precincts_total),
      .by = c(fips, county, contest_id)
    )
  county_top <- county_tot |>
    summarise(
      top = max(total),
      county_precincts = max(precincts_total),
      .by = fips
    ) |>
    mutate(ballots_counted = round(top / VOTE_PER_BALLOT))

  contests <- classes |>
    mutate(
      kind_rank = match(kind, kind_order),
      district = coalesce(district, 0L)
    ) |>
    arrange(kind_rank, district, display)

  prec <- parsed$precincts
  has_prec <- !is.null(prec) && nrow(prec) > 0

  per_contest <- map(contests$contest_id, \(cid) {
    cl <- filter(contests, contest_id == cid)
    cand_rows <- merged |>
      filter(contest_id == cid) |>
      summarise(
        votes = sum(votes),
        option_order = min(option_order),
        .by = c(candidate_id, name, party, incumbent)
      )
    cand_rows <- cand_rows |> arrange(desc(votes), option_order)
    ids <- cand_rows$candidate_id
    seats <- contest_seats(parsed$options, cid)
    winner_ids <- if (!is.null(official_winners) && any(official_winners$contest_id == cid)) {
      filter(official_winners, contest_id == cid)$candidate_id
    } else if (official) {
      auto_winners(cand_rows, seats)
    } else {
      character()
    }
    ct <- county_tot |>
      filter(contest_id == cid) |>
      left_join(county_top, by = "fips") |>
      mutate(
        ballot_share = pmin(precincts_total / pmax(county_precincts, 1), 1)
      ) |>
      arrange(fips)
    county_rows <- map(seq_len(nrow(ct)), \(i) {
      v <- merged |> filter(contest_id == cid, fips == ct$fips[i])
      v <- v[match(ids, v$candidate_id), ]
      vv <- coalesce(v$votes, 0)
      list(
        fips = ct$fips[i],
        name = ct$county[i],
        votes = votes_list(ids, vv),
        total = ct$total[i],
        ballots_counted = ct$ballots_counted[i],
        expected_ballots = ct$ballots_counted[i],
        pct_expected = 0,
        pct_expected_lo = 0,
        pct_expected_hi = 0,
        ballot_share = round(ct$ballot_share[i], 4)
      )
    })
    precinct_rows <- if (has_prec && cl$kind %in% cfg$precinct_kinds) {
      p <- prec |>
        filter(contest_id == cid) |>
        left_join(
          distinct(opts, contest_id, ballot_name, candidate_id),
          by = c("contest_id", "ballot_name")
        ) |>
        summarise(
          votes = sum(votes),
          .by = c(fips, precinct_name, candidate_id)
        )
      p |>
        mutate(precinct_id = precinct_key(fips, precinct_name)) |>
        arrange(precinct_id) |>
        group_by(precinct_id) |>
        group_map(\(g, k) {
          vv <- g$votes[match(ids, g$candidate_id)] |> coalesce(0)
          list(
            precinct_id = k$precinct_id,
            votes = votes_list(ids, vv),
            total = sum(vv)
          )
        }) |>
        unname()
    } else {
      list()
    }
    total_votes <- sum(cand_rows$votes)
    cand_summary <- pmap(
      list(
        cand_rows$candidate_id,
        cand_rows$name,
        cand_rows$party,
        cand_rows$incumbent,
        cand_rows$votes
      ),
      \(id, nm, pa, inc, vt) {
        list(
          candidate_id = id,
          name = nm,
          party = pa,
          incumbent = inc,
          votes = vt,
          pct = if_else(total_votes > 0, vt / total_votes, 0),
          winner = id %in% winner_ids
        )
      }
    )
    desc <- CONTEST_DESCRIPTIONS[[cid]] %||%
      if_else(
        cl$kind == "retention",
        str_c(
          "Judicial retention election for ",
          str_to_lower(str_sub(cl$court, 1, 1)),
          str_sub(cl$court, 2),
          ". Voters decide whether the judge stays in office for another term."
        ),
        NA_character_
      )
    counties_reporting <- sum(ct$total > 0)
    summary_entry <- list(
      contest_id = cid,
      name = cl$display,
      office = cl$kind,
      district = if (
        cl$kind %in%
          c("us-house", "state-house", "state-senate", "school-board")
      )
        cl$district else NULL,
      type = if_else(cl$measure, "measure", "candidate"),
      featured = cl$kind %in% cfg$featured_kinds,
      total_votes = total_votes,
      candidates = cand_summary,
      reporting = list(
        counties_reporting = counties_reporting,
        counties_total = nrow(ct),
        pct_expected = 0,
        pct_expected_lo = 0,
        pct_expected_hi = 0
      )
    )
    if (!is.na(desc)) summary_entry$description <- desc
    file_entry <- list(
      contest_id = cid,
      election_id = election_id,
      updated_at = updated_at,
      candidates = map(
        cand_summary,
        \(c) c[c("candidate_id", "name", "party")]
      ),
      counties = county_rows,
      precincts = precinct_rows
    )
    list(summary = summary_entry, file = file_entry)
  }) |>
    set_names(contests$contest_id)

  total_ballots <- sum(county_top$ballots_counted)
  summary <- list(
    election_id = election_id,
    name = if_else(
      election_id == ELECTION_ID,
      ELECTION_NAME,
      str_c(ELECTION_NAME, " (simulation)")
    ),
    date = ELECTION_DATE,
    status = status,
    updated_at = updated_at,
    source = "electionresults.utah.gov",
    as_of = as_of,
    precinct_geo = "precincts_2026",
    cd_plan = "cd2026",
    turnout = list(
      ballots_counted = total_ballots,
      registered = NA_real_,
      expected_ballots = NA_real_,
      expected_lo = NA_real_,
      expected_hi = NA_real_,
      pct_expected = 0
    ),
    contests = map(per_contest, "summary") |> unname()
  )
  list(
    summary = summary,
    contests = map(per_contest, "file"),
    counted_total = total_ballots,
    max_votes = max(map_dbl(per_contest, \(x) x$summary$total_votes))
  )
}

featured_ids <- function(results) {
  results$summary$contests |>
    keep(\(c) isTRUE(c$featured)) |>
    map_chr("contest_id")
}

# Appends a timeline snapshot only when a tracked contest's totals changed.
update_timeline <- function(path, results, cfg, t) {
  tl <- if (file.exists(path))
    jsonlite::read_json(path, simplifyVector = FALSE) else
    list(contests = list())
  tl$contests <- tl$contests %||% list()
  tracked <- results$summary$contests |>
    keep(\(c) c$office %in% cfg$timeline_kinds)
  for (c in tracked) {
    snap <- list(
      t = t,
      votes = map(c$candidates, \(x) x$votes) |>
        set_names(map_chr(c$candidates, "candidate_id")),
      total = c$total_votes
    )
    hist <- tl$contests[[c$contest_id]] %||% list()
    last <- if (length(hist) > 0) hist[[length(hist)]] else NULL
    if (c$total_votes > 0 && (is.null(last) || last$total != c$total_votes)) {
      tl$contests[[c$contest_id]] <- c(hist, list(snap))
    }
  }
  tl
}

write_results <- function(results, out_dir, timeline = NULL) {
  dir.create(
    file.path(out_dir, "contests"),
    recursive = TRUE,
    showWarnings = FALSE
  )
  write_json_file(results$summary, file.path(out_dir, "summary.json"))
  iwalk(
    results$contests,
    \(x, id)
      write_json_file(x, file.path(out_dir, "contests", str_c(id, ".json")))
  )
  if (!is.null(timeline))
    write_json_file(timeline, file.path(out_dir, "timeline.json"))
  stale <- setdiff(
    list.files(file.path(out_dir, "contests"), pattern = "\\.json$"),
    str_c(names(results$contests), ".json")
  )
  if (length(stale) > 0) unlink(file.path(out_dir, "contests", stale))
  invisible(out_dir)
}

write_site_config <- function(live_mode, featured) {
  write_site_json(
    list(
      current_election = ELECTION_ID,
      election_date = ELECTION_DATE,
      polls_close_utc = "2026-11-04T03:00:00Z",
      live_mode = live_mode,
      live_data_base = "data/results",
      featured_contests = featured
    ),
    "config.json"
  )
}

iso_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

# Copies a staging directory over the published one only after the model succeeded.
publish_dir <- function(staging, dest) {
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  files <- list.files(staging, recursive = TRUE)
  walk(files, \(f) {
    dir.create(
      dirname(file.path(dest, f)),
      recursive = TRUE,
      showWarnings = FALSE
    )
    file.copy(file.path(staging, f), file.path(dest, f), overwrite = TRUE)
  })
  stale <- setdiff(
    list.files(file.path(dest, "contests")),
    list.files(file.path(staging, "contests"))
  )
  if (length(stale) > 0) unlink(file.path(dest, "contests", stale))
  invisible(dest)
}

KNOWN_INCUMBENTS <- c("us-house-2:blake-moore", "us-house-3:celeste-maloy", "us-house-4:mike-kennedy")

# Display-name fixes for ballot names the generic parser cannot get right.
NAME_OVERRIDES <- tribble(
  ~ballot_name, ~candidate_id, ~display_name,
  "J. LOWRY SNOW", "lowry-snow", "J. Lowry Snow",
  "A, DANE ANDERSON", "dane-anderson", "Dane Anderson"
)

# Builds the candidate table from an export. Existing rows in candidates.csv win so hand edits survive re-runs.
generate_candidates <- function(parsed, existing = NULL) {
  gen <- parsed$options |>
    left_join(select(parsed$classes, contest_id, measure, kind), by = "contest_id") |>
    filter(!measure) |>
    summarise(
      party = first(party[!is.na(party)], default = NA_character_),
      option_order = min(option_order, na.rm = TRUE),
      .by = c(contest_id, ballot_name)
    ) |>
    mutate(parsed = parse_ballot_name(ballot_name)) |>
    unnest(parsed, names_sep = "_") |>
    transmute(
      contest_id, ballot_name,
      candidate_id = parsed_candidate_id,
      display_name = parsed_display_name,
      party = coalesce(party, "OTH"),
      option_order
    ) |>
    arrange(contest_id, option_order) |>
    distinct(contest_id, ballot_name, .keep_all = TRUE) |>
    left_join(NAME_OVERRIDES, by = "ballot_name", suffix = c("", ".o")) |>
    mutate(
      candidate_id = coalesce(candidate_id.o, candidate_id),
      display_name = coalesce(display_name.o, display_name),
      incumbent = str_c(contest_id, ":", candidate_id) %in% KNOWN_INCUMBENTS,
      website = NA_character_,
      note = case_when(
        party == "OTH" & candidate_id != "write-in" ~ "TODO: party unknown",
        str_detect(contest_id, "^(state-|school-)") ~ "incumbency not researched",
        .default = NA_character_
      )
    ) |>
    select(contest_id, candidate_id, ballot_name, display_name, party, incumbent, website, note)
  if (is.null(existing)) return(gen)
  gen |>
    anti_join(existing, by = c("contest_id", "ballot_name")) |>
    bind_rows(existing, y = _) |>
    arrange(contest_id)
}

candidates_json <- function(candidates) {
  candidates |>
    arrange(contest_id) |>
    group_by(contest_id) |>
    group_map(\(g, k) {
      pmap(g, \(candidate_id, display_name, party, incumbent, website, ...) {
        list(
          candidate_id = candidate_id, name = display_name, party = party,
          incumbent = isTRUE(incumbent), bio = NULL, website = if (is.na(website)) NULL else website
        )
      })
    }) |>
    set_names(sort(unique(candidates$contest_id)))
}
