"""Where the cards and the supply come from in the bots' test games (runs made with --trace).

    python tools/bot_league_economy.py <tag> [<tag> ...]

Per card effect (EFF lines, scenes/main/bot_turn.gd _econ_print): how often it fired, the supply it
brought (raw, and in Dust-equivalents: a Metals/Liquids is worth 1.4 Dust, Organix/Electrix 2, Thrust
2.8 - BotPlanner.U), the cards it drew, what it did to the hand, stored supply and archived cards.
Then the game as a whole: supply from the ship's income vs card effects vs recycling to pay, cards
drawn at the start of a Generation vs by effects, the deck over time, and dry draws.
"""
import collections
import json
import os
import re
import sys

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bot_league")
U = [1.0, 1.4, 1.4, 2.0, 2.0, 2.8]
NESTED = {"choice", "reflectors_choice"}   # their inner steps are reported on their own lines

tags = [a for a in sys.argv[1:] if not a.startswith("--")]
eff = collections.defaultdict(lambda: collections.Counter())
fired_games = collections.defaultdict(set)
per_gen = collections.defaultdict(lambda: collections.Counter())
deck = collections.defaultdict(list)
games = 0
dry = 0
bots_per_game = 3

for tag in tags:
    d = os.path.join(HERE, "logs_" + tag)
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".out"):
            continue
        games += 1
        gid = tag + "/" + fn
        last_call = None
        for line in open(os.path.join(d, fn), encoding="utf-8", errors="replace"):
            line = line.rstrip("\n")
            m = re.match(r"EFF g(\d) (.+?) \| (.+?) \| (\S+) \| ([-\d ]+) \| (-?\d+) \| (-?\d+) \| (-?\d+) \| (-?\d+)$", line)
            if m:
                g, bot, src, typ = int(m.group(1)), m.group(2), m.group(3), m.group(4)
                if typ in NESTED:
                    continue
                sup = [int(x) for x in m.group(5).split()]
                drawn, dhand, stored, tucked = (int(m.group(i)) for i in range(6, 10))
                c = eff[src]
                call = (g, bot, src)
                if call != last_call:   # consecutive steps of one source = one firing
                    c["fired"] += 1
                last_call = call
                gained = [max(0, x) for x in sup]
                c["supply"] += sum(gained)
                c["supply_u"] += sum(x * u for x, u in zip(sup, U))   # net: a fuse's spent Dust counts against it
                c["drawn"] += drawn
                c["dhand"] += dhand
                c["stored"] += stored
                c["tucked"] += tucked
                # cards that left the hand into the discard pile (recycled), not counting archived ones
                c["recycled"] += max(0, drawn - dhand - max(0, tucked))
                fired_games[src].add(gid)
                per_gen[g]["eff_supply_u"] += sum(x * u for x, u in zip(sup, U))
                per_gen[g]["eff_drawn"] += drawn
                continue
            m = re.match(r"TURN g(\d) .+ sup \[([\d, ]+)\]", line)
            if m:
                sup_now = [int(x) for x in m.group(2).split(",")]
                per_gen[int(m.group(1))]["held_u"] += sum(x * u for x, u in zip(sup_now, U))
                per_gen[int(m.group(1))]["turns"] += 1
                continue
            m = re.match(r"INC g(\d) .+ (\d)$", line)
            if m:
                per_gen[int(m.group(1))]["income_u"] += U[int(m.group(2))]
                continue
            m = re.match(r"FREE g(\d) .+ recycle (.+)$", line)
            if m:
                per_gen[int(m.group(1))]["pay_recycles"] += 1
                continue
            m = re.match(r"DECK g(\d) deck (-?\d+) discard (-?\d+) bot_hands ([\d,]+) seat_hand (-?\d+)", line)
            if m:
                g = int(m.group(1))
                deck[g].append((int(m.group(2)), int(m.group(3)), sum(int(x) for x in m.group(4).split(",")), int(m.group(5))))
                continue
            if line.startswith("DRY "):
                dry += 1

print("%d games (%d bots + the passive seat each)\n" % (games, bots_per_game))
print("Per card effect, per game (all bots together):")
print("%-34s %6s %6s %8s %7s %7s %7s %6s %7s" % ("source", "games", "fired", "gained", "net D-eq", "drawn", "recyc", "stored", "archiv"))
rows = sorted(eff.items(), key=lambda kv: -(kv[1]["supply_u"] + 1.2 * kv[1]["drawn"]))
for src, c in rows:
    if c["fired"] == 0:
        continue
    print("%-34s %6d %6.2f %8.2f %7.2f %7.2f %7.2f %6.2f %7.2f" % (
        src[:34], len(fired_games[src]), c["fired"] / games, c["supply"] / games, c["supply_u"] / games,
        c["drawn"] / games, c["recycled"] / games, c["stored"] / games, c["tucked"] / games))
print("\nPer firing (the card's strength each time it goes off):")
print("%-34s %8s %7s %7s" % ("source", "Dust-eq", "drawn", "recyc"))
for src, c in sorted(eff.items(), key=lambda kv: -(kv[1]["supply_u"] + 1.2 * kv[1]["drawn"]) / max(1, kv[1]["fired"])):
    if c["fired"] < 3:
        continue
    f = c["fired"]
    print("%-34s %8.2f %7.2f %7.2f" % (src[:34], c["supply_u"] / f, c["drawn"] / f, c["recycled"] / f))

print("\nPer Generation, per game (3 bots): supply in Dust-eq from income / from card effects; cards drawn by effects; recycles to pay")
for g in sorted(per_gen):
    p = per_gen[g]
    print("  g%d  income %6.1f  effects %6.1f  effect draws %5.1f  pay-recycles %5.1f   supply held at a bot's turn %5.1f" % (
        g, p["income_u"] / games, p["eff_supply_u"] / games, p["eff_drawn"] / games, p["pay_recycles"] / games,
        p["held_u"] / max(1, p["turns"])))
print("\nDeck at bot turns (average): deck / discard / 3 bots' hands / passive seat's hand")
for g in sorted(deck):
    v = deck[g]
    n = len(v)
    print("  g%d  deck %5.1f  discard %5.1f  bot hands %5.1f  seat %5.1f   (lowest deck+discard %d)" % (
        g, sum(x[0] for x in v) / n, sum(x[1] for x in v) / n, sum(x[2] for x in v) / n, sum(x[3] for x in v) / n,
        min(x[0] + x[1] for x in v)))
print("\ndraws that found the deck AND the discard pile empty: %d (%.2f per game)" % (dry, dry / max(1, games)))
