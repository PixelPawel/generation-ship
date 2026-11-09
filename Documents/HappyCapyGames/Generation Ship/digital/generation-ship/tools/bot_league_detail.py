"""Board details of bot_league runs: python tools/bot_league_detail.py <tag> [<tag> ...]"""
import json, os, statistics, sys
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_league")
SK = {"Stars", "Faceup archived", "Facedown archived", "Stored supply", "Greenhouses (Liquids bonus)", "Astra Cultura (Thrust bonus)"}
for tag in sys.argv[1:]:
    rows = [json.loads(l) for l in open(os.path.join(HERE, tag + ".jsonl"), encoding="utf-8") if l.strip()]
    sec, cards, exps, left, tuck, full, opt = [], [], [], [], [], [], []
    names = {}
    for r in rows:
        for b in r["bots"]:
            sec.append(len(b["sectors"])); cards.append(sum(s["cards"] for s in b["sectors"]))
            full.append(sum(1 for s in b["sectors"] if s["cards"] >= 5))
            opt.append(sum(1 for s in b["sectors"] if s.get("max_opt", 0) > 0 and s.get("opt", 0) >= s.get("max_opt", 0)))
            e = [l for l in b["lines"] if l["label"] not in SK]
            exps.append(len(e)); tuck.append(sum(s["tucked"] for s in b["sectors"]))
            left.append(sum(int(v) for v in b["supply"].values()))
            for l in e:
                names.setdefault(l["label"], []).append(l["vp"])
    print("%s: sectors %.1f  cards on stacks %.1f  complete %.1f  optimized %.1f  scoring exp/cond %.1f  tucked %.1f  supply left %.1f" % (
        (tag,) + tuple(statistics.mean(x) for x in (sec, cards, full, opt, exps, tuck, left))))
    top = sorted(names.items(), key=lambda kv: -sum(kv[1]))[:14]
    print("   " + ", ".join("%s %dx %.1f" % (k, len(v), statistics.mean(v)) for k, v in top))
