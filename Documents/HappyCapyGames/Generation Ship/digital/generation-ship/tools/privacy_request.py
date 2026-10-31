"""Answer a player's privacy request (GDPR access or erasure) from the API server's data.

    python tools/privacy_request.py find <name>        player ids whose leaderboard name contains <name>
    python tools/privacy_request.py show <id>          everything stored for that id, also saved as JSON
    python tools/privacy_request.py forget <id> [--yes]  delete it (asks first unless --yes)

<id> is the player id the game shows under Settings -> Privacy -> Player ID ("steam:..." or "dev:..."),
or a crash report's install id. Players are told to send that id with their request.

`show` writes privacy_<id>_<date>.json into digital/privacy_requests/ (not in git): send that file to the
player as the answer to an access request, then delete it. The server side is server/app/privacy.py.

Needs the admin token: env HCG_ADMIN_TOKEN, or the file ~/.hcg_admin_token
(the same value as ADMIN_TOKEN in /opt/hcg-api/.env on the server).
"""
import argparse
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

API = os.environ.get("HCG_API", "https://api.happycapygames.com")   # HCG_API: a local test server
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(HERE)), "privacy_requests")


def token() -> str:
    t = os.environ.get("HCG_ADMIN_TOKEN", "").strip()
    if not t:
        path = os.path.expanduser("~/.hcg_admin_token")
        if os.path.exists(path):
            t = open(path, encoding="utf-8").read().strip()
    if not t:
        sys.exit("No admin token: set HCG_ADMIN_TOKEN or write it to ~/.hcg_admin_token")
    return t


def call(method: str, path: str) -> dict:
    req = urllib.request.Request(API + path, method=method, headers={"X-Admin-Token": token()})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} -> {e.code}: {e.read().decode('utf-8', 'replace')}")


def subject_path(subject: str) -> str:
    return "/v1/admin/privacy/" + urllib.parse.quote(subject.strip(), safe="")


def when(ts) -> str:
    return datetime.datetime.fromtimestamp(int(ts)).strftime("%Y-%m-%d %H:%M") if ts else "-"


def cmd_find(name: str) -> None:
    players = call("GET", "/v1/admin/privacy/find?" + urllib.parse.urlencode({"name": name}))["players"]
    if not players:
        print("No leaderboard name contains", repr(name))
        return
    for p in players:
        print(f"{p['player']:<40} {p['name']:<26} {p['source']:<6} {p['score']:>4}  {p['platform']:<8} {when(p['updated_at'])}")


def cmd_show(subject: str) -> None:
    data = call("GET", subject_path(subject))
    total = 0
    for table, rows in data["data"].items():
        total += len(rows)
        print(f"{table}: {len(rows)}")
    if not total:
        print("Nothing stored for", subject)
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    ignore = os.path.join(OUT_DIR, ".gitignore")
    if not os.path.exists(ignore):   # players' data: never into git
        with open(ignore, "w", encoding="utf-8") as f:
            f.write("*\n")
    safe = re.sub(r"[^A-Za-z0-9-]", "_", subject)
    out = os.path.join(OUT_DIR, f"privacy_{safe}_{datetime.date.today()}.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("Saved", out)


def cmd_forget(subject: str, yes: bool) -> None:
    data = call("GET", subject_path(subject))["data"]
    counts = {t: len(rows) for t, rows in data.items() if rows}
    if not counts:
        print("Nothing stored for", subject)
        return
    print("Will delete:", ", ".join(f"{t} {n}" for t, n in counts.items()))
    if not yes and input("Type 'delete' to go ahead: ").strip().lower() != "delete":
        print("Cancelled")
        return
    print("Deleted:", call("DELETE", subject_path(subject))["deleted"])


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("find").add_argument("name")
    sub.add_parser("show").add_argument("subject")
    f = sub.add_parser("forget")
    f.add_argument("subject")
    f.add_argument("--yes", action="store_true")
    args = ap.parse_args()
    if args.cmd == "find":
        cmd_find(args.name)
    elif args.cmd == "show":
        cmd_show(args.subject)
    else:
        cmd_forget(args.subject, args.yes)


if __name__ == "__main__":
    main()
