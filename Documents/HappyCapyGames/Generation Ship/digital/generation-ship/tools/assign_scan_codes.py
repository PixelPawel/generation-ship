"""Give every distinct printed card face a scan code (the 12-light dial
printed around its colour orb, read by the in-app photo scan).

Adds/fills a "Code" column in the card sheets. Codes already in a sheet are
kept (they're printed — never renumber), new card names get the next free
code in their deck's range. Duplicate prints of one card share its code.
Run after adding cards to a sheet, then rerun bake_card_data.py.
"""
import csv, io, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DATA = os.path.join(ROOT, "data")
# sheet -> first..last code of its range (10 bits: 0-1023 available)
RANGES = {
    "Techs": (1, 199),
    "Promos": (200, 249),
    "Expeditions": (300, 399),
    "Advanced Sectors": (400, 449),
    "Dust Sectors": (450, 499),
}

def read(path):
    raw = open(path, "rb").read()
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")
    nl = "\r\n" if "\r\n" in text else "\n"
    rows = list(csv.reader(io.StringIO(text, newline="")))
    return rows, bom, nl, text.split(nl, 1)[0].startswith('"'), text.endswith(nl)

def write(path, rows, bom, nl, quote_all, trailing):
    out = io.StringIO()
    csv.writer(out, quoting=csv.QUOTE_ALL if quote_all else csv.QUOTE_MINIMAL, lineterminator=nl).writerows(rows)
    s = out.getvalue()
    if not trailing:
        s = s[: -len(nl)]
    open(path, "wb").write((b"\xef\xbb\xbf" if bom else b"") + s.encode("utf-8"))

def key(name):
    return " ".join(name.replace("‘", "'").replace("’", "'").split()).lower()

for sheet, (lo, hi) in RANGES.items():
    path = os.path.join(DATA, f"Generation Ship Full Card Details - {sheet}.csv")
    rows, *fmt = read(path)
    h = rows[0]
    if "Code" not in h:
        h.append("Code")
        for r in rows[1:]:
            r.append("")
    ci, ni, noi = h.index("Code"), h.index("Name"), h.index("No.")
    by_name, used = {}, set()
    for r in rows[1:]:                       # existing codes win
        while len(r) <= ci:
            r.append("")
        if r[ci].strip().isdigit():
            by_name.setdefault(key(r[ni]), int(r[ci])); used.add(int(r[ci]))
    nxt = lo
    for r in rows[1:]:
        if not r[noi].strip().isdigit() or r[ci].strip():
            continue
        k = key(r[ni])
        if k not in by_name:
            while nxt in used:
                nxt += 1
            assert nxt <= hi, f"{sheet}: code range {lo}-{hi} is full"
            by_name[k] = nxt; used.add(nxt)
        r[ci] = str(by_name[k])
    write(path, rows, *fmt)
    # the .EN copy (same rows by No.) gets the same codes
    en = path[:-4] + ".EN.csv"
    if os.path.exists(en):
        erows, *efmt = read(en)
        eh = erows[0]
        if "Code" not in eh:
            eh.append("Code")
            for r in erows[1:]:
                r.append("")
        eci, eno = eh.index("Code"), eh.index("No.")
        code_by_no = {r[noi].strip(): r[ci] for r in rows[1:] if r[noi].strip().isdigit()}
        for r in erows[1:]:
            while len(r) <= eci:
                r.append("")
            if r[eno].strip() in code_by_no:
                r[eci] = code_by_no[r[eno].strip()]
        write(en, erows, *efmt)
    print(f"{sheet}: {len(by_name)} distinct cards, codes {min(by_name.values())}-{max(by_name.values())}")
