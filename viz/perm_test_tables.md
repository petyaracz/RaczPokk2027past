# Permutation-test results: Latin tense -> Hungarian past-tense category

Companion tables for `viz/alluvial_latin_to_hu_tense.png`. Exact permutation
tests (20,000 permutations, label shuffling), each table its own multiple-
comparison family. Significance stars are based on the Holm-adjusted p value.

## Group-level: this (Latin tense x discourse) group's profile over the four
Hungarian categories vs the pooled other seven groups (chi-squared statistic)

| Discourse | Latin tense | n | p (Holm) | p (BH) | Sig. |
|---|---|---|---|---|---|
| Direct speech | present |  459 | 0.0004 | < 0.00005 | *** |
| Direct speech | imperfect |  844 | 0.0004 | < 0.00005 | *** |
| Direct speech | perfect | 2023 | 0.0004 | < 0.00005 | *** |
| Direct speech | pluperfect |  115 | 0.0004 | < 0.00005 | *** |
| Reported speech | present |   93 | 0.0004 | < 0.00005 | *** |
| Reported speech | imperfect |  124 | 0.0004 | < 0.00005 | *** |
| Reported speech | perfect | 1208 | 0.0004 | < 0.00005 | *** |
| Reported speech | pluperfect |   19 | 0.0004 | < 0.00005 | *** |

## Cell-level: this group's share of one Hungarian category vs the pooled
rest's share of that category (difference in proportion) -- one row per flow
in the alluvial diagram

| Discourse | Latin tense | Hungarian category | obs. diff | p (Holm) | p (BH) | Sig. |
|---|---|---|---|---|---|---|
| Direct speech | present | imperfective | +0.341 | 0.0016 | 0.0001 | ** |
| Direct speech | present | perfective | -0.169 | 0.0016 | 0.0001 | ** |
| Direct speech | present | complex_imperfective | -0.139 | 0.0016 | 0.0001 | ** |
| Direct speech | present | complex_perfective | -0.033 | 0.0018 | 0.0003 | ** |
| Direct speech | imperfect | imperfective | -0.440 | 0.0016 | 0.0001 | ** |
| Direct speech | imperfect | perfective | -0.189 | 0.0016 | 0.0001 | ** |
| Direct speech | imperfect | complex_imperfective | +0.644 | 0.0016 | 0.0001 | ** |
| Direct speech | imperfect | complex_perfective | -0.015 | 0.1562 | 0.0357 | ns |
| Direct speech | perfect | imperfective | +0.488 | 0.0016 | 0.0001 | ** |
| Direct speech | perfect | perfective | -0.230 | 0.0016 | 0.0001 | ** |
| Direct speech | perfect | complex_imperfective | -0.222 | 0.0016 | 0.0001 | ** |
| Direct speech | perfect | complex_perfective | -0.037 | 0.0016 | 0.0001 | ** |
| Direct speech | pluperfect | imperfective | -0.574 | 0.0016 | 0.0001 | ** |
| Direct speech | pluperfect | perfective | -0.143 | 0.0016 | 0.0001 | ** |
| Direct speech | pluperfect | complex_imperfective | -0.087 | 0.0567 | 0.0100 | ns |
| Direct speech | pluperfect | complex_perfective | +0.804 | 0.0016 | 0.0001 | ** |
| Reported speech | present | imperfective | -0.215 | 0.0016 | 0.0001 | ** |
| Reported speech | present | perfective | +0.322 | 0.0016 | 0.0001 | ** |
| Reported speech | present | complex_imperfective | -0.085 | 0.1329 | 0.0263 | ns |
| Reported speech | present | complex_perfective | -0.022 | 0.5388 | 0.2781 | ns |
| Reported speech | imperfect | imperfective | -0.244 | 0.0016 | 0.0001 | ** |
| Reported speech | imperfect | perfective | -0.120 | 0.0028 | 0.0004 | ** |
| Reported speech | imperfect | complex_imperfective | +0.397 | 0.0016 | 0.0001 | ** |
| Reported speech | imperfect | complex_perfective | -0.033 | 0.1562 | 0.0366 | ns |
| Reported speech | perfect | imperfective | -0.320 | 0.0016 | 0.0001 | ** |
| Reported speech | perfect | perfective | +0.526 | 0.0016 | 0.0001 | ** |
| Reported speech | perfect | complex_imperfective | -0.172 | 0.0016 | 0.0001 | ** |
| Reported speech | perfect | complex_perfective | -0.033 | 0.0016 | 0.0001 | ** |
| Reported speech | pluperfect | imperfective | -0.465 | 0.0016 | 0.0001 | ** |
| Reported speech | pluperfect | perfective | -0.105 | 0.5388 | 0.3462 | ns |
| Reported speech | pluperfect | complex_imperfective | -0.137 | 0.2937 | 0.1044 | ns |
| Reported speech | pluperfect | complex_perfective | +0.707 | 0.0016 | 0.0001 | ** |

