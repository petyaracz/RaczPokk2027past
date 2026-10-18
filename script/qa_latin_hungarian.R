#!/usr/bin/env Rscript
# draw out random verb pairs to see if the alignment checks out

setwd('~/Github/Racz2027past/')
set.seed(1337)
suppressMessages(library(tidyverse))


# read data
d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)

# only matched pairs have both a lat_lemma and a hu_lemma to compare; everything
# else (hu_only, lat_only, grc_only) is a one-sided row and tells us nothing
# about alignment quality
matched = d |>
  filter(row_type == "hu_lat") |>
  select(row_id, book, chapter, verse, align_conf, lat_form, lat_lemma, hu_lemma)

# the README's own known-limitations note: validate weighted towards
# align_conf = medium, since high is already trusted and medium is where
# alignment mistakes are most likely to be worth a human's time
conf_weight = c(high = 1, medium = 3, low = 2)
checker = matched |>
  mutate(w = conf_weight[align_conf]) |>
  slice_sample(n = 164, weight_by = w) |>
  select(-w)

googlesheets4::write_sheet(checker, 'https://docs.google.com/spreadsheets/d/1ngvqsGb3SwXBC_KBlCACvyq1gX7GxverKBeL4gcv8WQ/edit?usp=sharing', 'Sheet1')
