#!/usr/bin/env Rscript
# Alluvial version of viz_past_tense_latin.R: same four Latin indicative
# tenses (in) flowing to the same four Hungarian past-tense categories (out),
# faceted by discourse mode instead of stacked bars.
#
# Three discourse facets, not two: narration, parable, and other reported
# speech. Parables are coded as "speech" in discourse_mode (Jesus is the
# speaker) but behave tense-wise like narration -- see
# script/viz_idiosyncrasy_funnel.R and dat/parable_ranges.tsv (built by
# script/build_parable_flag.R from dat/parable_list.txt). Splitting them out
# tests that directly instead of pooling them into one "reported speech"
# bucket with everything else Jesus says.
#
# Reads dat/gospels_verbs_grc_lat_hu.tsv and dat/parable_ranges.tsv (run from
# the repository root).

set.seed(1337)
suppressMessages(library(tidyverse))
suppressMessages(library(ggalluvial))
suppressMessages(library(ggrepel))

d = read_tsv("dat/gospels_verbs_grc_lat_hu.tsv", show_col_types = FALSE)
parable_ranges = read_tsv("dat/parable_ranges.tsv", show_col_types = FALSE)

# four Hungarian past-tense categories under study, in a fixed display order
hu_levels = c("complex_perfective", "complex_imperfective", "perfective", "imperfective")
hu_labels = c("complex perfective\n(past/ipf + vala/volt)",
              "complex imperfective\n(present + vala/volt)",
              "perfective\n(-t/-tt)", "imperfective\n(-a/-e, -á/-é)")
hu_short = c("complex\nperfective", "complex\nimperfective", "perfective", "imperfective")

# core Latin indicative tenses that bear on past-tense choice
lat_levels = c("pluperfect", "imperfect", "present", "perfect")

# verse -> in_parable lookup (range join on book+chapter, then verse bounds;
# first match wins on the rare occasions two listed ranges overlap)
verse_lookup = d |> distinct(book, chapter, verse)
parable_flag = verse_lookup |>
  inner_join(parable_ranges, by = c("book", "chapter"), relationship = "many-to-many") |>
  filter(verse >= verse_start, verse <= verse_end) |>
  distinct(book, chapter, verse, .keep_all = TRUE) |>
  select(book, chapter, verse, parable_name)

plot_data = d |>
  filter(row_type == "hu_lat",
         lat_mood_analytic == "indicative",
         lat_tense_analytic %in% lat_levels,
         hu_tense_category %in% hu_levels) |>
  left_join(parable_flag, by = c("book", "chapter", "verse")) |>
  mutate(
    lat_tense_analytic = factor(lat_tense_analytic, levels = lat_levels),
    hu_tense_category = factor(hu_tense_category, levels = hu_levels, labels = hu_short),
    discourse = case_when(
      discourse_mode == "narration" ~ "Narration",
      !is.na(parable_name) ~ "Parable",
      TRUE ~ "Other reported speech"
    ) |> fct_relevel("Narration", "Parable", "Other reported speech")
  ) |>
  count(discourse, lat_tense_analytic, hu_tense_category, name = "n") |>
  # same categories, fill-only factor with reversed level order: used to flip
  # the alluvium draw/z-order in the narration and parable panels, so the
  # last-drawn ribbon (imperfective) doesn't paint over the others there --
  # both panels are imperfective-dominated, unlike "other reported speech".
  # The stratum axis order (hu_tense_category itself) is left untouched.
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
  geom_alluvium(data = filter(plot_data, discourse %in% c("Narration", "Parable")),
                aes(fill = hu_tense_category_rev),
                width = 0.28, alpha = 0.85, colour = "white", linewidth = 0.15) +
  geom_alluvium(data = filter(plot_data, discourse == "Other reported speech"),
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

ggsave("viz/alluvial_latin_to_hu_tense.png", p, width = 14.5, height = 7.8, dpi = 900)
cat("rows plotted:", nrow(plot_data), "\n")
print(plot_data |> group_by(discourse, lat_tense_analytic) |> summarise(total = sum(n), .groups = "drop"))
