# Maps the precinct names used in the 2026 results (clerk-chosen, county-specific) onto UGRC ballot areas
# (VistaIDs). Most counties report the VistaID itself; the rest follow one of a few shapes handled below.
# The reported list lives in config/precincts_2026_reported.csv (taken from the results export).

read_reported_2026 <- function() {
  read_csv(
    file.path(project_root(), "pipeline", "config", "precincts_2026_reported.csv"),
    col_types = cols(.default = col_character()),
    show_col_types = FALSE
  )
}

sanpete_codes <- c(
  "AXTELL SSD" = "AXT:SSD", "CENTERFIELD CITY" = "CEN:M", "EPHRAIM CITY 1" = "EPH:1M",
  "EPHRAIM CITY 2" = "EPH:2M", "EPHRAIM CITY 3" = "EPH:3M", "EPHRAIM U" = "EPH:U",
  "FAIRVIEW CITY" = "FRV:M", "FAIRVIEW U" = "FRV:U", "FAYETTE TOWN" = "FAY:M",
  "FEDERAL ONLY" = "FED:1", "FOUNTAIN GREEN CITY" = "FTG:M", "FOUNTAIN GREEN U" = "NS:U", "GUNNISON CITY" = "GUN:M",
  "MANTI CITY 1" = "MAN:1M", "MANTI CITY 2" = "MAN:2M", "MANTI CITY 3" = "MAN:3M",
  "MAYFIELD TOWN" = "MAY:M", "MORONI CITY" = "MOR:M", "MORONI U" = "MOR:U",
  "MT PLEASANT 1 U" = "MTP:1U", "MT PLEASANT 2 U" = "MTP:2U", "MT PLEASANT CITY 1" = "MTP:1M",
  "MT PLEASANT CITY 2" = "MTP:2M", "SOUTH SANPETE U" = "SS:U", "SPRING CITY" = "SPR:M",
  "SPRING CITY U, WALES U" = "SPR:U", "STERLING TOWN" = "STR:M", "STERLING U" = "STR:U",
  "WALES TOWN" = "WAL:M"
)

millard_codes <- c(
  ABRAHAM = "AB", DELTA = "DE", `DESERET-OASIS` = "DO", FILLMORE = "FIL", FLOWELL = "FO",
  GARRISON = "GA", HINCKLEY = "HN", HOLDEN = "HLD", KANOSH = "KAN", LEAMINGTON = "LEA",
  LYNNDYL = "LY", MEADOW = "MEA", `OAK CITY` = "OAK", SCIPIO = "SCP", SUTHERLAND = "SU"
)

juab_codes <- c(CALLAO = "CA", EUREKA = "EU", LEVAN = "LE", MONA = "MO", NEPHI = "NE", `ROCKY RIDGE` = "RR")

# Like nk0() but keeps the sub-precinct colon, so "11CC1:1" and "11CC11" stay distinct.
nkc <- \(x) str_replace_all(str_to_upper(x %||% ""), "[^A-Z0-9:]", "") |> str_replace_all("(?<![0-9])0+(?=[0-9])", "")

# One key per reported name, compared against one column of the ballot-area table.
reported_rule_2026 <- function(county_fips, r, vista_ids) {
  ru <- str_to_upper(str_squish(r))
  none <- list(key = NA_character_, col = NA_character_)
  switch(
    county_fips,
    "49033" = list(key = nk0(ru), col = "k_full"),
    "49007" = list(key = nk0(str_extract(ru, "^[0-9]{4}")), col = "k_full"),
    "49015" = list(key = as.character(as.integer(str_sub(str_extract(ru, "^08[0-9]{2}"), 3))), col = "k_pid"),
    "49009" = list(key = str_extract(ru, "^[0-9]{4}"), col = "k_pid"),
    "49041" = list(key = nk0(str_sub(ru, 1, 4)), col = "k_pid"),
    "49017" = list(key = as.character(as.integer(str_extract(ru, "[0-9]+$"))), col = "pnum"),
    "49047" = list(key = as.character(as.integer(str_extract(ru, "(?<=#)[0-9]+$"))), col = "pnum"),
    "49051" = list(key = nk0(str_extract(ru, "^26-[0-9]+")), col = "k_full"),
    "49055" = list(key = if_else(str_detect(ru, "FEDERAL"), NA_character_, str_c("28", str_sub(str_remove(ru, "^28 "), 1, 2))), col = "wayne"),
    "49031" = list(
      key = str_c("16", unname(piute_precinct[nk(ru)])),
      col = "k_parent"
    ),
    "49039" = list(key = unname(sanpete_codes[str_remove(ru, "^20 ")]) |> map_chr(\(x) if (is.na(x)) NA_character_ else nk0(str_c("20", x))), col = "k_full"),
    "49027" = {
      nm <- str_squish(str_remove(ru, "[0-9]+$"))
      num <- str_extract(ru, "[0-9]+$")
      code <- unname(millard_codes[nm])
      list(key = if_else(nm == "FEDERAL", "14FED1", str_c("14", code, num)) |> nk0(), col = "k_parent")
    },
    "49023" = {
      m <- str_match(ru, "^([A-Z ]+) #([0-9]+)(?::([A-Z0-9]+))?$")
      code <- unname(juab_codes[m[, 2]])
      sub <- coalesce(m[, 4], "I")
      key <- str_c("12", code, m[, 3], ":", sub)
      key <- if_else(str_detect(ru, "^FED"), "12FED:I", key)
      # Areas that are not split into inside/outside sub-areas carry no suffix (e.g. 12CA1).
      key <- if_else(key %in% vista_ids, key, str_remove(key, ":I$"))
      list(key = key, col = "vista_up")
    },
    none
  )
}

# Returns one row per (reported precinct, ballot area it covers).
alias_reported_2026 <- function(reported, vista) {
  fk <- vista |>
    sf::st_drop_geometry() |>
    as_tibble() |>
    mutate(
      county_fips = sprintf("49%03d", CountyID * 2L - 1L),
      id_np = str_remove(VistaID, str_c("^0?", CountyID)),
      k_full = nk0(VistaID),
      c_full = nkc(VistaID),
      c_np = nkc(id_np),
      k_parent = nk0(str_remove(VistaID, ":.*$")),
      k_pid = nk0(PrecinctID),
      pnum = as.character(as.integer(str_extract(PrecinctID, "[0-9]+$"))),
      vista_up = str_to_upper(VistaID)
    ) |>
    distinct(county_fips, VistaID, k_full, c_full, c_np, k_parent, k_pid, pnum, vista_up)

  fk <- fk |> mutate(wayne = str_c("28", str_sub(str_remove(VistaID, "^28"), 1, 2)))

  match_one <- \(cf, rows) {
    pool <- filter(fk, county_fips == cf)
    exact <- rows |>
      mutate(key = nkc(precinct)) |>
      inner_join(select(pool, VistaID, key = c_full), by = "key", relationship = "many-to-many") |>
      mutate(tier = "id")
    exact_np <- rows |>
      mutate(key = nkc(precinct)) |>
      inner_join(select(pool, VistaID, key = c_np), by = "key", relationship = "many-to-many") |>
      mutate(tier = "id")
    hit <- bind_rows(exact, exact_np) |> distinct(precinct, VistaID, tier)
    rest <- rows |> filter(!precinct %in% hit$precinct)
    if (nrow(rest) > 0) {
      rule <- reported_rule_2026(cf, rest$precinct, pool$vista_up)
      if (!is.na(rule$col[1]) || length(rule$key) > 1) {
        col <- rule$col
        ruled <- tibble(precinct = rest$precinct, key = rule$key) |>
          filter(!is.na(key)) |>
          inner_join(
            pool |> select(VistaID, key = all_of(col)),
            by = "key", relationship = "many-to-many"
          ) |>
          mutate(tier = "rule")
        hit <- bind_rows(hit, distinct(ruled, precinct, VistaID, tier))
      }
      still <- rest |> filter(!precinct %in% hit$precinct)
      if (nrow(still) > 0) {
        generic <- still |>
          mutate(key = nk0(precinct)) |>
          inner_join(select(pool, VistaID, key = k_parent), by = "key", relationship = "many-to-many") |>
          mutate(tier = "parent")
        hit <- bind_rows(hit, distinct(generic, precinct, VistaID, tier))
        # Reported without the sub-precinct colon (Summit "22FED3" for 22FED:3).
        no_colon <- still |>
          filter(!precinct %in% hit$precinct) |>
          mutate(key = nk0(precinct)) |>
          inner_join(select(pool, VistaID, key = k_full), by = "key", relationship = "many-to-many") |>
          mutate(tier = "nocolon")
        hit <- bind_rows(hit, distinct(no_colon, precinct, VistaID, tier))
      }
    }
    # A name without a colon covers every sub-area of that precinct that no other reported name claims
    # (Box Elder reports "02PER1" for 02PER1, 02PER1:M, ...).
    siblings <- hit |>
      filter(!str_detect(precinct, ":")) |>
      distinct(precinct, VistaID) |>
      mutate(parent_key = nk0(str_remove(VistaID, ":.*$"))) |>
      inner_join(select(pool, sib = VistaID, parent_key = k_parent), by = "parent_key", relationship = "many-to-many") |>
      filter(!sib %in% hit$VistaID) |>
      distinct(precinct, VistaID = sib) |>
      mutate(tier = "sibling")
    bind_rows(hit, siblings)
  }

  reported |>
    group_split(county_fips) |>
    map(\(g) match_one(g$county_fips[[1]], g) |> mutate(county_fips = g$county_fips[[1]])) |>
    list_rbind()
}
