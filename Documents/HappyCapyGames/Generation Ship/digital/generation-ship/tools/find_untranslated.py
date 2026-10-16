"""Lists UI texts the game passes to tr() that have no row in data/UI Strings.csv
(they show in English in every language). Also finds keys whose row has an
empty language column.

    python tools/find_untranslated.py            # print the missing keys
    python tools/find_untranslated.py --json f   # also write them to f (JSON list)

Only literal strings are found: tr("...") / main.tr("...") / tr('...'), and the
literal keys of _tr_targets / Label texts set via tr() later. Texts built at
runtime (tr(some_var)) need their keys added by hand.
"""
import csv
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CSV_PATH = os.path.join(ROOT, "data", "UI Strings.csv")
SKIP_DIRS = {"addons", ".godot", "android", "androidarm64", "Build", "linux32", "linux64", "linuxarm64",
             "osx", "win64", "redistributable_bin", "SteamBuildOutput", "tools"}
TR_RE = re.compile(r'\btr\(\s*"((?:[^"\\]|\\.)*)"\s*[,)]')


def unescape(s: str) -> str:
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def main() -> None:
    with open(CSV_PATH, encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))
    header = rows[0]
    keys = {r[0]: r for r in rows[1:] if r}
    found = {}
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for fn in filenames:
            if not fn.endswith(".gd"):
                continue
            path = os.path.join(dirpath, fn)
            text = open(path, encoding="utf-8").read()
            for m in TR_RE.finditer(text):
                key = unescape(m.group(1))
                line = text.count("\n", 0, m.start()) + 1
                found.setdefault(key, []).append("%s:%d" % (os.path.relpath(path, ROOT).replace("\\", "/"), line))
    missing = sorted(k for k in found if k not in keys)
    partial = sorted(k for k in found if k in keys and any(not c.strip() for c in keys[k][1:len(header)]))
    print("%d tr() texts, %d missing from UI Strings.csv, %d with empty columns" % (len(found), len(missing), len(partial)))
    for k in missing:
        print("MISSING  %r  (%s)" % (k, found[k][0]))
    for k in partial:
        print("PARTIAL  %r" % k)
    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        json.dump({"missing": missing, "partial": partial, "where": {k: found[k] for k in missing + partial}},
                  open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
