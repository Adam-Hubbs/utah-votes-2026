#!/usr/bin/env Rscript
# Builds boundary files (data/geo), per-vintage precinct geometry, and block-level crosswalks.
# Run from anywhere inside the repo: Rscript pipeline/scripts/build_geo.R

suppressPackageStartupMessages(library(sf))
sf_use_s2(FALSE)
source("pipeline/R/utils.R")
for (f in c("geo_sources", "geo_layers", "geo_blocks", "geo_match", "geo_precincts", "geo_vest", "history_ut_export", "history_medsl")) {
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

# ---- 2026 precincts: UGRC ballot areas as they stand now -------------------------------------------
ownership <- matches_2024 |>
  filter(!is.na(vista_id)) |>
  mutate(rank = tier_rank[tier]) |>
  group_by(county_fips, vista_id) |>
  filter(rank == min(rank)) |>
  ungroup() |>
  distinct(county_fips, precinct, vista_id)
one_to_one <- ownership |>
  mutate(n_vista = n(), .by = c(county_fips, precinct)) |>
  mutate(n_owner = n(), .by = c(county_fips, vista_id)) |>
  filter(n_vista == 1, n_owner == 1) |>
  select(county_fips, vista_id, reported = precinct)

vista_meta <- vista |>
  st_drop_geometry() |>
  as_tibble() |>
  mutate(
    county_fips = sprintf("49%03d", CountyID * 2L - 1L),
    id_np = str_remove(VistaID, str_c("^0?", CountyID))
  ) |>
  distinct(county_fips, vista_id = VistaID, id_np, AliasName)

units_2026_geom <- vista_geom |>
  left_join(vista_meta, by = c("county_fips", "vista_id")) |>
  left_join(one_to_one, by = c("county_fips", "vista_id")) |>
  mutate(
    name = coalesce(reported, id_np),
    precinct_id = precinct_key(county_fips, name)
  )
dup <- units_2026_geom |> st_drop_geometry() |> count(precinct_id) |> filter(n > 1)
if (nrow(dup) > 0) {
  message("2026 duplicate precinct ids resolved with vista id suffix: ", nrow(dup))
  units_2026_geom <- units_2026_geom |>
    mutate(precinct_id = if_else(precinct_id %in% dup$precinct_id, precinct_key(county_fips, str_c(name, "~", id_np)), precinct_id))
}
units_2026_geom <- units_2026_geom |>
  mutate(unit_id = precinct_id, vista_key = str_c(county_fips, "|", vista_id))
blocks_tbl <- blocks_tbl |>
  left_join(units_2026_geom |> st_drop_geometry() |> select(vista_key, unit2026 = unit_id), by = "vista_key")

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
