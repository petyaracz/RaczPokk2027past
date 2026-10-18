#!/usr/bin/env python3
"""
Greek-Latin(-Old Hungarian) verb alignment for the four Gospels.

Sources
-------
Greek and Latin: PROIEL treebank (Greek NT, ed. Tischendorf 1869; Jerome's
  Vulgate), dependency-annotated, with PROIEL's own token-level Latin->Greek
  alignment. Downloaded from GitHub, pinned to a commit (see URLS below).
  Licence CC BY-NC-SA 4.0. Cite: Haug & Jøhndal 2008, 'Creating a Parallel
  Treebank of the Old Indo-European Bible Translations', LaTeCH 2008, 27-34.

Old Hungarian: Jordánszky kódex (1516-1519), from the Old Hungarian Corpus
  (Ómagyar Korpusz, Hungarian Generative Diachronic Syntax projects,
  NYTK / Research Institute for Linguistics), tokenised, normalised,
  lemmatised and morphologically annotated:
    http://omagyarkorpusz.nytud.hu/documents/kodexek/JordK/rmkinput
  The script expects a local TSV extract of the four Gospels from that
  source (the corpus server redirects https->http and is not reliably
  scriptable), with header X1..X10:
    X1 page, X2 book_chapter (Mt_1), X3 verse, X4 original form,
    X5 normalised form, X6 modernised variant, X7 extra (mostly NA),
    X8 (NA), X9 lemma, X10 morphological tag (e.g. VPfx.V.Ipf.S3.Def)

English (discourse mode only): Catholic Public Domain Version (CPDV,
  translated from the Sixto-Clementine Vulgate, public domain), via
  openbible; one verse per line, 'Mark 1:7<TAB>text'. Its quotation marks
  (“ ” outer, ‘ ’ inner, nested further as needed) run across verses and
  give the quotation depth of every character. Four typographical slips
  are patched in CPDV_PATCHES.

Verse alignment
---------------
PROIEL's Vulgate numbering differs from the modern numbering used by the
Jordánszky extract and the CPDV in a few places (Mark 9: Vulgate 8:39 =
modern 9:1 and the whole chapter shifted by one; John 6 from v. 52; merged
or missing verses). Verses are aligned book by book with a banded DP
(1-1, 2-1, 1-2, 1-0, 0-1) scored on a Gale-Church length term, verb-lemma
overlap, and a prior for identical numbering. Verb alignment then runs
within each verse group. `verse` is the Hungarian (modern) number;
`verse_group_map` shows the Hungarian ~ Latin verses in each group.
The Jordánszky extract labels the split-off end of nine John chapters with
the next chapter's number; these are folded back (hu_source_label keeps the
original label).

Discourse mode
--------------
CPDV quote boundaries are projected onto the Hungarian verse: opening quotes
snap to the nearest Hungarian colon, closing quotes to the nearest . ? ! ;
(within a quarter of the verse), otherwise they are placed proportionally;
quotes at the very edge of the English verse stay at the edge. Each verb gets
discourse_depth (0 narration, 1 speech, 2+ speech within speech) and
discourse_mode. Latin/Greek-only rows inherit from the neighbouring
Hungarian verb. Check: of 3,151 first/second-person Hungarian finite verbs,
22 (0.7%) come out as narration outside the narrator's own passages
(Lk 1:1-4, Jn 1:14, 1:16, 19:35, 20:31, 21:24-25).

Modes
-----
  python3 proiel_gospel_verbs.py
      PROIEL only: one row per Greek verb with its aligned Latin token, plus
      Latin verbs not aligned to a Greek verb (as in the first version).

  python3 proiel_gospel_verbs.py --jordanszky jordk_mt_mk_lk_jn.tsv [--cpdv CPDV.txt]
      Greek + Latin + Old Hungarian (+ discourse mode): one row per verb unit,
      ordered by book, chapter, verse and Hungarian word order.

Hungarian verb units and the four past tenses
---------------------------------------------
An auxiliary is a token with lemma 'van', form vala/volt/volna (optionally
with the question clitic -e), tense/mood Ipf, Past or Cond and NO person
feature. This follows the corpus annotation, which tags auxiliary copulas
without person (V.Ipf, V.Past, V.Cond) and lexical copulas with person
(V.Ipf.S3 ...). Each auxiliary is attached to the nearest verb within three
tokens to its left, else within two tokens to its right; otherwise it is
kept as a verb of its own and flagged. Categories (hu_tense_category):
  perfective            -t/-tt past (tag Past), no auxiliary
  imperfective          -a/-e, -á/-é past (tag Ipf), no auxiliary
  complex_perfective    Past or Ipf + vala/volt
  complex_imperfective  present + vala/volt
  conditional_past      Past + volna;  other_plus_aux for anything else
  present, future, conditional, subjunctive, infinitive, gerund_van,
  participle_*, other   for the remaining verb forms
An unattached auxiliary is categorised from its own tag, with
hu_aux_rule = 'aux_tag_no_host'.

Hungarian-Latin alignment (heuristic, NOT gold)
-----------------------------------------------
Within each verse, Hungarian verb units are aligned to Latin verb units by
monotone dynamic programming (order-preserving, gaps allowed). Pair score =
  2 * lexical + 1 * morphological + 1 * positional - 1.5
lexical: P(Latin lemma | Hungarian lemma), first estimated from verse-level
  co-occurrence (Dice), then re-estimated from the first-pass alignment.
morphological: finiteness, mood and person/number compatibility.
positional: 1 - |difference in relative position within the verse|.
Latin 'sum' with relation 'aux' is folded into its head verb, mirroring the
Hungarian auxiliary handling. Greek verbs with no aligned Latin token are
placed into the sequence after the Latin token aligned to the nearest
preceding Greek token; they are never matched to Hungarian (the Jordánszky
translation was made from the Vulgate).

Output row types (row_type): hu_lat (matched), hu_only, lat_only,
grc_only. Latin rows carry their PROIEL-aligned Greek token where one
exists. align_conf: high / medium / low; verse_counts_equal flags verses
where Hungarian and Latin verb counts agree.
"""

import argparse
import collections
import csv
import math
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------
PROIEL_COMMIT = "8e388967a1335ed12335ddc655fe46993ee7d57a"  # master, 2023-05-02
BASE = f"https://raw.githubusercontent.com/proiel/proiel-treebank/{PROIEL_COMMIT}"
URLS = {
    "greek": f"{BASE}/greek-nt.xml",
    "latin": f"{BASE}/latin-nt.xml",
}
JORDANSZKY_SOURCE = "http://omagyarkorpusz.nytud.hu/documents/kodexek/JordK/rmkinput"

GOSPELS = ["MATT", "MARK", "LUKE", "JOHN"]
BOOK_NAMES = {"MATT": "Matthew", "MARK": "Mark", "LUKE": "Luke", "JOHN": "John"}
HU_BOOKS = {"Mt": "MATT", "Mk": "MARK", "Lk": "LUKE", "Jn": "JOHN"}

# ---------------------------------------------------------------------------
# PROIEL morphology
# ---------------------------------------------------------------------------
MORPH_FIELDS = ["person", "number", "tense", "mood", "voice", "gender", "case"]
MORPH_CODES = {
    "person": {"1": "1", "2": "2", "3": "3", "x": "uncertain"},
    "number": {"s": "sg", "d": "du", "p": "pl", "x": "uncertain"},
    "tense": {
        "p": "present", "i": "imperfect", "r": "perfect", "s": "resultative",
        "a": "aorist", "u": "past", "l": "pluperfect", "f": "future",
        "t": "future_perfect", "x": "uncertain",
    },
    "mood": {
        "i": "indicative", "s": "subjunctive", "m": "imperative",
        "o": "optative", "n": "infinitive", "p": "participle",
        "d": "gerund", "g": "gerundive", "u": "supine",
        "e": "ind_or_subj", "f": "ind_or_imp", "h": "subj_or_imp",
        "t": "finite", "x": "uncertain",
    },
    "voice": {"a": "active", "m": "middle", "p": "passive",
              "e": "middle_or_passive", "x": "uncertain"},
    "gender": {"m": "m", "f": "f", "n": "n", "p": "m_or_n", "o": "m_or_f",
               "r": "f_or_n", "q": "m_f_or_n", "x": "uncertain"},
    "case": {"n": "nom", "a": "acc", "o": "obl", "g": "gen", "c": "gen_or_dat",
             "e": "acc_or_dat", "d": "dat", "b": "abl", "i": "ins",
             "l": "loc", "v": "voc", "x": "uncertain", "z": "none"},
}
FINITE_MOODS = {"indicative", "subjunctive", "imperative", "optative",
                "ind_or_subj", "ind_or_imp", "subj_or_imp", "finite"}


def download(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print(f"cached: {dest}", file=sys.stderr)
        return
    print(f"downloading {url}", file=sys.stderr)
    tmp = dest + ".part"
    with urllib.request.urlopen(url) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 20):
            f.write(chunk)
    os.replace(tmp, dest)


def decode_morph(m):
    m = (m or "").ljust(10, "-")
    out = {}
    for i, field in enumerate(MORPH_FIELDS):
        c = m[i]
        out[field] = "" if c == "-" else MORPH_CODES[field].get(c, c)
    return out


def split_citation(cit):
    book, cv = cit.split(" ", 1)
    ch, vs = cv.split(".", 1)
    return book, int(ch), int(vs)


def load_proiel(path, books):
    """tokens_by_id, ordered tokens in `books`, verse text by (book, ch, vs)."""
    tokens, ordered, verse_text = {}, [], {}
    root = ET.parse(path).getroot()
    for sent in root.iter("sentence"):
        status = sent.get("status", "")
        for t in sent.iter("token"):
            form = t.get("form")
            if form is None:          # empty tokens (ellipsis) carry no form
                continue
            cit = t.get("citation-part") or ""
            if not cit:
                continue
            book, ch, vs = split_citation(cit)
            rec = {
                "id": t.get("id"), "form": form, "lemma": t.get("lemma", ""),
                "pos": t.get("part-of-speech", ""), "morph": t.get("morphology", ""),
                "relation": t.get("relation", ""), "head_id": t.get("head-id", ""),
                "align": t.get("alignment-id", ""),
                "book": book, "chapter": ch, "verse": vs,
                "sent_id": sent.get("id"), "sent_status": status,
                "after": t.get("presentation-after", " "),
                "before": t.get("presentation-before", ""),
            }
            tokens[rec["id"]] = rec
            if book in books:
                rec["order"] = len(ordered)
                ordered.append(rec)
                key = (book, ch, vs)
                verse_text[key] = verse_text.get(key, "") + rec["before"] + form + rec["after"]
    verse_text = {k: " ".join(v.split()) for k, v in verse_text.items()}
    return tokens, ordered, verse_text


def is_verb(rec):
    return rec is not None and rec["pos"] == "V-"


TOKEN_KEYS = ["token_id", "form", "lemma", "pos", "morph_raw", *MORPH_FIELDS,
              "finite", "relation", "head_lemma", "sent_id", "sent_status", "citation"]


def token_cols(prefix, rec, tokens):
    if rec is None:
        return {f"{prefix}_{k}": "" for k in TOKEN_KEYS}
    d = decode_morph(rec["morph"])
    head = tokens.get(rec["head_id"])
    out = {
        f"{prefix}_token_id": rec["id"], f"{prefix}_form": rec["form"],
        f"{prefix}_lemma": rec["lemma"], f"{prefix}_pos": rec["pos"],
        f"{prefix}_morph_raw": rec["morph"],
    }
    for k in MORPH_FIELDS:
        out[f"{prefix}_{k}"] = d[k]
    out[f"{prefix}_finite"] = "" if rec["pos"] != "V-" else str(d["mood"] in FINITE_MOODS).upper()
    out[f"{prefix}_relation"] = rec["relation"]
    out[f"{prefix}_head_lemma"] = head["lemma"] if head else ""
    out[f"{prefix}_sent_id"] = rec["sent_id"]
    out[f"{prefix}_sent_status"] = rec["sent_status"]
    out[f"{prefix}_citation"] = f"{rec['book']} {rec['chapter']}.{rec['verse']}"
    return out


def write_tsv(rows, path):
    fields = []
    for r in rows:
        for k in r:
            if k not in fields:
                fields.append(k)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter="\t", restval="",
                           quoting=csv.QUOTE_MINIMAL, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


# ---------------------------------------------------------------------------
# Mode 1: PROIEL only
# ---------------------------------------------------------------------------
def proiel_only(grc_tok, grc_ord, grc_text, lat_tok, lat_ord, lat_text, verse_text=True):
    lat_by_grc = collections.defaultdict(list)
    for rec in lat_ord:
        if rec["align"]:
            lat_by_grc[rec["align"]].append(rec)
    rows = []
    for g in grc_ord:
        if not is_verb(g):
            continue
        aligned = lat_by_grc.get(g["id"], [])
        lat_verbs = [x for x in aligned if is_verb(x)]
        primary = lat_verbs[0] if lat_verbs else (aligned[0] if aligned else None)
        row = {"row_type": "greek_verb", "book_code": g["book"],
               "chapter": g["chapter"], "verse": g["verse"]}
        row.update(token_cols("grc", g, grc_tok))
        row.update(token_cols("lat", primary, lat_tok))
        row["lat_n_aligned"] = len(aligned)
        row["lat_aligned_all"] = "|".join(f"{x['form']}/{x['pos']}/{x['morph']}" for x in aligned)
        rows.append(row)
    for l in lat_ord:
        if not is_verb(l):
            continue
        g = grc_tok.get(l["align"]) if l["align"] else None
        if is_verb(g):
            continue
        row = {"row_type": "latin_only", "book_code": l["book"],
               "chapter": l["chapter"], "verse": l["verse"]}
        row.update(token_cols("grc", g, grc_tok))
        row.update(token_cols("lat", l, lat_tok))
        row["lat_n_aligned"] = ""
        row["lat_aligned_all"] = ""
        rows.append(row)
    rank = {b: i for i, b in enumerate(GOSPELS)}
    rows.sort(key=lambda r: (rank.get(r["book_code"], 99), r["chapter"], r["verse"],
                             r["row_type"] != "greek_verb",
                             int(r["grc_token_id"] or r["lat_token_id"])))
    out = []
    for i, r in enumerate(rows, 1):
        key = (r["book_code"], r["chapter"], r["verse"])
        o = {"row_id": i, "row_type": r.pop("row_type"),
             "book": BOOK_NAMES[r["book_code"]], **r}
        if verse_text:
            o["grc_verse_text"] = grc_text.get(key, "")
            o["lat_verse_text"] = lat_text.get(key, "")
        out.append(o)
    return out


# ---------------------------------------------------------------------------
# Old Hungarian (Jordánszky)
# ---------------------------------------------------------------------------
HU_VERB_RE = re.compile(r"(^|\.)V(\.|$)")
HU_PERSON_RE = re.compile(r"^([SP])([123])")
AUX_FORM_RE = re.compile(r"^(vala|volt|volna)(-e)?$")


def hu_feats(tag):
    return tag.split(".") if tag and tag != "NA" else []


def hu_is_verb(tag):
    return bool(tag) and bool(HU_VERB_RE.search(tag))


def hu_person(tag):
    for f in hu_feats(tag):
        m = HU_PERSON_RE.match(f)
        if m:
            return m.group(2), ("sg" if m.group(1) == "S" else "pl")
    return "", ""


def hu_tense(tag):
    """Coarse tense/mood of a single Hungarian verb tag."""
    f = set(x.split("=")[0] for x in hu_feats(tag))
    if "Inf" in f:
        return "infinitive"
    if "PartAdv" in f:
        return "gerund_van"
    for p in ("PartPrf", "PartPrs", "PartFut"):
        if p in f:
            return "participle_" + p[4:].lower()
    if "Cond" in f:
        return "conditional"
    if "Subj" in f:
        return "subjunctive"
    if "Fut" in f:
        return "future"
    if "Past" in f:
        return "past"
    if "Ipf" in f:
        return "ipf"
    if f & {"_Nact"}:
        return "other"
    return "present"


def hu_finite(t):
    return t in {"present", "past", "ipf", "future", "conditional", "subjunctive"}


def is_aux(tok):
    if tok["lemma"] != "van" or not AUX_FORM_RE.match(tok["norm"].lower()):
        return False
    f = set(hu_feats(tok["tag"]))
    if not f & {"Ipf", "Past", "Cond"}:
        return False
    return hu_person(tok["tag"]) == ("", "")


def load_jordanszky(path, books):
    verses = collections.OrderedDict()
    with open(path, encoding="utf-8") as fh:
        rd = csv.reader(fh, delimiter="\t")
        header = next(rd)
        if header[:2] != ["X1", "X2"]:
            sys.exit("unexpected Jordánszky header: " + "\t".join(header))
        for r in rd:
            if len(r) < 10:
                continue
            bk, _, ch = r[1].partition("_")
            book = HU_BOOKS.get(bk)
            if book not in books or not ch.isdigit() or not r[2].isdigit():
                continue      # prologues, chapter headings
            key = (book, int(ch), int(r[2]))
            verses.setdefault(key, []).append({
                "page": r[0], "orig": r[3], "norm": r[4], "x6": r[5], "x7": r[6],
                "lemma": r[8], "tag": r[9], "label": f"{bk}_{ch} {r[2]}",
            })
    # Repair: in the extract, the split-off end of a chapter's last verse is
    # labelled with the NEXT chapter and the old verse number (e.g. Jn_2 51
    # between Jn_1 51 and Jn_2 1). Fold it back into the previous verse.
    keys = list(verses)
    for i in range(1, len(keys) - 1):
        a, b, c = keys[i - 1], keys[i], keys[i + 1]
        if (b[0] == a[0] and b[1] == a[1] + 1 and b[2] == a[2]
                and c[0] == b[0] and c[1] == b[1] and c[2] == 1):
            verses[a].extend(verses.pop(b))
    return verses


def hu_units(toks):
    """Group a verse's tokens into verb units (verb + attached auxiliary)."""
    for i, t in enumerate(toks):
        t["pos_in_verse"] = i + 1
    verbs = [i for i, t in enumerate(toks) if hu_is_verb(t["tag"])]
    aux_idx = {i for i in verbs if is_aux(toks[i])}
    host_of = {}
    for a in sorted(aux_idx):
        host = None
        for j in range(a - 1, max(-1, a - 4), -1):
            if j in aux_idx or j in host_of.values():
                continue
            if hu_is_verb(toks[j]["tag"]):
                host = j
                break
        if host is None:
            for j in range(a + 1, min(len(toks), a + 3)):
                if j not in aux_idx and hu_is_verb(toks[j]["tag"]) and j not in host_of.values():
                    host = j
                    break
        if host is not None:
            host_of[a] = host
    aux_by_host = {h: a for a, h in host_of.items()}
    units = []
    for i in verbs:
        if i in host_of:
            continue
        t = toks[i]
        a = aux_by_host.get(i)
        base = hu_tense(t["tag"])
        unit = {"tok": t, "aux": toks[a] if a is not None else None,
                "aux_distance": (a - i) if a is not None else "",
                "aux_rule": "", "base": base}
        if a is not None:
            aux_t = hu_tense(toks[a]["tag"])
            unit["aux_rule"] = "aux_tag_attached"
            if aux_t == "conditional":
                cat = "conditional_past" if base == "past" else "other_plus_aux"
            elif base in ("past", "ipf"):
                cat = "complex_perfective"
            elif base == "present":
                cat = "complex_imperfective"
            else:
                cat = "other_plus_aux"
        else:
            if i in aux_idx:
                unit["aux_rule"] = "aux_tag_no_host"
            cat = {"past": "perfective", "ipf": "imperfective"}.get(base, base)
        unit["category"] = cat
        units.append(unit)
    return units


def hu_unit_cols(u, verse_n):
    t, a = u["tok"], u["aux"]
    pers, num = hu_person(t["tag"])
    f = set(hu_feats(t["tag"]))
    return {
        "hu_pos_in_verse": t["pos_in_verse"], "hu_page": t["page"],
        "hu_form_orig": t["orig"], "hu_form_norm": t["norm"], "hu_lemma": t["lemma"],
        "hu_tag": t["tag"], "hu_x6": t["x6"], "hu_x7": t["x7"],
        "hu_preverb_attached": str("VPfx" in f).upper(),
        "hu_person": pers, "hu_number": num, "hu_definite": str("Def" in f).upper(),
        "hu_base_tense": u["base"],
        "hu_aux_form_orig": a["orig"] if a else "", "hu_aux_form_norm": a["norm"] if a else "",
        "hu_aux_tag": a["tag"] if a else "", "hu_aux_distance": u["aux_distance"],
        "hu_aux_rule": u["aux_rule"], "hu_tense_category": u["category"],
        "hu_finite": str(hu_finite(u["base"])).upper(),
    }


# ---------------------------------------------------------------------------
# Latin/Greek units per verse
# ---------------------------------------------------------------------------
def build_source_units(grc_tok, grc_ord, lat_tok, lat_ord):
    """Per Latin verse key: ordered list of source units (Latin verbs with aux
    folded in and PROIEL-aligned Greek; Greek-only verbs interleaved)."""
    lat_by_grc = collections.defaultdict(list)
    for rec in lat_ord:
        if rec["align"]:
            lat_by_grc[rec["align"]].append(rec)
    aux_of = {}
    for l in lat_ord:
        if is_verb(l) and l["lemma"] == "sum" and l["relation"] == "aux":
            h = lat_tok.get(l["head_id"])
            if is_verb(h) and h["id"] not in aux_of:
                aux_of[h["id"]] = l
    folded = {a["id"] for a in aux_of.values()}

    units = collections.defaultdict(list)
    for l in lat_ord:
        if not is_verb(l) or l["id"] in folded:
            continue
        g = grc_tok.get(l["align"]) if l["align"] else None
        units[(l["book"], l["chapter"], l["verse"])].append(
            {"kind": "lat", "lat": l, "aux": aux_of.get(l["id"]), "grc": g, "sort": l["order"]})

    # Greek verbs with no Latin token aligned at all. Each is anchored to the
    # Latin token aligned to the nearest preceding Greek token in the same
    # Greek verse (else the nearest following one), and filed under THAT
    # Latin token's verse, since Greek and Latin verse numbering differ in
    # places (e.g. Mark 9).
    by_gverse = collections.OrderedDict()
    for g in grc_ord:
        by_gverse.setdefault((g["book"], g["chapter"], g["verse"]), []).append(g)
    for gkey, gtoks in by_gverse.items():
        anchors = [max(lat_by_grc[g["id"]], key=lambda x: x["order"])
                   if g["id"] in lat_by_grc else None for g in gtoks]
        k = 0
        for i, g in enumerate(gtoks):
            if not is_verb(g) or anchors[i] is not None:
                continue
            prev = next((anchors[j] for j in range(i - 1, -1, -1) if anchors[j]), None)
            nxt = next((anchors[j] for j in range(i + 1, len(gtoks)) if anchors[j]), None)
            k += 1
            if prev is not None:
                a, sort = prev, prev["order"] + 0.5 + k * 1e-3
            elif nxt is not None:
                a, sort = nxt, nxt["order"] - 0.5 + k * 1e-3
            else:
                a, sort = None, -1 + k * 1e-3
            key = (a["book"], a["chapter"], a["verse"]) if a else gkey
            units[key].append({"kind": "grc", "lat": None, "aux": None, "grc": g, "sort": sort})
    for key in units:
        units[key].sort(key=lambda u: u["sort"])
    return units


# ---------------------------------------------------------------------------
# Alignment
# ---------------------------------------------------------------------------
PERF_PASSIVE = {"present": "perfect", "imperfect": "pluperfect", "future": "future_perfect",
                "perfect": "perfect", "pluperfect": "pluperfect",
                "future_perfect": "future_perfect"}


def lat_analytic(l, aux):
    """Tense and mood of a Latin verb unit, combining participle + sum:
    perfect participle + es/erat/erit -> perfect/pluperfect/future perfect;
    future participle + sum -> periphrastic_future."""
    d = decode_morph(l["morph"])
    if aux is None:
        return d["tense"], d["mood"]
    a = decode_morph(aux["morph"])
    if d["mood"] == "participle" and d["tense"] == "perfect":
        return PERF_PASSIVE.get(a["tense"], f"perfect+{a['tense']}"), a["mood"]
    if d["mood"] == "participle" and d["tense"] == "future":
        return "periphrastic_future", a["mood"]
    return f"{d['tense']}+{a['tense']}", a["mood"]


def morph_score(hu, src):
    l = src["lat"]
    d = decode_morph(l["morph"])
    if src["aux"] is not None:          # participle + sum counts as finite
        a = decode_morph(src["aux"]["morph"])
        d = dict(d, mood=a["mood"], person=a["person"], number=a["number"])
    lm = d["mood"]
    hb = hu["base"]
    if lm in FINITE_MOODS:
        if hu_finite(hb):
            s = 1.0
            hp, hn = hu_person(hu["tok"]["tag"])
            if hp and d["person"] and hp == d["person"] and hn == d["number"]:
                s += 0.5
            return s
        return 0.3 if hb == "gerund_van" else 0.1
    if lm == "participle":
        if hb == "gerund_van":
            return 1.0
        if hb.startswith("participle"):
            return 0.9
        return 0.5 if hu_finite(hb) else 0.2
    if lm == "infinitive":
        return 1.0 if hb == "infinitive" else (0.3 if hu_finite(hb) else 0.1)
    return 0.3


def align_verse(hu_list, src_list, lex):
    """Monotone DP. Returns list of (hu_index|None, src_index|None, score parts)."""
    cand = [i for i, s in enumerate(src_list) if s["kind"] == "lat"]
    n, m = len(hu_list), len(cand)
    pair = {}
    for i, h in enumerate(hu_list):
        for jj, j in enumerate(cand):
            s = src_list[j]
            lx = lex(h["tok"]["lemma"], s["lat"]["lemma"])
            mo = morph_score(h, s)
            po = 1 - abs((i + 0.5) / max(n, 1) - (jj + 0.5) / max(m, 1))
            pair[i, jj] = (2 * lx + mo + po - 1.5, lx, mo, po)
    best = [[0.0] * (m + 1) for _ in range(n + 1)]
    back = [[None] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        for jj in range(m + 1):
            if i == 0 and jj == 0:
                continue
            opts = []
            if i > 0:
                opts.append((best[i - 1][jj], "h"))
            if jj > 0:
                opts.append((best[i][jj - 1], "s"))
            if i > 0 and jj > 0 and pair[i - 1, jj - 1][0] > 0:
                opts.append((best[i - 1][jj - 1] + pair[i - 1, jj - 1][0], "m"))
            best[i][jj], back[i][jj] = max(opts, key=lambda x: x[0])
    path, i, jj = [], n, m
    while i or jj:
        op = back[i][jj]
        if op == "m":
            path.append((i - 1, cand[jj - 1], pair[i - 1, jj - 1]))
            i, jj = i - 1, jj - 1
        elif op == "h":
            path.append((i - 1, None, None))
            i -= 1
        else:
            path.append((None, cand[jj - 1], None))
            jj -= 1
    path.reverse()
    # interleave Greek-only units at their source positions
    matched_src = {p[1] for p in path if p[1] is not None}
    out, src_cursor = [], 0
    for h, s, sc in path:
        if s is not None:
            while src_cursor < s:
                if src_list[src_cursor]["kind"] == "grc":
                    out.append((None, src_cursor, None))
                src_cursor += 1
            src_cursor = s + 1
        out.append((h, s, sc))
    while src_cursor < len(src_list):
        if src_list[src_cursor]["kind"] == "grc":
            out.append((None, src_cursor, None))
        src_cursor += 1
    return out


def make_lexicon(pairs_counter, hu_count, smoothing=0.5):
    def lex(h, l):
        c = pairs_counter.get((h, l), 0)
        n = hu_count.get(h, 0)
        return c / (n + smoothing) if n else 0.0
    return lex


def dice_lexicon(hu_units_by_verse, src_by_verse):
    hu_df, lat_df, co = collections.Counter(), collections.Counter(), collections.Counter()
    for key, hl in hu_units_by_verse.items():
        hs = {u["tok"]["lemma"] for u in hl}
        ls = {s["lat"]["lemma"] for s in src_by_verse.get(key, []) if s["kind"] == "lat"}
        hu_df.update(hs)
        lat_df.update(ls)
        for h in hs:
            for l in ls:
                co[h, l] += 1
    def lex(h, l):
        c = co.get((h, l), 0)
        return 2 * c / (hu_df[h] + lat_df[l]) if c else 0.0
    return lex


def confidence(sc):
    if sc is None:
        return ""
    total, lx, mo, po = sc
    if lx >= 0.3 and mo >= 1.0:
        return "high"
    if total >= 0.5:
        return "medium"
    return "low"


# ---------------------------------------------------------------------------
# Verse alignment (PROIEL Latin numbering vs Hungarian/modern numbering)
# ---------------------------------------------------------------------------
def verse_similarity(hu_units_list, src_units_list, hu_len, src_len, lex, ratio):
    """Gale-Church-style length term plus verb-lemma overlap."""
    lat = [s["lat"]["lemma"] for s in src_units_list if s["kind"] == "lat"]
    hu = [u["tok"]["lemma"] for u in hu_units_list]
    if hu and lat:
        lexs = sum(max(lex(h, l) for l in lat) for h in hu) / max(len(hu), len(lat))
    else:
        lexs = 0.0
    lens = -abs(math.log((hu_len + 1) / (ratio * src_len + 1)))
    return 2 * lexs + lens


SAME_NUMBER_BONUS = 0.8
BAND = 12   # max verse offset considered within a book


def align_chapter_verses(hu_keys, src_keys, hu, src, hu_len, src_len, lex, ratio):
    """Banded DP over a book's verses with 1-1, 2-1, 1-2, 1-0, 0-1 moves.
    Returns a list of (hu_key_list, src_key_list) groups in order."""
    n, m = len(hu_keys), len(src_keys)
    NEG = -1e9
    best = [[NEG] * (m + 1) for _ in range(n + 1)]
    back = [[None] * (m + 1) for _ in range(n + 1)]
    best[0][0] = 0.0

    def sim(hi, si):
        hk, sk = hu_keys[hi[0]:hi[1]], src_keys[si[0]:si[1]]
        hl = [u for k in hk for u in hu.get(k, [])]
        sl = [u for k in sk for u in src.get(k, [])]
        return verse_similarity(hl, sl, sum(hu_len.get(k, 0) for k in hk),
                                sum(src_len.get(k, 0) for k in sk), lex, ratio)

    moves = [(1, 1, 0.0), (2, 1, -0.6), (1, 2, -0.6), (1, 0, -2.5), (0, 1, -2.5)]
    band = BAND + abs(n - m)
    for i in range(n + 1):
        for j in range(max(0, i - band), min(m, i + band) + 1):
            if best[i][j] == NEG:
                continue
            for di, dj, pen in moves:
                ni, nj = i + di, j + dj
                if ni > n or nj > m:
                    continue
                s = pen if (di == 0 or dj == 0) else sim((i, ni), (j, nj)) + pen
                # prior: verse numbering usually agrees; a shift needs evidence
                if di and dj and hu_keys[i][1:] == src_keys[j][1:]:
                    s += SAME_NUMBER_BONUS if (di, dj) == (1, 1) else SAME_NUMBER_BONUS / 2
                if best[i][j] + s > best[ni][nj]:
                    best[ni][nj] = best[i][j] + s
                    back[ni][nj] = (i, j)
    groups, i, j = [], n, m
    while i or j:
        pi, pj = back[i][j]
        groups.append((hu_keys[pi:i], src_keys[pj:j]))
        i, j = pi, pj
    groups.reverse()
    return groups


def verse_groups(hu, src, hu_len, src_len, lex):
    """Align verses book by book (shifts can cross chapter boundaries, e.g.
    Vulgate Mark 8:39 = modern 9:1). Keys come from hu_len/src_len, which
    include verses without verbs, so that length can anchor the alignment."""
    rank = {b: i for i, b in enumerate(GOSPELS)}
    shared = [k for k in hu_len if k in src_len]
    tot_h = sum(hu_len[k] for k in shared)
    tot_s = sum(src_len[k] for k in shared)
    ratio = tot_h / tot_s if tot_s else 1.0
    groups = []
    for book in sorted({k[0] for k in hu_len} | {k[0] for k in src_len}, key=rank.get):
        hk = sorted(k for k in hu_len if k[0] == book)
        sk = sorted(k for k in src_len if k[0] == book)
        groups.extend(align_chapter_verses(hk, sk, hu, src, hu_len, src_len, lex, ratio))
    return groups


# ---------------------------------------------------------------------------
# Discourse mode from the CPDV (Catholic Public Domain Version)
# ---------------------------------------------------------------------------
CPDV_BOOKS = {"Matthew": "MATT", "Mark": "MARK", "Luke": "LUKE", "John": "JOHN"}
# Typographical slips in the CPDV quotation marks (found by a nesting check),
# patched as (old, new) substring replacements within the verse.
CPDV_PATCHES = {
    ("MARK", 5, 41): ("(I say to you) arise.", "(I say to you) arise.”"),
    ("MARK", 10, 19): ("“Do not commit adultery", "‘Do not commit adultery"),
    ("MARK", 10, 19, "b"): ("Honor your father and mother.”", "Honor your father and mother.’”"),
    ("MARK", 12, 32): ("said to him: Well said", "said to him: “Well said"),
    ("LUKE", 7, 27): ("written: “Behold", "written: ‘Behold"),
    ("LUKE", 7, 27, "b"): ("way before you.”", "way before you.’"),
}


def load_cpdv(path, books):
    """Return {(book, ch, vs): (text, depth_per_char)} for the Gospels.
    Depth is the quotation nesting level (0 narration, 1 speech, 2 speech
    within speech, ...). Quotes run across verses; the stack is reset at
    chapter boundaries (no well-formed quote in the CPDV Gospels crosses one)."""
    verses = collections.OrderedDict()
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"^(Matthew|Mark|Luke|John) (\d+):(\d+)\t(.*)$", line.rstrip("\n"))
            if not m:
                continue
            key = (CPDV_BOOKS[m.group(1)], int(m.group(2)), int(m.group(3)))
            if key[0] not in books:
                continue
            text = m.group(4)
            for pk, (old, new) in CPDV_PATCHES.items():
                if pk[:3] == key and old in text:
                    text = text.replace(old, new, 1)
            verses[key] = text
    out, stack, prev_ch = {}, [], None
    for key, text in verses.items():
        if key[:2] != prev_ch:
            stack, prev_ch = [], key[:2]
        depth = []
        for i, c in enumerate(text):
            depth.append(len(stack))
            if c == "“":
                stack.append("D")
            elif c == "‘":
                stack.append("S")
            elif c == "”" and stack and stack[-1] == "D":
                stack.pop()
            elif c == "’":
                p = text[i - 1] if i else " "
                n = text[i + 1] if i + 1 < len(text) else " "
                if not (p.isalpha() and n.isalpha()) and stack and stack[-1] == "S":
                    stack.pop()
        out[key] = (text, depth, len(stack))
    return out


def cpdv_boundaries(text, depth):
    """Depth at verse start and list of (relative position, new depth, kind)."""
    L = max(len(text), 1)
    start = depth[0] if depth else 0
    bounds, cur = [], start
    for i in range(1, len(depth)):
        if depth[i] != cur:
            bounds.append((i / L, depth[i], "open" if depth[i] > cur else "close"))
            cur = depth[i]
    end_depth = cur
    return start, bounds, end_depth


def hu_token_relpos(toks):
    """Relative character position (midpoint) of each token in the verse."""
    forms = [t["norm"] if t["norm"] != "NA" else "" for t in toks]
    total = sum(len(f) + 1 for f in forms) or 1
    pos, out = 0, []
    for f in forms:
        out.append((pos + len(f) / 2) / total)
        pos += len(f) + 1
    return out


EDGE = 0.04   # share of the verse treated as its edge for quote projection


def hu_depths(toks, cpdv_entry):
    """Project CPDV quote boundaries onto Hungarian tokens. Opening quotes are
    snapped to the nearest Hungarian colon, closing quotes to the nearest
    sentence-final punctuation, within 0.25 of the verse; otherwise placed
    proportionally. Returns per-token (depth, snap kinds, min boundary dist)."""
    rel = hu_token_relpos(toks)
    if cpdv_entry is None:
        return [("", "no_cpdv_verse", "")] * len(toks), False, ""
    text, depth, _ = cpdv_entry
    start, bounds, _ = cpdv_boundaries(text, depth)
    colons = [i for i, t in enumerate(toks) if t["norm"] == ":"]
    finals = [i for i, t in enumerate(toks) if t["norm"] in (".", "?", "!", ";")]
    snapped = []           # (token index where new depth starts, new depth, how)
    for q, d, kind in bounds:
        # quotes at the very start/end of the English verse stay at the edge
        if q <= EDGE:
            snapped.append((0, d, "verse_edge"))
            continue
        if q >= 1 - EDGE:
            snapped.append((len(toks), d, "verse_edge"))
            continue
        pool = colons if kind == "open" else finals
        cand = [(abs(rel[i] - q), i) for i in pool]
        cand = [c for c in cand if c[0] <= 0.25]
        if cand:
            idx = min(cand)[1] + 1
            how = "colon" if kind == "open" else "punct"
        else:
            idx = next((i for i, r in enumerate(rel) if r >= q), len(toks))
            how = "proportional"
        snapped.append((idx, d, how))
    # keep boundary order monotone
    for k in range(1, len(snapped)):
        if snapped[k][0] < snapped[k - 1][0]:
            snapped[k] = (snapped[k - 1][0], snapped[k][1], snapped[k][2])
    out = []
    for i in range(len(toks)):
        d, how = start, "inherited" if start else "none"
        for idx, nd, h in snapped:
            if idx <= i:
                d, how = nd, h
        dist = min((abs(i - idx) for idx, _, _ in snapped), default="")
        out.append((d, how, dist))
    return out, bool(bounds), start


def discourse_label(d):
    if d == "":
        return ""
    return {0: "narration", 1: "speech"}.get(d, "embedded_speech")


# ---------------------------------------------------------------------------
# Merge
# ---------------------------------------------------------------------------
EMPTY_HU = {"tok": {"pos_in_verse": "", "page": "", "orig": "", "norm": "", "x6": "",
                    "x7": "", "lemma": "", "tag": "", "label": ""},
            "aux": None, "aux_distance": "", "aux_rule": "", "base": "", "category": ""}


def merge_hungarian(grc_tok, grc_ord, grc_text, lat_tok, lat_ord, lat_text,
                    hu_verses, cpdv=None, verse_text=True):
    src = build_source_units(grc_tok, grc_ord, lat_tok, lat_ord)
    hu = {k: hu_units(v) for k, v in hu_verses.items()}
    hu_len = {k: sum(1 for t in v if t["norm"][:1].isalpha()) for k, v in hu_verses.items()}
    lat_len, grc_len = collections.Counter(), collections.Counter()
    for t in lat_ord:
        lat_len[(t["book"], t["chapter"], t["verse"])] += 1
    for t in grc_ord:
        grc_len[(t["book"], t["chapter"], t["verse"])] += 1
    # all Latin verses (with or without verbs), plus verses that only exist
    # as a key for Greek-only units, measured by their Greek length
    src_len = dict(lat_len)
    for k in src:
        src_len.setdefault(k, grc_len.get(k, 0))

    # lexicon: Dice on same-numbered verses, then re-estimated twice from
    # verb alignments within verse groups
    lex = dice_lexicon(hu, src)
    groups = verse_groups(hu, src, hu_len, src_len, lex)
    for _ in range(2):
        pc, hc = collections.Counter(), collections.Counter()
        for hk, sk in groups:
            hl = [u for k in hk for u in hu.get(k, [])]
            sl = [u for k in sk for u in src.get(k, [])]
            for h, s, sc in align_verse(hl, sl, lex):
                if h is not None:
                    hc[hl[h]["tok"]["lemma"]] += 1
                    if s is not None:
                        pc[hl[h]["tok"]["lemma"], sl[s]["lat"]["lemma"]] += 1
        lex = make_lexicon(pc, hc)
        groups = verse_groups(hu, src, hu_len, src_len, lex)

    # discourse depth per Hungarian token
    hu_disc = {}
    for k, toks in hu_verses.items():
        hu_disc[k] = hu_depths(toks, cpdv.get(k)) if cpdv else None

    rows = []
    for gi, (hk, sk) in enumerate(groups, 1):
        hl, hl_keys = [], []
        for k in hk:
            for u in hu.get(k, []):
                hl.append(u)
                hl_keys.append(k)
        sl = [u for k in sk for u in src.get(k, [])]
        n_lat = sum(s["kind"] == "lat" for s in sl)
        hu_text = " | ".join(" ".join(t["norm"] for t in hu_verses[k] if t["norm"] != "NA")
                             for k in hk)
        group_label = (",".join(f"{k[1]}.{k[2]}" for k in hk) + " ~ " +
                       ",".join(f"{k[1]}.{k[2]}" for k in sk))
        last_key, last_disc = (hk[0] if hk else (sk[0] if sk else None)), None
        pending = []      # source-only rows waiting for a discourse value
        for h, s, sc in align_verse(hl, sl, lex):
            hu_u = hl[h] if h is not None else None
            su = sl[s] if s is not None else None
            if hu_u:
                key = hl_keys[h]
            elif hk:
                key = last_key
            else:
                r_ = su["lat"] or su["grc"]
                key = (r_["book"], r_["chapter"], r_["verse"])
            if hu_u and su:
                rtype = "hu_lat"
            elif hu_u:
                rtype = "hu_only"
            else:
                rtype = "lat_only" if su["kind"] == "lat" else "grc_only"
            row = {"row_type": rtype, "book": BOOK_NAMES[key[0]], "book_code": key[0],
                   "chapter": key[1], "verse": key[2], "verse_group": gi,
                   "verse_group_map": group_label}
            row.update(hu_unit_cols(hu_u or EMPTY_HU, 0))
            row["hu_source_label"] = hu_u["tok"]["label"] if hu_u else ""
            # discourse
            disc = None
            if hu_u and cpdv:
                per_tok, mixed, start = hu_disc[key]
                d, how, dist = per_tok[hu_u["tok"]["pos_in_verse"] - 1]
                disc = (d, how, dist, mixed)
                for pr in pending:
                    pr.update(disc_cols(disc, "from_next_hu_verb"))
                pending = []
                last_disc = disc
            row.update({
                "align_score": f"{sc[0]:.3f}" if sc else "",
                "align_lex": f"{sc[1]:.3f}" if sc else "",
                "align_morph": f"{sc[2]:.2f}" if sc else "",
                "align_pos": f"{sc[3]:.3f}" if sc else "",
                "align_conf": confidence(sc),
                "verse_n_hu": len(hl), "verse_n_lat": n_lat,
                "verse_counts_equal": str(len(hl) == n_lat).upper(),
            })
            row.update(token_cols("lat", su["lat"] if su else None, lat_tok))
            a = su["aux"] if su else None
            row["lat_aux_form"] = a["form"] if a else ""
            row["lat_aux_morph_raw"] = a["morph"] if a else ""
            row["lat_aux_tense"] = decode_morph(a["morph"])["tense"] if a else ""
            row["lat_tense_analytic"], row["lat_mood_analytic"] = (
                lat_analytic(su["lat"], a) if su and su["lat"] else ("", ""))
            row.update(token_cols("grc", su["grc"] if su else None, grc_tok))
            if cpdv:
                if disc is not None:
                    row.update(disc_cols(disc, "hu_token"))
                elif last_disc is not None:
                    row.update(disc_cols(last_disc, "from_prev_hu_verb"))
                elif hk:
                    pending.append(row)
                else:     # no Hungarian in this group: CPDV verse depth at relative Latin position
                    row.update(disc_cols(source_only_disc(su, key, cpdv, lat_text, grc_text),
                                         "cpdv_by_source_position"))
            if verse_text:
                row["hu_verse_text"] = hu_text
                row["lat_verse_text"] = " | ".join(lat_text.get(k, "") for k in sk if k in lat_text)
                row["grc_verse_text"] = " | ".join(grc_text.get(k, "") for k in sk if k in grc_text)
                if cpdv:
                    row["cpdv_verse_text"] = " | ".join(cpdv[k][0] for k in (hk or [key]) if k in cpdv)
            rows.append(row)
            if hu_u:
                last_key = key
        for pr in pending:
            pr.update(disc_cols(("", "none", "", False), "unresolved"))
    for i, r in enumerate(rows, 1):
        r["row_id"] = i
    return [{"row_id": r.pop("row_id"), **r} for r in rows]


def disc_cols(disc, source):
    d, how, dist, mixed = disc
    return {"discourse_depth": d, "discourse_mode": discourse_label(d),
            "discourse_boundary": how, "discourse_boundary_dist_tokens": dist,
            "cpdv_verse_mixed": str(bool(mixed)).upper(), "discourse_source": source}


def source_only_disc(su, key, cpdv, lat_text, grc_text):
    entry = cpdv.get(key)
    if entry is None:
        return ("", "no_cpdv_verse", "", False)
    text, depth, _ = entry
    tok = su["lat"] or su["grc"]
    vt = (lat_text if su["lat"] else grc_text).get((tok["book"], tok["chapter"], tok["verse"]), "")
    q = vt.find(tok["form"]) / max(len(vt), 1) if vt else 0.5
    i = min(int(max(q, 0) * len(text)), len(text) - 1) if text else 0
    start, bounds, _ = cpdv_boundaries(text, depth)
    return (depth[i] if depth else "", "proportional", "", bool(bounds))


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--books", nargs="+", default=GOSPELS,
                    help="PROIEL book codes (default: MATT MARK LUKE JOHN)")
    ap.add_argument("--data-dir", default="proiel_data", help="cache for PROIEL XML")
    ap.add_argument("--jordanszky", help="local TSV extract of the Jordánszky Gospels "
                                         f"(source: {JORDANSZKY_SOURCE})")
    ap.add_argument("--cpdv", help="Catholic Public Domain Version, one verse per line "
                                   "('Mark 1:7<TAB>text'), for discourse mode")
    ap.add_argument("-o", "--output", default=None)
    ap.add_argument("--no-verse-text", action="store_true")
    args = ap.parse_args()
    books = set(args.books)

    os.makedirs(args.data_dir, exist_ok=True)
    paths = {}
    for lang, url in URLS.items():
        paths[lang] = os.path.join(args.data_dir, os.path.basename(url))
        download(url, paths[lang])
    print("parsing Greek ...", file=sys.stderr)
    grc = load_proiel(paths["greek"], books)
    print("parsing Latin ...", file=sys.stderr)
    lat = load_proiel(paths["latin"], books)

    if args.jordanszky:
        hu_verses = load_jordanszky(args.jordanszky, books)
        print(f"Jordánszky: {len(hu_verses)} verses", file=sys.stderr)
        cpdv = load_cpdv(args.cpdv, books) if args.cpdv else None
        rows = merge_hungarian(*grc, *lat, hu_verses, cpdv, not args.no_verse_text)
        out = args.output or "gospels_verbs_grc_lat_hu.tsv"
    else:
        rows = proiel_only(*grc, *lat, not args.no_verse_text)
        out = args.output or "gospels_verbs_grc_lat.tsv"
    write_tsv(rows, out)
    c = collections.Counter(r["row_type"] for r in rows)
    print(f"wrote {len(rows)} rows to {out}: {dict(c)}", file=sys.stderr)


if __name__ == "__main__":
    main()
