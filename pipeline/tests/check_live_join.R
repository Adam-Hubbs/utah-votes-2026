#!/usr/bin/env Rscript
# Every precinct name in a 2026 results export must join to a precincts_2026 polygon.
#   Rscript pipeline/tests/check_live_join.R [path/to/export.json]
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
for (f in c("live_api", "live_normalize")) source(file.path(project_root(), "pipeline", "R", str_c(f, ".R")))

path <- coalesce(commandArgs(trailingOnly = TRUE)[1], raw_dir("probe", "exp2026_now.json"))
parsed <- parse_export(jsonlite::read_json(path))
polygon_ids <- jsonlite::read_json(data_dir("geo", "precincts_2026.topo.json"))$objects$precincts$geometries |>
  map_chr(\(g) g$properties$precinct_id)

reported <- parsed$precincts |>
  mutate(precinct_id = precinct_key(fips, precinct_name)) |>
  summarise(votes = sum(votes), .by = c(precinct_id, contest_id))
unjoined <- reported |> filter(!precinct_id %in% polygon_ids)

cat("reported precinct names:", n_distinct(reported$precinct_id), "\n")
cat("names without a polygon:", n_distinct(unjoined$precinct_id), "(", sum(unjoined$votes), "votes )\n")
unjoined |> distinct(precinct_id) |> print(n = Inf)
cat("polygons never reported:", sum(!polygon_ids %in% reported$precinct_id), "\n")
