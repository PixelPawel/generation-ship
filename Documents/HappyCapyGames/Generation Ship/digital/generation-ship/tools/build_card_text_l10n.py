"""Compile translated card names/effects into data/Card Text Translations.csv.

Source: data/translations/<sheet>.<LANG>.csv (folder is .gdignore'd, so the
game can't read it directly). Output rows: key,de,it,pl,es,fr with keys
  tech:<No.>:name / :effect        (Techs sheet)
  promo:<No.>:name / :effect       (Promos sheet)
  expedition:<No.>:name / :effect  (Expeditions sheet)
  adv:<No.>:name / :effect         (Advanced Sectors sheet)
  dust:<English name>:name / :effect  (Dust Sectors; game keys dust by name)
Rerun after the translation sheets change.
"""
import csv, io, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DATA = os.path.join(ROOT, "data")
TR = os.path.join(DATA, "translations")
LANGS = ["de", "it", "pl", "es", "fr"]
PREFIX = "Generation Ship Full Card Details - "
SHEETS = {"tech": "Techs", "promo": "Promos", "expedition": "Expeditions",
          "adv": "Advanced Sectors", "dust": "Dust Sectors"}

def read(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    return [{k.strip().lstrip("﻿"): (v or "") for k, v in r.items() if k} for r in rows]

def no(r):
    v = r.get("No.", "").strip()
    return v if v.isdigit() else None

# English dust sector names by No., so dust rows can be keyed by name.
dust_en = {no(r): r["Name"].strip() for r in read(os.path.join(DATA, PREFIX + "Dust Sectors.csv")) if no(r)}

table = {}   # key -> {lang: text}
missing = []
for kind, sheet in SHEETS.items():
    for lang in LANGS:
        path = os.path.join(TR, f"{PREFIX}{sheet}.{lang.upper()}.csv")
        if not os.path.exists(path):
            missing.append(path); continue
        for r in read(path):
            n = no(r)
            if n is None:
                continue
            ident = dust_en.get(n) if kind == "dust" else n
            if not ident:
                continue
            for field, col in (("name", "Name"), ("effect", "Effect")):
                text = r.get(col, "").strip()
                if text:
                    table.setdefault(f"{kind}:{ident}:{field}", {})[lang] = text

out = os.path.join(DATA, "Card Text Translations.csv")
with open(out, "w", encoding="utf-8", newline="") as f:
    w = csv.writer(f, quoting=csv.QUOTE_ALL, lineterminator="\n")
    w.writerow(["key"] + LANGS)
    for key in sorted(table):
        w.writerow([key] + [table[key].get(l, "") for l in LANGS])
print(f"{len(table)} keys -> {out}")
for m in missing:
    print("missing sheet:", m)
