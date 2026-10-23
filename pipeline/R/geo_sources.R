source_if_missing <- function(fn, file) {
  if (!exists(fn, mode = "function")) source(file)
}

ugrc_base <- "https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services"

download_cached <- function(url, dest, force = FALSE) {
  if (force || !file.exists(dest) || file.size(dest) == 0) {
    httr2::request(url) |>
      httr2::req_retry(max_tries = 4) |>
      httr2::req_timeout(900) |>
      httr2::req_perform(path = dest)
  }
  dest
}

# Pages by OBJECTID because exceededTransferLimit caps each response at 1-2k features.
arcgis_layer <- function(service, layer = 0, force = FALSE) {
  dest <- raw_dir("geo", str_c("ugrc_", service, ".geojson"))
  if (!force && file.exists(dest)) return(sf::st_read(dest, quiet = TRUE))
  url <- str_c(ugrc_base, "/", service, "/FeatureServer/", layer, "/query")
  page_size <- 1000L
  fetch_page <- \(offset) {
    path <- tempfile(fileext = ".geojson")
    httr2::request(url) |>
      httr2::req_url_query(
        where = "1=1", outFields = "*", outSR = 4326, f = "geojson",
        resultOffset = offset, resultRecordCount = page_size,
        orderByFields = "OBJECTID"
      ) |>
      httr2::req_retry(max_tries = 4) |>
      httr2::req_perform(path = path)
    sf::st_read(path, quiet = TRUE)
  }
  pages <- list()
  offset <- 0L
  repeat {
    page <- fetch_page(offset)
    if (nrow(page) == 0) break
    pages[[length(pages) + 1L]] <- page
    offset <- offset + nrow(page)
    if (nrow(page) < 10) break
  }
  out <- dplyr::bind_rows(pages)
  sf::st_write(out, dest, delete_dsn = TRUE, quiet = TRUE)
  out
}
