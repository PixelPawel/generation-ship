"""How much the bots hoard in their test games (runs made with --trace), and what a hand limit does.

    python tools/bot_league_hoard.py <tag> [<tag> ...]

Per Generation: the bots' hands at their first and last turn, the supply they hold, researches and
passes, how many cards the hand limit recycled (RLIM lines), the passive seat's hand, the deck +
discard pile, and draws that found both empty.

The rule tried out 2026-11-17 (off in real games): --bv reslimit=6 = a player who passes or researches
recycles the hand down to 6 cards first (the passive seat too). The hoarding bots of that test:
--bv w2_hand=8,w3_hand=8,w4_hand=8,w2_units=3,w3_units=3,w4_units=3 (a card in hand at 8 points).
"""
import os, re, sys, json, collections, statistics
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_league")
U = [1.0, 1.4, 1.4, 2.0, 2.0, 2.8]
ACTIONS = "pass|research|place_tech|buy_sector|buy_adv_sector|start_auction_adv|start_auction"
for tag in sys.argv[1:]:
    d = os.path.join(HERE, "logs_" + tag)
    last = {}            # (game, gen, bot) -> (hand, units) at its last turn of the Generation
    first = {}
    acts = collections.defaultdict(collections.Counter)
    rlim = collections.defaultdict(list)   # cards recycled by the limit, per bot and Generation
    deck = collections.defaultdict(list)
    dry = collections.Counter()
    games = 0
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".out"):
            continue
        games += 1
        dumped = collections.Counter()
        for line in open(os.path.join(d, fn), encoding="utf-8", errors="replace"):
            m = re.match(r"TURN g(\d) (.+?) sup \[([\d, ]+)\] total \d+ hand (\d+)", line)
            if m:
                g = int(m.group(1)); key = (fn, g, m.group(2))
                units = sum(int(x) * u for x, u in zip(m.group(3).split(","), U))
                last[key] = (int(m.group(4)), units)
                first.setdefault(key, (int(m.group(4)), units))
                continue
            m = re.match(r"ACT g(\d) (.+?) (%s)( |$)" % ACTIONS, line)
            if m:
                acts[int(m.group(1))][m.group(3)] += 1
                continue
            m = re.match(r"RLIM g(\d) (.+?) (?:research |pass )?hand (\d+) recycled (\d+)", line)
            if m:
                dumped[(int(m.group(1)), m.group(2))] += int(m.group(4))
                continue
            m = re.match(r"DECK g(\d) deck (-?\d+) discard (-?\d+) bot_hands ([\d,]+) seat_hand (-?\d+)", line)
            if m:
                deck[int(m.group(1))].append((int(m.group(2)), int(m.group(3)), int(m.group(5))))
                continue
            m = re.match(r"DRY g(\d) wanted (\d+) got (\d+)", line)
            if m:
                dry[int(m.group(1))] += int(m.group(2)) - int(m.group(3))
                dry["games:" + fn] += 1
        for (g, _bot), n in dumped.items():
            rlim[g].append(n)
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
        print("  g%d  hand at first turn %4.1f (max %2d) | at last turn %4.1f (max %2d), supply %4.1f D-eq | research %4.1f pass %3.1f per bot | limit recycled %4.1f cards per bot (max %2d) | seat hand %4.1f | deck+discard avg %5.1f lowest %3d | missing draws %d" % (
            g, statistics.mean(fh), max(fh), statistics.mean(hs), max(hs), statistics.mean(us),
            a["research"] / (3.0 * games), a["pass"] / (3.0 * games),
            sum(rlim[g]) / (3.0 * games), max(rlim[g]) if rlim[g] else 0,
            statistics.mean(x[2] for x in dk),
            statistics.mean(x[0] + x[1] for x in dk), min(x[0] + x[1] for x in dk), dry[g]))
    print("  games with a dry draw: %d of %d" % (sum(1 for k in dry if str(k).startswith("games:")), games))
