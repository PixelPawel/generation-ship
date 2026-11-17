"""How much the bots hoard in their test games (runs made with --trace), and what a hand limit does.

    python tools/bot_league_hoard.py <tag> [<tag> ...]

Per Generation: the bots' hands at their first and last turn, the supply they hold, researches and
passes, how often the hand-limit rule fired and how many cards it recycled (RLIM lines), bots that
passed holding more than 6 cards, the deck + discard pile, and draws that found both empty.

The rule tried out 2026-11-17 (off in real games): --bv reslimit=6 = a player's first Research of a
Generation recycles the hand down to 6 cards first; the bot may pass instead. With resforce=1 as well
it has to research before it passes (a hand limit there is no way around). The hoarding bots of that
test: --bv w2_hand=8,w3_hand=8,w4_hand=8,w2_units=3,w3_units=3,w4_units=3 (a card in hand at 8 points).
"""
import os, re, sys, json, collections, statistics
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_league")
U = [1.0, 1.4, 1.4, 2.0, 2.0, 2.8]
for tag in sys.argv[1:]:
    d = os.path.join(HERE, "logs_" + tag)
    last = {}            # (game, gen, bot) -> (hand, units) at its last turn of the Generation
    first = {}
    acts = collections.defaultdict(collections.Counter)
    rlim = collections.defaultdict(list)
    passes = collections.defaultdict(list)
    deck = collections.defaultdict(list)
    dry = collections.Counter()
    games = 0
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".out"):
            continue
        games += 1
        for line in open(os.path.join(d, fn), encoding="utf-8", errors="replace"):
            m = re.match(r"TURN g(\d) (.+?) sup \[([\d, ]+)\] total \d+ hand (\d+)", line)
            if m:
                g = int(m.group(1)); key = (fn, g, m.group(2))
                units = sum(int(x) * u for x, u in zip(m.group(3).split(","), U))
                last[key] = (int(m.group(4)), units)
                first.setdefault(key, (int(m.group(4)), units))
                continue
            m = re.match(r"ACT g(\d) (.+?) (pass|research|place_tech|buy_sector|buy_adv_sector|start_auction_adv|start_auction)( |$)", line)
            if m:
                acts[int(m.group(1))][m.group(3)] += 1
                continue
            m = re.match(r"RLIM g(\d) .+ hand (\d+) recycled (\d+)", line)
            if m:
                rlim[int(m.group(1))].append(int(m.group(3)))
                continue
            m = re.match(r"PASS g(\d) .+ hand (\d+) researched (\d)", line)
            if m:
                passes[int(m.group(1))].append((int(m.group(2)), int(m.group(3))))
                continue
            m = re.match(r"DECK g(\d) deck (-?\d+) discard (-?\d+) bot_hands ([\d,]+) seat_hand (-?\d+)", line)
            if m:
                deck[int(m.group(1))].append((int(m.group(2)), int(m.group(3))))
                continue
            m = re.match(r"DRY g(\d) wanted (\d+) got (\d+)", line)
            if m:
                dry[int(m.group(1))] += int(m.group(2)) - int(m.group(3))
                dry["games:" + fn] += 1
    rows = [json.loads(l) for l in open(os.path.join(HERE, tag + ".jsonl"), encoding="utf-8") if l.strip()]
    vps = [b["vp"] for r in rows for b in r["bots"]]
    endsup = [sum(int(v) * U[int(k)] for k, v in b["supply"].items()) for r in rows for b in r["bots"]]
    print("== %s: %d games, bot score avg %.1f (min %d, max %d), winner avg %.1f; supply left at the end %.1f Dust-eq" % (
        tag, games, statistics.mean(vps), min(vps), max(vps), statistics.mean(max(b["vp"] for b in r["bots"]) for r in rows), statistics.mean(endsup)))
    for g in range(1, 5):
        hs = [v[0] for k, v in last.items() if k[1] == g]
        us = [v[1] for k, v in last.items() if k[1] == g]
        fh = [v[0] for k, v in first.items() if k[1] == g]
        dk = deck[g]
        a = acts[g]
        ps = passes[g]
        print("  g%d  hand at first turn %4.1f (max %2d) | at last turn %4.1f (max %2d), supply %4.1f D-eq | research %4.1f pass %3.1f per bot | rule fired %4.2f per bot, %4.1f cards each | passed holding >6: %4.2f per bot | deck+discard avg %5.1f lowest %3d | missing draws %d" % (
            g, statistics.mean(fh), max(fh), statistics.mean(hs), max(hs), statistics.mean(us),
            a["research"] / (3.0 * games), a["pass"] / (3.0 * games),
            len(rlim[g]) / (3.0 * games), statistics.mean(rlim[g]) if rlim[g] else 0.0,
            sum(1 for h, r in ps if h > 6) / (3.0 * games),
            statistics.mean(x[0] + x[1] for x in dk), min(x[0] + x[1] for x in dk), dry[g]))
    print("  games with a dry draw: %d of %d" % (sum(1 for k in dry if str(k).startswith("games:")), games))
