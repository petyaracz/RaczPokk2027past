#!/usr/bin/env Rscript
# Three figures telling the discourse-context story in one script:
#   1. alluvial_latin_to_hu_tense_overall.png -- whole corpus, no discourse
#      split (messy, motivates the split that follows)
#   2. barplot_hu_tense_by_context.png -- Hungarian category composition
#      (100% stacked) by discourse context
#   3. heatmap_parable_depth.png -- modal Hungarian category x robustness,
#      same discourse contexts, one compact panel
#
# Discourse contexts (both plots 2 and 3): narration, and parable / other
# reported speech each split by quotation depth. Depth 1/2 are relabelled
# "speech" / "embedded speech" -- the terms discourse_mode itself already
# uses (depth 1 = discourse_mode "speech", depth 2 = "embedded_speech") --
# rather than an opaque depth number.
#
# Reads dat/gospels_verbs_grc_lat_hu.tsv and dat/parable_ranges.tsv (run from
# the repository root).

set.seed(1337)
suppressMessages(library(tidyverse))
suppressMessages(library(ggalluvial))
suppressMessages(library(ggrepel))

d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)
parable_ranges = read_tsv("dat/parable_ranges.tsv", show_col_types = FALSE)

# canonical category -> colour mapping, shared by all three plots
canonical_pal = c(imperfective = "#2a78d6", perfective = "#eb6834",
                   complex_imperfective = "#1baf7a", complex_perfective = "#eda100")

hu_levels = c("imperfective", "perfective", "complex_imperfective", "complex_perfective")
hu_short = c("imperfective", "perfective", "complex\nimperfective", "complex\nperfective")
hu_labels = c("imperfective\n(-a/-e, -á/-é)", "perfective\n(-t/-tt)",
              "complex imperfective\n(present + vala/volt)",
              "complex perfective\n(past/ipf + vala/volt)")
pal = canonical_pal[hu_levels]
names(pal) = hu_short

lat_levels = c("present", "perfect", "imperfect", "pluperfect")

verse_lookup = d |> distinct(book, chapter, verse)
parable_flag = verse_lookup |>
  inner_join(parable_ranges, by = c("book", "chapter"), relationship = "many-to-many") |>
  filter(verse >= verse_start, verse <= verse_end) |>
  distinct(book, chapter, verse, .keep_all = TRUE) |>
  select(book, chapter, verse, parable_name)

cell_levels = c("Narration", "Parable,\nspeech", "Parable,\nembedded speech",
                 "Other,\nspeech", "Other,\nembedded speech")

base = d |>
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
      !is.na(parable_name) & discourse_depth == 1 ~ "Parable,\nspeech",
      !is.na(parable_name) & discourse_depth == 2 ~ "Parable,\nembedded speech",
      discourse_depth == 1 ~ "Other,\nspeech",
      TRUE ~ "Other,\nembedded speech"
    ) |> factor(levels = cell_levels)
  )

# ============================================================ #
# 1. Overall alluvial, no discourse split                      #
# ============================================================ #

plot_data_1 = base |> count(lat_tense_analytic, hu_tense_category, name = "n")
total_n = sum(plot_data_1$n)

p1 = ggplot(plot_data_1,
            aes(axis1 = lat_tense_analytic, axis2 = hu_tense_category, y = n)) +
  geom_alluvium(aes(fill = hu_tense_category), width = 0.28, alpha = 0.85,
                colour = "white", linewidth = 0.15) +
  geom_stratum(width = 0.28, fill = "#e1e0d9", colour = "#52514e", linewidth = 0.3) +
  geom_text_repel(
    stat = "stratum",
    aes(label = paste0(after_stat(stratum), "\nn=", after_stat(count)),
        x = after_stat(x) + ifelse(after_stat(x) == 1, -0.2, 0.2),
        hjust = after_stat(ifelse(x == 1, 1, 0))),
    size = 3.1, lineheight = 0.85, min.segment.length = Inf,
    box.padding = 0.15, direction = "y", seed = 1337
  ) +
  scale_x_discrete(limits = c("Latin tense", "Hungarian category"), expand = c(0.35, 0.35)) +
  scale_fill_manual(values = pal, breaks = hu_short, name = "Hungarian past-tense category", labels = hu_labels) +
  labs(
    y = "Number of matched Hungarian verbs",
    title = "Old Hungarian past-tense choice against the Latin source tense",
    subtitle = paste0("Jordánszky kódex (1516-1519) vs the Vulgate, four Gospels; all matched verb pairs pooled, n = ", total_n),
    caption = "Source: PROIEL treebank (Latin) + Ómagyar Korpusz (Jordánszky) + CPDV discourse projection"
  ) +
  theme_bw(base_size = 11) +
  theme(
    panel.grid = element_blank(),
    axis.title.x = element_blank(),
    axis.text.y = element_blank(),
    axis.ticks = element_blank(),
    legend.position = "bottom",
    legend.title = element_text(size = 9),
    legend.text = element_text(size = 8),
    plot.title = element_text(face = "bold", size = 12),
    plot.subtitle = element_text(colour = "#52514e", size = 9),
    plot.caption = element_text(colour = "#898781", size = 7)
  )

ggsave("viz/alluvial_latin_to_hu_tense_overall.png", p1, width = 9, height = 7.8, dpi = 900)

# ============================================================ #
# 2. Hungarian category composition by discourse context        #
# ============================================================ #

plot_data_2 = base |> count(cell, hu_tense_category, name = "n") |>
  group_by(cell) |> mutate(total = sum(n), pct = 100 * n / total) |> ungroup()

cell_totals = plot_data_2 |> distinct(cell, total)
cell_labeller = as_labeller(
  setNames(paste0(str_replace(cell_totals$cell, "\n", " "), "\n(n = ", cell_totals$total, ")"), cell_totals$cell)
)

p2 = ggplot(plot_data_2, aes(x = cell, y = pct, fill = hu_tense_category)) +
  geom_col(width = 0.7, colour = "white", linewidth = 0.4) +
  geom_text(aes(label = if_else(pct >= 5, paste0(round(pct), "%"), "")),
            position = position_stack(vjust = 0.5), colour = "white", size = 3, fontface = "bold") +
  scale_x_discrete(labels = cell_labeller) +
  scale_y_continuous(expand = c(0, 0)) +
  scale_fill_manual(values = pal, breaks = hu_short, name = "Hungarian past-tense category", labels = hu_labels) +
  labs(
    x = NULL, y = "% of tokens in that discourse context",
    title = "Hungarian past-tense category composition by discourse context",
    subtitle = "100% stacked; n is the token count for that context",
    caption = "Source: PROIEL treebank (Latin) + Ómagyar Korpusz (Jordánszky) + CPDV discourse projection"
  ) +
  theme_bw(base_size = 11) +
  theme(
    panel.grid = element_blank(),
    axis.ticks.x = element_blank(),
    legend.position = "bottom",
    legend.title = element_text(size = 9),
    legend.text = element_text(size = 8),
    plot.title = element_text(face = "bold", size = 12),
    plot.subtitle = element_text(colour = "#52514e", size = 9),
    plot.caption = element_text(colour = "#898781", size = 7)
  )

ggsave("viz/barplot_hu_tense_by_context.png", p2, width = 9, height = 6.5, dpi = 900)

# ============================================================ #
# 3. Heatmap: modal category x robustness, same contexts        #
# ============================================================ #

# axes ordered by frequency, most common first -- top of the y-axis for
# Latin tense, top of the legend for Hungarian category (ggplot's y-axis and
# legend read "first" in opposite visual directions, hence the asc/desc mix)
lat_levels_freq = base |> count(lat_tense_analytic) |> arrange(n) |> pull(lat_tense_analytic) |> as.character()
hu_levels_freq = base |> count(hu_tense_category) |> arrange(desc(n)) |> pull(hu_tense_category) |> as.character()

plot_data_3 = base |>
  count(cell, lat_tense_analytic, hu_tense_category, name = "cat_n") |>
  group_by(cell, lat_tense_analytic) |>
  mutate(n = sum(cat_n), pct = 100 * cat_n / n) |>
  slice_max(cat_n, n = 1, with_ties = FALSE) |>
  ungroup() |>
  rename(modal_category = hu_tense_category)

luminance = function(hex) {
  rgb = grDevices::col2rgb(hex) / 255
  0.299 * rgb[1, ] + 0.587 * rgb[2, ] + 0.114 * rgb[3, ]
}
plot_data_3 = plot_data_3 |>
  mutate(
    blended_luminance = (pct / 100) * luminance(pal[as.character(modal_category)]) + (1 - pct / 100) * 1,
    text_colour = if_else(blended_luminance < 0.6, "white", "#2b2a28")
  )

p3 = ggplot(plot_data_3, aes(x = cell, y = lat_tense_analytic)) +
  geom_tile(aes(fill = modal_category, alpha = pct), colour = "white", linewidth = 1.2) +
  geom_text(aes(label = paste0(modal_category, "\n", round(pct), "%, n=", n), colour = text_colour),
            size = 2.7, lineheight = 0.9, fontface = "bold") +
  scale_fill_manual(values = pal, name = "Modal Hungarian\npast-tense category") +
  scale_alpha_continuous(range = c(0.25, 1), limits = c(0, 100), name = "% in modal category\n(of that cell)") +
  scale_colour_identity() +
  scale_y_discrete(limits = lat_levels_freq) +
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

ggsave("viz/heatmap_parable_depth.png", p3, width = 10, height = 5, dpi = 900)

cat("plot 1 (overall alluvial) total n:", total_n, "\n")
cat("plot 2 (barplot) cells:\n")
print(cell_totals)
cat("plot 3 (heatmap) rows plotted:", nrow(plot_data_3), "\n")
