# Election-night runbook

Everything below runs from the repo root. Raw downloads are cached in `UTEL_RAW_DIR`
(`export UTEL_RAW_DIR=/Users/adamhubbs/local_dev/election_project/pipeline/raw` when working in a worktree).

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

## Election night

Automatic: the `*/10` cron (and the 02:30Z start cron) launch `election-night.yml`; it loops about every 100 s, commits
`web/public/data/results/2026-general` and `web/public/data/config.json` only when something changed, pushes to `main`
and dispatches `deploy.yml` at most every 3 minutes (a final dispatch always goes out when the loop ends).

Manual start: Actions -> "Election night scraper" -> Run workflow.

Local fallback (GitHub runners blocked, or to run in parallel):

```bash
export UTEL_RAW_DIR=/Users/adamhubbs/local_dev/election_project/pipeline/raw
END_TIME=2026-11-05T08:00:00Z pipeline/scripts/election_night_loop.sh
# PUSH=0 commits locally only; DEPLOY=0 skips the deploy dispatch; ONCE=1 does a single pass
```

Status lives in `config.json` `live_mode`: `pre` -> `live` (first vote counted) -> `final` (API says official).

### Calling races (winners are never automatic)

Add a row to `pipeline/config/calls.csv` and commit/push (or let the loop pick it up: a changed config file forces a
rebuild on the next pass):

```
contest_id,candidate_id,called_at,by
us-house-1,ben-mcadams,2026-11-04T05:12:00Z,manual
amendment-a,for,2026-11-04T06:30:00Z,manual
```

The candidate gets `winner: true` and the contest gets `call: {candidate_id, called_at, by}`. After certification, if the API
sets `isWinner` on statewide contests (it did not for 2024), that is used when no manual call exists. Leads never set a winner.

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
* Counted fraction `f_c = counted_c / T_c ~ Beta(m k, (1-m) k)`, `k = 12` (counties differ a lot in processing speed),
  `logit m = logit m(h) + eta`, `m(h) = 0.975 - 0.355 exp(-h/22h)` with h = hours since the 8 pm MT close (0.62 at close).
  `eta = s(h) t_3` is a heavy-tailed statewide pace shift with `s(h) = 0.5 + 0.2 exp(-h/24h)`, so early on a low count can be
  explained by either low turnout or slow pace; the split is decided by the priors, which keeps early intervals honest.
  Since 2025's HB 300 mail ballots must be *received* by 8 pm Election Day, so a large share (drop-box ballots) is counted after the first report.
* Posterior: exact 2-D grid over (delta, eta) with eps_c integrated out per county on a 1-D grid, then 4000 joint Monte Carlo
  draws (counties inform each other through delta/eta). The county log-likelihood is multiplied by 0.35 (`likelihood_power`)
  because counties are not independent evidence about the statewide shift/pace. ~2 s. Counties with no votes yet use the prior.
  `counted <= T` holds by construction.
* Optional `pipeline/config/ballots_returned.csv` (`fips,returned`; absent by default - no official per-county returned-ballot feed
  was found to scrape): `0.97 * returned` becomes a lower bound on `T_c`.
* Overrides (`remaining_ballots.csv`) and `final` counties replace the model for that county.
* Propagation: county `pct_expected(+lo/hi)` = counted / quantiles of T. A contest's `reporting.pct_expected` divides its votes
  by the draw-wise sum over counties of `T_c * rho_c` where `rho_c` is the contest's votes-per-counted-ballot in that county (for
  counties with nothing counted: the pooled rate times `ballot_share`). Summary `turnout` and `model.json.history` use the same draws.

Intervals are 5th-95th percentiles (90 %).

### Back-test (`Rscript pipeline/tests/backtest_expected_vote.R 40`)

Truth = real county totals (2022 ballots; 2024 top-of-ticket votes / 0.97). Fake nights use a *different* process than the model
(logit-normal county noise, uniform statewide pace in 0.50-0.85 at the first drop, then geometric catch-up). Priors are built from the *other*
election's county pattern with a +-0.2 logit statewide miss. 40 replicates per cell; coverage = share of true values inside the 90 % interval.

| scenario | stage | counted | county cover | statewide cover | statewide MAPE | width state (rel.) | width county (rel.) |
|---|---|---|---|---|---|---|---|
| 2022 truth, 2024 pattern, +0.2 miss | first drop (1h) | 69 % | 0.91 | 0.93 | 10.0 % | 45 % | 45 % |
|  | next morning (14h) | 84 % | 0.96 | 1.00 | 5.0 % | 32 % | 34 % |
|  | day two (36h) | 93 % | 0.98 | 0.97 | 2.4 % | 18 % | 22 % |
| 2024 truth, 2022 pattern, -0.2 miss | first drop (1h) | 66 % | 0.94 | 0.93 | 4.9 % | 24 % | 24 % |
|  | next morning (14h) | 85 % | 0.98 | 1.00 | 2.4 % | 16 % | 17 % |
|  | day two (36h) | 94 % | 0.97 | 1.00 | 1.7 % | 8 % | 11 % |
| 2022 truth, noisy own pattern, +0.2 miss | first drop (1h) | 68 % | 0.93 | 0.88 | 8.1 % | 42 % | 44 % |
|  | next morning (14h) | 85 % | 0.98 | 0.95 | 3.7 % | 27 % | 31 % |
|  | day two (36h) | 94 % | 0.99 | 0.88 | 4.1 % | 16 % | 21 % |
| surge: +25 % ballots vs 2022 | first drop (1h) | 66 % | 0.94 | 0.90 | 8.8 % | 29 % | 30 % |
|  | next morning (14h) | 85 % | 0.95 | 0.90 | 5.0 % | 17 % | 19 % |
|  | day two (36h) | 94 % | 0.98 | 0.97 | 2.0 % | 8 % | 12 % |
| slump: -25 % ballots vs 2022 | first drop (1h) | 73 % | 0.91 | 0.95 | 13.0 % | 63 % | 65 % |
|  | next morning (14h) | 85 % | 0.97 | 1.00 | 4.2 % | 38 % | 43 % |
|  | day two (36h) | 94 % | 0.98 | 0.93 | 2.8 % | 18 % | 26 % |

Honest reading: with 40 replicates per cell, coverage has a standard error of about 0.05 statewide, so every cell is within noise of
or above 0.85-0.90. The price is width: at the first drop the statewide 90 % interval is 25-65 % of the truth (the turnout/pace split is
not identifiable from counts alone), narrowing to 8-18 % by day two. Before this recalibration (normal priors, `k = 25`) the first-drop
statewide coverage was 0.45-0.55 in two scenarios with widths of 10-22 %. Only a "ballots remaining" statement
(`remaining_ballots.csv`) removes the ambiguity. `UTEL_MODEL_OVERRIDES="sigma_delta=0.5"` lets the back-test try other priors.
