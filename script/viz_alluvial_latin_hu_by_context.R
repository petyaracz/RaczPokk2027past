#!/usr/bin/env Rscript
# Plot 2 of 3 in the discourse-context story (see viz_alluvial_latin_hu_
# overall.R for 1, viz_heatmap_parable_depth.R for 3): the same flows,
# faceted by discourse context -- narration, parable, and other reported
# speech, with parable and other speech further split by quotation depth
# (1 = that voice's own words, 2 = a character quoted within it). Same five
# cells as the heatmap's columns, same order, so the two plots read side by
# side: this one shows the tenses are doing something different per
# context; the heatmap gives the categorical summary.
#
# Reads dat/gospels_verbs_grc_lat_hu.tsv and dat/parable_ranges.tsv (run from
# the repository root).

set.seed(1337)
suppressMessages(library(tidyverse))
suppressMessages(library(ggalluvial))
suppressMessages(library(ggrepel))

d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)
parable_ranges = read_tsv("dat/parable_ranges.tsv", show_col_types = FALSE)

hu_levels = c("complex_perfective", "complex_imperfective", "perfective", "imperfective")
hu_labels = c("complex perfective\n(past/ipf + vala/volt)",
              "complex imperfective\n(present + vala/volt)",
              "perfective\n(-t/-tt)", "imperfective\n(-a/-e, -á/-é)")
hu_short = c("complex\nperfective", "complex\nimperfective", "perfective", "imperfective")
lat_levels = c("pluperfect", "imperfect", "present", "perfect")

verse_lookup = d |> distinct(book, chapter, verse)
parable_flag = verse_lookup |>
  inner_join(parable_ranges, by = c("book", "chapter"), relationship = "many-to-many") |>
  filter(verse >= verse_start, verse <= verse_end) |>
  distinct(book, chapter, verse, .keep_all = TRUE) |>
  select(book, chapter, verse, parable_name)

cell_levels = c("Narration", "Parable,\ndepth 1", "Parable,\ndepth 2",
                 "Other speech,\ndepth 1", "Other speech,\ndepth 2")

plot_data = d |>
  filter(row_type == "hu_lat",
         lat_mood_analytic == "indicative",
         lat_tense_analytic %in% lat_levels,
         hu_tense_category %in% hu_levels,
         discourse_depth %in% c(0, 1, 2)) |>
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
  count(cell, lat_tense_analytic, hu_tense_category, name = "n") |>
  # fill-only factor with reversed level order: flips the alluvium draw/
  # z-order in the two imperfective-dominated panels (Narration, Parable
  # depth 1) so the last-drawn ribbon doesn't paint over the others there;
  # the other three panels lean perfective and keep the default order. The
  # stratum axis order (hu_tense_category itself) is untouched.
  mutate(hu_tense_category_rev = factor(as.character(hu_tense_category), levels = rev(hu_short)))

pal = c("#eda100", "#1baf7a", "#eb6834", "#2a78d6")
names(pal) = hu_short

reversed_cells = c("Narration", "Parable,\ndepth 1")

discourse_totals = plot_data |> group_by(cell) |> summarise(total = sum(n), .groups = "drop")
discourse_labeller = as_labeller(
  setNames(paste0(str_replace(discourse_totals$cell, "\n", " "), " (n = ", discourse_totals$total, ")"),
           discourse_totals$cell)
)

p = ggplot(plot_data,
           aes(axis1 = lat_tense_analytic, axis2 = hu_tense_category, y = n)) +
  geom_alluvium(data = filter(plot_data, cell %in% reversed_cells),
                aes(fill = hu_tense_category_rev),
                width = 0.28, alpha = 0.85, colour = "white", linewidth = 0.15) +
  geom_alluvium(data = filter(plot_data, !cell %in% reversed_cells),
                aes(fill = hu_tense_category),
                width = 0.28, alpha = 0.85, colour = "white", linewidth = 0.15) +
  geom_stratum(width = 0.28, fill = "#e1e0d9", colour = "#52514e", linewidth = 0.3) +
  geom_text_repel(
    stat = "stratum",
    aes(label = paste0(after_stat(stratum), "\nn=", after_stat(count)),
        x = after_stat(x) + ifelse(after_stat(x) == 1, -0.2, 0.2),
        hjust = after_stat(ifelse(x == 1, 1, 0))),
    size = 2.6, lineheight = 0.85, min.segment.length = Inf,
    box.padding = 0.12, direction = "y", seed = 1337
  ) +
  facet_wrap(~cell, scales = "free_y", nrow = 1, labeller = discourse_labeller) +
  scale_x_discrete(limits = c("Latin tense", "Hungarian category"), expand = c(0.38, 0.38)) +
  scale_fill_manual(values = pal, breaks = hu_short, name = "Hungarian past-tense category", labels = hu_labels) +
  labs(
    y = "Number of matched Hungarian verbs",
    title = "Past-tense choice varies sharply by discourse context",
    subtitle = "Narration, parable, and other reported speech, split by quotation depth (1 = that voice's own words, 2 = a character quoted within it)",
    caption = "Source: PROIEL treebank (Latin) + Ómagyar Korpusz (Jordánszky) + CPDV discourse projection"
  ) +
  theme_bw(base_size = 11) +
  theme(
    panel.grid = element_blank(),
    panel.spacing.x = unit(1.5, "lines"),
    axis.title.x = element_blank(),
    axis.text.y = element_blank(),
    axis.ticks = element_blank(),
    legend.position = "bottom",
    legend.title = element_text(size = 9),
    legend.text = element_text(size = 8),
    strip.background = element_rect(fill = "#e1e0d9", colour = NA),
    strip.text = element_text(face = "bold", size = 8),
    plot.title = element_text(face = "bold", size = 12),
    plot.subtitle = element_text(colour = "#52514e", size = 9),
    plot.caption = element_text(colour = "#898781", size = 7)
  )

ggsave("viz/alluvial_latin_to_hu_tense_by_context.png", p, width = 18, height = 7.8, dpi = 900)
cat("rows plotted:", nrow(plot_data), "\n")
print(plot_data |> group_by(cell, lat_tense_analytic) |> summarise(total = sum(n), .groups = "drop"))
