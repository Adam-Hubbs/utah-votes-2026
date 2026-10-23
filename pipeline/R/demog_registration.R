registration_url <- "https://vote.utah.gov/wp-content/uploads/2026/10/10.19.2026-Active-Voters-by-County-and-Party.pdf"
registration_as_of <- "2026-10-19"

party_code <- c(
  Republican = "REP", Democratic = "DEM", Unaffiliated = "UNA", Libertarian = "LIB",
  Constitution = "CON", Forward = "FWD", Green = "GRN", `Independent` = "IAP", `Peoples' Freedom` = "PFP"
)

# pdftotext (poppler) keeps the table layout; "Independent American" wraps onto two lines.
parse_registration_pdf <- function(pdf) {
  lines <- system2("pdftotext", c("-layout", shQuote(pdf), "-"), stdout = TRUE)
  tibble(line = str_remove(lines, "^\\f")) |>
    mutate(
      m = str_match(line, "^(.+?)\\s{2,}(Constitution|Democratic|Forward|Green|Independent|Libertarian|Peoples.? Freedom|Republican|Unaffiliated)\\s+([0-9,]+)\\s*$")
    ) |>
    filter(!is.na(m[, 1])) |>
    transmute(
      county = str_squish(m[, 2]),
      party = party_code[m[, 3]],
      voters = parse_number(m[, 4])
    )
}

county_registration <- function(url = registration_url) {
  pdf <- raw_dir("registration", basename(url))
  if (!file.exists(pdf)) acs_download(url, pdf)
  long <- parse_registration_pdf(pdf)
  stopifnot(n_distinct(long$county) == 29)
  long |>
    mutate(fips = county_fips_from_name(county)) |>
    pivot_wider(names_from = party, values_from = voters, values_fill = 0) |>
    mutate(
      OTH = rowSums(pick(any_of(c("LIB", "CON", "FWD", "GRN", "IAP", "PFP")))),
      total = REP + DEM + UNA + OTH,
      as_of = registration_as_of
    )
}

registration_record <- function(row) {
  list(
    REP = row$REP, DEM = row$DEM, UNA = row$UNA, OTH = row$OTH, total = row$total,
    LIB = row$LIB, CON = row$CON, FWD = row$FWD, GRN = row$GRN, IAP = row$IAP,
    as_of = row$as_of
  )
}
