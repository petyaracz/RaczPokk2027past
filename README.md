# Gospel past tense: Greek – Latin – Old Hungarian verb alignment

One script, `proiel_gospel_verbs.py`, builds a token-level table of every verb in the four Gospels, aligned across:

- **Greek** (Tischendorf 1869) and **Latin** (Vulgate), from the PROIEL treebank, with PROIEL's own Latin→Greek token alignment;
- **Old Hungarian**, the Jordánszky kódex (1516–1519), from the Ómagyar Korpusz;
- **discourse mode** (narration / speech / speech within speech), projected from the quotation marks of the Catholic Public Domain Version (CPDV).

The research question: how do Old Hungarian past tense choices (perfective *-t*, imperfective *-a/-e, -á/-é*, complex perfective with *vala/volt*, complex imperfective with *vala/volt*) map onto the Greek and Latin source tenses?

Python ≥ 3.8, standard library only. Runtime is about 30 s. The output is deterministic: identical inputs give a byte-identical TSV.

---

## 1. Inputs

| Input | Where it comes from | How the script gets it |
|---|---|---|
| `greek-nt.xml`, `latin-nt.xml` | PROIEL treebank, GitHub, pinned commit `8e388967a1335ed12335ddc655fe46993ee7d57a` (master, 2023-05-02) | Downloaded automatically into `--data-dir` (default `proiel_data/`); cached on later runs |
| `jordk_mt_mk_lk_jn.tsv` | Jordánszky kódex, Ómagyar Korpusz: <http://omagyarkorpusz.nytud.hu/documents/kodexek/JordK/rmkinput>; the four Gospels were extracted by hand | Local file, passed with `--jordanszky` |
| `CPDV.txt` | Catholic Public Domain Version, via openbible; one verse per line, `Mark 1:7<TAB>text`; the whole Bible is fine | Local file, passed with `--cpdv` |

PROIEL URLs:

```
https://raw.githubusercontent.com/proiel/proiel-treebank/8e388967a1335ed12335ddc655fe46993ee7d57a/greek-nt.xml
https://raw.githubusercontent.com/proiel/proiel-treebank/8e388967a1335ed12335ddc655fe46993ee7d57a/latin-nt.xml
```

If `raw.githubusercontent.com` is blocked (it was in the Claude sandbox), get the same files with git and place them in the cache directory:

```bash
git clone https://github.com/proiel/proiel-treebank.git
cd proiel-treebank && git checkout 8e388967a1335ed12335ddc655fe46993ee7d57a && cd ..
mkdir -p proiel_data && cp proiel-treebank/greek-nt.xml proiel-treebank/latin-nt.xml proiel_data/
```

The Ómagyar Korpusz server redirects https→http, which defeats some fetchers. That is why the Jordánszky extract is a local file.

**Jordánszky TSV format.** Header `X1 … X10`, one token per line:

| Column | Content |
|---|---|
| X1 | page |
| X2 | book_chapter (`Mt_1`, `Mk_9`, `Lk_24`, `Jn_6`; also `Prol` and similar) |
| X3 | verse (`-` for headings) |
| X4 | original form |
| X5 | normalised form |
| X6 | modernised variant |
| X7, X8 | mostly `NA` |
| X9 | lemma |
| X10 | morphological tag, e.g. `VPfx.V.Ipf.S3.Def` |

Rows with a non-numeric chapter or verse (prologues, chapter headings) are skipped.

**Input checksums** (sha256) of the files used for the reference run:

```
93f868f54109acf305c0bd5f465e65509c90798ac176ddd20b09ebcfae9f422f  proiel_data/greek-nt.xml
be667e068e6f1965110c08b245d2b279b645af1ffe8026d276a9feb065151dff  proiel_data/latin-nt.xml
413ee454b7404c84306b69f92a52c2036f6b0ad4eb03659ac0ff8a69aeff52f9  jordk_mt_mk_lk_jn.tsv
719a78683964426e66a19e9ec57811ea26b80212b00ffd39d0c3039ba1614d34  CPDV.txt
```

---

## 2. Running

```bash
# Full table: Greek + Latin + Old Hungarian + discourse mode
python3 proiel_gospel_verbs.py --jordanszky jordk_mt_mk_lk_jn.tsv --cpdv CPDV.txt
#   -> gospels_verbs_grc_lat_hu.tsv

# Greek + Latin only (PROIEL), no Hungarian
python3 proiel_gospel_verbs.py
#   -> gospels_verbs_grc_lat.tsv
```

Options:

- `--books MARK` (or any subset of `MATT MARK LUKE JOHN`)
- `--data-dir DIR`
- `-o FILE`
- `--no-verse-text`, which drops the verse-text columns and most of the 17 MB

---

## 3. Verifying a rerun

**Expected output checksums** for the inputs above:

```
a5b12ce14a4e7afb05e75ffb838e2f8e02988beee894120cffe8133da32d421e  gospels_verbs_grc_lat_hu.tsv
6521ee7c4141b80cd8ee5687d75a5e49e22079d8f26a0807971223839ac7d945  gospels_verbs_grc_lat.tsv
```

**Expected counts.** stderr should end with:

```
wrote 16408 rows to gospels_verbs_grc_lat_hu.tsv: {'hu_lat': 13782, 'lat_only': 1263, 'grc_only': 571, 'hu_only': 792}
wrote 16626 rows to gospels_verbs_grc_lat.tsv: {'greek_verb': 14695, 'latin_only': 1931}
```

If the checksums differ, for instance after a code change, run the substantive checks below. Each line prints `OK` or `FAIL` with the observed value. The thresholds are the reference values, with tolerance where a small change is harmless.

```python
import csv, collections
R = list(csv.DictReader(open("gospels_verbs_grc_lat_hu.tsv", encoding="utf-8"), delimiter="\t"))
hu = [r for r in R if r["hu_lemma"]]
m  = [r for r in R if r["row_type"] == "hu_lat"]
def check(name, ok, val): print(("OK  " if ok else "FAIL"), name, val)

# 1. Every Hungarian verb appears exactly once, in word order within each verse
check("hu verb units", len(hu) == 14574, len(hu))
last, bad = {}, 0
for r in hu:
    k = (r["book_code"], r["chapter"], r["verse"]); p = int(r["hu_pos_in_verse"])
    bad += k in last and p < last[k]; last[k] = p
check("word order violations", bad == 0, bad)

# 2. Tense categories (from the corpus tags + vala/volt/volna attachment)
c = collections.Counter(r["hu_tense_category"] for r in hu)
check("imperfective",          c["imperfective"] == 3525, c["imperfective"])
check("perfective",            c["perfective"] == 858, c["perfective"])
check("complex_imperfective",  c["complex_imperfective"] == 737, c["complex_imperfective"])
check("complex_perfective",    c["complex_perfective"] == 168, c["complex_perfective"])
aux = collections.Counter(r["hu_aux_rule"] for r in hu)
check("aux attached / unattached", aux["aux_tag_attached"] == 1314 and aux["aux_tag_no_host"] == 40, dict(aux))

# 3. Verse mapping: the known Vulgate shift in Mark 9 is found
g = {r["verse_group_map"] for r in R if r["book_code"] == "MARK"}
check("Mark 9:1 ~ Vulgate 8:39", "9.1 ~ 8.39" in g, "")
check("Mark 9:2 ~ Vulgate 9:1",  "9.2 ~ 9.1" in g, "")

# 4. Alignment sanity: Latin tense -> Hungarian category has the expected main cells
ct = collections.Counter((r["lat_tense_analytic"], r["hu_tense_category"])
                         for r in m if r["lat_mood_analytic"] == "indicative")
check("Latin perfect -> imperfective dominant", ct["perfect","imperfective"] > 2 * ct["perfect","perfective"],
      (ct["perfect","imperfective"], ct["perfect","perfective"]))
check("Latin imperfect -> complex imperfective dominant",
      ct["imperfect","complex_imperfective"] > ct["imperfect","imperfective"],
      (ct["imperfect","complex_imperfective"], ct["imperfect","imperfective"]))
check("Latin pluperfect -> complex perfective dominant",
      ct["pluperfect","complex_perfective"] > 0.5 * sum(v for (t, _), v in ct.items() if t == "pluperfect"),
      ct["pluperfect","complex_perfective"])
conf = collections.Counter(r["align_conf"] for r in m)
check("high-confidence matches >= 9500", conf["high"] >= 9500, dict(conf))

# 5. Discourse mode: 1st/2nd person verbs should almost never be narration,
#    except where the evangelist speaks in his own voice
exc = {("LUKE",1,v) for v in range(1,5)} | {("JOHN",1,14),("JOHN",1,16),("JOHN",19,35),
                                             ("JOHN",20,31),("JOHN",21,24),("JOHN",21,25)}
fin = [r for r in hu if r["hu_finite"] == "TRUE" and r["hu_person"]]
non3 = [r for r in fin if r["hu_person"] != "3"]
err = [r for r in non3 if r["discourse_mode"] == "narration"
       and (r["book_code"], int(r["chapter"]), int(r["verse"])) not in exc]
check("1st/2nd person tagged narration < 1.5%", len(err) / len(non3) < 0.015,
      f"{len(err)}/{len(non3)}")
```

Reference values: 22/3151 (0.7%) for check 5; perfect→imperfective 2,463 against perfect→perfective 714; imperfect→complex imperfective 630 against imperfect→imperfective 315; pluperfect→complex perfective 108; `align_conf` high 9,589, medium 4,018, low 175.

---

## 4. Output columns (`gospels_verbs_grc_lat_hu.tsv`, 88 columns)

There is one row per verb unit, ordered by book, chapter, verse (modern/Hungarian numbering) and Hungarian word order. Latin- and Greek-only rows are interleaved at their source position.

| Group | Columns | Notes |
|---|---|---|
| Row | `row_id`, `row_type`, `book`, `book_code`, `chapter`, `verse`, `verse_group`, `verse_group_map` | `row_type` ∈ `hu_lat`, `hu_only`, `lat_only`, `grc_only`. `verse_group_map` is "Hungarian verses ~ PROIEL Latin verses", e.g. `9.1 ~ 8.39` |
| Hungarian | `hu_pos_in_verse`, `hu_page`, `hu_form_orig`, `hu_form_norm`, `hu_lemma`, `hu_tag`, `hu_x6`, `hu_x7`, `hu_preverb_attached`, `hu_person`, `hu_number`, `hu_definite`, `hu_base_tense`, `hu_finite`, `hu_source_label` | `hu_base_tense` comes from the lexical verb's own tag: `past` (-t), `ipf` (-a/-e, -á/-é), `present`, `future`, `conditional`, `subjunctive`, `infinitive`, `gerund_van`, `participle_*` |
| Auxiliary | `hu_aux_form_orig`, `hu_aux_form_norm`, `hu_aux_tag`, `hu_aux_distance`, `hu_aux_rule` | distance is aux position minus verb position |
| **Category** | `hu_tense_category` | `perfective`, `imperfective`, `complex_perfective` (past or ipf + vala/volt), `complex_imperfective` (present + vala/volt), `conditional_past` (past + volna), `other_plus_aux`, otherwise the base tense |
| Alignment | `align_score`, `align_lex`, `align_morph`, `align_pos`, `align_conf`, `verse_n_hu`, `verse_n_lat`, `verse_counts_equal` | `align_conf` ∈ high / medium / low |
| Latin | `lat_*` (token id, form, lemma, PROIEL morphology raw and decoded, finiteness, relation, head lemma, sentence id/status, citation), `lat_aux_form`, `lat_aux_morph_raw`, `lat_aux_tense`, **`lat_tense_analytic`**, **`lat_mood_analytic`** | the analytic columns combine participle + *sum*: *baptizatus est* is a perfect indicative, *vestitus erat* a pluperfect |
| Greek | `grc_*`, same fields as Latin | the Greek token PROIEL aligns to the Latin one |
| Discourse | `discourse_depth`, `discourse_mode`, `discourse_boundary`, `discourse_boundary_dist_tokens`, `cpdv_verse_mixed`, `discourse_source` | depth 0 narration, 1 speech, 2+ speech within speech |
| Text | `hu_verse_text`, `lat_verse_text`, `grc_verse_text`, `cpdv_verse_text` | verses in a group are joined with ` \| ` |

---

## 5. What the code does, and why

1. **Parse PROIEL.** Tokens with no surface form (empty tokens for ellipsis) are dropped. Morphology is decoded from PROIEL's 10-position code.
2. **Build Latin units.** Latin *sum* with relation `aux` is folded into its head verb. Greek verbs with no aligned Latin token become `grc` units, anchored after the Latin token aligned to the nearest preceding Greek token in the same Greek verse, and filed under *that* Latin token's verse.
3. **Parse the Jordánszky extract.** The split-off ends of nine John chapters are labelled with the next chapter's number (e.g. `Jn_2 51` between `Jn_1 51` and `Jn_2 1`). They are folded back into the previous verse.
4. **Build Hungarian units.** An auxiliary is lemma *van* with form *vala/volt/volna* (± *-e*), tense or mood `Ipf`/`Past`/`Cond`, and **no person feature**. This follows the corpus annotation, which tags auxiliaries without person and lexical copulas with person: *keze megaszott vala* is correctly lexical. Each auxiliary attaches to the nearest verb up to 3 tokens to its left, else up to 2 to its right. Otherwise it stays a verb of its own, with `hu_aux_rule = aux_tag_no_host`.
5. **Align verses.** PROIEL uses Vulgate numbering; the Jordánszky extract and the CPDV use modern numbering. They differ in Mark 9 (shifted by one from Vulgate 8:39 = modern 9:1), in John 6 from verse 52, and in a few merged or missing verses. Each book is aligned with a banded DP (moves 1-1, 2-1, 1-2, 1-0, 0-1). The score combines a Gale–Church length term, verb-lemma overlap and a +0.8 prior for identical chapter:verse.
6. **Align verbs within each verse group.** This is a monotone DP: order is preserved and gaps are allowed. A pair scores `2·lexical + morphological + positional − 1.5` and is kept only if the score is positive. The lexical term is P(Latin lemma | Hungarian lemma). It starts as verse-level Dice co-occurrence and is re-estimated twice from the alignments, with the verse alignment redone each time. The Jordánszky translation was made from the Vulgate, so Hungarian is aligned to Latin. Greek comes in through PROIEL's alignment, and Greek-only units are never matched to Hungarian.
7. **Project discourse mode.**
   - The CPDV quote stack (`“ ”` and `‘ ’`, nested) gives every character a depth. Depth carries across verses and resets at chapter boundaries.
   - Four typographical slips are patched in `CPDV_PATCHES`: Mark 5:41, 10:19, 12:32 and Luke 7:27. They were found with a nesting check.
   - English boundaries are projected onto the Hungarian verse: openings snap to the nearest Hungarian colon and closings to the nearest `. ? ! ;`, within 25% of the verse. Otherwise they are placed proportionally. Quotes in the first or last 4% of the English verse stay at that edge.
   - Latin- and Greek-only rows inherit the value of the neighbouring Hungarian verb.

Tunable constants sit at module level: `SAME_NUMBER_BONUS`, `BAND`, `EDGE`, `CPDV_PATCHES`.

---

## 6. Known limitations

- **The Hungarian–Latin alignment is heuristic, not gold.** Validate on a random hand-checked sample before modelling, weighted towards `align_conf = medium`. Reorderings against the Latin produce gaps where there should be matches, because the DP is monotone. **Checked:** a 164-row sample of `hu_lat` pairs, weighted towards `align_conf = medium` (`script/qa_latin_hungarian.R`), all correctly aligned on comparison of the Latin and Hungarian forms.
- **Many `hu_only` rows are not missed matches.** They are dominated by *van*, *mond* and *lesz*: copulas and *dicens*-type expansions with no Latin verb. Some are missed matches.
- **PROIEL alignment gaps.** 571 Greek verbs have no Latin token aligned. Some are omissions in the Vulgate, some gaps in PROIEL's semi-automatic alignment, which is reported at over 90% accuracy on Old Church Slavonic.
- **Textual bases differ.** The Greek text is Tischendorf, the Latin is PROIEL's Vulgate, and the Jordánszky Vorlage is a medieval Vulgate manuscript. Verses absent from Tischendorf (e.g. Mark 7:16, 9:44, 9:46) have Latin and Hungarian but no Greek.
- **Discourse mode follows the CPDV editor's reading of the Latin.** Scripture citations ("it is written: …") count as speech. The 22 remaining first- and second-person verbs labelled narration are mostly in mixed verses where the Hungarian has no colon.
- **Greek periphrastics** (ἦν + participle) are not folded together, unlike Latin *sum* and Hungarian *vala*.
- **Licences.** PROIEL is CC BY-NC-SA 4.0, so derived data must keep that licence. Cite Haug & Jøhndal (2008), "Creating a Parallel Treebank of the Old Indo-European Bible Translations", LaTeCH 2008, 27–34. The CPDV is public domain. Cite the Ómagyar Korpusz for the Jordánszky annotation.

---

## 7. Notes for a next Claude instance

- **Files used in the session:**
  - `proiel_gospel_verbs.py`, the script;
  - `jordk_mt_mk_lk_jn.tsv` and `CPDV.txt`, both uploaded by the user;
  - `proiel_data/`, the PROIEL XML at the pinned commit.
- **Sandbox network.** `raw.githubusercontent.com` and `omagyarkorpusz.nytud.hu` were blocked; `git clone` from GitHub worked. Use the git route in §1 and the user's local files.
- **Verifying a rerun.** Run both modes, compare checksums (§3), and if they differ run the §3 checks.
- **Context.** The study pairs with the user's Diachronica paper on Old and Middle Hungarian past tense variation. Planned extensions:
  - other translations with different Vorlagen (Müncheni kódex from the Latin; Sylvester 1541 and Károli 1590 drawing on the Greek);
  - a hand-checked alignment sample;
  - modelling Hungarian category ~ source tense + discourse mode + person.
- **First substantive finding.** The *-t* perfective is almost confined to speech: 71 cases in narration against 787 in speech or embedded speech. Narration uses *-á/-é* and *vala* forms. Any model of source-tense effects needs discourse mode in it.

---

## 8. Preliminary results

Alluvial diagram of the four core Latin indicative tenses (present, imperfect, perfect, pluperfect) against the four Hungarian past-tense categories, faceted by discourse mode (`script/viz_alluvial_latin_hu.R`):

![Alluvial diagram: Latin tense to Hungarian past-tense category, by discourse mode](viz/alluvial_latin_to_hu_tense.png)

Statistical backing: exact permutation tests (20,000 permutations, label shuffling; `script/perm_test_past_tense_latin.R`), formatted for reporting by `script/report_perm_test_tables.R`. Each table below is its own multiple-comparison family; significance stars use the Holm-adjusted p value.

**Group-level**: does this (Latin tense x discourse) group's profile over the four Hungarian categories differ from the pooled other seven groups? (chi-squared statistic)

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

**Cell-level**: this group's share of one Hungarian category vs the pooled rest's share of that category (difference in proportion) — one row per flow in the alluvial diagram above.

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

Six of 32 cells are non-significant at Holm-adjusted p < .05, concentrated in the smallest flows (pluperfect → perfective/complex imperfective, present → complex categories in reported speech). These are also the flows too thin to read by eye in the alluvial diagram, so the plot and the table agree: every visually distinct band is a statistically supported shift.
