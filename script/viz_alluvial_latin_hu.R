#!/usr/bin/env Rscript
# Alluvial version of viz_past_tense_latin.R: same four Latin indicative
# tenses (in) flowing to the same four Hungarian past-tense categories (out),
# faceted by discourse mode instead of stacked bars.
# Reads dat/gospels_verbs_grc_lat_hu.tsv (run from the repository root).

set.seed(1337)
suppressMessages(library(tidyverse))
suppressMessages(library(ggalluvial))
suppressMessages(library(ggrepel))

d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)

# four Hungarian past-tense categories under study, in a fixed display order
hu_levels = c("imperfective", "perfective", "complex_imperfective", "complex_perfective")
hu_labels = c("imperfective\n(-a/-e, -á/-é)", "perfective\n(-t/-tt)",
              "complex imperfective\n(present + vala/volt)",
              "complex perfective\n(past/ipf + vala/volt)")
hu_short = c("imperfective", "perfective", "complex\nimperfective", "complex\nperfective")

# core Latin indicative tenses that bear on past-tense choice
lat_levels = c("present", "imperfect", "perfect", "pluperfect")

plot_data = d |>
  filter(row_type == "hu_lat",
         lat_mood_analytic == "indicative",
         lat_tense_analytic %in% lat_levels,
         hu_tense_category %in% hu_levels) |>
  mutate(
    lat_tense_analytic = factor(lat_tense_analytic, levels = lat_levels),
    hu_tense_category = factor(hu_tense_category, levels = hu_levels, labels = hu_short),
    discourse = if_else(discourse_mode == "narration", "Direct speech", "Reported speech")
  ) |>
  count(discourse, lat_tense_analytic, hu_tense_category, name = "n")

pal = c("#2a78d6", "#eb6834", "#1baf7a", "#eda100")
names(pal) = hu_short

p = ggplot(plot_data,
           aes(axis1 = lat_tense_analytic, axis2 = hu_tense_category, y = n)) +
  geom_alluvium(aes(fill = hu_tense_category), width = 0.28, alpha = 0.85, colour = "white", linewidth = 0.15) +
  geom_stratum(width = 0.28, fill = "#e1e0d9", colour = "#52514e", linewidth = 0.3) +
  geom_text_repel(
    stat = "stratum",
    aes(label = after_stat(stratum),
        x = after_stat(x) + ifelse(after_stat(x) == 1, -0.2, 0.2),
        hjust = after_stat(ifelse(x == 1, 1, 0))),
    size = 2.9, lineheight = 0.85, min.segment.length = Inf,
    box.padding = 0.15, direction = "y", seed = 1337
  ) +
  facet_wrap(~discourse) +
  scale_x_discrete(limits = c("Latin tense", "Hungarian category"), expand = c(0.32, 0.32)) +
  scale_fill_manual(values = pal, name = "Hungarian past-tense category", labels = hu_labels) +
  labs(
    y = "Number of matched Hungarian verbs",
    title = "Old Hungarian past-tense choice against the Latin source tense",
    subtitle = "Jordánszky kódex (1516-1519) vs the Vulgate, four Gospels; matched verb pairs only",
    caption = "Source: PROIEL treebank (Latin) + Ómagyar Korpusz (Jordánszky) + CPDV discourse projection"
  ) +
  theme_bw(base_size = 11) +
  theme(
    panel.grid = element_blank(),
    panel.spacing.x = unit(2.2, "lines"),
    axis.title.x = element_blank(),
    axis.text.y = element_blank(),
    axis.ticks = element_blank(),
    legend.position = "bottom",
    legend.title = element_text(size = 9),
    legend.text = element_text(size = 8),
    strip.background = element_rect(fill = "#e1e0d9", colour = NA),
    strip.text = element_text(face = "bold"),
    plot.title = element_text(face = "bold", size = 12),
    plot.subtitle = element_text(colour = "#52514e", size = 9),
    plot.caption = element_text(colour = "#898781", size = 7)
  )

ggsave("viz/alluvial_latin_to_hu_tense.png", p, width = 10.5, height = 7.8, dpi = 900)
cat("rows plotted:", nrow(plot_data), "\n")
print(plot_data |> group_by(discourse, lat_tense_analytic) |> summarise(total = sum(n), .groups = "drop"))
