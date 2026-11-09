"""Fits the planner's outlook model (scripts/game/bot_planner.gd W) to the bots' own games.

    python tools/bot_league_fit.py <tag> [<tag> ...] [--ridge 3.0]

Each run must have been made with --trace. For every bot and Generation start (2, 3, 4) the FEAT line
gives the position's features and the points on the ship; the target is what the bot went on to add
(final score - points then). One ridge regression per Generation; prints the W dictionary to paste into
bot_planner.gd, with R2 and the weights by name.
"""
import json, os, re, sys
import numpy as np

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_league")
FEATURES = ["one", "units", "income", "hand", "capacity", "open_sectors", "synergy", "hand_stars", "opt_open", "ship"]
ridge = float(sys.argv[sys.argv.index("--ridge") + 1]) if "--ridge" in sys.argv else 3.0
tags = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and sys.argv[i - 1] != "--ridge"]

data = {2: [], 3: [], 4: []}
for tag in tags:
    d = os.path.join(HERE, "logs_" + tag)
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".out"):
            continue
        res = os.path.join(d, fn[:-4] + ".json")
        if not os.path.exists(res):
            continue
        row = json.loads(open(res, encoding="utf-8").read().strip().splitlines()[-1])
        final = {b["name"]: b["vp"] for b in row["bots"]}
        for line in open(os.path.join(d, fn), encoding="utf-8", errors="replace"):
            m = re.match(r"FEAT g(\d) (.+?) vp (\d+) \| (.+)", line)
            if not m:
                continue
            g, name, vp = int(m.group(1)), m.group(2), int(m.group(3))
            f = [float(x) for x in m.group(4).split()]
            if g in data and name in final and len(f) == len(FEATURES):
                data[g].append((f, final[name] - vp))

print("const W: Dictionary = {")
report = []
for g in (2, 3, 4):
    X = np.array([f for f, _ in data[g]]); y = np.array([t for _, t in data[g]])
    # left out: "ship" everywhere (the same thing as income, and the two only trade off against each
    # other); income in the last Generation (it has been paid out: it is in units by then)
    off = [FEATURES.index("ship")] + ([FEATURES.index("income")] if g == 4 else [])
    for k in off:
        X[:, k] = 0.0
    if len(y) < 20:
        print("\t# gen %d: only %d samples" % (g, len(y)))
        continue
    # ridge on standardised features (the constant is not penalised)
    mu = X[:, 1:].mean(0); sd = X[:, 1:].std(0); sd[sd == 0] = 1.0
    Z = (X[:, 1:] - mu) / sd
    A = Z.T @ Z + ridge * np.eye(Z.shape[1])
    beta = np.linalg.solve(A, Z.T @ (y - y.mean()))
    w = beta / sd
    w0 = y.mean() - (w * mu).sum()
    pred = w0 + X[:, 1:] @ w
    r2 = 1 - ((y - pred) ** 2).sum() / ((y - y.mean()) ** 2).sum()
    print("\t%d: [%s]," % (g, ", ".join("%.3f" % v for v in [w0] + list(w))))
    report.append("gen %d (n=%d, adds %.1f on average, R2 %.2f): " % (g, len(y), y.mean(), r2)
                  + "  ".join("%s %+.2f" % (n, v) for n, v in zip(FEATURES, [w0] + list(w))))
    report.append("        feature means: " + "  ".join("%s %.1f" % (n, v) for n, v in zip(FEATURES[1:], mu)))
print("}")
print("\n".join(report))
