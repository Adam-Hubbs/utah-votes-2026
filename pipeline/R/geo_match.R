# Matches precinct names as reported in results to UGRC VistaBallotAreas features.
# Reported names are county-specific (clerk-chosen) and often differ from VistaIDs, so matching is a
# ladder: exact VistaID -> parent precinct -> county-specific rule -> abbreviation (subsequence) match.

nk <- \(x) str_to_upper(str_replace_all(x %||% "", "[^A-Za-z0-9]", ""))

# "BC01" and "BC1" must compare equal.
nk0 <- \(x) str_replace_all(nk(x), "(?<![0-9])0+(?=[0-9])", "")

vista_keys <- function(vista) {
  vista |>
    mutate(
      county_fips = sprintf("49%03d", CountyID * 2L - 1L),
      id_np = str_remove(VistaID, str_c("^0?", CountyID)),
      parent_np = str_remove(id_np, ":.*$"),
      sub_np = if_else(str_detect(id_np, ":"), str_remove(id_np, "^[^:]*:"), ""),
      k_full = nk0(id_np),
      k_parent = nk0(parent_np),
      k_alias = nk0(AliasName)
    )
}

subsequence_of <- \(code, word) {
  if (nchar(code) == 0 || nchar(word) == 0) return(FALSE)
  chars <- str_split_1(code, "")
  pos <- 0L
  for (ch in chars) {
    hit <- str_locate(str_sub(word, pos + 1L), fixed(ch))[1, "start"]
    if (is.na(hit)) return(FALSE)
    pos <- pos + hit
  }
  TRUE
}

# Weber County: reported 3-letter city codes vs UGRC 2-letter ones.
weber_prefix <- c(
  CNP = "CN", COV = "CV", CSU = "CS", CWS = "CW", FRW = "FW", HAR = "HA", HPR = "HP",
  HUN = "HU", MSC = "MS", NOG = "NO", OGD = "OG", PLC = "PC", PLV = "PV", RIV = "RI",
  ROY = "RY", SOG = "SO", UIN = "UI", WAT = "WT", WHV = "WH"
)

piute_precinct <- c(MARYSVALE = "1", JUNCTION = "2", CIRCLEVILLE = "3", KINGSTON = "4", GREENWICH = "5")

# Returns raw candidate strings (sub-precinct colon retained) derived from a reported name by county rule.
county_rule_keys <- function(county_fips, reported) {
  r <- str_squish(reported)
  ru <- str_to_upper(r)
  rn <- nk(r)
  out <- switch(
    county_fips,
    "49005" = str_replace(ru, "^LOG", "LG") |> str_replace("^UNINHC", "UNHC") |> str_replace("(?<=:U)[0-9]+$", ""),
    "49057" = {
      pre <- str_sub(ru, 1, 3)
      if (pre %in% names(weber_prefix)) str_c(weber_prefix[[pre]], str_sub(ru, 4)) else NA_character_
    },
    "49049" = str_replace(ru, "^([A-Z]+)[34]([0-9]{2})", "\\1\\2"),
    "49051" = str_extract(r, "^[0-9]{3}"),
    "49007" = str_extract(r, "^[0-9]+"),
    "49015" = str_extract(r, "^[0-9]+"),
    "49031" = unname(piute_precinct[rn]),
    "49009" = case_when(
      rn == "DUTCHJOHN" ~ "1001",
      rn == "MANILA" ~ "1002",
      rn == "BROWNSPARK" ~ "1003",
      .default = NA_character_
    ),
    NA_character_
  )
  out[!is.na(out)]
}

# Counties whose reported names are "<town words> <number>" abbreviated by the UGRC code.
abbreviation_counties <- c("49001", "49003", "49017", "49023", "49027", "49047", "49055", "49039")

abbreviation_match <- function(county_fips, reported, vista_k) {
  r <- str_squish(reported)
  r_clean <- r |>
    str_remove_all("(?i)\\binside/outside\\b") |>
    str_remove("\\s*:.*$") |>
    str_replace_all(",.*$", "")
  num <- str_extract(r_clean, "[0-9]+\\s*U?$") |> str_remove("\\s*U$") |> str_remove("^0+")
  words <- r_clean |> str_remove("#?\\s*[0-9]+\\s*U?$") |> nk()
  if (str_length(words) == 0) return(character())

  parents <- vista_k |>
    filter(county_fips == !!county_fips) |>
    distinct(parent_np) |>
    mutate(
      code = str_extract(parent_np, "^[A-Za-z]+"),
      digits = str_extract(parent_np, "(?<=[A-Za-z])[0-9]+$") |> str_remove("^0+") |> replace_values(NA ~ "")
    ) |>
    filter(!is.na(code))
  want_num <- if (is.na(num)) "" else num
  cand <- parents |>
    filter(
      str_sub(str_to_upper(code), 1, 1) == str_sub(words, 1, 1),
      map_lgl(str_to_upper(code), \(cd) subsequence_of(cd, words))
    )
  if (county_fips == "49039") want_num <- ""
  by_num <- cand |> filter(digits == want_num)
  if (nrow(by_num) == 1) return(by_num$parent_np)
  if (nrow(by_num) > 1) {
    # Prefer the tightest abbreviation when several codes are subsequences (e.g. DE vs DEL).
    return(by_num$parent_np[which.max(str_length(by_num$code))])
  }
  if (is.na(num) && nrow(cand) == 1) return(cand$parent_np)
  if (county_fips == "49047" && !is.na(num)) {
    n <- parents |> filter(str_detect(parent_np, str_c(num, "$|", str_pad(num, 2, pad = "0"), "$")))
    # Uintah numbers precincts uniquely, so the number alone identifies the area.
    if (nrow(n) == 1) return(n$parent_np)
  }
  character()
}

match_precincts_to_vista <- function(reported, vista) {
  vk <- vista_keys(vista) |> st_drop_geometry() |> as_tibble()

  rows <- reported |>
    distinct(county_fips, precinct) |>
    mutate(rid = row_number())

  one <- \(cf, p) {
    pool <- vk |> filter(county_fips == cf)
    r0 <- nk0(p)
    sub_stripped <- nk0(str_remove(p, ":.*$"))
    rule <- county_rule_keys(cf, p)

    full_hit <- pool |> filter(k_full %in% c(r0, nk0(rule))) |> pull(VistaID)
    if (length(full_hit) > 0) return(tibble(vista_id = full_hit, tier = "exact"))

    parent_keys <- unique(c(sub_stripped, nk0(str_remove(rule, ":.*$"))))
    parent_hit <- pool |> filter(k_parent %in% parent_keys) |> pull(VistaID)
    if (length(parent_hit) > 0) return(tibble(vista_id = parent_hit, tier = "parent"))

    alias_hit <- pool |> filter(k_alias %in% c(r0, sub_stripped)) |> pull(VistaID)
    if (length(alias_hit) > 0) return(tibble(vista_id = alias_hit, tier = "alias"))

    if (cf %in% abbreviation_counties) {
      pp <- abbreviation_match(cf, p, vk)
      if (length(pp) > 0) {
        hit <- pool |> filter(parent_np %in% pp)
        if (cf == "49039") {
          sub_want <- case_when(
            str_detect(p, "(?i)\\s+u$|\\bU,") ~ "U",
            str_detect(p, "(?i)\\b[0-9]\\s*U$") ~ str_c(str_extract(p, "[0-9]"), "U"),
            str_detect(p, "[0-9]$") ~ str_c(str_extract(p, "[0-9]$"), "M"),
            .default = "M"
          )
          exact_sub <- hit |> filter(sub_np == sub_want)
          if (nrow(exact_sub) > 0) hit <- exact_sub
        }
        if (cf == "49023") {
          # Juab reports "Nephi #3" for the inside-city (:I) piece and "Nephi #3:U" for the unincorporated piece.
          want <- if (str_detect(p, ":")) str_remove(p, "^.*:") else "I"
          exact_sub <- hit |> filter(sub_np %in% c(want, ""))
          if (nrow(exact_sub) > 0) hit <- exact_sub
        }
        return(tibble(vista_id = hit$VistaID, tier = "abbrev"))
      }
    }
    if (cf == "49043") {
      letters_only <- str_extract(nk(p), "^[A-Z]+")
      cands <- pool |> distinct(parent_np) |> mutate(cd = str_extract(parent_np, "^[A-Z]+")) |>
        filter(!is.na(cd), nchar(cd) >= 2, str_sub(cd, 1, 1) == str_sub(letters_only, 1, 1),
               map_lgl(cd, \(x) subsequence_of(x, letters_only)))
      if (nrow(cands) > 0) {
        best <- cands |>
          arrange(desc(str_sub(cd, -1) == str_sub(letters_only, -1)), desc(nchar(cd)))
        hit <- pool |> filter(parent_np == best$parent_np[[1]])
        return(tibble(vista_id = hit$VistaID, tier = "approx"))
      }
    }
    tibble(vista_id = character(), tier = character())
  }

  rows |>
    mutate(hits = map2(county_fips, precinct, one)) |>
    unnest(hits, keep_empty = TRUE)
}
