#!/usr/bin/env Rscript
# Plot 1 of 3 in the discourse-context story (see viz_alluvial_latin_hu_by_
# context.R and viz_heatmap_parable_depth.R for 2 and 3): the whole corpus,
# no discourse breakdown. Same four Latin indicative tenses flowing to the
# same four Hungarian past-tense categories as the later plots, but pooled,
# so the flows are visibly a mix of clean and messy -- motivating the
# discourse-context split that follows.
#
# Reads dat/gospels_verbs_grc_lat_hu.tsv (run from the repository root).

set.seed(1337)
suppressMessages(library(tidyverse))
suppressMessages(library(ggalluvial))
suppressMessages(library(ggrepel))

d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)

hu_levels = c("complex_perfective", "complex_imperfective", "perfective", "imperfective")
hu_labels = c("complex perfective\n(past/ipf + vala/volt)",
              "complex imperfective\n(present + vala/volt)",
              "perfective\n(-t/-tt)", "imperfective\n(-a/-e, -á/-é)")
hu_short = c("complex\nperfective", "complex\nimperfective", "perfective", "imperfective")
lat_levels = c("pluperfect", "imperfect", "present", "perfect")

plot_data = d |>
  filter(row_type == "hu_lat",
         lat_mood_analytic == "indicative",
         lat_tense_analytic %in% lat_levels,
         hu_tense_category %in% hu_levels) |>
  mutate(
    lat_tense_analytic = factor(lat_tense_analytic, levels = lat_levels),
    hu_tense_category = factor(hu_tense_category, levels = hu_levels, labels = hu_short)
  ) |>
  count(lat_tense_analytic, hu_tense_category, name = "n") |>
  # fill-only factor with reversed level order: the whole corpus is
  # imperfective-dominated (67%), so without this the last-drawn imperfective
  # ribbon paints over the minority perfective/complex flows crossing under it
  mutate(hu_tense_category_rev = factor(as.character(hu_tense_category), levels = rev(hu_short)))

pal = c("#eda100", "#1baf7a", "#eb6834", "#2a78d6")
names(pal) = hu_short

total_n = sum(plot_data$n)

p = ggplot(plot_data,
           aes(axis1 = lat_tense_analytic, axis2 = hu_tense_category, y = n)) +
  geom_alluvium(aes(fill = hu_tense_category_rev),
                width = 0.28, alpha = 0.85, colour = "white", linewidth = 0.15) +
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

ggsave("viz/alluvial_latin_to_hu_tense_overall.png", p, width = 9, height = 7.8, dpi = 900)
cat("rows plotted:", nrow(plot_data), "total n:", total_n, "\n")
print(plot_data |> group_by(lat_tense_analytic) |> summarise(total = sum(n), .groups = "drop"))
