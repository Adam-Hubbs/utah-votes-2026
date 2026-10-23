house_rating_sources <- tibble(
  col = 1:3,
  source = c("cook", "inside", "sabato"),
  name = c("Cook Political Report", "Inside Elections", "Sabato's Crystal Ball")
)

# Wikipedia lists only seats rated competitive by at least one outlet; every unlisted seat is
# Solid/Safe for all of them, so Solid counts are the outlet's published party total minus the listed non-solid seats.
parse_house_ratings <- function(wikitext) {
  lines <- str_split_1(wikitext, "\n")
  row_start <- which(str_detect(lines, "^!\\{\\{ushr\\|"))
  overall_at <- which(str_detect(lines, "^! colspan=\"4\" \\|Overall"))
  bounds <- c(row_start, overall_at)

  rows <- map2(bounds[-length(bounds)], bounds[-1], \(a, b) {
    cells <- lines[a:(b - 1)] |> str_subset("USRaceRating") |> str_match("USRaceRating\\|([A-Za-z-]+)(?:\\|([DR]))?")
    tibble(
      district = str_match(lines[a], "ushr\\|([A-Z]+)\\|([A-Z0-9]+)")[1, 2:3] |> str_c(collapse = "-"),
      col = seq_len(nrow(cells)),
      category = cells[, 2],
      party = cells[, 3]
    )
  }) |> list_rbind()

  rated <- rows |>
    filter(col <= 3) |>
    mutate(
      level = case_when(category == "Safe" ~ "Solid", category == "Tossup" ~ "Toss-up", .default = category),
      label = if_else(level == "Toss-up", "Toss-up", str_c(level, " ", party))
    ) |>
    inner_join(house_rating_sources, by = "col")

  totals <- lines[overall_at:(overall_at + 12)] |>
    str_subset("^\\| \\{\\{[Pp]arty shading") |>
    str_match("D – (\\d+)<br>R – (\\d+)<br>(\\d+) tossups") |>
    as_tibble(.name_repair = "minimal") |>
    set_names(c("raw", "D", "R", "tossups")) |>
    slice_head(n = 3) |>
    mutate(source = house_rating_sources$source, across(c(D, R, tossups), as.integer))

  listed <- rated |> count(source, label)
  solid <- totals |>
    select(source, D, R) |>
    pivot_longer(c(D, R), names_to = "party", values_to = "total") |>
    left_join(
      listed |>
        filter(str_detect(label, "^(Likely|Lean|Tilt) [DR]$")) |>
        mutate(party = str_sub(label, -1)) |>
        summarise(listed = sum(n), .by = c(source, party)),
      by = c("source", "party")
    ) |>
    transmute(source, label = str_c("Solid ", party), n = total - coalesce(listed, 0L))

  dates <- lines |>
    str_subset("^!\\[\\[(Cook Political Report|Stuart Rothenberg|Sabato)") |>
    str_match("small\\|([A-Za-z]+)\\.?,?\\s*(\\d+),<br>\\s*(\\d{4})") |>
    as_tibble(.name_repair = "minimal") |>
    set_names(c("raw", "month", "day", "year")) |>
    transmute(source = house_rating_sources$source, as_of = format(lubridate::mdy(str_c(month, " ", day, ", ", year))))

  list(
    counts = bind_rows(listed |> filter(!str_detect(label, "^Solid")), solid) |> left_join(dates, by = "source"),
    totals = totals
  )
}
