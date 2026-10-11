"""Show the crash reports players sent from the Windows launcher (tools/launcher), most common first.

    python tools/crash_report.py [--days 30]      # grouped list
    python tools/crash_report.py --show 17        # one report with its full godot.log

Needs the admin token: env HCG_ADMIN_TOKEN, or the file ~/.hcg_admin_token
(the same value as ADMIN_TOKEN in /opt/hcg-api/.env on the server).
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = os.environ.get("HCG_API", "https://api.happycapygames.com")   # HCG_API: a local test server


def token() -> str:
    t = os.environ.get("HCG_ADMIN_TOKEN", "").strip()
    if not t:
        path = os.path.join(os.path.expanduser("~"), ".hcg_admin_token")
        if os.path.exists(path):
            t = open(path, encoding="utf-8").read().strip()
    if not t:
        sys.exit("No admin token: set HCG_ADMIN_TOKEN or write it to ~/.hcg_admin_token")
    return t


def get(path: str) -> dict:
    req = urllib.request.Request(API + path, headers={"X-Admin-Token": token()})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit("%s %s: %s" % (e.code, path, e.read().decode("utf-8", "replace")))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--show", type=int, help="one report's id: print it with its full log")
    a = ap.parse_args()
    if a.show:
        r = get("/v1/crashes/%d" % a.show)
        log = r.pop("log")
        r["created_at"] = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(r["created_at"]))
        for k, v in r.items():
            print("%-10s %s" % (k, v))
        print("\n" + log)
        return
    rep = get("/v1/crashes/report?days=%d" % a.days)
    print("%d reports in the last %d days, %d different problems\n" % (rep["total"], a.days, len(rep["groups"])))
    for g in rep["groups"]:
        print("%d players, %d reports  [%s]  latest id %d, %s" % (
            g["players"], g["count"], " ".join("%s:%d" % kv for kv in g["phases"].items()), g["latest_id"],
            time.strftime("%Y-%m-%d", time.gmtime(g["last_at"]))))
        print("  " + g["summary"])
        print("  GPUs: " + "; ".join("%s x%d" % kv for kv in g["gpus"].items()))
        if g["safe_mode"]:
            print("  %d of them already in safe graphics mode" % g["safe_mode"])
        if g["builds"]:
            print("  builds: " + ", ".join(g["builds"]))
        print()


if __name__ == "__main__":
    main()
