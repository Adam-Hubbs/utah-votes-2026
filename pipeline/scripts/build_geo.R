#!/usr/bin/env Rscript
# Builds boundary files (data/geo), per-vintage precinct geometry, and block-level crosswalks.
# Run from anywhere inside the repo: Rscript pipeline/scripts/build_geo.R

suppressPackageStartupMessages(library(sf))
sf_use_s2(FALSE)
source("pipeline/R/utils.R")
for (f in c("geo_sources", "geo_layers", "geo_blocks", "geo_match", "geo_precincts", "geo_alias2026", "geo_vest", "history_ut_export", "history_medsl")) {
  source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))
}
if (Sys.getenv("UTEL_RAW_DIR") == "") message("UTEL_RAW_DIR not set; using ", raw_dir("x") |> dirname())

geo_out <- \(...) data_dir("geo", ...)
simplify_pct <- 12

# ---- boundaries -----------------------------------------------------------------------------------
counties <- layer_counties()
cd2026 <- layer_districts("political_us_congress_districts_2026_to_2032", "DISTRICT")
cd2022 <- layer_districts("political_us_congress_districts_2022_to_2026", "DISTRICT")
cd2012 <- layer_districts("USCongressDistricts2012", "DISTRICT")
state_house <- layer_districts("UtahHouseDistricts2022to2032", "DIST")
state_senate <- layer_districts("UtahSenateDistricts2022to2032", "DIST")

stopifnot(
  setequal(counties$fips, utah_counties$fips),
  nrow(cd2026) == 4, nrow(cd2022) == 4, nrow(cd2012) == 4,
  nrow(state_house) == 75, nrow(state_senate) == 29
)

# The court-ordered 2026 map must have a Salt Lake County district 1; fail loudly if UGRC changes the layer.
slc <- counties |> filter(fips == "49035")
d1_share <- cd2026 |>
  filter(district == 1) |>
  st_intersection(slc) |>
  st_area() |>
  as.numeric() / as.numeric(st_area(filter(cd2026, district == 1)))
stopifnot(d1_share > 0.99)

write_topojson(counties, geo_out("counties.topo.json"), "counties", keep_pct = 10)
write_topojson(cd2026, geo_out("cd2026.topo.json"), "districts", keep_pct = 10)
write_topojson(cd2022, geo_out("cd2022.topo.json"), "districts", keep_pct = 10)
write_topojson(cd2012, geo_out("cd2012.topo.json"), "districts", keep_pct = 10)
write_topojson(state_house, geo_out("state_house.topo.json"), "districts", keep_pct = 10)
write_topojson(state_senate, geo_out("state_senate.topo.json"), "districts", keep_pct = 10)

# ---- places ---------------------------------------------------------------------------------------
places <- arcgis_layer("UtahMunicipalBoundaries") |>
  to_proj() |>
  arrange(desc(POPLASTCENSUS)) |>
  slice_head(n = 25)
place_pts <- places |>
  st_point_on_surface() |>
  st_transform(4326)
places_tbl <- tibble(
  name = places$NAME,
  lon = round(st_coordinates(place_pts)[, 1], 4),
  lat = round(st_coordinates(place_pts)[, 2], 4),
  rank = seq_len(nrow(places)),
  population = places$POPLASTCENSUS
)
write_site_json(places_tbl, "geo", "places.json")

# ---- blocks ---------------------------------------------------------------------------------------
blocks <- blocks_points()

nearest_fill <- function(blocks_pts, polys, col) {
  hit <- st_join(blocks_pts, polys[col], join = st_within)
  hit <- hit[!duplicated(hit$geoid20), ]
  missing <- which(is.na(st_drop_geometry(hit)[[col]]))
  if (length(missing) > 0) {
    nearest <- st_nearest_feature(hit[missing, ], polys)
    hit[[col]][missing] <- st_drop_geometry(polys)[[col]][nearest]
  }
  st_drop_geometry(hit)[[col]]
}

blocks_tbl <- st_drop_geometry(blocks) |> as_tibble()
blocks_tbl$cd2012 <- nearest_fill(blocks, cd2012 |> rename(cd2012 = district), "cd2012")
blocks_tbl$cd2022 <- nearest_fill(blocks, cd2022 |> rename(cd2022 = district), "cd2022")
blocks_tbl$cd2026 <- nearest_fill(blocks, cd2026 |> rename(cd2026 = district), "cd2026")

# ---- Vista (current UGRC) ballot areas ------------------------------------------------------------
vista <- layer_vista()
vista_geom <- vista_by_id(vista)
vista_for_blocks <- vista_geom |> mutate(vista_key = str_c(county_fips, "|", vista_id))
blocks_vista <- st_join(blocks, vista_for_blocks["vista_key"], join = st_within)
blocks_vista <- blocks_vista[!duplicated(blocks_vista$geoid20), ]
vk <- st_drop_geometry(blocks_vista)$vista_key
# Blocks that fall in a gap between ballot areas are attached to the nearest area of their own county.
gap <- which(is.na(vk))
if (length(gap) > 0) {
  gap_fix <- map_chr(gap, \(i) {
    pool <- vista_for_blocks |> filter(county_fips == blocks$county_fips[i])
    pool$vista_key[st_nearest_feature(blocks[i, ], pool)]
  })
  vk[gap] <- gap_fix
}
blocks_tbl$vista_key <- vk
message("blocks outside any ballot area (attached to nearest): ", length(gap))

# ---- 2024 reported precincts matched onto Vista features -------------------------------------------
export_2024 <- download_cached(
  ut_export_url("Utah/export-general11052024.json"),
  raw_dir("results", "export-general11052024.json")
) |>
  ut_export_contest_tables()
votes_2024 <- export_2024$local |>
  filter(item_id == "State-1") |>
  summarise(votes = sum(votes), .by = c(county_fips, precinct))
v24 <- build_reported_vintage(votes_2024, vista, vista_geom, blocks_tbl, cd2022 |> rename(district = district), "cd2022")
matches_2024 <- v24$matches
cl_2024 <- list(members = v24$members, vista_units = v24$vista_units)
units_2024 <- v24$units
blocks_tbl$unit2024 <- v24$block_unit

# ---- 2022 reported precincts (MEDSL) -------------------------------------------------------------------
medsl_2022 <- medsl_2022_long()
votes_2022 <- medsl_2022 |>
  filter(office == "US SENATE") |>
  summarise(votes = sum(votes), .by = c(county_fips, precinct))
v22 <- build_reported_vintage(votes_2022, vista, vista_geom, blocks_tbl, cd2022, "cd2022")
units_2022 <- v22$units
blocks_tbl$unit2022 <- v22$block_unit

# ---- 2026 precincts: UGRC ballot areas, named as the 2026 results name them --------------------------
# precinct_id must equal the id the results use (precinct_key(fips, reported name)); see geo_alias2026.R.
reported_2026 <- read_reported_2026()
alias_2026 <- alias_reported_2026(reported_2026, vista) |>
  mutate(unit_id = precinct_key(county_fips, precinct))
claimed <- alias_2026 |>
  distinct(county_fips, VistaID) |>
  mutate(n_claims = n(), .by = c(county_fips, VistaID))
stopifnot(all(claimed$n_claims == 1))

vista_meta <- vista |>
  st_drop_geometry() |>
  as_tibble() |>
  mutate(
    county_fips = sprintf("49%03d", CountyID * 2L - 1L),
    id_np = str_remove(VistaID, str_c("^0?", CountyID))
  ) |>
  distinct(county_fips, vista_id = VistaID, id_np)

alias_units <- alias_2026 |>
  transmute(county_fips, vista_id = VistaID, unit_id, name = precinct)
leftover <- vista_meta |>
  anti_join(alias_units, by = c("county_fips", "vista_id")) |>
  transmute(county_fips, vista_id, name = id_np, unit_id = precinct_key(county_fips, id_np))
unit_map <- bind_rows(alias_units, leftover)
dup_units <- unit_map |> distinct(unit_id, county_fips, vista_id) |> count(unit_id, vista_id) |> filter(n > 1)
stopifnot(nrow(dup_units) == 0)
clash <- leftover |> filter(unit_id %in% alias_units$unit_id)
if (nrow(clash) > 0) {
  message("unclaimed ballot areas whose id collides with a reported precinct: ", nrow(clash))
  unit_map <- unit_map |>
    mutate(unit_id = if_else(vista_id %in% clash$vista_id & !(vista_id %in% alias_units$vista_id), precinct_key(county_fips, str_c(name, "~", vista_id)), unit_id))
}

units_2026_geom <- vista_geom |>
  rename(vista_id = vista_id) |>
  inner_join(unit_map, by = c("county_fips", "vista_id")) |>
  group_by(unit_id, county_fips, name) |>
  summarise(vista_id = first(vista_id), geometry = sf::st_union(geometry), .groups = "drop") |>
  mutate(precinct_id = unit_id)
blocks_tbl <- blocks_tbl |>
  left_join(
    unit_map |> transmute(vista_key = str_c(county_fips, "|", vista_id), unit2026 = unit_id),
    by = "vista_key"
  )
stopifnot(!anyNA(blocks_tbl$unit2026))

units_2026 <- units_2026_geom |>
  plurality_district(blocks_tbl, "unit2026", "cd2026", cd2026) |>
  transmute(
    precinct_id,
    county_fips,
    name,
    cd2026 = district,
    vista_id
  )

# ---- VEST vintages (2016, 2018, 2020) --------------------------------------------------------------
vest <- map(c(`2016` = 2016, `2018` = 2018, `2020` = 2020), vest_precincts)
vest_unit_ids <- imap(vest, \(sf_y, yr) {
  hit <- st_join(blocks, sf_y["unit_id"], join = st_within)
  hit <- hit[!duplicated(hit$geoid20), ]
  ids <- st_drop_geometry(hit)$unit_id
  gap <- which(is.na(ids))
  ids[gap] <- map_chr(gap, \(i) {
    pool <- sf_y |> filter(county_fips == blocks$county_fips[i])
    if (nrow(pool) == 0) NA_character_ else pool$unit_id[st_nearest_feature(blocks[i, ], pool)]
  })
  ids
})
for (yr in names(vest_unit_ids)) blocks_tbl[[str_c("unit", yr)]] <- vest_unit_ids[[yr]]

cd_plan_for_year <- c(`2016` = "cd2012", `2018` = "cd2012", `2020` = "cd2012")
vest_out <- imap(vest, \(sf_y, yr) {
  plan_col <- cd_plan_for_year[[yr]]
  polys <- get(plan_col)
  sf_y |>
    plurality_district(blocks_tbl, str_c("unit", yr), plan_col, polys) |>
    transmute(precinct_id, county_fips, name, !!plan_col := district)
})

# ---- write precinct topojson -----------------------------------------------------------------------
write_topojson(units_2026, geo_out("precincts_2026.topo.json"), "precincts", keep_pct = simplify_pct)
write_topojson(units_2024, geo_out("precincts_2024.topo.json"), "precincts", keep_pct = simplify_pct)
write_topojson(units_2022, geo_out("precincts_2022.topo.json"), "precincts", keep_pct = simplify_pct)
iwalk(vest_out, \(x, yr) write_topojson(x, geo_out(str_c("precincts_", yr, ".topo.json")), "precincts", keep_pct = simplify_pct))

# ---- match tiers and metadata -----------------------------------------------------------------------
tier_votes <- \(matches, votes) {
  matches |>
    filter(!is.na(vista_id)) |>
    mutate(rank = tier_rank[tier]) |>
    summarise(tier = first(tier[rank == min(rank)]), .by = c(county_fips, precinct)) |>
    right_join(votes, by = c("county_fips", "precinct")) |>
    mutate(tier = coalesce(tier, "unmatched")) |>
    summarise(precincts = n(), votes = sum(votes), .by = tier) |>
    mutate(pct_votes = round(votes / sum(votes), 4)) |>
    arrange(desc(votes))
}
tiers_json <- \(tbl) pmap(tbl, \(tier, precincts, votes, pct_votes) list(tier = tier, precincts = precincts, votes = votes, pct_votes = pct_votes))

meta <- list(
  generated = format(Sys.Date()),
  projection = "WGS84 (EPSG:4326); built in NAD83 / UTM 12N, simplified with mapshaper (Visvalingam, keep-shapes), TopoJSON quantization 1e5",
  simplification = list(precincts = str_c(simplify_pct, "% of vertices retained"), districts_counties = "10% of vertices retained"),
  boundaries = list(
    counties = list(source = "UGRC UtahCountyBoundaries (services1.arcgis.com/99lidPhWCzftIe9K)", vintage = "current"),
    cd2026 = list(
      source = "UGRC political_us_congress_districts_2026_to_2032 (court-ordered map, Nov 2025)",
      note = "District 1 lies entirely in Salt Lake County (verified at build time)"
    ),
    cd2022 = list(source = "UGRC political_us_congress_districts_2022_to_2026", used_for = "2022-2024 elections"),
    cd2012 = list(source = "UGRC USCongressDistricts2012", used_for = "2016-2020 elections"),
    state_house = list(source = "UGRC UtahHouseDistricts2022to2032"),
    state_senate = list(source = "UGRC UtahSenateDistricts2022to2032"),
    places = list(source = "UGRC UtahMunicipalBoundaries; 25 largest by 2020 census population; point on surface of boundary")
  ),
  precincts = list(
    precincts_2026 = list(
      source = "UGRC VistaBallotAreas FeatureServer, retrieved on the build date; one feature per VistaID (sub-precinct level where UGRC has sub-precincts)",
      vintage = "2026 ballot areas (UGRC edits dated 2025-04 to 2026-09)",
      naming = "precinct_id is {county_fips}-{precinct name exactly as the 2026 results report it}, so geometry joins to results by id. Reported names are mapped to UGRC ballot areas by pipeline/R/geo_alias2026.R (a reported precinct covering several sub-precinct areas becomes one dissolved unit); ballot areas no reported name covers keep their VistaID without the county prefix. `vista_id` is the first UGRC id of the unit.",
      reported_match = list(precincts = nrow(reported_2026), matched = n_distinct(alias_2026$precinct, alias_2026$county_fips), note = "unmatched names are federal-only precincts (no residents) plus 3UNKN (Cache) and Fountain Green U (Sanpete)"),
      cd2026 = "plurality of block voting-age population (internal points) within the feature"
    ),
    precincts_2024 = list(
      source = "RECONSTRUCTED. No archived 2024 precinct boundaries are openly available (VEST 2024 is fee-for-service at the UF Election Lab; UGRC publishes only the current layer and a 2011 archive). Names reported in the official 2024 media export were matched to the current UGRC ballot areas and the matched areas merged into one geometry per reported precinct.",
      vintage = "2026 UGRC geometry grouped to 2024 reported precincts; boundaries may differ from the 2024 originals where counties redrew precincts after the 2024 election (notably Summit and Utah counties, where numbering changed)",
      match_tiers = tiers_json(tier_votes(matches_2024, votes_2024)),
      cd2022 = "plurality of block voting-age population within the unit"
    ),
    precincts_2022 = list(
      source = "RECONSTRUCTED the same way as precincts_2024 from MEDSL 2022 precinct names (Harvard Dataverse doi:10.7910/DVN/UYQIEP)",
      vintage = "2026 UGRC geometry grouped to 2022 reported precincts (approximate)",
      match_tiers = tiers_json(tier_votes(v22$matches, votes_2022))
    ),
    precincts_2020 = list(source = "VEST 2020 Precinct-Level Election Results (Harvard Dataverse doi:10.7910/DVN/K7760H)", vintage = "2020 originals"),
    precincts_2018 = list(source = "VEST 2018 Precinct-Level Election Results (doi:10.7910/DVN/UBKYRU)", vintage = "2018 originals"),
    precincts_2016 = list(source = "VEST 2016 Precinct-Level Election Results (doi:10.7910/DVN/NH5S2I)", vintage = "2016 originals")
  ),
  crosswalks = list(
    method = "2020 Census blocks (TIGER/Line tabblock20) with P.L. 94-171 total population (P1_001N) and voting-age population (P3_001N, ut2020.pl). Each block's internal point (point on surface) is assigned to a precinct of each vintage and to each congressional plan; weight(source s -> target t) = VAP(s and t) / VAP(s). Precincts with no VAP fall back to total population, then to equal split.",
    blocks = nrow(blocks_tbl),
    total_population = sum(blocks_tbl$pop),
    voting_age_population = sum(blocks_tbl$vap),
    files = c("history/crosswalks/precinct_2024_to_cd2026.json", "history/crosswalks/precinct_2024_to_precinct_2026.json"),
    unmatched_votes = "Votes in reported precincts that could not be matched to geometry are spread over the county's uncovered blocks by VAP when building district baselines"
  )
)
write_site_json(meta, "geo", "meta.json")

# ---- keep tables for the history build ------------------------------------------------------------
saveRDS(
  list(
    blocks = blocks_tbl,
    matches_2024 = matches_2024,
    reported_clusters_2024 = cl_2024$members,
    matches_2022 = v22$matches,
    reported_clusters_2022 = v22$members,
    units_2024_ids = units_2024 |> st_drop_geometry(),
    units_2022_ids = units_2022 |> st_drop_geometry(),
    units_2026_ids = units_2026 |> st_drop_geometry()
  ),
  raw_dir("geo", "build_geo_state.rds")
)
message("geo build complete")
