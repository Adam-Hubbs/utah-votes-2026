# Votes counted per county over time (historical)

Built by `pipeline/scripts/build_count_timeline.R` from Wayback Machine captures of the Lt. Governor's results sites.
Downloads are cached in `$UTEL_RAW_DIR/timing/` (not in git); requests are throttled to 40/min with retry/backoff.

## Files

| file | content |
|---|---|
| `county_count_timeline.csv` | one row per election, county and capture; the contest with the most votes per county/source |
| `county_count_timeline_all_series.csv` | every (contest, county) series with at least two captures |
| `old_site_raw_contest_county_snapshots.csv` | every parsed `countyCount/<contest id>` table (all contests, 2016-2022) |
| `old_site_county_page_snapshots.csv` | county-page contest totals (county offices) per capture |
| `old_site_statewide_snapshots.csv` | statewide pages (`federal`, `statewide`, `uscongress/0`, ...): statewide totals only |
| `old_site_completion_report.csv` | the "County Completion Report" status page per capture (last-update stamp per county) |

Columns of the two timeline files: `election_id, county_fips, county, timestamp_utc, hours_since_close, counted, final_counted,
frac_of_final, source, contest_id, contest, final_days_after_close, final_reliable`.
`counted` is the sum of candidate votes in the contest (not ballots; top-of-ticket votes are about 99 % of ballots cast).
`final_counted` is the last capture of the same series; `final_reliable` is true only when that capture is 10+ days after close
(certified-like). Polls close 03:00 UTC the day after Election Day.

## Coverage

| election | what exists | usable early points (county level) |
|---|---|---|
| 2016 general | President / Governor / amendments, 29 counties, county pages | none before +43 h |
| 2018 general | Proposition 2 (29 counties, +16 h) and Senate (statewide only, +29 h) | one county vector (Prop 2) |
| 2020 general | President (29 counties) at +97 h, +107 h; statewide Governor at +21 h | none before +97 h |
| 2022 general | Senate (29 counties) at +22 h and 2022-11-30 final; U.S. House 1/2 (+8 h, +22 h); statewide Senate at +12.6 h; Davis, Utah, Weber county pages; Salt Lake on Clarity at +2 h, +23 h, +66 h | one full county vector at +22 h |
| 2024 general | nothing: the new site's APIs were only captured after canvass (`turnout`/`stats` endpoints are empty) | none |
| 2025 municipal general | export captured at -0.5 h (zeros), +19 h, and final (sum of votes in all municipal contests, 26 counties) | one vector at +19 h |

The old site (`electionresults.utah.gov/elections/...`, 2014-2022) is the useful source. Clarity ENR is blocked (403) on the live
host and Wayback holds Clarity only for Salt Lake County (2019-2022). Salt Lake's Clarity "ballots cast" series ends at 263,191 on
2022-11-11 although the canvassed county total is about 381,000, so treat its `final_counted` as not final.

## Caveats

* Capture time is when the Wayback crawler fetched the page (the page refreshed every 60 s); results may be slightly older.
* Pre-election captures (negative hours) are zeros and are kept for reference only.
* `contest` differs between counties when a county-page series is chosen; use `contest_id` to follow a series.
* Not found: 2024 general intermediate counts, any official "ballots remaining" log, 2018/2020 election-night versions.
  Other leads not pursued: Salt Lake County 2024 primary precinct `turnout` endpoint (6 captures, primary only).
