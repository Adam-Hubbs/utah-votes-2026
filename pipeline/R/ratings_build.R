rating_scale <- c("Solid D", "Likely D", "Lean D", "Toss-up", "Lean R", "Likely R", "Solid R")

rating_sources <- tribble(
  ~id, ~name, ~url,
  "cook", "Cook Political Report", "https://www.cookpolitical.com/ratings/house-race-ratings",
  "sabato", "Sabato's Crystal Ball", "https://centerforpolitics.org/crystalball/2026-house/",
  "inside-elections", "Inside Elections", "https://insideelections.com/ratings/house",
  "ddhq", "Decision Desk HQ / The Hill", "https://decisiondeskhq.com/",
  "silver-bulletin", "Silver Bulletin (FLIPR)", "https://www.natesilver.net/p/nate-silver-2026-midterm-election-polls-model",
  "split-ticket", "Split Ticket", "https://split-ticket.org/",
  "race-to-the-wh", "Race to the WH", "https://www.racetothewh.com/",
  "fox-news", "Fox News Power Rankings", "https://www.foxnews.com/",
  "cnalysis", "CNalysis", "https://www.cnalysis.com/",
  "elections-daily", "Elections Daily", "https://electionsdaily.com/"
)

normalize_rating <- function(raw) {
  str_replace(raw, "^(Safe|Solid)", "Solid") |>
    str_replace("^Tilt", "Lean") |>
    str_replace("^Toss[- ]?up.*", "Toss-up")
}

build_ratings_json <- function(ratings, forecasts, sources = rating_sources) {
  verified <- ratings |> filter(!is.na(rating), rating != "") |> mutate(display = normalize_rating(rating))
  bad <- setdiff(verified$display, rating_scale)
  if (length(bad) > 0) stop("Ratings not on the 7-point scale: ", str_c(bad, collapse = ", "))

  by_contest <- \(col) verified |>
    group_split(contest_id) |>
    set_names(map_chr(group_split(verified, contest_id), \(d) d$contest_id[1])) |>
    map(\(d) set_names(as.list(d[[col]]), d$source_id))

  list(
    updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    sources = sources |> semi_join(verified, by = c("id" = "source_id")) |> pmap(list),
    ratings = by_contest("display"),
    # Safe -> Solid for display; the raw label is kept for transparency.
    raw = verified |> filter(display != rating) |> group_split(contest_id) |>
      (\(g) set_names(g, map_chr(g, \(d) d$contest_id[1])))() |>
      map(\(d) set_names(as.list(d$rating), d$source_id)),
    as_of = by_contest("as_of"),
    urls = by_contest("url"),
    scale = rating_scale,
    forecasts = forecasts |>
      group_split(contest_id) |>
      (\(g) set_names(g, map_chr(g, \(d) d$contest_id[1])))() |>
      map(\(d) d |> select(source, prob_dem, as_of, url) |> pmap(list))
  )
}
