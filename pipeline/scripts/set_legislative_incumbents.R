#!/usr/bin/env Rscript
# Marks incumbents in state-house-* and state-senate-* contests from the current seat holders in legislature_seats.csv.
# Usage (repo root): Rscript pipeline/scripts/set_legislative_incumbents.R
library(dplyr)
library(purrr)
library(readr)
library(stringr)
library(tidyr)

root <- Sys.getenv("UTEL_ROOT", unset = ".")
cand_path <- file.path(root, "pipeline", "config", "candidates.csv")
seats_path <- file.path(root, "pipeline", "config", "legislature_seats.csv")

unresearched <- "incumbency not researched"
roster_note <- "incumbent per le.utah.gov roster"
suffixes <- c("jr", "sr", "ii", "iii", "iv")

nickname_classes <- list(
  robert = c("rob", "bob", "bobby", "robbie"),
  clinton = "clint",
  calvin = "cal",
  norman = "norm",
  william = c("bill", "billy", "will", "willy"),
  michael = c("mike", "mikey"),
  jacob = "jake",
  christopher = c("chris", "christian"),
  daniel = c("dan", "danny"),
  kenneth = c("ken", "kenny"),
  stephen = "steve",
  steven = "steve",
  thomas = c("tom", "tommy"),
  james = c("jim", "jimmy"),
  douglas = "doug",
  matthew = "matt",
  nathan = "nate",
  joseph = "joe",
  richard = c("rick", "dick", "rich"),
  anthony = "tony",
  samuel = "sam",
  benjamin = "ben",
  andrew = c("andy", "drew"),
  david = "dave",
  gregory = "greg",
  elizabeth = c("liz", "beth", "betsy", "liza"),
  katherine = c("kate", "katie", "kathy", "kat", "katy"),
  catherine = c("cathy", "kate", "katie", "katy"),
  kathleen = c("kathy", "kathie"),
  patricia = c("pat", "trish"),
  nicholas = "nick",
  timothy = "tim",
  jonathan = "jon",
  edward = c("ed", "eddie", "ted"),
  charles = c("chuck", "charlie"),
  jennifer = c("jen", "jenny"),
  margaret = c("maggie", "peggy", "meg")
)
nickname_sets <- imap(nickname_classes, \(alts, canon) c(canon, alts))

nickname_equiv <- \(a, b) any(map_lgl(nickname_sets, \(s) all(c(a, b) %in% s)))

parse_name <- \(x) {
  toks <- x |>
    str_to_lower() |>
    str_replace_all("[^a-z \\-]", "") |>
    str_squish() |>
    str_split_1(" ")
  toks <- toks[!toks %in% suffixes & toks != ""]
  n <- length(toks)
  list(
    last = str_split_1(toks[n], "-"),
    given = toks[-n] |> str_split("-") |> unlist() |> discard(\(t) t == "")
  )
}

match_tier <- \(cand, holder) {
  if (!any(cand$last %in% holder$last)) return("")
  cg <- cand$given[nchar(cand$given) > 1]
  hg <- holder$given[nchar(holder$given) > 1]
  if (any(cg %in% hg)) return("exact")
  pairs <- expand_grid(c = cg, h = hg)
  if (any(map2_lgl(pairs$c, pairs$h, nickname_equiv))) return("nickname")
  if (length(cand$given) > 0 && length(holder$given) > 0 &&
    str_sub(cand$given[1], 1, 1) == str_sub(holder$given[1], 1, 1)) {
    return("initial-only")
  }
  ""
}

cands <- read_csv(
  cand_path,
  col_types = cols(.default = col_character(), incumbent = col_logical()),
  show_col_types = FALSE
)

seats <- read_csv(seats_path, col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  mutate(
    contest_id = str_c("state-", chamber, "-", district),
    holder = replace_na(holder, "")
  ) |>
  filter(contest_id %in% cands$contest_id)

seat_matches <- cands |>
  select(contest_id, candidate_id, display_name) |>
  inner_join(seats |> select(contest_id, holder), by = "contest_id", relationship = "many-to-many") |>
  filter(holder != "") |>
  mutate(
    tier = map2_chr(display_name, holder, \(d, h) match_tier(parse_name(d), parse_name(h)))
  ) |>
  filter(tier != "")

seat_status <- seats |>
  mutate(
    n_matched = map_int(contest_id, \(id) {
      sum(seat_matches$contest_id == id & seat_matches$tier %in% c("exact", "nickname"))
    }),
    status = case_when(
      holder == "" ~ "VACANT",
      n_matched == 1 ~ "matched",
      n_matched > 1 ~ "AMBIGUOUS",
      .default = "NOT FOUND"
    )
  )

walk(seq_len(nrow(seat_status)), \(i) {
  s <- seat_status[i, ]
  message(sprintf("%-16s holder: %-26s %s", s$contest_id, s$holder, s$status))
  m <- seat_matches |> filter(contest_id == s$contest_id)
  walk(seq_len(nrow(m)), \(j) {
    message(sprintf("    %-12s %-28s %s", m$tier[j], m$display_name[j], m$candidate_id[j]))
  })
})

matched_keys <- seat_matches |>
  filter(tier %in% c("exact", "nickname")) |>
  semi_join(seat_status |> filter(status == "matched"), by = "contest_id") |>
  transmute(key = str_c(contest_id, "|", candidate_id)) |>
  pull(key)

resolved_contests <- seat_status |> filter(status == "matched") |> pull(contest_id)
legislative <- str_detect(cands$contest_id, "^state-(house|senate)-\\d+$")
is_incumbent <- str_c(cands$contest_id, "|", cands$candidate_id) %in% matched_keys

updated <- cands |>
  mutate(
    incumbent = if_else(legislative, is_incumbent, incumbent),
    note = case_when(
      !legislative ~ note,
      is_incumbent ~ roster_note,
      contest_id %in% resolved_contests & note == unresearched ~ NA_character_,
      .default = note
    )
  )

write_csv(updated, cand_path, na = "")
message(sprintf(
  "Incumbents marked: %d house, %d senate. Seats matched: %d; not found: %d; ambiguous: %d; vacant: %d",
  sum(is_incumbent & str_starts(cands$contest_id, "state-house-")),
  sum(is_incumbent & str_starts(cands$contest_id, "state-senate-")),
  sum(seat_status$status == "matched"),
  sum(seat_status$status == "NOT FOUND"),
  sum(seat_status$status == "AMBIGUOUS"),
  sum(seat_status$status == "VACANT")
))
