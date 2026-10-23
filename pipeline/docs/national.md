# National (U.S. Senate and House) tab

Utah is the focus; this is a small context layer. Everything is static JSON under `web/public/data/national/`.

## Inputs

| file | what | maintained by |
|---|---|---|
| `pipeline/config/national_senate.csv` | 35 races (33 Class 2 + FL and OH specials): incumbent, open seat, Cook / Sabato / Inside ratings | by hand, from Wikipedia "2026 United States Senate elections" predictions table (ratings as of 2026-10-14 to 10-20) |
| `pipeline/config/national_senate_candidates.csv` | nominees and notable independents; `main_opponent` marks the independent who is the real challenger where the Democrat withdrew (ID, NE, SD); `poll_name` maps to the NYT spelling | by hand |
| `pipeline/config/national_meta.json` | Senate composition (53 R, 45 D, 2 I; 31 R / 32 D / 2 I not up), House composition (218 R, 214 D, 1 I, 2 vacant), rating source dates | by hand |
| `pipeline/config/national_house_ratings.csv` | House seat counts per category for Cook, Inside, Sabato | `Rscript pipeline/scripts/update_national_house_ratings.R` (parses Wikipedia's ratings page; Solid = outlet total minus listed competitive seats) |
| `polls/senate.csv`, `polls/house.csv` | NYT poll database | external (`POLLS_BASE_URL` honoured) |

Poll averages reuse `average_candidates()` / `average_margin()` with the Utah state-average settings from `pipeline/config/polls.json`. Only general-election questions with the Republican nominee and the Democratic nominee (or main independent) are used, from the last 120 days. Margin = Republican minus main opponent, in points (positive = R). Poll values stay on the 0-100 scale; seat counts are integers.

## Outputs

`senate.json`, `senate_polls.json` (trackers for the 8 closest polled races, same shape as `polls/polls.json` + `averages.json` with contest ids `senate-XX`), `house.json`.

## Election night: no national results

The national tab and header ticker are pre-election context only (current composition, consensus ratings, poll averages) and are labelled that way. We do not report national results or calls: no free, permitted machine-readable feed exists (AP's is paid and forbids redistribution; networks are not licensed for scraping; state feeds are undocumented and vary), and race calls are not entered by hand.
