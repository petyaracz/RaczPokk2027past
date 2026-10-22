#!/usr/bin/env Rscript
# Same alluvial design as script/viz_alluvial_latin_hu.R (same filters, same
# four Latin tenses -> four Hungarian categories, same palette/z-order trick,
# free y-scales, n= counts on every stratum, total n in each strip title),
# but faceted by discourse_depth (0/1/2) instead of the narration/parable/
# other-reported-speech split.
#
# Rationale: the parable vs. non-parable split in viz_alluvial_latin_hu.R
# turned out to be a proxy for discourse depth -- within parables, depth 1
# (the parable's own narrating voice) tracks narration, while depth 2
# (a character quoted *inside* the parable) flips to the ordinary
# reported-speech pattern. This version tests whether depth alone, without
# reference to parables at all, drives the same split.
#
# Reads dat/gospels_verbs_grc_lat_hu.tsv (run from the repository root).

set.seed(1337)
suppressMessages(library(tidyverse))
suppressMessages(library(ggalluvial))
suppressMessages(library(ggrepel))

d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)

# four Hungarian past-tense categories under study, in a fixed display order
hu_levels = c("complex_perfective", "complex_imperfective", "perfective", "imperfective")
hu_labels = c("complex perfective\n(past/ipf + vala/volt)",
              "complex imperfective\n(present + vala/volt)",
              "perfective\n(-t/-tt)", "imperfective\n(-a/-e, -á/-é)")
hu_short = c("complex\nperfective", "complex\nimperfective", "perfective", "imperfective")

# core Latin indicative tenses that bear on past-tense choice
lat_levels = c("pluperfect", "imperfect", "present", "perfect")

plot_data = d |>
  filter(row_type == "hu_lat",
         lat_mood_analytic == "indicative",
         lat_tense_analytic %in% lat_levels,
         hu_tense_category %in% hu_levels,
         discourse_depth %in% c(0, 1, 2)) |>
  mutate(
    lat_tense_analytic = factor(lat_tense_analytic, levels = lat_levels),
    hu_tense_category = factor(hu_tense_category, levels = hu_levels, labels = hu_short),
    discourse = factor(paste0("Depth ", discourse_depth), levels = c("Depth 0", "Depth 1", "Depth 2"))
  ) |>
  count(discourse, lat_tense_analytic, hu_tense_category, name = "n") |>
  # fill-only factor with reversed level order: used to flip the alluvium
  # draw/z-order in the depth-0 panel only, the one clearly dominated by a
  # single category (imperfective), so its ribbon doesn't paint over the
  # minority flows. Depth 1 and 2 are more evenly split and keep the default
  # order. The stratum axis order (hu_tense_category itself) is untouched.
  mutate(hu_tense_category_rev = factor(as.character(hu_tense_category), levels = rev(hu_short)))

pal = c("#eda100", "#1baf7a", "#eb6834", "#2a78d6")
names(pal) = hu_short

# strip titles get a total-n suffix without touching the "discourse" column
# itself, which the two geom_alluvium calls below filter on by its plain value
discourse_totals = plot_data |> group_by(discourse) |> summarise(total = sum(n), .groups = "drop")
discourse_labeller = as_labeller(
  setNames(paste0(discourse_totals$discourse, " (n = ", discourse_totals$total, ")"), discourse_totals$discourse)
)

p = ggplot(plot_data,
           aes(axis1 = lat_tense_analytic, axis2 = hu_tense_category, y = n)) +
  geom_alluvium(data = filter(plot_data, discourse == "Depth 0"),
                aes(fill = hu_tense_category_rev),
                width = 0.28, alpha = 0.85, colour = "white", linewidth = 0.15) +
  geom_alluvium(data = filter(plot_data, discourse %in% c("Depth 1", "Depth 2")),
                aes(fill = hu_tense_category),
                width = 0.28, alpha = 0.85, colour = "white", linewidth = 0.15) +
  geom_stratum(width = 0.28, fill = "#e1e0d9", colour = "#52514e", linewidth = 0.3) +
  geom_text_repel(
    stat = "stratum",
    aes(label = paste0(after_stat(stratum), "\nn=", after_stat(count)),
        x = after_stat(x) + ifelse(after_stat(x) == 1, -0.2, 0.2),
        hjust = after_stat(ifelse(x == 1, 1, 0))),
    size = 2.9, lineheight = 0.85, min.segment.length = Inf,
    box.padding = 0.15, direction = "y", seed = 1337
  ) +
  facet_wrap(~discourse, scales = "free_y", labeller = discourse_labeller) +
  scale_x_discrete(limits = c("Latin tense", "Hungarian category"), expand = c(0.32, 0.32)) +
  scale_fill_manual(values = pal, breaks = hu_short, name = "Hungarian past-tense category", labels = hu_labels) +
  labs(
    y = "Number of matched Hungarian verbs",
    title = "Old Hungarian past-tense choice against the Latin source tense",
    subtitle = "By discourse depth (0 = narration, 1 = direct speech, 2 = speech quoted within speech)",
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

ggsave("viz/alluvial_latin_to_hu_tense_depth.png", p, width = 14.5, height = 7.8, dpi = 900)
cat("rows plotted:", nrow(plot_data), "\n")
print(plot_data |> group_by(discourse, lat_tense_analytic) |> summarise(total = sum(n), .groups = "drop"))
