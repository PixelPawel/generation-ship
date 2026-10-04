"""Pull the players' translation comments from the API server into a report.

    python tools/translation_comments_report.py [--lang PL] [--field effect] [--status open|done|ignored|all]

Needs the admin token: env HCG_ADMIN_TOKEN, or the file ~/.hcg_admin_token
(the same value as ADMIN_TOKEN in /opt/hcg-api/.env on the server).

Writes two files into digital/translation_reports/ (not in git):
  comments_<date>.csv   one row per comment, with the card's English and
                        translated text for that part, ready for a spreadsheet
  comments_<date>.md    readable: grouped per card and part, busiest first

Triage a comment afterwards (it then drops out of the default "open" report):
    python tools/translation_comments_report.py --mark 42 done
"""
import argparse
import csv
import datetime
import glob
import json
import os
import re
import sys
import urllib.error
import urllib.request

API = os.environ.get("HCG_API", "https://api.happycapygames.com")   # HCG_API: a local test server
HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
DATA = os.path.join(GAME, "data")
OUT_DIR = os.path.join(os.path.dirname(GAME), "translation_reports")
FIELD_COLUMNS = {
    "name": ["Name"],
    "flavor": ["Flavor"],
    "effect": ["Effect", "Effect 1", "Effect 2", "Optimize 1", "Optimize 2", "Optimize 3", "Solve"],
}


def token() -> str:
    t = os.environ.get("HCG_ADMIN_TOKEN", "").strip()
    if not t:
        path = os.path.expanduser("~/.hcg_admin_token")
        if os.path.exists(path):
            t = open(path, encoding="utf-8").read().strip()
    if not t:
        sys.exit("No admin token: set HCG_ADMIN_TOKEN or put it in ~/.hcg_admin_token")
    return t


def api(path: str, body: dict | None = None):
    req = urllib.request.Request(API + path, headers={"X-Admin-Token": token(), "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None,
                                 method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit(f"Server said {e.code}: {e.read().decode('utf-8', 'replace')}")


def clean(s: str) -> str:
    """Same as TranslationVotes.board_name(): keep only [A-Za-z0-9_]."""
    return re.sub(r"[^A-Za-z0-9_]", "", s)


def rows_of(path: str) -> list[dict]:
    with open(path, encoding="utf-8-sig") as f:
        return [{k.strip().strip('"'): (v or "") for k, v in r.items() if k} for r in csv.DictReader(f)]


def card_texts() -> tuple[dict, dict]:
    """card file id (cleaned link without extension) -> {field: text}, for EN and per language."""
    en: dict = {}
    for path in glob.glob(os.path.join(DATA, "Generation Ship Full Card Details - *.csv")):
        if "Glossary" in path:
            continue
        for r in rows_of(path):
            link = os.path.splitext(r.get("Link", ""))[0]
            if link and (".EN." in path or clean(link) not in en):
                en[clean(link)] = r
    tr: dict = {}
    for path in glob.glob(os.path.join(DATA, "translations", "*.csv")):
        lang = path.rsplit(".", 2)[-2].upper()
        for r in rows_of(path):
            link = os.path.splitext(r.get("Link", ""))[0]
            if link:
                tr[(lang, clean(link))] = r
    return en, tr


def part_text(row: dict | None, field: str) -> str:
    if not row:
        return ""
    parts = [row.get(c, "").strip() for c in FIELD_COLUMNS[field]]
    return " / ".join(p.replace("\n", " ") for p in parts if p and not set(p) <= {"⭐", " "})


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lang")
    ap.add_argument("--field", choices=sorted(FIELD_COLUMNS))
    ap.add_argument("--status", default="open", choices=["open", "done", "ignored", "all"])
    ap.add_argument("--mark", nargs=2, metavar=("ID", "STATUS"), help="set one comment's status and exit")
    a = ap.parse_args()
    if a.mark:
        api(f"/v1/comments/{int(a.mark[0])}/status", {"status": a.mark[1]})
        print(f"comment {a.mark[0]} -> {a.mark[1]}")
        return

    q = [f"status={'' if a.status == 'all' else a.status}"]
    if a.lang:
        q.append(f"lang={a.lang.upper()}")
    if a.field:
        q.append(f"field={a.field}")
    rep = api("/v1/comments/report?" + "&".join(q))
    en, tr = card_texts()

    os.makedirs(OUT_DIR, exist_ok=True)
    stamp = datetime.date.today().isoformat()
    csv_path = os.path.join(OUT_DIR, f"comments_{stamp}.csv")
    md_path = os.path.join(OUT_DIR, f"comments_{stamp}.md")
    with open(csv_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["id", "lang", "card", "file", "part", "english", "current translation", "comment",
                    "player", "players on this part", "votes up", "votes down", "version", "status", "sent (UTC)"])
        for g in rep["groups"]:
            file_id = g["key"].split("_", 2)[2].split("_", 1)[-1]
            en_row, tr_row = en.get(file_id), tr.get((g["lang"], file_id))
            name = (en_row or {}).get("Name", "") or file_id
            for c in g["comments"]:
                sent = datetime.datetime.fromtimestamp(c["created_at"], datetime.timezone.utc).strftime("%Y-%m-%d %H:%M")
                w.writerow([c["id"], g["lang"], name, file_id, g["field"], part_text(en_row, g["field"]),
                            part_text(tr_row, g["field"]), c["text"], c["player"], g["players"],
                            g["votes_up"], g["votes_down"], c["version"], c["status"], sent])
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(f"# Translation comments, {stamp}\n\n{rep['total']} comment(s), status: {a.status}\n")
        for g in rep["groups"]:
            file_id = g["key"].split("_", 2)[2].split("_", 1)[-1]
            en_row, tr_row = en.get(file_id), tr.get((g["lang"], file_id))
            name = (en_row or {}).get("Name", "") or file_id
            f.write(f"\n## {g['lang']} · {name} · {g['field']}  ({g['players']} player(s), votes ▲{g['votes_up']} ▼{g['votes_down']})\n\n")
            f.write(f"- **English:** {part_text(en_row, g['field']) or '–'}\n")
            f.write(f"- **Current {g['lang']}:** {part_text(tr_row, g['field']) or '–'}\n\n")
            for c in g["comments"]:
                f.write(f"  - #{c['id']} ({c['player']}, v{c['version'] or '?'}): {c['text']}\n")
    print(f"{rep['total']} comment(s) in {len(rep['groups'])} group(s)\n  {csv_path}\n  {md_path}")


if __name__ == "__main__":
    main()
