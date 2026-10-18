#!/usr/bin/env Rscript
# Formats the two permutation-test outputs (viz/perm_test_group_level.tsv,
# viz/perm_test_cell_level.tsv) as markdown tables, in the same Latin-tense x
# discourse-mode x Hungarian-category order as the alluvial diagram
# (viz/alluvial_latin_to_hu_tense.png), for reporting alongside it.
# Run from the repository root.

suppressMessages(library(tidyverse))

hu_levels = c("imperfective", "perfective", "complex_imperfective", "complex_perfective")
lat_levels = c("present", "imperfect", "perfect", "pluperfect")
discourse_levels = c("narration", "speech")
discourse_labels = c(narration = "Direct speech", speech = "Reported speech")

N_PERM = 20000
fmt_p = function(p) if_else(p <= 1 / (N_PERM + 1), sprintf("< %.5f", 1 / (N_PERM + 1)), sprintf("%.4f", p))
stars = function(p) case_when(p < 0.001 ~ "***", p < 0.01 ~ "**", p < 0.05 ~ "*", TRUE ~ "ns")

split_group = function(df) {
  df |>
    separate(group, into = c("lat_tense_analytic", "discourse_raw"), sep = "_") |>
    mutate(
      lat_tense_analytic = factor(lat_tense_analytic, levels = lat_levels),
      discourse_raw = factor(discourse_raw, levels = discourse_levels),
      discourse = discourse_labels[as.character(discourse_raw)]
    )
}

# ---------------------------------------------------------------------------
# Group-level table: 8 rows, one per Latin tense x discourse mode
# ---------------------------------------------------------------------------
group_tbl = read_tsv("viz/perm_test_group_level.tsv", show_col_types = FALSE) |>
  split_group() |>
  arrange(discourse_raw, lat_tense_analytic) |>
  transmute(
    Discourse = discourse,
    `Latin tense` = as.character(lat_tense_analytic),
    n = n_tokens,
    `p (Holm)` = fmt_p(p_holm),
    `p (BH)` = fmt_p(p_bh),
    Sig. = stars(p_holm)
  )

# ---------------------------------------------------------------------------
# Cell-level table: 32 rows, one per Latin tense x discourse x Hungarian category
# ---------------------------------------------------------------------------
cell_tbl = read_tsv("viz/perm_test_cell_level.tsv", show_col_types = FALSE) |>
  split_group() |>
  mutate(hu_tense_category = factor(hu_tense_category, levels = hu_levels)) |>
  arrange(discourse_raw, lat_tense_analytic, hu_tense_category) |>
  transmute(
    Discourse = discourse,
    `Latin tense` = as.character(lat_tense_analytic),
    `Hungarian category` = as.character(hu_tense_category),
    `obs. diff` = sprintf("%+.3f", obs_diff),
    `p (Holm)` = fmt_p(p_holm),
    `p (BH)` = fmt_p(p_bh),
    Sig. = stars(p_holm)
  )

to_markdown = function(df) {
  header = paste0("| ", paste(names(df), collapse = " | "), " |")
  sep = paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  rows = apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  paste(c(header, sep, rows), collapse = "\n")
}

out = c(
  "# Permutation-test results: Latin tense -> Hungarian past-tense category",
  "",
  "Companion tables for `viz/alluvial_latin_to_hu_tense.png`. Exact permutation",
  "tests (20,000 permutations, label shuffling), each table its own multiple-",
  "comparison family. Significance stars are based on the Holm-adjusted p value.",
  "",
  "## Group-level: this (Latin tense x discourse) group's profile over the four",
  "Hungarian categories vs the pooled other seven groups (chi-squared statistic)",
  "",
  to_markdown(group_tbl),
  "",
  "## Cell-level: this group's share of one Hungarian category vs the pooled",
  "rest's share of that category (difference in proportion) -- one row per flow",
  "in the alluvial diagram",
  "",
  to_markdown(cell_tbl),
  ""
)

writeLines(out, "viz/perm_test_tables.md")
cat("Wrote viz/perm_test_tables.md\n")
