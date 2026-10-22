#!/usr/bin/env Rscript
# Parses dat/parable_list.txt (a synoptic parable table: parable name x
# Mark/Matthew/Luke/Thomas verse references) into a clean, long reference
# table of (book, chapter, verse_start, verse_end, parable_name), for joining
# onto dat/gospels_verbs_grc_lat_hu.tsv as a verse-level in_parable flag.
#
# Parsing rules, driven by the source file's own conventions:
# - Every verse reference self-declares its book via an "Mk"/"Mt"/"Lk" prefix
#   (e.g. "Lk 8:16; and Lk 11:33"), so references are extracted by regex from
#   the raw line text rather than by tracking which column they sit in.
#   Thomas references ("GTh ...") don't match this pattern and are dropped
#   automatically -- Thomas isn't in our gospel data.
# - Bracketed spans are dropped before extracting references. Two different
#   things get bracketed in this file and both are excluded for the same
#   reason (too uncertain / not the parable's core narrated content to count
#   as confidently "in a parable"): (a) whole rows whose name starts with
#   "[", e.g. "[Interpretation of Sower & Seed]", "[Why Jesus Uses
#   Parables]" -- meta-commentary, not narrative; (b) bracketed notes inside
#   an otherwise normal row, e.g. Doorkeeper's Luke cell "[cf. Lk
#   12:35-38]" -- a tentative cross-reference, not a confirmed parallel.
# - Header rows ("Parables (incl. Sayings, ...)"), section headers
#   ("Additional Parables ..."), and total-count rows ("Total Number of
#   Markan Parables  13  ...") contain no "Bk C:V" pattern and so
#   contribute no rows -- no explicit filtering needed for those.
#
# Output: dat/parable_ranges.tsv

suppressMessages(library(tidyverse))

lines = read_lines("dat/parable_list.txt")

book_lookup = c(Mk = "Mark", Mt = "Matthew", Lk = "Luke")
ref_re = "(Mk|Mt|Lk)\\.?\\s*(\\d+):(\\d+)(?:-(\\d+))?"

parse_line = function(line) {
  fields = str_split(line, "\t")[[1]]
  if (length(fields) < 2) return(NULL)

  raw_name = trimws(fields[1])
  if (raw_name == "" || str_starts(raw_name, "\\[")) return(NULL)

  rest = paste(fields[-1], collapse = " ")
  rest_clean = str_remove_all(rest, "\\[[^]]*\\]")

  matches = str_match_all(rest_clean, ref_re)[[1]]
  if (nrow(matches) == 0) return(NULL)

  tibble(
    parable_name = trimws(str_remove_all(raw_name, "\\[[^]]*\\]|^\"|\"$")),
    book = book_lookup[matches[, 2]],
    chapter = as.integer(matches[, 3]),
    verse_start = as.integer(matches[, 4]),
    verse_end = if_else(is.na(matches[, 5]), matches[, 4], matches[, 5]) |> as.integer()
  )
}

parable_ranges = map(lines, parse_line) |> list_rbind()

write_tsv(parable_ranges, "dat/parable_ranges.tsv")

cat("parsed", nrow(parable_ranges), "book-specific parable references,",
    "covering", n_distinct(parable_ranges$parable_name), "named parables\n")
print(parable_ranges |> count(book))
