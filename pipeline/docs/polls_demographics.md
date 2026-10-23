# Polls, ratings and demographics pipeline

## Entry points

| script | output | notes |
|---|---|---|
| `Rscript pipeline/scripts/build_polls.R` | `web/public/data/polls/{polls,averages,national}.json` | env `POLLS_BASE_URL` (URL or directory holding `house.csv`, `senate.csv`, `governor.csv`, `other.csv`, `president.csv`, `president-averages.csv`; default `polls/`). Tunables in `pipeline/config/polls.json`. Fails with a message listing missing columns. Rewrites a file only when its content changed besides `updated_at`. |
| `Rscript pipeline/scripts/build_ratings.R` | `web/public/data/ratings.json` | reads `pipeline/config/ratings.csv` and `forecasts.csv` (hand-maintained). |
| `Rscript pipeline/scripts/build_demographics.R` | `web/public/data/demographics/{state,counties,cd2026,cd2022}.json` | needs `pdftotext` (poppler) for the registration PDF. First run downloads ~500 MB of ACS bulk files into the shared raw cache. |

Tests: `Rscript pipeline/tests/test_polls.R`, `Rscript pipeline/tests/test_polls_demographics.R`.

## Poll averages

Utah rows: `state == "UT"`, cycle 2026. Contest id comes from `office_type` + `seat_number`
(`seat_name` has typos such as "Third Congressional Election"). Primary polls stay in `polls.json`
(`stage: "primary"`) and are excluded from averages. "Don't know / Someone else / Would not vote"
become `undecided / someone-else / would-not-vote` with `party: null` and are excluded from averages.

For each date `d` from the first poll to today, over polls with `end_date <= d` (one question per poll,
likely voters preferred over registered over adults):

    w = 0.5^(age_days/21) * sqrt(n/600) * quality * partisan_penalty / sqrt(k_eff)

* `quality` = 0.5 + numeric_grade/3 (grade 0-3), 1 if unrated (all Utah polls are unrated).
* `partisan_penalty` = 0.5 for partisan-sponsored or internal polls, else 1.
* `k_eff` = recency-weighted number of polls from the same pollster, so a frequent pollster's total
  weight grows with sqrt(k) instead of k.
* Candidate average = weighted mean of the candidate's share across polls where the candidate appears.
* 95% band = 1.96 * sqrt(sampling variance of the weighted mean (design effect 1.3) + 2.5^2 / effective number of polls),
  with a floor of +/-4 points when there are 2 or fewer polls.
* Margin (`margin`, `margin_series`) = REP minus DEM average in points, positive = Republican lead; its band uses the
  multinomial variance of a difference, house SD 3.5, floor +/-6 for 2 or fewer polls.

Extra keys vs the contract: per contest `n_pollsters`, `last_poll_date`, `margin`, `margin_series`.
With one poll the average equals that poll (only the band is added).

`national.json`: generic ballot = same machinery with half-life 10 days, reference n 1000, 120-day window, daily since
2025-01-01 (`DEM`, `REP`, `margin` = REP minus DEM, `latest` with band and `n_polls`); approval = NYT's own average series.

## Ratings

`ratings.csv` keeps the raw label (`Safe D`); `ratings.json` shows it on the 7-point scale (Safe -> Solid) and keeps the raw label in `raw` where it differs.
Rows with empty `rating` are sources checked but not verifiable. The publishers' own pages are paywalled or block automated access,
so ratings were read from the Wikipedia prediction table for the Utah House races (which cites them); `as_of` is the date shown there.
`forecasts.csv` holds prediction-market probabilities (`prob_dem`, as of 2026-10-22, read from 2026election.com).

## Demographics

* Source: ACS 2020-2024 5-year, the table-based bulk summary file on www2.census.gov (the Census API now rejects requests without a key).
  Tables B01001, B01002, B01003, B03002, B15003, B19001, B19013 for the state, 29 counties, 4 congressional districts (119th Congress,
  the 2022-2024 map) and 2,020 block groups.
* 2026 districts: UGRC court-ordered boundaries. Each 2020 census block is assigned to a district by its internal point; a block group's
  counts are split by the 2020 population of its blocks in each district; counts are summed and percentages recomputed.
  District medians (age, household income) are interpolated from the summed age and income-bracket counts and are approximate.
* Validation: the same method applied to the 2022-2024 districts reproduces the published ACS CD figures (population within 0.3%,
  shares within about 0.3 points, medians within 1%).
* Registration: Utah Lt. Governor "Active Voters by County and Party" PDF (as of 2026-10-19). `OTH` = Libertarian, Constitution, Forward,
  Green, Independent American. Not published by congressional district, so district units have `registration: null`.
* `pct_urban` is null (not computed).
