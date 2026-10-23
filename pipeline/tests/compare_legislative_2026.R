#!/usr/bin/env Rscript
# Compares 2026 pre-election legislative win probabilities under the production prior and the proposed leg_spec prior.
#   Rscript pipeline/tests/compare_legislative_2026.R <dir_with_old_needle.json> <dir_with_new_needle.json>
source(file.path(Sys.getenv("UTEL_ROOT", "."), "pipeline", "R", "utils.R"))
a <- commandArgs(TRUE)
read_n <- \(dir) {
  n <- read_json(file.path(dir, "needle.json"), simplifyVector = FALSE)$contests
  imap(n, \(c, id) tibble(id = id, a = c$pair[[1]], b = c$pair[[2]], prob_a = c$prob[[1]], share_a = c$prior$share_a, src = c$prior$source)) |> list_rbind()
}
label <- \(p) {
  q <- pmax(p, 1 - p)
  case_when(q >= 0.95 ~ "Safe", q >= 0.8 ~ "Likely", q >= 0.6 ~ "Lean", .default = "Toss-up")
}
smry <- read_json(file.path(a[1], "summary.json"), simplifyVector = FALSE)$contests
cand_tbl <- smry |>
  keep(\(c) str_detect(c$contest_id, "^state-")) |>
  map(\(c) tibble(id = c$contest_id, a_party = NA_character_, b_party = NA_character_, cands = list(c$candidates))) |>
  list_rbind()
cmp <- read_n(a[1]) |>
  filter(str_detect(id, "^state-")) |>
  inner_join(read_n(a[2]) |> filter(str_detect(id, "^state-")), by = c("id", "a", "b"), suffix = c("_old", "_new")) |>
  mutate(
    side = if_else(prob_a_new >= 0.5, "a", "b"),
    label_old = label(prob_a_old),
    label_new = label(prob_a_new),
    fav_old = if_else(prob_a_old >= 0.5, a, b),
    fav_new = if_else(prob_a_new >= 0.5, a, b)
  ) |>
  left_join(
    smry |>
      keep(\(c) str_detect(c$contest_id, "^state-")) |>
      map(\(c) tibble(id = c$contest_id, parties = str_c(map_chr(c$candidates, \(x) str_c(x$party %||% "?", if_else(isTRUE(x$incumbent), "*", ""))), collapse = " v "))) |>
      list_rbind(),
    by = "id"
  )
write_csv(cmp |> mutate(across(where(is.double), \(x) round(x, 4))), file.path(project_root(), "pipeline", "tests", "eval_legislative_2026_comparison.csv"))
print(count(cmp, label_old, label_new))
print(cmp |> mutate(d = abs(prob_a_new - prob_a_old)) |> arrange(desc(d)) |> select(id, parties, prob_a_old, prob_a_new, share_a_old, share_a_new, label_old, label_new) |> head(25), width = 200)
print(cmp |> summarise(flips = sum(fav_old != fav_new), n = n()))
