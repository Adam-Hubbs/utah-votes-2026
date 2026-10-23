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

Match tiers (share of 2024 presidential votes): exact name 88.1%, abbreviation rule 4.8%, parent precinct 2.8%, approximate (Summit
letters-only, Washington "CO..." county areas, federal-only) 1.9%, alias 1.2%, unmatched 1.1%. Statewide 98.9% of 2024 votes (95.7% of precincts) and
98.9% of 2022 votes (92.3% of precincts) carry a geometry; per-county rates are in `data/geo/match_rates.json` and `geo/meta.json`.
Weak spots that remain: Utah County (95.3% of 2024 votes; 98 reported precincts incl. SQ410, OR360-363, PR367-369 have no 2026 counterpart, the
"N..." and most "U..." names are zero-vote), Summit (SSE13, SSS11, SSW22, NSN24 have no UGRC area), Tooele (ST02, LC01, TE01, IB01, DG02 have no
UGRC area), Carbon and Utah in 2022. Even exact-name matches can differ in shape from the true 2024 precinct where a county redrew lines after 2024.
Unmatched precincts have votes in the county totals but no geometry.

Matching rules added for blank-precinct work (`geo_match.R`): Washington "CO"+code county areas -> "X"+code (CODAV -> XDAV:01, CONH28 -> XNHS:28);
Cache "MEN02:I" -> "MEN:I"; Emery 2022 "Ferron #2" -> parent 2; Juab 2022 "MO" -> MO1+MO2, "CA11" -> CA1; Wayne "Torrey" prefers TO06 over
TE05; reported "Federal" -> a UGRC FED area when the county has one. After clustering, a populated sub-area (`:1`, `:2U`, ...) whose reported row has zero
votes while a sibling of the same parent precinct has votes joins the sibling's unit (`merge_zero_vote_siblings`, e.g. Tooele LP01:1 + LP01:2).

## Blank precinct polygons

`Rscript pipeline/tests/diagnose_blank_precincts.R` classifies polygons with no votes in a statewide contest (a: no residents, c: populated and a
same-prefix neighbour has more votes than residents, d: other) and counts reported precincts that matched nothing (b). Polygons come from matches, so a
failed match shows up as missing area and missing votes (b), not as a blank polygon.

| year | polygons | blank before | blank after | a no residents | c combined | d other | b unmatched precincts / votes |
|---|---|---|---|---|---|---|---|
| 2016 | 2296 | 101 | 101 | 75 | 7 | 19 | VEST, none |
| 2018 | 2337 | 121 | 121 | 86 | 7 | 28 | VEST, none |
| 2020 | 2423 | 161 | 161 | 122 | 16 | 23 | VEST, none |
| 2022 | 2509 | 105 | 91 | 76 | 7 | 8 | 220 / 12,337 (was 258 / 22,615) |
| 2024 | 2792 | 281 | 228 | 164 | 29 | 35 | 133 / 16,928 (was 163 / 23,277) |

Category d includes group quarters (2024 Draper DRP901 holds the state prison, 3,151 VAP and no voters). The 2022 geometry also has units whose number was reused
by a different area in 2026 (Nephi NE1/NE2 have votes but no residents inside the polygon); those cannot be fixed without 2022 boundaries.

`vap` (2020 voting-age population) is written on every precinct polygon so the map can separate legitimately empty areas from populated ones with no result.

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
