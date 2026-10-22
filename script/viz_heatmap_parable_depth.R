#!/usr/bin/env Rscript
# Compact replacement for the 4-panel alluvial
# (viz_alluvial_latin_hu_parable_depth.R): now that the Latin-tense ->
# Hungarian-category mapping is close to categorical within each discourse
# cell, a heatmap says the same thing in one panel instead of four.
#
# Fill = which of the four Hungarian categories is modal for that
# (Latin tense, discourse cell) combination; alpha = how dominant it is
# (share of tokens in that category). A plain "% imperfective" metric was
# tried first and rejected: pluperfect and imperfect are *also*
# near-categorical in narration, just toward complex_perfective/
# complex_imperfective rather than plain imperfective (e.g. narration
# pluperfect is 82% complex_perfective) -- a binary imperfective-vs-rest
# scale would have misrepresented those rows as "mixed" when they are just
# as robust as the clearly imperfective ones, only pointing at a different
# category. Showing the modal category explicitly avoids that.
#
# Rows = Latin tense, columns = the four parable x depth cells plus
# narration (depth 0) as a reference anchor. Each tile carries n so sparse
# cells are visibly less certain rather than hidden.
#
# Reads dat/gospels_verbs_grc_lat_hu.tsv and dat/parable_ranges.tsv (run from
# the repository root).

set.seed(1337)
suppressMessages(library(tidyverse))

d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)
parable_ranges = read_tsv("dat/parable_ranges.tsv", show_col_types = FALSE)

hu_levels_raw = c("complex_perfective", "complex_imperfective", "perfective", "imperfective")
lat_levels_raw = c("pluperfect", "imperfect", "present", "perfect")

verse_lookup = d |> distinct(book, chapter, verse)
parable_flag = verse_lookup |>
  inner_join(parable_ranges, by = c("book", "chapter"), relationship = "many-to-many") |>
  filter(verse >= verse_start, verse <= verse_end) |>
  distinct(book, chapter, verse, .keep_all = TRUE) |>
  select(book, chapter, verse, parable_name)

filtered = d |>
  filter(row_type == "hu_lat",
         lat_mood_analytic == "indicative",
         lat_tense_analytic %in% lat_levels_raw,
         hu_tense_category %in% hu_levels_raw,
         discourse_depth %in% c(0, 1, 2))

# both axes ordered by frequency, most common first -- top of the y-axis for
# Latin tense, top of the legend for Hungarian category (ggplot's y-axis and
# legend read that "first" in opposite visual directions, hence the
# apparently inconsistent asc/desc sort below for the same intent)
lat_levels = filtered |> count(lat_tense_analytic) |> arrange(n) |> pull(lat_tense_analytic)
hu_levels = filtered |> count(hu_tense_category) |> arrange(desc(n)) |> pull(hu_tense_category)
hu_short = str_replace(hu_levels, "_", "\n")

cell_levels = c("Narration", "Parable,\ndepth 1", "Parable,\ndepth 2",
                 "Other speech,\ndepth 1", "Other speech,\ndepth 2")

plot_data = filtered |>
  left_join(parable_flag, by = c("book", "chapter", "verse")) |>
  mutate(
    lat_tense_analytic = factor(lat_tense_analytic, levels = lat_levels),
    hu_tense_category = factor(hu_tense_category, levels = hu_levels, labels = hu_short),
    cell = case_when(
      discourse_depth == 0 ~ "Narration",
      !is.na(parable_name) ~ paste0("Parable,\ndepth ", discourse_depth),
      TRUE ~ paste0("Other speech,\ndepth ", discourse_depth)
    ) |> factor(levels = cell_levels)
  ) |>
  count(cell, lat_tense_analytic, hu_tense_category, name = "cat_n") |>
  group_by(cell, lat_tense_analytic) |>
  mutate(n = sum(cat_n), pct = 100 * cat_n / n) |>
  slice_max(cat_n, n = 1, with_ties = FALSE) |>
  ungroup() |>
  rename(modal_category = hu_tense_category)

# canonical category -> colour mapping, kept independent of the frequency
# ordering above so e.g. "imperfective" stays blue regardless of rank
canonical_pal = c(complex_perfective = "#eda100", complex_imperfective = "#1baf7a",
                   perfective = "#eb6834", imperfective = "#2a78d6")
pal = canonical_pal[hu_levels]
names(pal) = hu_short

# luminance-based text colour: dark text on pale/alpha-light tiles, white
# text on saturated, high-dominance tiles
luminance = function(hex) {
  rgb = grDevices::col2rgb(hex) / 255
  0.299 * rgb[1, ] + 0.587 * rgb[2, ] + 0.114 * rgb[3, ]
}
plot_data = plot_data |>
  mutate(
    blended_luminance = (pct / 100) * luminance(pal[as.character(modal_category)]) + (1 - pct / 100) * 1,
    text_colour = if_else(blended_luminance < 0.6, "white", "#2b2a28")
  )

p = ggplot(plot_data, aes(x = cell, y = lat_tense_analytic)) +
  geom_tile(aes(fill = modal_category, alpha = pct), colour = "white", linewidth = 1.2) +
  geom_text(aes(label = paste0(modal_category, "\n", round(pct), "%, n=", n), colour = text_colour),
            size = 2.7, lineheight = 0.9, fontface = "bold") +
  scale_fill_manual(values = pal, name = "Modal Hungarian\npast-tense category") +
  scale_alpha_continuous(range = c(0.25, 1), limits = c(0, 100), name = "% in modal category\n(of that cell)") +
  scale_colour_identity() +
  scale_y_discrete(limits = lat_levels) +
  labs(
    x = NULL, y = NULL,
    title = "Latin tense and Hungarian past-tense category pair up near-categorically within each discourse context",
    subtitle = "Colour = modal Hungarian category; shade = how dominant it is",
    caption = "Source: PROIEL treebank (Latin) + Ómagyar Korpusz (Jordánszky) + CPDV discourse projection"
  ) +
  theme_bw(base_size = 11) +
  theme(
    panel.grid = element_blank(),
    axis.ticks = element_blank(),
    plot.title = element_text(face = "bold", size = 11),
    plot.subtitle = element_text(colour = "#52514e", size = 9),
    plot.caption = element_text(colour = "#898781", size = 7),
    legend.title = element_text(size = 8),
    legend.text = element_text(size = 8)
  )

ggsave("viz/heatmap_parable_depth.png", p, width = 10, height = 5, dpi = 900)
cat("rows plotted:", nrow(plot_data), "\n")
print(plot_data |> select(cell, lat_tense_analytic, modal_category, pct, n) |> arrange(cell, lat_tense_analytic))
