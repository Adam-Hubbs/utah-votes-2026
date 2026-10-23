# Geography and historical results

Build: `export UTEL_RAW_DIR=<shared raw cache>; Rscript pipeline/scripts/build_geo.R; Rscript pipeline/scripts/build_history.R`
(geo first; it leaves block assignments and name matches in `$UTEL_RAW_DIR/geo/build_geo_state.rds`). Downloads are cached in the raw dir.
Extra R dependencies beyond DESCRIPTION: none (uses sf, httr2, readr, jsonlite, purrr, dplyr, tidyr, stringr). `npx mapshaper` is required.

## Sources

| output | source | vintage |
|---|---|---|
| counties, cd2022, cd2026, cd2012, state_house, state_senate, places | UGRC ArcGIS services (services1.arcgis.com/99lidPhWCzftIe9K): UtahCountyBoundaries, political_us_congress_districts_2022_to_2026, political_us_congress_districts_2026_to_2032, USCongressDistricts2012, UtahHouseDistricts2022to2032, UtahSenateDistricts2022to2032, UtahMunicipalBoundaries | current |
| precincts_2026 | UGRC VistaBallotAreas (3,341 rows, edits dated 2025-04 to 2026-09) | 2026 |
| precincts_2016/2018/2020 | VEST on Harvard Dataverse (ut_YYYY.zip in doi:10.7910/DVN/NH5S2I, UBKYRU, K7760H) | original |
| precincts_2024, precincts_2022 | reconstructed, see below | approximate |
| 2024 results | official media export `Utah/export-general11052024.json` | final |
| 2022 results | MEDSL 2022 Utah precinct file (doi:10.7910/DVN/UYQIEP) | final |
| 2016/2018/2020 statewide contests | VEST shapefile attributes | final |
| 2016/2018/2020 U.S. House (county level only) | OpenElections `openelections-data-ut` (2016, 2018 county files; 2020 precinct file summed to counties) | see caveats |
| blocks | Census TIGER 2020 tabblock20 + P.L. 94-171 (ut2020.pl.zip: P1_001N, P3_001N) | 2020 |

The Census API now demands a key for block-level queries, so the P.L. files from the Census FTP site are used instead.

## 2024 and 2022 precinct geometry (important caveat)

No openly archived 2024 or 2022 Utah precinct boundaries exist: VEST 2022/2024 are not on Dataverse (the UF Election Lab copy is
fee-for-service), and UGRC only publishes the live layer plus a 2011 archive. `precincts_2024` and `precincts_2022` are therefore
reconstructed: each precinct name in the results is matched (county-specific rules in `pipeline/R/geo_match.R`) to the current UGRC
ballot areas, and matched areas are unioned into one geometry per reported precinct. Where several reported names fall into one
UGRC area they are merged into one unit (the results file uses the highest-vote name as `precinct_id`).

Match tiers (share of 2024 presidential votes): exact name 88.0%, abbreviation rule 4.8%, parent precinct 2.8%, approximate (Summit
County, letters-only) 1.6%, alias 1.2%, unmatched 1.6%. Statewide 98.4% of 2024 votes (94.8% of precincts) and 97.9% of 2022 votes
carry a geometry; per-county rates are in `data/geo/match_rates.json` and `geo/meta.json`.
Weak spots: Utah County (95.3% of votes; district-digit rule on names such as AF301 -> AF01), Washington (95.3%), Summit (94.7%),
Tooele (96.4%), Wayne (82.6%), and 2022 Emery (0%), Juab (73%), Duchesne (90.5%). Even exact-name matches can differ in shape from the
true 2024 precinct where a county redrew lines after 2024. Unmatched precincts have votes in the county totals but no geometry.

## Crosswalks and baselines

Blocks are assigned by internal point (point on surface). weight(s -> t) = VAP(s and t) / VAP(s), falling back to total population then
equal split. `history/crosswalks/precinct_2024_to_cd2026.json` and `..._to_precinct_2026.json` are committed (about 0.3 MB).
Baselines aggregate every statewide contest (president, U.S. Senate, governor, AG, auditor, treasurer) of 2016-2024 into cd2026
and cd2022. Votes in reported precincts without geometry are spread over the county's uncovered blocks by VAP, so district totals sum to
official statewide totals. The 2022 U.S. Senate had no Democratic nominee (McMullin, unaffiliated, is in OTH); those rows carry a `note`.

## Caveats

* 2016/2018/2020 U.S. House results exist at county level only (counties list the portion of a split county per district; no precinct
  rows). 2020 comes from summed OpenElections precinct rows with inconsistent candidate spellings; candidates are matched by surname
  and totals look right (e.g. UT-4 Owens 179,688 vs McAdams 175,923) but they were not audited against certified canvass files.
* Write-in candidates are dropped for 2022 (MEDSL) and for the VEST/OpenElections years; 2024 includes the export's write-in lines.
* `incumbent` flags come from a hand-kept table in `history_common.R`.
* Party for some minor 2022 candidates is `OTH` where it could not be established from the sources.
* 2024 Constitutional Amendment A does not appear in the official export (only B and C).
* Election ids in `results/index.json` have `precinct_geo` of precincts_YYYY and `cd_plan` cd2012 (2016-2020) or cd2022 (2022-2024).
* Simplified TopoJSON precinct layers fail strict validity tests in a few spots (mapshaper `keep-shapes` simplification); they render fine.
