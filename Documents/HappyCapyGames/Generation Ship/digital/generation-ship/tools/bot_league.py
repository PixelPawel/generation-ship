"""Bot-vs-bot test games (scripts/game/bot_sim.gd): plays N seeded Versus games headless, three bots each,
in parallel, and summarises their scores and where the points came from.

    python tools/bot_league.py <tag> [--games 30] [--diff 2,2,2] [--jobs 6] [--speed 30] [--seed0 1]
    python tools/bot_league.py --report <tag> [<tag> ...]      # compare finished runs

Results: tools/bot_league/<tag>.jsonl (one line per game). The player's seat passes every turn, so it is
three bots against each other; nothing reaches the leaderboard or Steam.
"""
import json, os, statistics, subprocess, sys, time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
OUT = os.path.join(HERE, "bot_league")
GODOT = r"C:\Program Files (x86)\Godot 4\Godot_v4.7-stable_win64_console.exe"
EXPEDITION_SKIP = {"Stars", "Faceup archived", "Facedown archived", "Stored supply",
                   "Greenhouses (Liquids bonus)", "Astra Cultura (Thrust bonus)"}


def arg(name, default):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name) + 1]
    return default


def play(tag, seed, diff, speed, out_path, log_dir):
    cmd = [GODOT, "--headless", "--path", PROJECT, "--log-file", os.path.join(log_dir, "g%d.log" % seed), "--",
           "--botsim", "--botsim-seed=%d" % seed, "--botsim-diff=" + diff, "--botsim-speed=%s" % speed,
           "--botsim-out=" + os.path.join(log_dir, "g%d.json" % seed).replace("\\", "/")]
    t0 = time.time()
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
        return seed, time.time() - t0, None
    except subprocess.TimeoutExpired:
        return seed, time.time() - t0, "timeout"


def load(tag):
    rows = []
    with open(os.path.join(OUT, tag + ".jsonl"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def summarise(tag):
    rows = load(tag)
    by_diff = defaultdict(list)
    cats = defaultdict(lambda: defaultdict(list))
    adv = defaultdict(list)
    wins = []
    for r in rows:
        best = max(b["vp"] for b in r["bots"])
        wins.append(best)
        for b in r["bots"]:
            d = b["diff"]
            by_diff[d].append(b["vp"])
            c = defaultdict(int)
            for l in b["lines"]:
                key = l["label"] if l["label"] in EXPEDITION_SKIP else "Expeditions/conditional"
                c[key] += l["vp"]
            for k in ["Stars", "Faceup archived", "Facedown archived", "Stored supply", "Expeditions/conditional"]:
                cats[d][k].append(c.get(k, 0))
            adv[d].append(sum(1 for s in b["sectors"] if s["adv"]))
    names = {0: "Easy", 1: "Normal", 2: "Hard"}
    print("== %s: %d games" % (tag, len(rows)))
    for d in sorted(by_diff):
        v = by_diff[d]
        print("  %-6s avg %5.1f  median %4.0f  min %3d  max %3d   (n=%d)" % (
            names.get(d, d), statistics.mean(v), statistics.median(v), min(v), max(v), len(v)))
        print("         " + "  ".join("%s %.1f" % (k.split()[0] if k != "Expeditions/conditional" else "Exped", statistics.mean(x))
                                    for k, x in cats[d].items()) + "   adv.sectors %.1f" % statistics.mean(adv[d]))
    if wins:
        print("  winner avg %.1f, max %d" % (statistics.mean(wins), max(wins)))


def main():
    if "--report" in sys.argv:
        for tag in sys.argv[sys.argv.index("--report") + 1:]:
            summarise(tag)
        return
    tag = sys.argv[1]
    games = int(arg("--games", "30"))
    diff = arg("--diff", "2,2,2")
    jobs = int(arg("--jobs", "6"))
    speed = arg("--speed", "30")
    seed0 = int(arg("--seed0", "1"))
    os.makedirs(OUT, exist_ok=True)
    out_path = os.path.join(OUT, tag + ".jsonl")
    if os.path.exists(out_path):
        os.remove(out_path)
    log_dir = os.path.join(OUT, "logs_" + tag)
    os.makedirs(log_dir, exist_ok=True)
    for old in os.listdir(log_dir):                            # a rerun of the same tag starts clean
        if old.endswith(".json"):
            os.remove(os.path.join(log_dir, old))
    t0 = time.time()
    fails = []
    with ThreadPoolExecutor(jobs) as ex:
        for seed, secs, err in ex.map(lambda s: play(tag, s, diff, speed, out_path, log_dir), range(seed0, seed0 + games)):
            if err:
                fails.append((seed, err))
    with open(out_path, "w", encoding="utf-8") as out:          # each game wrote its own file: merge
        for seed in range(seed0, seed0 + games):
            p = os.path.join(log_dir, "g%d.json" % seed)
            if os.path.exists(p):
                for line in open(p, encoding="utf-8"):
                    if line.strip():
                        out.write(line.strip() + "\n")
            elif seed not in [f[0] for f in fails]:
                fails.append((seed, "no result"))
    print("%d games in %.0f s, %d failed %s" % (games, time.time() - t0, len(fails), fails[:5]))
    summarise(tag)


if __name__ == "__main__":
    main()
