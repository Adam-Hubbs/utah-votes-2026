# Utah Votes 2026

A static, server-free Utah election site: poll tracker and poll averages, prognosticator ratings,
demographics, historical results, and a live election-night dashboard with county and precinct maps,
a Bayesian estimate of the vote still to be counted, and an NYT-style live needle. Utah is the focus;
state races (legislature, judicial retention, school board) and a small national U.S. Senate/House
section are included.

See the site here: [https://adam-hubbs.github.io/utah-votes-2026/#/results]

See [ARCHITECTURE.md](ARCHITECTURE.md) for the data contracts and design decisions.

## Layout

| Path | What |
|---|---|
| `polls/` | NYT poll CSVs. Can be hosted elsewhere and updated independently (`POLLS_BASE_URL`). |
| `pipeline/` | R data pipeline (tidyverse). Scripts in `pipeline/scripts/`, hand-maintained inputs in `pipeline/config/`, runbooks in `pipeline/docs/`. |
| `web/` | Vite + React + TypeScript + D3 front end. Everything the site reads lives in `web/public/data/`. |
| `.github/workflows/` | Deploy, poll refresh, election-night loop, post-election canvass. |

## Run the site locally

```sh
cd web
npm ci
npm run dev          # http://localhost:5173
```

URL switches (kept for the browser session):

* `?sim=1` — a simulated election night (`data/results/2026-sim/`), to preview the live dashboard.
* `?mode=pre|live|final` — force the page mode.
* `?mock=1` — the front end's synthetic mock data (`web/public/mock/data/`).

`npm run build` writes a fully static site to `web/dist/` (relative paths, hash routing — it works from any
sub-path on GitHub Pages or Cloudflare Pages).

## Refresh data

Run from the repository root. Downloads are cached in `pipeline/raw/` (gitignored).

```sh
Rscript pipeline/scripts/build_polls.R            # polls, averages, national context (POLLS_BASE_URL optional)
Rscript pipeline/scripts/build_ratings.R          # race ratings from pipeline/config/ratings.csv
Rscript pipeline/scripts/build_national.R         # U.S. Senate/House tab
Rscript pipeline/scripts/build_2026_contests.R    # 2026 contests, candidates, pre-election files
Rscript pipeline/scripts/build_legislature.R      # legislature seats, judges
Rscript pipeline/scripts/build_geo.R              # boundaries, precinct vintages, crosswalks (slow, needs sf + npx mapshaper)
Rscript pipeline/scripts/build_history.R          # historical results, district baselines, county trends
Rscript pipeline/scripts/build_demographics.R     # ACS + voter registration (needs sf, pdftotext)
Rscript pipeline/scripts/scrape_live.R --simulate-sequence   # rebuild the simulated night
```

## Election night

Full runbook: [`pipeline/docs/live.md`](pipeline/docs/live.md). In short:

* `scrape_live.R` pulls the Lt. Governor's results export (statewide, county and precinct results), normalizes it,
  runs the expected-vote model and the needle, and writes `web/public/data/results/2026-general/`.
* The `election-night.yml` workflow runs one long job that loops scrape → model → commit → deploy every few minutes,
  with a cron watchdog that restarts it if it dies. `canvass.yml` keeps updating every 30 minutes for two weeks.
* If GitHub's runners can't reach the results site, run `pipeline/scripts/election_night_loop.sh` on a laptop.
* There are no race calls. Winners are marked automatically once Utah's results are official; until then candidates are
  shown as leading. The national tab is pre-election context only (see [`pipeline/docs/national.md`](pipeline/docs/national.md)).
* If a county announces how many ballots it still has to count, enter it in `pipeline/config/remaining_ballots.csv`.

## Hosting (not set up yet)

Push to GitHub, enable Pages with "GitHub Actions" as the source, and `deploy.yml` publishes `web/dist` on every push
to `main`. The poll-refresh and election-night workflows need `contents: write` and `actions: write` permissions
(already declared) and an optional repository variable `POLLS_BASE_URL`.
