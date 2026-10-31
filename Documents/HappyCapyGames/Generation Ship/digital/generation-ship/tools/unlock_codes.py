"""Full-game codes for the Android app (Versus + Co-op), made on the API server.

    python tools/unlock_codes.py make <count> <batch> [--uses 1] [--note "..."]
    python tools/unlock_codes.py report

`make` creates a batch (e.g. "gamefound-backers", "contest-2026-11") and saves
it as Generation Ship/Unlock Codes/<batch>.csv, outside git: the codes are as
good as money, keep the file private. A code unlocks ONE player by default (one
install: after a reinstall or on a new phone it no longer works); --uses N
allows N. Players enter it in the app
(Versus or Co-op -> "Enter a code"), any case, with or without the dashes.

`report` lists every batch: codes made, codes used, players unlocked.

Needs the admin token: env HCG_ADMIN_TOKEN, or the file ~/.hcg_admin_token
(the same value as ADMIN_TOKEN in /opt/hcg-api/.env on the server).
"""
import argparse
import csv
import datetime
import json
import os
import sys
import urllib.error
import urllib.request

API = os.environ.get("HCG_API", "https://api.happycapygames.com")   # HCG_API: a local test server
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "Unlock Codes")
MAX_PER_CALL = 5000                                                  # server/app/unlock.py MAX_BATCH


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
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit(f"Server said {e.code}: {e.read().decode('utf-8', 'replace')}")


def make(count: int, batch: str, uses: int, note: str) -> None:
    path = os.path.join(OUT_DIR, batch + ".csv")
    if os.path.exists(path):
        sys.exit(f"{path} exists already - pick a new batch name")
    codes: list[str] = []
    while len(codes) < count:   # the server makes at most MAX_PER_CALL per request
        n = min(MAX_PER_CALL, count - len(codes))
        codes += api("/v1/unlock/codes", {"count": n, "batch": batch, "max_uses": uses, "note": note})["codes"]
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["code", "batch", "players per code", "made"])
        made = datetime.date.today().isoformat()
        for code in codes:
            w.writerow([code, batch, uses, made])
    print(f"{len(codes)} codes -> {path}")


def report() -> None:
    batches = api("/v1/unlock/report")["batches"]
    if not batches:
        print("No codes yet.")
        return
    print(f"{'batch':<28}{'codes':>7}{'used':>7}{'players':>9}  made")
    for b in batches:
        made = datetime.date.fromtimestamp(b["created_at"]).isoformat()
        print(f"{b['batch']:<28}{b['codes']:>7}{b['used_codes']:>7}{b['redemptions']:>9}  {made}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("make")
    m.add_argument("count", type=int)
    m.add_argument("batch")
    m.add_argument("--uses", type=int, default=1)
    m.add_argument("--note", default="")
    sub.add_parser("report")
    a = ap.parse_args()
    if a.cmd == "make":
        make(a.count, a.batch, a.uses, a.note)
    else:
        report()


if __name__ == "__main__":
    main()
