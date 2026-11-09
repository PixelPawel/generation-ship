"""How well the planner's forecast matches the final score: python tools/bot_league_calib.py <tag>
(a run made with --trace). Per Generation: the forecast at the bot's first turn vs its final score."""
import json, os, re, statistics, sys
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_league")
tag = sys.argv[1]
d = os.path.join(HERE, "logs_" + tag)
per_gen = {}
for fn in sorted(os.listdir(d)):
    if not fn.endswith(".out"):
        continue
    res = os.path.join(d, fn[:-4] + ".json")
    if not os.path.exists(res):
        continue
    row = json.loads(open(res, encoding="utf-8").read().strip().splitlines()[-1])
    final = {b["name"]: b["vp"] for b in row["bots"]}
    first = {}
    for line in open(os.path.join(d, fn), encoding="utf-8", errors="replace"):
        m = re.match(r"PLAN g(\d) (.+?) base ([\d.]+) best", line)
        if m and (m.group(1), m.group(2)) not in first:
            first[(m.group(1), m.group(2))] = float(m.group(3))
    for (g, name), v in first.items():
        if name in final:
            per_gen.setdefault(g, []).append((v, final[name]))
for g in sorted(per_gen):
    xs = [a for a, _ in per_gen[g]]; ys = [b for _, b in per_gen[g]]
    n = len(xs); mx, my = statistics.mean(xs), statistics.mean(ys)
    cov = sum((a - mx) * (b - my) for a, b in zip(xs, ys))
    r = cov / ((sum((a - mx) ** 2 for a in xs) * sum((b - my) ** 2 for b in ys)) ** 0.5 or 1)
    print("gen %s: forecast %.1f  final %.1f  (bias %+.1f)  r=%.2f  n=%d" % (g, mx, my, mx - my, r, n))
