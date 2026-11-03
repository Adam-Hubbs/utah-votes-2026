# Election-night runbook

Everything below runs from the repo root. Raw downloads are cached in `UTEL_RAW_DIR`
(`export UTEL_RAW_DIR=<path to main checkout>/pipeline/raw` when working in a worktree).

## What runs

| piece | role |
|---|---|
| `pipeline/scripts/build_2026_contests.R` | one-off: builds `candidates.csv`/`candidates.json` and the zero-vote `results/2026-general/*` ("pre") from the published ballot structure |
| `pipeline/scripts/scrape_live.R` | fetch -> normalize -> write summary/contests/timeline -> run model -> publish -> `config.json` |
| `pipeline/scripts/model_expected_vote.R` | re-run only the expected-vote model (also called by the scraper) |
| `pipeline/scripts/election_night_loop.sh` | scrape loop that commits, pushes and dispatches `deploy.yml` (used by Actions and as the local fallback) |
| `.github/workflows/election-night.yml` | one long job (<= 5h40m loop) + `*/10` watchdog, window 02:15Z Nov 4 - 08:00Z Nov 5 |
| `.github/workflows/canvass.yml` | one scrape every 30 min until Nov 19 08:00Z (skips the election-night window) |
| `.github/workflows/deploy.yml` | builds `web/` and publishes to GitHub Pages on push to main or dispatch |

Source: `electionresults.utah.gov` media export (`/cdn/results/Utah/export-General11032026.json`, one request incl. precincts);
fallback to `/data` for each of the 29 counties (no precincts) if the export is missing or unparsable. A cheap HEAD request
compares the ETag first, so an unchanged export is never re-downloaded.

## Before election night (checklist)

1. `Rscript pipeline/scripts/build_2026_contests.R` - confirms the API still lists the same contests (re-run with
   `--refresh-candidates` to append any new/changed candidates; existing hand edits in `candidates.csv` are kept).
2. Review `pipeline/config/candidates.csv` (`note` column: "incumbency not researched" for legislature/school board;
   parties come from the export; `NONPARTISAN` maps to `UNA`).
3. Drill: `Rscript pipeline/scripts/scrape_live.R --simulate-sequence` writes a progressing fake night to
   `web/public/data/results/2026-sim/` (`--simulate 0.45 --seed 1` for a single snapshot; `--steps 5` for a partial sequence).
4. Enable Pages (Settings -> Pages -> Source: GitHub Actions). Scheduled workflows only run from the default branch, so merge to `main`.
5. Run `election-night.yml` manually once (Actions -> Run workflow, tick "ignore_window", `end_time` ~10 minutes ahead) to
   confirm the runner can reach the results site. The first steps log `HTTP <code>` for each endpoint. A 403 means the
   runner is blocked - use the local fallback below.
6. Registration: until the API publishes `voterRegistration` the model uses `pipeline/config/county_baselines.csv`
   (Lt. Governor active-voter report of 2026-10-19). Re-run `Rscript pipeline/scripts/build_live_baselines.R` to refresh it (needs `pdftotext`).

## Precinct join check

Every precinct name in the export must map to a `precincts_2026` polygon (`precinct_id = {fips}-{NAME UPPERCASED}`).
`Rscript pipeline/tests/check_live_join.R [export.json]` runs the real parser on an export and lists names without a polygon; the scraper also logs
`[scrape] N reported precincts have no polygon` on every pass. With the export of 2026-10-22: 3,152 names, 15 without a polygon, all with no residents or
unlocatable: 14 federal-only precincts (UGRC has no area; they can carry a few votes, e.g. Utah County FED301/FED401 had 944 in 2024) and Cache `3UNKN`.
Those votes count in county totals but cannot be drawn. `20 Fountain Green U` is mapped to the UGRC area `NS:U`. Box Elder-style reports of a parent
precinct (`02PER1`) cover every unclaimed sub-area of that parent (`02PER1:M`), so populated sub-areas are not left blank.

## Election night

Automatic: the `*/10` cron (and the 02:30Z start cron) launch `election-night.yml`; it loops about every 100 s, commits
`web/public/data/results/2026-general` and `web/public/data/config.json` only when something changed, pushes to `main`
and dispatches `deploy.yml` at most every 3 minutes (a final dispatch always goes out when the loop ends).

Manual start: Actions -> "Election night scraper" -> Run workflow.

Local fallback (GitHub runners blocked, or to run in parallel):

```bash
export UTEL_RAW_DIR=<path to main checkout>/pipeline/raw
END_TIME=2026-11-05T08:00:00Z pipeline/scripts/election_night_loop.sh
# PUSH=0 commits locally only; DEPLOY=0 skips the deploy dispatch; ONCE=1 does a single pass
```

Status lives in `config.json` `live_mode`: `pre` -> `live` (first vote counted) -> `final` (API says official).

### Winners (automatic, never manual)

There is no call mechanism. `build_results()` (`pipeline/R/live_normalize.R`) marks `winner: true` only when results are
official: the statewide `/data` feed reports `isOfficialResults` (live status `final`), or it sets `isWinner` on a contest
(the API did not for 2024; that is used when present). Then the top vote-getter wins, or the top `voteFor` candidates in
multi-seat contests (`auto_winners()`); a tie at the cutoff awards nothing. Measures and judicial retention are a single
seat between For/Yes and Against/No, i.e. more than 50% yes. Until the results are official, candidates are only
"leading" in the UI and nothing is marked won.

### Overriding the expected-vote estimate

If a clerk or the Lt. Governor publishes ballots remaining, edit `pipeline/config/remaining_ballots.csv`:

```
fips,remaining,final,as_of,note
49035,85000,,2026-11-04T06:00:00Z,"Salt Lake clerk briefing"
49049,,true,2026-11-05T01:00:00Z,"Utah: all ballots counted"
```

`remaining` sets expected = counted + remaining (relative sd 5 %), `source: "reported_remaining"`; `final=true` sets expected =
counted, `source: "final"`. Rerun immediately with `Rscript pipeline/scripts/model_expected_vote.R` or wait for the next loop pass.
Priors can be tuned in `pipeline/config/live.yml` under `model:` (names as in `model_defaults()`, e.g. `m0`, `tau_hours`, `mu_delta`).

### Troubleshooting

* `[scrape] FAILED: ...` - the scraper refuses to publish when fewer than 29 counties are present, previously published
  contests vanish, or total votes drop by more than `max_vote_drop_fraction` (20 %). Previous good files stay in place.
  If the drop is legitimate (county re-count), run `Rscript pipeline/scripts/scrape_live.R --force` after raising the limit in `live.yml`.
* Unknown candidate warning - a candidate is missing from `candidates.csv`; votes are kept under an auto-generated slug and
  `OTH` party. Run `build_2026_contests.R --refresh-candidates`, fix, commit.
* Export 404 / HTTP error - the scraper falls back to per-county `/data` (no precinct rows; `precincts` arrays become empty).
* Push races with other workflows - the loop does `pull --rebase --autostash` and retries four times.
* Repo growth: each pass rewrites ~130 JSON files (about 2-3 MB). ~150 passes is fine; squash `main` history after the canvass if size matters.

## Data notes

* Counted ballots are inferred: `max(contest total in county) / 0.97` because the API's county `ballotsCast` is not reliable
  (the 2024 payload reports registration-like numbers). `ballot_share` on county rows (contest precincts / county precincts)
  approximates what fraction of a county a district covers.
* County-only legislative contests appear with party prefixes in names ("DEM JARED NEAL"); these are stripped and the prefix is used as party.
* Local contests (county commission, municipal courts, local school boards) are ignored.
* Retention contest files contain county rows only (no precinct list) to keep commits small; see `precinct_kinds` in `live.yml`.
* Contract extensions: optional `description` on contests; summary has `as_of`, `source_etag`, `inputs_hash`; county rows in contest files have `ballot_share`.

## Expected-vote model (`pipeline/R/model_expected.R`)

Utah votes by mail, so precincts-reporting is meaningless. For each county c:

* Eventual ballots `T_c = R_c * p_c`, `R_c` = active registered voters, `logit p_c = logit(turnout_2022_c) + delta + eps_c`;
  `delta = 0.10 + 0.6 t_3` (Student-t, 3 df: heavy-tailed because Utah midterm turnout swings a lot between cycles, e.g. the 2018 surge),
  `eps_c ~ N(0, s_c^2)` with `s_c^2 = 0.17^2 + (0.6 / sqrt(R_c/1000))^2` (small counties are noisier).
* Eventual ballots `T_c = R_c * p_c`, `R_c` = active registered voters, `logit p_c = logit(turnout_2022_c) + delta + eps_c` (2026 is a midterm following the
  2022 midterm, so the base year is already the comparable one; `mu_delta = 0.10`, `delta = 0.10 + 0.6 t_3`, Student-t with 3 df: Utah turnout swings between cycles
  by 0.4-1.5 logit). `eps_c ~ N(0, s_c^2)`, `s_c^2 = 0.22^2 + (0.7 / sqrt(R_c/1000))^2` (small counties are noisier).
* Counted fraction `f_c = counted_c / T_c ~ Beta(m_c k, (1-m_c) k)`, `k = 6`, `logit m_c = logit m(h) + eta - 0.6 (ln R_c - mean_R(ln R))`,
  `m(h) = 0.99 - 0.37 exp(-h/70h)` with h = hours since the 8 pm MT close (0.62 at close). `eta = s(h) t_3` is a heavy-tailed statewide pace shift,
  `s(h) = 0.6 + 0.3 exp(-h/24h)`. The size term makes large counties count more slowly than small ones (in every archived capture the logit of the
  counted share falls 0.3-0.8 per log unit of size); it is centred on the registration-weighted mean so `m(h)` stays the statewide curve.
  Pace parameters come from archived Utah counts (`pipeline/data/timing`, evaluation in `pipeline/tests/eval_turnout_model.R`): about 70 % of the final vote
  is counted at +22 h and 87 % at +97 h in 2016-2022 (2025's one post-HB 300 point at +19 h: 75 %), with the last ballots arriving over the second week.
  Early on a low count can be explained by either low turnout or slow pace; the split is decided by the priors, which keeps early intervals honest.
* Posterior: exact 2-D grid over (delta, eta) with eps_c integrated out per county on a 1-D grid, then 4000 joint Monte Carlo
  draws (counties inform each other through delta/eta). The county log-likelihood is multiplied by 0.25 (`likelihood_power`)
  because counties are not independent evidence about the statewide shift/pace. ~0.5 s per fit. Counties with no votes yet use the prior.
  `counted <= T` holds by construction.
* Optional `pipeline/config/ballots_returned.csv` (`fips,returned`; absent by default - no official per-county returned-ballot feed
  was found to scrape): `0.97 * returned` becomes a lower bound on `T_c`.
* Overrides (`remaining_ballots.csv`) and `final` counties replace the model for that county.
* Propagation: county `pct_expected(+lo/hi)` = counted / quantiles of T. A contest's `reporting.pct_expected` divides its votes
  by the draw-wise sum over counties of `T_c * rho_c` where `rho_c` is the contest's votes-per-counted-ballot in that county (for
  counties with nothing counted: the pooled rate times `ballot_share`). Summary `turnout` and `model.json.history` use the same draws.

Intervals are 5th-95th percentiles (90 %).

### Evaluation against real counts (2016-2025 archive)

`Rscript pipeline/tests/eval_turnout_model.R` replays the model through the archived timelines (full report: `pipeline/tests/report/`, built by
`build_turnout_report.R`). Before/after the 2026-10-23 recalibration (old: tau 22 h, k 12, no size term, scales 0.7/0.5, 0.17/0.6, power 0.35):

| check | before | after |
|---|---|---|
| observed statewide share counted vs model median, 9 early points (median PIT; 0.5 = calibrated) | 0.17 | 0.46 |
| warped real patterns, statewide bias of expected ballots at +24 h (prior as deployed / centred) | +11.9 % / +5.7 % | +5.0 % / +2.6 % |
| warped real patterns, county 90 % cover of small / mid / large at +24 h | 36 % / 58 % / 55 % | 100 % / 86 % / 78 % |

Re-run the script for current numbers; the report lists them. Caveats: only two full county vectors (2022 +22 h, 2020 +97 h) and one 2025
vector exist; 2025 and later elections run under HB 300 (ballots must arrive by 8 pm Election Day), which may count faster than 2016-2022.

### Synthetic back-test (`Rscript pipeline/tests/backtest_expected_vote.R 40`)

Truth = real county totals (2022 ballots; 2024 top-of-ticket votes / 0.97). Fake nights follow the archived pace (statewide share of the final vote
`1 - 0.38 exp(-h/90h)` with a logit-normal statewide shift, size gradient 0.4 and logit-normal county noise); the earlier generator (uniform
50-85 % at the first drop, geometric catch-up) was faster than any archived election and flattered the old model. Priors are built from the *other*
election's county pattern with a +-0.2 logit statewide miss. 40 replicates per cell; coverage = share of true values inside the 90 % interval.

| scenario | stage | counted | county cover | statewide cover | statewide MAPE | width state (rel.) | width county (rel.) |
|---|---|---|---|---|---|---|---|
| 2022 truth, 2024 pattern, +0.2 miss | first drop (1h) | 60 % | 0.98 | 1.00 | 4.1 % | 32 % | 34 % |
|  | next morning (14h) | 67 % | 0.98 | 1.00 | 3.2 % | 29 % | 31 % |
|  | day two (36h) | 70 % | 0.99 | 1.00 | 3.5 % | 27 % | 29 % |
| 2024 truth, 2022 pattern, -0.2 miss | first drop (1h) | 61 % | 0.98 | 1.00 | 6.2 % | 19 % | 20 % |
|  | next morning (14h) | 64 % | 0.93 | 0.95 | 6.2 % | 17 % | 18 % |
|  | day two (36h) | 72 % | 0.95 | 0.97 | 4.8 % | 14 % | 15 % |
| 2022 truth, noisy own pattern, +0.2 miss | first drop (1h) | 63 % | 1.00 | 1.00 | 3.2 % | 30 % | 32 % |
|  | next morning (14h) | 67 % | 1.00 | 1.00 | 3.9 % | 28 % | 30 % |
|  | day two (36h) | 69 % | 0.99 | 1.00 | 3.5 % | 26 % | 27 % |
| surge: +25 % ballots vs 2022 | first drop (1h) | 58 % | 0.92 | 0.85 | 9.1 % | 21 % | 21 % |
|  | next morning (14h) | 62 % | 0.88 | 0.82 | 8.5 % | 19 % | 19 % |
|  | day two (36h) | 72 % | 0.96 | 0.95 | 5.3 % | 15 % | 16 % |
| slump: -25 % ballots vs 2022 | first drop (1h) | 64 % | 1.00 | 1.00 | 4.0 % | 46 % | 48 % |
|  | next morning (14h) | 63 % | 1.00 | 1.00 | 4.2 % | 44 % | 44 % |
|  | day two (36h) | 71 % | 1.00 | 1.00 | 3.3 % | 37 % | 38 % |

Read with a standard error of about 0.05 statewide. The price of honest coverage is width: 25-45 % of the truth at the first drop, still 14-37 % at day two,
because the counted share is a long way from complete. Only a "ballots remaining" statement (`remaining_ballots.csv`) removes the turnout/pace
ambiguity. `UTEL_MODEL_OVERRIDES="sigma_delta=0.5"` lets the back-test try other priors.
