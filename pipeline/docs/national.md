# National (U.S. Senate and House) tab

Utah is the focus; this is a small context layer. Everything is static JSON under `web/public/data/national/`.

## Inputs

| file | what | maintained by |
|---|---|---|
| `pipeline/config/national_senate.csv` | 35 races (33 Class 2 + FL and OH specials): incumbent, open seat, Cook / Sabato / Inside ratings | by hand, from Wikipedia "2026 United States Senate elections" predictions table (ratings as of 2026-10-14 to 10-20) |
| `pipeline/config/national_senate_candidates.csv` | nominees and notable independents; `main_opponent` marks the independent who is the real challenger where the Democrat withdrew (ID, NE, SD); `poll_name` maps to the NYT spelling | by hand |
| `pipeline/config/national_meta.json` | Senate composition (53 R, 45 D, 2 I; 31 R / 32 D / 2 I not up), House composition (218 R, 214 D, 1 I, 2 vacant), rating source dates | by hand |
| `pipeline/config/national_house_ratings.csv` | House seat counts per category for Cook, Inside, Sabato | `Rscript pipeline/scripts/update_national_house_ratings.R` (parses Wikipedia's ratings page; Solid = outlet total minus listed competitive seats) |
| `pipeline/config/national_calls.csv` | election-night calls | by hand during the night |
| `polls/senate.csv`, `polls/house.csv` | NYT poll database | external (`POLLS_BASE_URL` honoured) |

Poll averages reuse `average_candidates()` / `average_margin()` with the Utah state-average settings from `pipeline/config/polls.json`. Only general-election questions with the Republican nominee and the Democratic nominee (or main independent) are used, from the last 120 days. Margin = Republican minus main opponent, in points (positive = R). Poll values stay on the 0-100 scale; seat counts are integers.

## Outputs

`senate.json`, `senate_polls.json` (trackers for the 8 closest polled races, same shape as `polls/polls.json` + `averages.json` with contest ids `senate-XX`), `house.json`; the same files under `sim/` for `?sim=1` (built with `build_national.R --sim` from `national_calls_sim.csv`).

## Election night: calls are manual

No free, official, machine-readable national results feed exists. AP's feed is paid and its terms forbid redistribution; networks' pages are not licensed for scraping. State election offices publish JSON feeds (for example North Carolina, Georgia, Maine, Ohio, Texas), but each is a different, undocumented schema whose 2026 election-night URLs are not published ahead of time, so we could not verify any of them. We therefore did not implement `scrape_national.R`. If you verify a state feed before the night, add a scraper that writes rows to `national_calls.csv`-compatible output.

To enter a call (from a news organization's projection, such as AP, NBC, CNN, Fox):

1. Quick: `Rscript pipeline/scripts/add_national_call.R senate ME REP "Susan Collins" "AP"` (House: `house CA 22 DEM "Name" "AP"`; use `-` for no district). It adds or replaces the row and rebuilds the JSON.
2. Or edit `pipeline/config/national_calls.csv` directly (columns: chamber, state, district, winner_party DEM|REP|IND, winner_name, called_by, called_at, note) and push to `main`; the election-night loop pulls, rebuilds (`build_national.R`) and commits `web/public/data/national` on every pass.

Rows with an invalid chamber or party fail the build loudly and the previous JSON stays in place. The page stays useful with no calls (ratings, polls, composition).
