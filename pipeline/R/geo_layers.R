# Loading and shaping of boundary layers. Everything is held in NAD83 / UTM 12N (EPSG:26912) so areas and
# point-in-polygon tests are planar; output is converted to WGS84 when written.

geo_crs <- 26912L

to_proj <- \(x) sf::st_transform(sf::st_make_valid(x), geo_crs)

layer_counties <- function() {
  arcgis_layer("UtahCountyBoundaries") |>
    transmute(
      fips = FIPS_STR,
      name = str_to_title(NAME),
      county_nbr = COUNTYNBR
    ) |>
    to_proj() |>
    arrange(fips)
}

layer_districts <- function(service, field) {
  arcgis_layer(service) |>
    transmute(district = as.integer(.data[[field]])) |>
    to_proj() |>
    arrange(district)
}

layer_vista <- function() {
  arcgis_layer("VistaBallotAreas") |> to_proj()
}

# One row per block: the polygon (by id_col) containing the block's internal point, NA when none.
assign_points <- function(points, polys, id_col) {
  joined <- sf::st_join(points, polys[, id_col], join = sf::st_within, left = TRUE)
  joined <- joined[!duplicated(joined$geoid20), ]
  sf::st_drop_geometry(joined)
}

write_topojson <- function(sf_obj, path, object, keep_pct = 8, quantization = 100000, precision = NULL) {
  tmp_dir <- tempfile("topo")
  dir.create(tmp_dir)
  geojson <- file.path(tmp_dir, str_c(object, ".geojson"))
  sf_obj |>
    sf::st_transform(4326) |>
    sf::st_write(geojson, delete_dsn = TRUE, quiet = TRUE)
  args <- c(
    "-y", "mapshaper", geojson,
    "-rename-layers", object,
    if (!is.null(keep_pct)) c("-simplify", str_c(keep_pct, "%"), "visvalingam", "weighted", "keep-shapes"),
    "-o", path, "format=topojson", str_c("quantization=", quantization), "force"
  )
  out <- system2("npx", args, stdout = TRUE, stderr = TRUE)
  if (!file.exists(path)) stop("mapshaper failed: ", str_c(out, collapse = "\n"))
  invisible(path)
}
