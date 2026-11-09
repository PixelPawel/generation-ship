"""Where the bots' supply and cards go, per Generation: python tools/bot_league_flow.py <tag> (a --trace run)."""
import os, re, statistics, sys
from collections import defaultdict
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_league")
tag = sys.argv[1]
d = os.path.join(HERE, "logs_" + tag)
agg = defaultdict(lambda: defaultdict(list))
for fn in sorted(os.listdir(d)):
    if not fn.endswith(".out"):
        continue
    cur = defaultdict(lambda: defaultdict(float)); first = {}
    for line in open(os.path.join(d, fn), encoding="utf-8", errors="replace"):
        m = re.match(r"TURN g(\d) (.+?) sup \[([\d, ]+)\] total (\d+) hand (\d+) ship (\d+)", line)
        if m:
            key = (m.group(1), m.group(2))
            if key not in first:
                first[key] = 1
                cur[key]["start_supply"] = int(m.group(4)); cur[key]["start_hand"] = int(m.group(5)); cur[key]["start_ship"] = int(m.group(6))
            cur[key]["end_supply"] = int(m.group(4)); cur[key]["end_hand"] = int(m.group(5))
            continue
        m = re.match(r"ACT g(\d) (.+?) (place_tech|buy_sector|start_auction_adv|start_auction|research|pass)", line)
        if m:
            cur[(m.group(1), m.group(2))][m.group(3)] += 1; continue
        m = re.match(r"FREE g(\d) (.+?) (fuse|recycle)", line)
        if m:
            cur[(m.group(1), m.group(2))][m.group(3)] += 1; continue
        m = re.match(r"WIN g(\d) (.+?) (.+) for (\d+) (\w+)", line)
        if m:
            for name in [k[1] for k in first if k[0] == m.group(1)]:
                if m.group(2).startswith(name) and (m.group(2) == name or m.group(2)[len(name)] == " " and not m.group(2)[len(name) + 1:].split(" ")[0].isdigit()):
                    pass
    for key, v in cur.items():
        for name in ["start_supply", "start_hand", "start_ship", "place_tech", "buy_sector", "start_auction", "start_auction_adv", "research", "fuse", "recycle", "end_supply", "end_hand"]:
            agg[key[0]][name].append(v.get(name, 0))
cols = ["start_supply", "start_hand", "start_ship", "place_tech", "buy_sector", "start_auction", "start_auction_adv", "research", "fuse", "recycle", "end_supply", "end_hand"]
print("gen  " + "  ".join("%9s" % c[:9] for c in cols))
for g in sorted(agg):
    print("g%s   " % g + "  ".join("%9.1f" % statistics.mean(agg[g][c]) for c in cols))
