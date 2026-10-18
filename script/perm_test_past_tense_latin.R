#!/usr/bin/env Rscript
# Permutation tests for the eight (Latin tense x discourse mode) groups shown
# in viz_past_tense_latin.R, against their profile over the four Hungarian
# past-tense categories. Run from the repository root.
#
# Two layers, each a separate permutation-test family with its own
# correction, because they ask different questions:
#   1. Eight group-level omnibus tests: does this group's distribution over
#      the four Hungarian categories differ from the pooled distribution of
#      the other seven groups? (chi-squared statistic, label permutation)
#   2. A 32-cell breakdown (group x Hungarian label): which category is over-
#      or under-represented in which group? (difference in proportion,
#      label permutation) -- the "maybe more, given the four Hungarian
#      labels" extension.
# Both are exact permutation (randomisation) tests: no chi-squared
# asymptotics, no expected-cell-count assumptions. p = (1 + #permutations at
# least as extreme) / (1 + N_PERM) so p is never reported as exactly zero.

set.seed(1337)
suppressMessages(library(tidyverse))

N_PERM = 20000

d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)

hu_levels = c("imperfective", "perfective", "complex_imperfective", "complex_perfective")
lat_levels = c("present", "imperfect", "perfect", "pluperfect")

m = d |>
  filter(row_type == "hu_lat",
         lat_mood_analytic == "indicative",
         lat_tense_analytic %in% lat_levels,
         hu_tense_category %in% hu_levels) |>
  mutate(
    discourse = if_else(discourse_mode == "narration", "narration", "speech"),
    group = paste(lat_tense_analytic, discourse, sep = "_")
  ) |>
  select(group, hu_tense_category)

groups = sort(unique(m$group))
n = nrow(m)
group_code = match(m$group, groups)                    # 1..8, fixed
cat_code0  = match(m$hu_tense_category, hu_levels)      # 1..4, permuted

# fast rxc cross-tab via integer binning (avoids table()'s factor overhead)
cross_tab = function(gcode, ccode, ngroup, ncat) {
  matrix(tabulate(gcode + (ccode - 1L) * ngroup, nbins = ngroup * ncat),
         nrow = ngroup, ncol = ncat)
}
chi2_stat = function(tab) {
  rt = rowSums(tab); ct = colSums(tab); ntot = sum(tab)
  expected = outer(rt, ct) / ntot
  sum((tab - expected)^2 / expected)
}

cat(sprintf("N = %d matched hu_lat verbs, indicative mood, 4 core Latin tenses x 2 discourse modes\n", n))
cat(sprintf("Permutations per test: %d\n\n", N_PERM))

# ---------------------------------------------------------------------------
# 1. Global omnibus test: group (8) independent of Hungarian category (4)?
# ---------------------------------------------------------------------------
obs_tab = cross_tab(group_code, cat_code0, 8, 4)
obs_chi2 = chi2_stat(obs_tab)
perm_chi2 = replicate(N_PERM, {
  ccode = sample(cat_code0)
  chi2_stat(cross_tab(group_code, ccode, 8, 4))
})
p_global = (1 + sum(perm_chi2 >= obs_chi2)) / (1 + N_PERM)
cat(sprintf("Global omnibus (8 groups x 4 categories): chi2 = %.1f, p = %.4g\n\n", obs_chi2, p_global))

# ---------------------------------------------------------------------------
# 2. Eight group-level tests: this group vs the pooled other seven
# ---------------------------------------------------------------------------
one_vs_rest_p = function(target) {
  gflag = as.integer(group_code == match(target, groups)) + 1L   # 1 = this, 2 = rest
  obs = chi2_stat(cross_tab(gflag, cat_code0, 2, 4))
  perm = replicate(N_PERM, chi2_stat(cross_tab(gflag, sample(cat_code0), 2, 4)))
  (1 + sum(perm >= obs)) / (1 + N_PERM)
}

group_n = m |> count(group, name = "n_tokens")

group_results = tibble(group = groups) |>
  mutate(p_raw = map_dbl(group, one_vs_rest_p)) |>
  left_join(group_n, by = "group") |>
  mutate(p_holm = p.adjust(p_raw, method = "holm"),
         p_bh   = p.adjust(p_raw, method = "BH")) |>
  arrange(p_raw) |>
  select(group, n_tokens, p_raw, p_holm, p_bh)

fmt_p = function(p) if_else(p <= 1 / (N_PERM + 1), sprintf("< %.5f", 1 / (N_PERM + 1)), sprintf("%.5f", p))

cat("Eight group-level tests (profile vs the pooled rest), Holm and BH correction across the 8:\n")
group_results |> mutate(across(starts_with("p_"), fmt_p)) |> print(n = Inf)
cat("\n")

# ---------------------------------------------------------------------------
# 3. 32-cell breakdown: group x Hungarian label, which cell drives it
# ---------------------------------------------------------------------------
cell_p = function(target_group, target_cat) {
  in_group = group_code == match(target_group, groups)
  in_cat = cat_code0 == match(target_cat, hu_levels)
  obs_diff = mean(in_cat[in_group]) - mean(in_cat[!in_group])
  perm_diff = replicate(N_PERM, {
    pg = sample(in_group)
    mean(in_cat[pg]) - mean(in_cat[!pg])
  })
  p = (1 + sum(abs(perm_diff) >= abs(obs_diff))) / (1 + N_PERM)
  tibble(obs_diff = obs_diff, p_raw = p)
}

cell_results = expand_grid(group = groups, hu_tense_category = hu_levels) |>
  mutate(res = map2(group, hu_tense_category, cell_p)) |>
  unnest(res) |>
  mutate(p_holm = p.adjust(p_raw, method = "holm"),
         p_bh   = p.adjust(p_raw, method = "BH")) |>
  arrange(p_raw)

cat("32-cell breakdown (group x Hungarian label, obs_diff = this group's share minus the rest's share),\n")
cat("Holm and BH correction across all 32:\n")
cell_results |> mutate(across(starts_with("p_"), fmt_p)) |> print(n = Inf)

write_tsv(group_results, "viz/perm_test_group_level.tsv")
write_tsv(cell_results, "viz/perm_test_cell_level.tsv")
cat("\nWrote viz/perm_test_group_level.tsv and viz/perm_test_cell_level.tsv\n")
