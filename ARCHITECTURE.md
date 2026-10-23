# Utah Elections 2026 — Architecture & Data Contracts

A fully static election site (poll tracker + live election-night dashboard) for Utah.
No server: everything is pre-computed JSON served next to a static front end.

```
polls/                    NYT poll CSVs (updated independently; also fetchable by URL)
pipeline/                 R data pipeline (tidyverse, base pipe |>, \(x) lambdas)
  DESCRIPTION             R package dependencies (used by GitHub Actions)
  R/                      shared functions (sourced by scripts)
  scripts/                entry points, run with `Rscript pipeline/scripts/<name>.R`
  config/                 hand-maintained inputs (ratings, candidate parties, overrides)
  raw/                    downloaded source files (gitignored, cache)
web/                      Vite + React + TypeScript + D3 front end
  public/data/            ALL pipeline outputs land here (committed)
.github/workflows/        deploy, polls refresh, election-night scraper loop
```

## Key facts discovered

* Utah's official results site (`electionresults.utah.gov`) is an Enhanced Voting SPA with a public JSON API:
  * `GET /results/public/api/jurisdictions/Utah` — jurisdiction + list of elections (`publicElectionId`).
  * `GET /results/public/api/elections/{jurisdiction}/{publicElectionId}/data` — election, `ballotItems`
    (contests with `summaryResults.ballotOptions[].voteCount`, `party.abbreviation`), `localityElections`
    (one per county: `ballotsCast`, `precinctsReporting`, reporting statuses), voter registration, turnout.
    `{jurisdiction}` can be `Utah` or a county shortName such as `salt-lake-county-ut`.
  * `GET .../{publicElectionId}/vr`, `/stats`, `/turnout`, `/localities`, `/closeraces`.
  * Media export (all contests, statewide + every county + **precinct-level** results):
    `GET /cdn/results/{mediaExportPath}` where `mediaExportPath` comes from the jurisdiction/data payload,
    e.g. `Utah/export-general11052024.json` (29 MB). For 2026 it is `Utah/export-General11032026.json`
    (404 until results are published).
  * 2026 general = `General11032026`; 2024 general = `General11052024`. Elections available in this
    system: 2023 onward. Earlier years must come from other sources (MEDSL, OpenElections, VEST, Utah LG archives).
  * In the 2026 data the `party` is null on ballot options right now, so party comes from
    `pipeline/config/candidates.csv`.
* County ids: the API uses Utah county numbers `01`–`29` (alphabetical; `mapFeatureId`, export `localResults[].id`
  may differ — always join on names normalized to the county name). We use **5-digit FIPS** (`49035` = Salt Lake) as the canonical county key in every output.
* 2026 statewide contests: U.S. House 1–4 (new court-ordered map), Constitutional Amendments A and B,
  state legislature (some multi-county at state level, the rest in county data), State School Board, judicial retention.
  No U.S. Senate or governor race in 2026.
* Utah elections are almost entirely vote-by-mail. "Precincts reporting" is not meaningful (every precinct reports partially in
  the first batch), so we estimate **percent of expected vote counted** with a Bayesian model.

## Boundary changes (critical)

* **Congressional districts changed between 2024 and 2026.** The 2022–2024 map (adopted 2021) was replaced by a
  court-ordered map in Nov 2025 that creates a Salt Lake County–based district (District 1 in the new map;
  Ben McAdams is the Democratic nominee). We keep BOTH maps: `cd2022` (used 2022–2024) and `cd2026`.
* **Precincts change every cycle.** Never assume a precinct name means the same area across years. Precinct
  geometry is versioned by election year: `precincts_2024`, `precincts_2026`, etc. Results for election Y are only
  joined to `precincts_Y` geometry.
* **Crosswalks are population-weighted using 2020 Census blocks.** Each block (with 2020 total population and
  voting-age population) is assigned to a precinct of each vintage and to each district plan (by block internal point).
  The weight of source unit s in target unit t = VAP(s ∩ t) / VAP(s). This yields:
  * `precinct_2024 → cd2026` (re-aggregate 2024 / 2022 results into the new districts: "Trump +X in the new UT-2"),
  * `precinct_2024 → precinct_2026` (precinct-level swing maps between cycles),
  * `precinct_Y → county` is exact (precincts nest in counties).
  If block-level assignment is impossible for some vintage, fall back to area-weighted overlay and record it in metadata.

## Canonical identifiers

| thing | format | example |
|---|---|---|
| election_id | `{year}-{type}` | `2026-general`, `2024-general`, `2022-general` |
| contest_id | kebab-case office + district | `us-house-1`, `president`, `us-senate`, `governor`, `amendment-a`, `state-house-23`, `state-senate-11`, `school-board-7`, `retention-<slug>`, `attorney-general` |
| county key | 5-digit FIPS string | `"49035"` |
| precinct_id | `{county_fips}-{precinct name as reported, uppercased, trimmed}` | `"49035-ALT001"` |
| party | upper-case abbreviation | `REP`, `DEM`, `LIB`, `CON`, `IAP`, `UUP`, `GRN`, `FWD`, `NPA`/`UNA`, `OTH` |
| candidate_id | slug of name | `ben-mcadams` |

Party colour group: `REP` → red, `DEM` → blue, everything else → yellow (third party). For ballot measures
`FOR`/`YES` and `AGAINST`/`NO` use neutral green/purple-free palette: FOR = teal `#1b9e77`-ish, AGAINST = orange-brown; the front end decides.

## Output files (`web/public/data/…`) — the contract between pipeline and front end

All JSON, UTF-8, numbers as numbers, dates ISO-8601 (`YYYY-MM-DD`), timestamps ISO with `Z`.
Shares, percentages and margins are always proportions in 0–1 (e.g. `pct: 0.594`), never 0–100 — except poll `pct`/`avg`, which follow the NYT files and are 0–100.

### Site configuration
`config.json`
```json
{ "current_election": "2026-general", "election_date": "2026-11-03", "polls_close_utc": "2026-11-04T03:00:00Z",
  "live_mode": "pre" , "live_data_base": "data/results", "featured_contests": ["us-house-1","us-house-2","us-house-3","us-house-4","amendment-a","amendment-b"] }
```
`live_mode`: `pre` | `live` | `final`. The election-night scraper flips it to `live`.

### Geography (`data/geo/`) — TopoJSON, WGS84, simplified for web
| file | object name | properties |
|---|---|---|
| `counties.topo.json` | `counties` | `fips`, `name` (e.g. "Salt Lake"), `county_nbr` ("18") |
| `cd2026.topo.json` | `districts` | `district` (int) |
| `cd2022.topo.json` | `districts` | `district` (int) |
| `state_house.topo.json` / `state_senate.topo.json` | `districts` | `district` (int) |
| `precincts_2026.topo.json` | `precincts` | `precinct_id`, `county_fips`, `name`, `cd2026` |
| `precincts_2024.topo.json` | `precincts` | `precinct_id`, `county_fips`, `name`, `cd2022` |
| `places.json` | – | `[{name, lon, lat, rank}]` label points for major cities |
`geo/meta.json` lists sources, vintages, simplification, crosswalk method.

### Results (`data/results/{election_id}/`) — same schema for historical AND live
`data/results/index.json`
```json
{ "elections": [ { "election_id": "2024-general", "name": "2024 General Election", "date": "2024-11-05",
    "status": "final", "precinct_geo": "precincts_2024", "cd_plan": "cd2022",
    "contests": [ { "contest_id": "president", "name": "President", "office": "president" } ] } ] }
```
`data/results/{election_id}/summary.json`
```json
{ "election_id": "2026-general", "name": "2026 General Election", "date": "2026-11-03",
  "status": "pre|live|final", "updated_at": "2026-11-04T04:12:00Z", "source": "electionresults.utah.gov",
  "precinct_geo": "precincts_2026", "cd_plan": "cd2026",
  "turnout": { "ballots_counted": 0, "registered": 2000000, "expected_ballots": 1100000,
               "expected_lo": 1000000, "expected_hi": 1200000, "pct_expected": 0.0 },
  "contests": [ {
    "contest_id": "us-house-1", "name": "U.S. House District 1", "office": "us-house", "district": 1,
    "type": "candidate",                 // or "measure"
    "featured": true,
    "total_votes": 0,
    "candidates": [ { "candidate_id": "ben-mcadams", "name": "Ben McAdams", "party": "DEM",
                      "incumbent": false, "votes": 0, "pct": 0.0, "winner": false } ],  // winner is true only once results are official (see pipeline/docs/live.md)
    "reporting": { "counties_reporting": 0, "counties_total": 7,
                   "pct_expected": 0.0, "pct_expected_lo": 0.0, "pct_expected_hi": 0.0 }
  } ] }
```
For measures, `candidates` holds options with `candidate_id` `for`/`against` (or `yes`/`no`) and `party: null`.

`data/results/{election_id}/contests/{contest_id}.json`
```json
{ "contest_id": "us-house-1", "election_id": "2026-general", "updated_at": "...",
  "candidates": [ {"candidate_id": "...", "name": "...", "party": "DEM"} ],
  "counties": [ { "fips": "49035", "name": "Salt Lake", "votes": {"ben-mcadams": 0}, "total": 0,
                  "ballots_counted": 0, "expected_ballots": 0, "pct_expected": 0.0,
                  "pct_expected_lo": 0.0, "pct_expected_hi": 0.0 } ],
  "precincts": [ { "precinct_id": "49035-ALT001", "votes": {"ben-mcadams": 0}, "total": 0 } ] }
```

`data/results/{election_id}/model.json` (live only; Bayesian expected-vote model)
```json
{ "updated_at": "...", "draws": 4000, "method": "short text",
  "statewide": { "counted": 0, "expected_median": 0, "expected_lo": 0, "expected_hi": 0, "pct_expected": 0 },
  "counties": [ { "fips": "49035", "registered": 0, "counted": 0, "expected_median": 0, "expected_lo": 0,
                  "expected_hi": 0, "pct_expected": 0, "pct_expected_lo": 0, "pct_expected_hi": 0,
                  "source": "model|reported_remaining|final" } ],
  "history": [ { "t": "...", "counted": 0, "expected_median": 0 } ] }
```
`data/results/{election_id}/timeline.json` (live) — snapshots of each featured contest's totals over time for "how the count evolved" charts:
`{ "contests": { "us-house-1": [ { "t": "...", "votes": {"ben-mcadams": 0}, "total": 0 } ] } }`

### Historical cross-plan aggregates (`data/history/`)
`data/history/cd2026_baselines.json` — past statewide contests re-aggregated to the 2026 districts via the crosswalk:
```json
{ "method": "2020-block VAP-weighted precinct→district crosswalk",
  "districts": { "1": [ { "election_id": "2024-general", "contest_id": "president", "name": "2024 President",
                          "votes": {"REP": 0, "DEM": 0, "OTH": 0}, "total": 0, "margin": -0.25 } ] } }
```
`margin` = (REP − DEM) / total (positive = R lead). Same structure for `cd2022_baselines.json` (actual old districts).
`data/history/county_trends.json` — per county, per (election, contest) two-party margin & turnout for trend charts.
`data/history/precinct_swing_2024_2026.json` is produced post-election only (needs 2026 results).

### Polls (`data/polls/`)
`polls.json` — every Utah poll (one entry per poll question):
```json
[ { "poll_id": "...", "question_id": "...", "contest_id": "us-house-1", "stage": "general|primary",
    "pollster": "Lighthouse Research", "sponsor": "Utah Debate Commission", "start_date": "2026-09-08",
    "end_date": "2026-09-10", "sample_size": 515, "population": "rv", "partisan": null, "internal": false,
    "url": "...", "numeric_grade": null,
    "results": [ { "candidate_id": "ben-mcadams", "name": "Ben McAdams", "party": "DEM", "pct": 62.7 } ] } ]
```
`averages.json` — `{ "updated_at": "...", "method": "...", "contests": { "us-house-1": {
   "n_polls": 1, "latest": [ {"candidate_id","name","party","avg","lo","hi"} ],
   "series": [ {"date": "2026-09-10", "candidate_id": "...", "avg": 0, "lo": 0, "hi": 0} ] } } }`
`national.json` — national context from the same NYT files: generic congressional ballot average and Trump approval average series
`{ "generic_ballot": {"series": [{"date","DEM","REP"}], "latest": {...}}, "approval": {"series": [{"date","approve","disapprove"}], "latest": {...}} }`.

### Ratings, candidates, demographics
`ratings.json` — `{ "updated_at": "...", "sources": [{"id":"cook","name":"Cook Political Report","url":"..."}],
  "ratings": { "us-house-1": { "cook": "Solid D", "sabato": "Safe D" } }, "scale": ["Solid D","Likely D","Lean D","Toss-up","Lean R","Likely R","Solid R"] }`
`candidates.json` — `{ "us-house-1": [ {"candidate_id","name","party","incumbent","bio","website"} ] }`
`demographics/counties.json`, `demographics/cd2026.json`, `demographics/state.json` —
`{ "source": "ACS 2020–2024 5-year", "units": [ { "id": "49035", "name": "Salt Lake", "population": 0,
   "median_age": 0, "pct_white_nh": 0, "pct_hispanic": 0, "pct_asian": 0, "pct_black": 0, "pct_bachelors_plus": 0,
   "median_hh_income": 0, "pct_under_18": 0, "pct_65_plus": 0, "pct_urban": null,
   "registration": { "REP": 0, "DEM": 0, "UNA": 0, "OTH": 0, "total": 0, "as_of": "..." } } ] }`
Proportions are 0–1. For `cd2026` units the id is the district number as a string.

## Live election night

* `pipeline/scripts/scrape_live.R` pulls the media export (falls back to `/data` for state + each county),
  normalizes to the results schema above, writes `data/results/2026-general/*`, appends to `timeline.json`,
  then runs `pipeline/scripts/model_expected_vote.R`, which writes `model.json` and fills every `pct_expected*`.
* `--simulate <fraction>` mode builds a fake partial count (from 2024 turnout patterns + polls) so the live UI
  can be tested before election night; output goes to `data/results/2026-sim/` and the site shows it with `?sim=1`.
* GitHub Actions `election-night.yml`: one long-running job (≤ 5h50m) that loops scrape → model → commit → dispatch deploy
  every ~3 minutes, plus a `*/10` cron watchdog in the same concurrency group so a new loop starts if one dies.
  This beats a bare 5-minute cron (GitHub delays scheduled runs heavily at busy times and each cold start re-installs R).
* Post-election canvass (Utah counts for ~2 weeks): `canvass.yml` runs every 30 minutes Nov 4–Nov 18.

## Code style

* R: tidyverse, base pipe `|>`, `\(x)` lambdas, `if_else`/`case_when`/`purrr::map*` (never `ifelse`/`sapply`/`lapply`/`vapply`),
  httr2 for HTTP, sf for geometry. S7/R6 only if OOP is genuinely needed. Comments only to explain *why*.
* TypeScript/React: function components, hooks, strict TS, small focused components, comments only for *why*.

## State races (`/state`)

Hand-maintained inputs: `pipeline/config/legislature_seats.csv` (all 75 House + 29 Senate seats: holder, party, `up_2026`,
`incumbent_running`, `running_for`, `uncontested`, `note`; seeded from `https://le.utah.gov/data/legislators.json` plus the 2026 contest list,
`Rscript pipeline/scripts/build_legislature.R --refresh-seats` re-seeds and overwrites manual edits) and `pipeline/config/judges.csv`
(judge, court, JPEC recommendation). `Rscript pipeline/scripts/build_legislature.R` writes the two files below. Party codes: `REP`, `DEM`, `FWD` (Forward).

`legislature.json`
```json
{ "updated_at": "...", "roster_source": "...",
  "chambers": { "house": { "seats": 75, "majority": 38, "supermajority": 50,
      "current": {"REP": 60, "DEM": 14}, "holdovers": {}, "up_2026": {"REP": 60, "DEM": 14}, "vacant": 1,
      "seats_list": [ { "district": 1, "contest_id": "state-house-1", "holder": "Thomas W. Peterson", "holder_party": "REP",
         "holder_since": "...", "vacant": false, "up": true, "incumbent_running": true, "running_for": null,
         "uncontested": false, "pres24_margin": 0.64, "note": null } ] },
    "senate": { "seats": 29, "majority": 15, "supermajority": 20, "...": "same shape; holdovers = seats not on the 2026 ballot" } } }
```
`contest_id` is null for holdover seats and for seats whose contest is not in `results/2026-general/summary.json`; `incumbent_running`/`uncontested`
are null when unknown/not applicable. `pres24_margin` = (Trump − Harris) / total votes in the 2024 presidential race re-aggregated to the
district via the 2020-block VAP crosswalk (block → district by internal point, block → 2024 precinct); positive = R. Supermajority = two thirds
(veto override).

`judges.json`: `{ "updated_at", "jpec_source", "judges": { "<contest_id>": { "judge", "title", "court", "court_level": "supreme|appeals|district|juvenile|justice",
"jpec_recommendation", "jpec_score_summary", "appointing_governor", "appointed_year" } } }`. Retention needs more than 50% yes.

Front end: `pages/StatePage.tsx`, `components/state/*`, `lib/legislature.ts`, `data/legislature.ts`, `styles/state.css`. A seat counts as "won" only when the
contest has a candidate with `winner: true`; otherwise it is "leading". Seats without a contest are shown as not yet decided.

## National (U.S. Senate and House)

Context tab at `#/national` plus a ticker under the header on every page. Details: `pipeline/docs/national.md`.
Built by `pipeline/scripts/build_national.R` (also in `polls.yml` and the election-night loop). It carries no results or calls.
Poll values are on the 0-100 scale, margins are in points (REP minus main opponent, positive = R lead); seat counts are integers.

`data/national/senate.json`
```json
{ "updated_at": "...", "composition": { "current": {"DEM":45,"REP":53,"IND":2}, "not_up": {"DEM":32,"REP":31,"IND":2}, "majority": 51, "vp_tiebreak": "REP" },
  "composition_source": {"name","url","as_of"}, "ratings_sources": [{"id":"cook","name","as_of","url"}], "poll_note": "...",
  "races": [ { "state": "ME", "state_name": "Maine", "special": false, "incumbent": "...", "incumbent_party": "REP", "open": false, "status_note": null,
    "candidates": [{"name","party"}], "tracker": true,
    "poll_avg": { "n_polls": 21, "last_poll_date": "...", "latest": [{"candidate_id","name","party","avg","lo","hi"}],
                  "margin": {"value": -1.7, "lo": 0, "hi": 0, "opponent": "...", "opponent_party": "DEM"} },
    "ratings": {"cook":"Tossup","sabato":"Tossup","inside":"Tossup"} } ] }
```
`data/national/senate_polls.json` is `{updated_at, polls: Poll[], averages: {"senate-ME": ContestAverage}}` for the closest races.
`data/national/house.json`: `{updated_at, composition: {current:{DEM,REP,IND,vacant}, majority:218, source}, ratings_tally: {via, url, sources:[{id, as_of, counts:{"Solid D":n,"Likely D","Lean D","Tilt D","Toss-up",...}}]}, generic_ballot: {date,DEM,REP,margin,...}}`.

## Needle

A live probabilistic projection of each contest's FINAL result (`pipeline/R/model_needle.R`, run by `scrape_live.R` right after the
expected-vote model, by the simulator, by `build_2026_contests.R` for the pre-election file, or alone with
`Rscript pipeline/scripts/model_needle.R [results_dir]`). Covers U.S. House 1-4, both amendments and every state House/Senate contest with two or
more real candidates (~8 s total; 5,000 draws for featured contests, 2,500 for the rest).

`data/results/{election_id}/needle.json`
```json
{ "updated_at": "...", "draws": 5000, "draws_other": 2500, "method": "...", "environment_shift_logit": 0.11,
  "contests": { "us-house-1": {
     "stage": "pre|early|live|final", "pct_expected": 0.42,
     "pair": ["ben-mcadams", "riley-owen"],
     "prob": { "ben-mcadams": 0.97, "riley-owen": 0.03 }, "capped": false,
     "margin": { "median": 0.31, "lo50": 0.27, "hi50": 0.35, "lo90": 0.21, "hi90": 0.40 },
     "shares": { "ben-mcadams": { "median": 0.63, "lo90": 0.58, "hi90": 0.68 }, "riley-owen": {}, "other": {} },
     "prior": { "share_a": 0.71, "source": "poll average blended with 2024 fundamentals" },
     "history": [ { "t": "...", "pct_expected": 0.1, "prob": {"ben-mcadams": 0.9}, "margin_median": 0.3, "margin_lo90": 0.1, "margin_hi90": 0.45 } ] } } }
```
* `pair` = the two candidates the margin is defined on (a minus b, as a proportion of ALL votes): DEM then REP when both run (otherwise the
  non-REP candidate then the REP, or the first two); measures `["for","against"]`. `prob` is the chance a / b finishes ahead, **capped to
  [0.01, 0.99]** (`capped` is true when the cap applied; the UI prints ">99%" / "<1%").
* `forecast` (boolean): `false` only on a measure at stage `pre`. There is no public polling for amendments, so the 50% prior carries no information; the UI shows "No forecast — there is no public polling" instead of a probability (`ForecastSummary`, `competitiveness.ts` ignores it). Once votes are counted it is `true`.
* `stage`: `pre` nothing counted (prior only), `early` under 5% of expected vote counted (prior-dominated), `live`, `final` (all counties final or status final).
  `history` exists only for featured contests and only while counting (one point per new timestamp).

Method (details in the R file header and the Methodology page):
* Precinct model: remaining share of a in precinct j is `logit = alpha + beta*x_j + eta_county + lambda + lambda_county + eps_j`, `x_j` = centred logit of the
  2024 presidential two-party Democratic share on the 2026 precinct (`pipeline/config/needle_baseline_2026.csv`, built by `pipeline/scripts/build_needle_prep.R`
  from the block crosswalk). (alpha, beta) have a Gaussian prior and are updated by a GLS fit over counted precincts with a compound-symmetric county effect;
  county offsets are then calibrated so the model reproduces the vote-weighted counted totals. `lambda` (late-ballot shift, sd 0.15 logit, mean 0) plus an
  `misfit` term (0.08) are NOT identified from counts; they are assumptions (no historical timing data in the repo).
* Priors: U.S. House = poll average (two-party, with its band and 4 pts extra) blended by precision with fundamentals (2024 baseline shifted by the generic-ballot
  change since 2024 vs the 2024 national House margin R+2.6, elasticity 0.5, capped at 0.3 logit; sd 6.5 pts). The third-party share of the House vote is set from history by number of minor candidates (`house_other_by_minor`: 0 -> 1%, 1 -> 4.7%, 2+ -> 7.4%; 2016-2024), not from poll undecideds.
  Legislature = fundamentals WITHOUT the generic-ballot shift, corrected by `leg_spec` (fitted on 2018-2024: logit share = -0.037 + 0.867 x logit baseline - 0.176 [R incumbent] + 0.152 [challenger-side incumbent] - 0.413 [non-Democratic
  challenger]; total prior sd 0.30 logit, 0.50 for non-Democratic challengers; `pipeline/tests/eval_legislative_spec.R`), plus a leave-one-out
  pooled statewide swing learned from the other legislative contests once at least 5 have counted votes. Amendments = 50% +/- 0.55 logit with a free slope on 2024 partisanship.
* Remaining ballots: county expected ballots T_c are lognormal fitted to `model.json` (median, 90% interval), correlated across counties (rho 0.7); contest votes
  in a county scale as counted contest votes / counted ballots * T_c (or ballot_share * 0.97 for counties with nothing counted) and are allocated to precincts by their baseline size and own count.
* Back-test: `Rscript pipeline/tests/backtest_needle.R [reps] [draws]` replays 2024 (president, House 1-4 incl. forced close-race variants, Amendments B/C, 12 legislative contests) with partial
  counts at 25/50/75/90%; results in `pipeline/tests/backtest_needle_results.csv` (summary) and `backtest_needle_runs.csv` (every run). With late shifts as assumed the 90% margin interval covers 83-93%; in a "stress" scenario 72-74%.
