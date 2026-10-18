#!/usr/bin/env Rscript
# How the four Old Hungarian past-tense categories map onto the Latin source
# tense, crossed with discourse mode (narration vs reported speech).
# Reads dat/gospels_verbs_grc_lat_hu.tsv (run from the repository root).

set.seed(1337)
suppressMessages(library(tidyverse))

d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)

# four Hungarian past-tense categories under study, in a fixed display order
hu_levels = c("imperfective", "perfective", "complex_imperfective", "complex_perfective")
hu_labels = c("imperfective\n(-a/-e, -á/-é)", "perfective\n(-t/-tt)",
              "complex imperfective\n(present + vala/volt)",
              "complex perfective\n(past/ipf + vala/volt)")

# core Latin indicative tenses that bear on past-tense choice
lat_levels = c("present", "imperfect", "perfect", "pluperfect")

plot_data = d |>
  filter(row_type == "hu_lat",
         lat_mood_analytic == "indicative",
         lat_tense_analytic %in% lat_levels,
         hu_tense_category %in% hu_levels) |>
  mutate(
    lat_tense_analytic = factor(lat_tense_analytic, levels = lat_levels),
    hu_tense_category = factor(hu_tense_category, levels = hu_levels, labels = hu_labels),
    discourse = if_else(discourse_mode == "narration", "Narration", "Reported speech")
  ) |>
  count(discourse, lat_tense_analytic, hu_tense_category, name = "n") |>
  group_by(discourse, lat_tense_analytic) |>
  mutate(total = sum(n), prop = n / total) |>
  ungroup()

n_labels = plot_data |>
  distinct(discourse, lat_tense_analytic, total)

pal = c("#2a78d6", "#eb6834", "#1baf7a", "#eda100")
names(pal) = hu_labels

p = ggplot(plot_data, aes(x = lat_tense_analytic, y = prop, fill = hu_tense_category)) +
  geom_col(width = 0.72, colour = "white", linewidth = 0.4) +
  geom_text(
    data = plot_data |> filter(prop >= 0.08),
    aes(label = scales::percent(prop, accuracy = 1)),
    position = position_stack(vjust = 0.5), colour = "white", size = 3.1, fontface = "bold"
  ) +
  geom_text(
    data = n_labels, aes(x = lat_tense_analytic, y = 1.04, label = paste0("n=", total)),
    inherit.aes = FALSE, colour = "#52514e", size = 2.9
  ) +
  facet_wrap(~discourse) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1.09), expand = c(0, 0)) +
  scale_fill_manual(values = pal, name = "Hungarian past-tense category") +
  labs(
    x = "Latin source tense (indicative)",
    y = "Share of matched Hungarian verbs",
    title = "Old Hungarian past-tense choice against the Latin source tense",
    subtitle = "Jordánszky kódex (1516-1519) vs the Vulgate, four Gospels; matched verb pairs only",
    caption = "Source: PROIEL treebank (Latin) + Ómagyar Korpusz (Jordánszky) + CPDV discourse projection"
  ) +
  theme_bw(base_size = 11) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    legend.position = "bottom",
    legend.title = element_text(size = 9),
    legend.text = element_text(size = 8),
    strip.background = element_rect(fill = "#e1e0d9", colour = NA),
    strip.text = element_text(face = "bold"),
    plot.title = element_text(face = "bold", size = 12),
    plot.subtitle = element_text(colour = "#52514e", size = 9),
    plot.caption = element_text(colour = "#898781", size = 7)
  )

ggsave("viz/past_tense_by_latin_tense_discourse.png", p, width = 8.5, height = 5.2, dpi = 900)
cat("rows plotted:", nrow(plot_data), "\n")
print(n_labels |> arrange(discourse, lat_tense_analytic))
