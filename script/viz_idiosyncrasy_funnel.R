#!/usr/bin/env Rscript
# Descriptive (no model fit) look at two questions about Old Hungarian
# past-tense choice: do individual verbs behave idiosyncratically relative
# to the "usual" Latin-tense -> Hungarian-category mapping, and do chapters?
#
# "Usual" is defined per (lat_tense_analytic, reported_speech) cell as the
# modal Hungarian category -- the dominant flow in each cell of
# script/viz_alluvial_latin_hu.R. Each token is then flagged as matching or
# not matching that cell's mode; a lemma/chapter's "idiosyncrasy" is just its
# mismatch rate. Plotted as a funnel plot (rate vs log token count, with a
# binomial noise band around the population rate) so genuine outliers are
# separable from small-n noise.
#
# Verbs: frequency-dependent identity. The top 50 lemmas are kept individual;
# everything rarer is pooled into frequency bands (1 / 2-4 / 5-9 / 10+
# tokens), since a verb with 1-2 tokens has no real individual signal.
# Chapters: kept individual throughout -- token counts per chapter are much
# more even, so no banding is needed; the confound of chapters differing in
# their narration/speech mix is already handled because "usual" is
# conditioned on reported_speech per token, before aggregating to chapter.
#
# Reads dat/gospels_verbs_grc_lat_hu.tsv (run from the repository root).

set.seed(1337)
suppressMessages(library(tidyverse))
suppressMessages(library(ggrepel))

d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)

lat_levels = c("present", "imperfect", "perfect", "pluperfect")
hu_levels = c("imperfective", "perfective", "complex_imperfective", "complex_perfective")

model_data = d |>
  filter(row_type == "hu_lat",
         lat_mood_analytic == "indicative",
         lat_tense_analytic %in% lat_levels,
         hu_tense_category %in% hu_levels) |>
  mutate(
    lat_tense_analytic = factor(lat_tense_analytic, levels = lat_levels),
    hu_tense_category = factor(hu_tense_category, levels = hu_levels),
    reported_speech = if_else(discourse_mode == "narration", "no", "yes"),
    chapter_id = paste(book, chapter)
  )

# -- "usual" category per (Latin tense, reported speech) cell -- #

expected_tbl = model_data |>
  count(lat_tense_analytic, reported_speech, hu_tense_category) |>
  group_by(lat_tense_analytic, reported_speech) |>
  slice_max(n, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(lat_tense_analytic, reported_speech, expected_category = hu_tense_category)

model_data = model_data |>
  left_join(expected_tbl, by = c("lat_tense_analytic", "reported_speech")) |>
  mutate(matches_expected = hu_tense_category == expected_category)

# population mismatch rate: the funnel's centre line
p0 = 1 - mean(model_data$matches_expected)

# binomial 95% noise band around p0 as a function of token count n; curve_for()
# spans each plot's own data range so the ribbon isn't stretched past it
funnel_band = function(n, p0) {
  se = sqrt(p0 * (1 - p0) / n)
  tibble(n = n, lower = pmax(0, p0 - 1.96 * se), upper = pmin(1, p0 + 1.96 * se))
}
curve_for = function(n_vec, p0) funnel_band(exp(seq(log(min(n_vec)), log(max(n_vec)), length.out = 400)), p0)

# -- verb-level: top 50 individual, rest pooled into frequency bands -- #

lemma_freq = model_data |> count(hu_lemma, name = "lemma_n")

top50 = lemma_freq |>
  arrange(desc(lemma_n), hu_lemma) |>
  slice(1:50) |>
  pull(hu_lemma)

verb_summary = model_data |>
  left_join(lemma_freq, by = "hu_lemma") |>
  mutate(
    verb_group = case_when(
      hu_lemma %in% top50 ~ hu_lemma,
      lemma_n == 1 ~ "freq 1",
      lemma_n <= 4 ~ "freq 2-4",
      lemma_n <= 9 ~ "freq 5-9",
      TRUE ~ "freq 10-15"
    ),
    group_type = if_else(hu_lemma %in% top50, "individual verb", "frequency band")
  ) |>
  group_by(verb_group, group_type) |>
  summarise(n = n(), idiosyncrasy = 1 - mean(matches_expected), .groups = "drop") |>
  mutate(
    se = sqrt(p0 * (1 - p0) / n),
    # "above the band" = more idiosyncratic than chance -- the thing we're
    # looking for (verb X always picks a different tense). Points that fall
    # below the band are more regular than chance and are left unlabelled to
    # keep the plot legible; they're still visible as plain points.
    above_band = idiosyncrasy > pmin(1, p0 + 1.96 * se)
  )

p_verb = ggplot(verb_summary, aes(x = n, y = idiosyncrasy)) +
  geom_ribbon(data = curve_for(verb_summary$n, p0), aes(x = n, ymin = lower, ymax = upper),
              inherit.aes = FALSE, fill = "#2a78d6", alpha = 0.12) +
  geom_hline(yintercept = p0, linetype = "dashed", colour = "#52514e", linewidth = 0.3) +
  geom_point(aes(colour = group_type, shape = group_type), alpha = 0.8) +
  geom_text_repel(
    data = verb_summary |> filter(group_type == "frequency band" | above_band),
    aes(label = verb_group), size = 2.8, seed = 1337, max.overlaps = 20
  ) +
  scale_x_log10() +
  scale_colour_manual(values = c("individual verb" = "#eb6834", "frequency band" = "#1baf7a")) +
  labs(
    x = "Tokens (log scale)", y = "Idiosyncrasy rate (deviation from usual Hungarian category)",
    colour = NULL, shape = NULL,
    title = "Do frequent verbs behave more idiosyncratically?",
    subtitle = "Top 50 Hungarian verb lemmas individually; rarer lemmas pooled into frequency bands",
    caption = "Dashed line: population mismatch rate. Band: 95% binomial noise envelope around it.\nLabelled points sit above the band (more idiosyncratic than chance); unlabelled points below it are more regular than chance."
  ) +
  theme_bw(base_size = 11) +
  theme(legend.position = "bottom")

ggsave("viz/funnel_verb_idiosyncrasy.png", p_verb, width = 9, height = 6.5, dpi = 900)

# -- chapter-level: kept individual, no banding -- #

chapter_summary = model_data |>
  group_by(chapter_id) |>
  summarise(n = n(), idiosyncrasy = 1 - mean(matches_expected), .groups = "drop") |>
  mutate(
    se = sqrt(p0 * (1 - p0) / n),
    above_band = idiosyncrasy > pmin(1, p0 + 1.96 * se)
  )

p_chapter = ggplot(chapter_summary, aes(x = n, y = idiosyncrasy)) +
  geom_ribbon(data = curve_for(chapter_summary$n, p0), aes(x = n, ymin = lower, ymax = upper),
              inherit.aes = FALSE, fill = "#2a78d6", alpha = 0.12) +
  geom_hline(yintercept = p0, linetype = "dashed", colour = "#52514e", linewidth = 0.3) +
  geom_point(colour = "#eb6834", alpha = 0.8) +
  geom_text_repel(
    data = chapter_summary |> filter(above_band),
    aes(label = chapter_id), size = 2.8, seed = 1337, max.overlaps = 20
  ) +
  scale_x_log10() +
  labs(
    x = "Tokens (log scale)", y = "Idiosyncrasy rate (deviation from usual Hungarian category)",
    title = "Do chapters behave idiosyncratically?",
    subtitle = "One point per book:chapter; \"usual\" is conditioned on reported speech, so discourse-mode mix is already controlled for",
    caption = "Dashed line: population mismatch rate. Band: 95% binomial noise envelope around it.\nLabelled points sit above the band (more idiosyncratic than chance); unlabelled points below it are more regular than chance."
  ) +
  theme_bw(base_size = 11)

ggsave("viz/funnel_chapter_idiosyncrasy.png", p_chapter, width = 9, height = 6.5, dpi = 900)

cat("population mismatch rate (p0):", round(p0, 3), "\n")
cat("verb groups plotted:", nrow(verb_summary), "(", length(top50), "individual +",
    nrow(verb_summary) - length(top50), "bands)\n")
cat("chapters plotted:", nrow(chapter_summary), "\n")
cat("verbs above band:", sum(verb_summary$above_band), "\n")
cat("chapters above band:", sum(chapter_summary$above_band), "\n")
