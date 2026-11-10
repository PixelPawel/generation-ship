class_name BotAI
extends RefCounted
const FleetRules = preload("res://scripts/game/fleet_rules.gd")
const BotValue = preload("res://scripts/game/bot_value.gd")   # Hard/Normal: plays valued in projected final VP

enum Difficulty { EASY = 0, NORMAL = 1, HARD = 2, VERY_HARD = 3 }

const TECH_CAPACITY: int = 5   # matches SectorSlot's 5 tech-slot children
const MAX_SECTORS: int = 6     # matches the "max 6 sectors" ship rule

# Skill flags per difficulty. Rule resolution (card effects, optimize triggers) is NOT gated here —
# that happens uniformly for every bot in bot_turn.gd, since that's just playing the game correctly,
# not a difficulty-scaled skill.
# Targets (2026-11-10): Easy 15-20, Normal 30-40, Hard 65+, Very Hard 90+. Measured in two-player
# games against a bot of the same level (tools/bot_league.py, 32 games): Easy 18, Normal 36, Hard 67,
# Very Hard 60 - and 77 against a Hard bot (see BotPlanner's notes and head_start below).
static func skills_for(difficulty: int) -> Dictionary:
	match difficulty:
		# value_model: plays valued in projected final VP (BotValue, 2026-11-09); foresight = how much of the
		# remaining game the projection sees; bid_scale = how close to that worth it bids
		# planner: plays tried out in BotTurn's sandbox and searched several deep (BotPlanner); Very Hard
		# follows more lines further
		Difficulty.HARD, Difficulty.VERY_HARD:
			return {
				rich_valuation = true, optimize_aware = true, fuse = "proactive",
				recycle = true, bid_ev = true, can_research = true, smart_research = true,
				randomness = 0.0, value_model = true, foresight = 1.0, bid_scale = 1.0, planner = true,
			}
		Difficulty.NORMAL:
			return {
				rich_valuation = true, optimize_aware = true, fuse = "reactive",
				recycle = true, bid_ev = false, can_research = true, smart_research = false,
				randomness = 0.0, value_model = true, foresight = 0.6, bid_scale = 0.8,
			}
		_:
			# Easy (2026-11-10; it used to pick at random and pass 35% of its turns: 2 points a game):
			# Normal's judgement with a beginner's habits. It sees little further than the ship as it is
			# (foresight), as often as not takes any play that looks all right instead of the best
			# (blunder), pays with the supply it has (one fuse; recycling a card for it is what it thinks
			# of on one turn in sixteen - with it every turn it scores 35), bids low, never researches.
			# (randomness: its old self, still what it plays in Generation Fleet)
			return {
				rich_valuation = false, optimize_aware = false, fuse = "off",
				recycle = false, bid_ev = false, can_research = false, smart_research = false,
				randomness = 0.35, value_model = true, foresight = BotValue.k("efore", 0.3), bid_scale = BotValue.k("ebid", 0.5),
				blunder = BotValue.k("eblunder", 0.5), early_pass = BotValue.k("epass", 0.0),
				pay_fuses = int(BotValue.k("efuse", 1.0)), pay_recycle = BotValue.k("erec", 0.06),
			}

## A head start for Very Hard, OFF as it stands (0 cards, no supply): what it would get on top of the
## rules at the start of every Generation - {cards: extra cards drawn, supply: {colour: extra supply}}.
## Hard and Very Hard play the same game by the rules; Very Hard thinks further and fuses and recycles
## to raise a bid. Against a Hard bot in a two-player game that is worth 77 points (2026-11-10,
## tools/bot_league.py), and nothing tried got it further by the rules: the 12 expeditions are shared.
## With 1 extra card a Generation it scored 86, with 2 it scored 104, with 2 and a Thrust 115.
## (--bv-vbcards / --bv-vbsup<colour>: test games)
const VERY_HARD_BONUS_CARDS: int = 0
const VERY_HARD_BONUS_SUPPLY: Dictionary = {}

static func head_start(difficulty: int) -> Dictionary:
	if difficulty < Difficulty.VERY_HARD or GameNetwork.fleet_mode:
		return {cards = 0, supply = {}}
	var supply: Dictionary = {}
	for c: int in 6:
		var n: int = int(BotValue.k("vbsup%d" % c, float(int(VERY_HARD_BONUS_SUPPLY.get(c, 0)))))
		if n > 0:
			supply[c] = n
	return {cards = int(BotValue.k("vbcards", float(VERY_HARD_BONUS_CARDS))), supply = supply}

# Returns {type, card?, slot_idx?}
# type: "pass" | "research" | "buy_sector" | "place_tech" | "start_auction"
static func decide_action(
	difficulty: int,
	hand: Array[CardData],
	supplies: Dictionary,
	bot_board: Array,
	gen: int,
	market_sectors: Array[CardData],
	market_expeditions: Array[CardData],
	market_adv_sectors: Array[CardData] = [],
	market_adv_auction: Array[CardData] = []
) -> Dictionary:
	var skills: Dictionary = skills_for(difficulty)
	var candidates: Array[Dictionary] = _get_affordable_sector_plays(market_sectors, supplies, bot_board)
	candidates.append_array(_get_affordable_tech_plays(hand, supplies, bot_board))
	candidates.append_array(_get_affordable_auction_plays(market_expeditions, supplies, bot_board))
	# Generation Fleet: advanced sectors sell at their printed cost (no auction)
	for play: Dictionary in _all_adv_sector_plays(market_adv_sectors, bot_board):
		if _is_affordable(play, supplies):
			candidates.append(play)

	if difficulty == Difficulty.EASY:
		if candidates.is_empty() or randf() < float(skills.get("randomness", 0.0)):
			return {type = "pass"}
		return candidates[randi() % candidates.size()]

	# Versus: the advanced sectors are auctioned — a bot that never started one never had one
	if bool(skills.get("value_model", false)) and bot_board.size() < MAX_SECTORS:
		for card: CardData in market_adv_auction:
			var play: Dictionary = {type = "start_auction_adv", card = card, color = int(card.adv_color), cost = maxi(0, card.adv_cost)}
			if _is_affordable(play, supplies):
				candidates.append(play)

	if candidates.is_empty():
		return _decide_research_or_pass(hand, supplies, skills)

	if bool(skills.get("value_model", false)):
		var ranked: Array[Dictionary] = rank_by_value(candidates, bot_board, gen, float(skills.get("foresight", 1.0)))
		if OS.get_cmdline_user_args().has("--botsim-trace"):   # tools/bot_league.py tuning
			var parts: PackedStringArray = []
			for k: int in mini(5, ranked.size()):
				var p: Dictionary = ranked[k]
				parts.append("%s %s%s %.2f" % [p["type"], (p["card"] as CardData).card_name,
						(" @%d" % int(p["slot_idx"])) if p.has("slot_idx") else "", float(p["_value"])])
			print("TRACE g%d sup %s sectors %d hand %d | %s" % [gen, str(supplies.values()), bot_board.size(), hand.size(), " | ".join(parts)])
		if float(ranked[0].get("_value", 0.0)) <= 0.0:
			return _decide_research_or_pass(hand, supplies, skills)   # nothing worth its supply now
		return ranked[0]

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _score_play(a, bot_board, skills) > _score_play(b, bot_board, skills))
	return candidates[0]

## Hard/Normal (value model): the turn's play and the free actions that pay for it, as
## {action: {...}, free: [{fuse: {source, target}} | {recycle: CardData}]}. Plays are tried best first; each
## gets the cheapest way to afford it — fuses up the supply chains (several steps: Dust -> Liquids -> Organix),
## then recycling the hand cards worth least placed — as long as what is given up costs less than the play
## gains. The bots used to fuse one step toward their single best play only and recycle only when one card
## of exactly the right colour did it: they ended Generations with 6-8 Dust and hands of 13 cards they
## couldn't pay for (tools/bot_league.py traces, 2026-11-09).
static func plan_turn(
	difficulty: int, hand: Array[CardData], supplies: Dictionary, bot_board: Array, gen: int,
	market_sectors: Array[CardData], market_expeditions: Array[CardData], market_adv_auction: Array[CardData]
) -> Dictionary:
	var skills: Dictionary = skills_for(difficulty)
	var foresight: float = float(skills.get("foresight", 1.0))
	var plays: Array[Dictionary] = _all_sector_plays(market_sectors, bot_board)
	plays.append_array(_all_tech_plays(hand, bot_board))
	plays.append_array(_all_auction_plays(market_expeditions, bot_board))
	if bot_board.size() < MAX_SECTORS:
		for card: CardData in market_adv_auction:
			plays.append({type = "start_auction_adv", card = card, color = int(card.adv_color), cost = maxi(0, card.adv_cost)})
	var allowed: Array[Dictionary] = []
	for p: Dictionary in plays:
		if str(p.get("type", "")) in ["place_tech", "start_auction", "buy_adv_sector"] and FleetRules.blocks_place(_play_color(p)):
			continue
		allowed.append(p)
	var ranked: Array[Dictionary] = _worthwhile(rank_by_value(allowed, bot_board, gen, foresight))
	# what each hand card is worth: placed now (its best slot), and at least what a card in hand is worth
	# later (BotValue.CARD_VP) — one not worth its supply today often is next Generation. Without that floor
	# the bots recycled ~11 cards a game, cards that could have been on the ship earning supply.
	var keep: Dictionary = {}
	var floor_vp: float = BotValue.CARD_VP[clampi(gen, 0, BotValue.ROUNDS)]
	for c: CardData in hand:
		keep[c] = floor_vp
	for p: Dictionary in ranked:
		if str(p.get("type", "")) == "place_tech":
			var c: CardData = p["card"] as CardData
			keep[c] = maxf(float(keep.get(c, floor_vp)), float(p["_value"]))
	if OS.get_cmdline_user_args().has("--botsim-trace"):
		var parts: PackedStringArray = []
		for k: int in mini(5, ranked.size()):
			var q: Dictionary = ranked[k]
			parts.append("%s %s%s %.2f" % [q["type"], (q["card"] as CardData).card_name,
					(" @%d" % int(q["slot_idx"])) if q.has("slot_idx") else "", float(q["_value"])])
		print("TRACE g%d sup %s sectors %d hand %d | %s" % [gen, str(supplies.values()), bot_board.size(), hand.size(), " | ".join(parts)])
	# the weaker levels' habits (skills_for): done for this Generation on a whim; any play that looks
	# all right instead of the best one
	if randf() < float(skills.get("early_pass", 0.0)):
		return {action = {type = "pass"}, free = []}
	if randf() < float(skills.get("blunder", 0.0)):
		ranked.shuffle()
	var may_recycle: bool = randf() < float(skills.get("pay_recycle", 1.0))   # (this turn)
	for p: Dictionary in ranked:
		var pay: Dictionary = plan_to_afford(p, supplies, hand, keep, float(p["_value"]),
				int(skills.get("pay_fuses", 99)), may_recycle)
		if bool(pay.get("ok", false)):
			return {action = p, free = pay["steps"]}
	if OS.get_cmdline_user_args().has("--botsim-trace"):
		var hs: PackedStringArray = []
		for c: CardData in hand:
			hs.append("%s(%s%d)" % [c.card_name, CardData.color_name(c.color).left(2), c.cost])
		print("PASS g%d sup %s worthwhile %d of %d plays | hand %s" % [gen, str(supplies.values()), ranked.size(), allowed.size(), ", ".join(hs)])
	return {action = _decide_research_or_pass(hand, supplies, skills), free = []}

## The fuses and recycles that make play affordable, cheapest first: {ok, steps, loss}. Gives up when what
## the recycled cards were worth (keep) reaches the play's own worth.
static func plan_to_afford(play: Dictionary, supplies: Dictionary, hand: Array[CardData], keep: Dictionary, play_value: float,
		max_fuses: int = 99, may_recycle: bool = true) -> Dictionary:
	var work: Dictionary = supplies.duplicate()
	var steps: Array = []
	var pool: Array[CardData] = hand.duplicate()
	pool.erase(play["card"])
	var color: int = _play_color(play)
	var cost: int = int(play.get("cost", maxi(0, (play["card"] as CardData).cost) + FleetRules.cost_increase(play["card"] as CardData)))
	var loss: float = 0.0
	var fuses: int = 0
	for _i: int in 16:
		if can_pay(work, color, cost):
			return {ok = true, steps = steps, loss = loss}
		var f: Dictionary = _fuse_step_toward(color, work, 3) if fuses < max_fuses else {}
		if not f.is_empty():
			work[int(f["source"])] = int(work.get(int(f["source"]), 0)) - 2
			work[int(f["target"])] = int(work.get(int(f["target"]), 0)) + 1
			steps.append({fuse = f})
			fuses += 1
			continue
		if not may_recycle:
			return {ok = false}
		var best: CardData = null
		var best_keep: float = INF
		for c: CardData in pool:
			if not _feeds(int(c.color), color) or FleetRules.blocks_recycle(int(c.color)) or FleetRules.blocks_gain(int(c.color)):
				continue
			var k: float = float(keep.get(c, 0.0))
			if k < best_keep:
				best_keep = k
				best = c
		if best == null or loss + maxf(best_keep, 0.0) >= play_value:
			return {ok = false}
		work[int(best.color)] = int(work.get(int(best.color), 0)) + CardData.recycle_amount(best)
		pool.erase(best)
		loss += maxf(best_keep, 0.0)
		steps.append({recycle = best})
	return {ok = false}

# One fuse on the way to target: straight into it from a source with 2+, else (depth) into one of its
# sources first.
static func _fuse_step_toward(target: int, work: Dictionary, depth: int) -> Dictionary:
	if depth <= 0 or FleetRules.blocks_fuse(target):
		return {}
	var srcs: Array[int] = []
	for source: int in SupplyUI.FUSE_MAP:
		if (SupplyUI.FUSE_MAP[source] as Array).has(target) and not FleetRules.blocks_fuse(source):
			srcs.append(source)
	srcs.sort_custom(func(a: int, b: int) -> bool: return int(work.get(a, 0)) > int(work.get(b, 0)))
	for s: int in srcs:
		if int(work.get(s, 0)) >= 2:
			return {source = s, target = target}
	for s: int in srcs:
		var deeper: Dictionary = _fuse_step_toward(s, work, depth - 1)
		if not deeper.is_empty():
			return deeper
	return {}

# Supply of colour src helps pay for a target-coloured cost: it pays directly (same chain, at or above),
# or fuses up into the target.
static func _feeds(src: int, target: int) -> bool:
	if CardData.valid_payment_colors(target as CardData.SupplyColor).has(src as CardData.SupplyColor):
		return true
	var frontier: Array[int] = [src]
	for _d: int in 4:
		var nxt: Array[int] = []
		for s: int in frontier:
			for t_v: Variant in (SupplyUI.FUSE_MAP.get(s, []) as Array):
				var t: int = int(t_v)
				if t == target:
					return true
				nxt.append(t)
		frontier = nxt
	return false

## Plays sorted by BotValue.value (best first), each with its "_value".
static func rank_by_value(plays: Array[Dictionary], bot_board: Array, gen: int, foresight: float) -> Array[Dictionary]:
	var base: float = BotValue.projected_vp(bot_board, gen, foresight)
	var out: Array[Dictionary] = []
	for p: Dictionary in plays:
		var q: Dictionary = p.duplicate()
		q["_value"] = BotValue.value(p, bot_board, gen, foresight, base)
		out.append(q)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["_value"]) > float(b["_value"]))
	return out

static func _decide_research_or_pass(hand: Array[CardData], supplies: Dictionary, skills: Dictionary) -> Dictionary:
	if hand.size() <= 1 or not bool(skills.get("can_research", false)):
		return {type = "pass"}
	var pick: CardData
	if bool(skills.get("smart_research", false)):
		pick = _least_affordable_card(hand, supplies)
	else:
		var sorted: Array[CardData] = hand.duplicate()
		sorted.sort_custom(func(a: CardData, b: CardData) -> bool: return a.cost < b.cost)
		pick = sorted[0]
	return {type = "research", card = pick}

static func _least_affordable_card(hand: Array[CardData], supplies: Dictionary) -> CardData:
	var worst: CardData = hand[0]
	var worst_gap: int = -999999
	for card: CardData in hand:
		var gap: int = card.cost - (supplies.get(int(card.color), 0) as int)
		if gap > worst_gap:
			worst_gap = gap
			worst = card
	return worst


static func decide_bid(
	difficulty: int,
	current_bid: int,
	supplies: Dictionary,
	card: CardData,
	is_adv: bool,
	bot_board: Array,
	cost_color: int = -1,
	gen: int = 2
) -> int:
	# cost_color is the auction's actual payment color, which Wormhole
	# Surfing can change away from the card's own.
	var color: int = cost_color if cost_color >= 0 else int(card.adv_color if is_adv else card.color)
	# a bid can be paid with the higher supplies of the colour's chain too, as the humans' bids
	var budget: int = 0
	for c: CardData.SupplyColor in CardData.valid_payment_colors(color as CardData.SupplyColor):
		budget += int(supplies.get(int(c), 0))
	var skills: Dictionary = skills_for(difficulty)
	if bool(skills.get("value_model", false)):
		# up to what the card adds to the projected final score, in supply (BotValue.max_bid)
		var nb: int = current_bid + 1
		var cap: int = int(floor(float(BotValue.max_bid(card, is_adv, bot_board, gen, float(skills.get("foresight", 1.0))))
				* float(skills.get("bid_scale", 1.0))))
		return nb if nb <= budget and nb <= cap else 0
	# Keep raising while the next bid is both affordable (leaving one unit
	# of headroom rather than spending the color down to zero) and still
	# within what the card looks like it's actually worth. Every difficulty
	# now consults the same real valuation (BotScoring.estimate_bid_value)
	# — Easy used to never bid at all (bid_ev gate always false, card worth
	# never even computed), and Normal only ever compared the bid against
	# raw supply with no notion of the card's value at all. Easy/Normal
	# stay more cautious than Hard's full EV via a willingness discount —
	# the same idea _score_play already applies (0.8x) when Hard considers
	# starting an auction in the first place — rather than bidding right up
	# to the estimate like Hard does.
	var next_bid: int = current_bid + 1
	if next_bid > budget - 1:
		return 0
	var worth: int = BotScoring.estimate_bid_value(card, is_adv, bot_board)
	var willingness: float = 1.0
	match difficulty:
		Difficulty.EASY:
			willingness = 0.5
		Difficulty.NORMAL:
			willingness = 0.75
	return next_bid if next_bid <= worth * willingness else 0


# ── Fuse & recycle (free actions, called before the main action) ────────────

# Returns an ordered list of {source, target} 2:1 fuses (SupplyUI.FUSE_MAP)
# worth performing before deciding the main action. Only ever fuses when the
# fuses actually make a play affordable, and only for a play better than the
# best one already affordable — fusing loses half the supply, so a fuse that
# doesn't unlock anything (or unlocks something the bot didn't need) is pure
# waste. Hard used to do exactly that: it fused toward lower-ranked plays even
# with its top play already affordable, and kept fusing toward plays it still
# couldn't reach, burning up to 10 supply a turn for nothing — one reason
# Normal tended to beat it. Reactive (Normal) only considers the single best
# play with up to 2 fuses; proactive (Hard) walks down the ranked plays with
# up to 5. Only direct (one-hop) fuses — no Dust→Metals→Electrix chains.
static func suggest_fuses(
	difficulty: int, hand: Array[CardData], supplies: Dictionary,
	bot_board: Array, market_sectors: Array[CardData], gen: int = 2
) -> Array[Dictionary]:
	var skills: Dictionary = skills_for(difficulty)
	var mode: String = String(skills.get("fuse", "off"))
	if mode == "off":
		return []
	var candidates: Array[Dictionary] = _all_sector_plays(market_sectors, bot_board)
	candidates.append_array(_all_tech_plays(hand, bot_board))
	if candidates.is_empty():
		return []
	if bool(skills.get("value_model", false)):
		candidates = _worthwhile(rank_by_value(candidates, bot_board, gen, float(skills.get("foresight", 1.0))))
		if candidates.is_empty():
			return []
	else:
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _score_play(a, bot_board, skills) > _score_play(b, bot_board, skills))

	var max_ops: int = 5 if mode == "proactive" else 2
	var scan_limit: int = candidates.size() if mode == "proactive" else 1
	for i: int in mini(scan_limit, candidates.size()):
		var cand: Dictionary = candidates[i]
		if _is_affordable(cand, supplies):
			return []   # the best play within reach needs no fusing
		var plan: Array[Dictionary] = _plan_fuses_to_afford(cand, supplies, max_ops)
		if not plan.is_empty():
			return plan
	return []

# The fuses that make `play` affordable, or [] if it can't be reached within
# max_ops direct fuses.
static func _plan_fuses_to_afford(play: Dictionary, supplies: Dictionary, max_ops: int) -> Array[Dictionary]:
	var working: Dictionary = supplies.duplicate()
	var fuses: Array[Dictionary] = []
	for _op: int in max_ops:
		var f: Dictionary = _find_fuse_toward(_play_color(play), working)
		if f.is_empty():
			return []
		working[int(f["source"])] = (working.get(int(f["source"]), 0) as int) - 2
		working[int(f["target"])] = (working.get(int(f["target"]), 0) as int) + 1
		fuses.append(f)
		if _is_affordable(play, working):
			return fuses
	return []

static func _find_fuse_toward(target_color: int, supplies: Dictionary) -> Dictionary:
	var best_source: int = -1
	var best_amount: int = 1  # need at least 2 to fuse
	if FleetRules.blocks_fuse(target_color):   # Fleet: Smelter Accident / Anti-Fusion Field
		return {}
	for source: int in SupplyUI.FUSE_MAP:
		var dsts: Array = SupplyUI.FUSE_MAP[source] as Array
		if not dsts.has(target_color) or FleetRules.blocks_fuse(source):
			continue
		var have: int = supplies.get(source, 0) as int
		if have >= 2 and have > best_amount:
			best_amount = have
			best_source = source
	if best_source == -1:
		return {}
	return {source = best_source, target = target_color}

# Returns a single hand card worth recycling for supply because doing so
# would unlock (or move closer to unlocking) the best currently-unaffordable
# candidate play — or null if recycling wouldn't help right now.
static func suggest_recycle(
	difficulty: int, hand: Array[CardData], supplies: Dictionary,
	bot_board: Array, market_sectors: Array[CardData], gen: int = 2
) -> CardData:
	var skills: Dictionary = skills_for(difficulty)
	if not bool(skills.get("recycle", false)) or hand.is_empty():
		return null
	var candidates: Array[Dictionary] = _all_sector_plays(market_sectors, bot_board)
	candidates.append_array(_all_tech_plays(hand, bot_board))
	if candidates.is_empty():
		return null
	if bool(skills.get("value_model", false)):
		candidates = _worthwhile(rank_by_value(candidates, bot_board, gen, float(skills.get("foresight", 1.0))))
	else:
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _score_play(a, bot_board, skills) > _score_play(b, bot_board, skills))
	# Only when the recycled supply actually makes a play affordable — a card
	# recycled just to get "closer" was a card thrown away for nothing.
	for play: Dictionary in candidates:
		if _is_affordable(play, supplies):
			continue
		var needed: int = _play_color(play)
		# Fleet: Pandemic / Barbarism forbid the recycle, Mining Incident / Smelter Accident the gain
		if FleetRules.blocks_recycle(needed) or FleetRules.blocks_gain(needed):
			continue
		for card: CardData in hand:
			if int(card.color) != needed or card == play.get("card"):
				continue
			var after: Dictionary = supplies.duplicate()
			after[needed] = (after.get(needed, 0) as int) + CardData.recycle_amount(card)
			if _is_affordable(play, after):
				return card
	return null

## Plays worth their supply (BotValue), in rank order.
static func _worthwhile(ranked: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in ranked:
		if float(p.get("_value", 0.0)) > 0.0:
			out.append(p)
	return out

static func pick_stack_slot(bot_board: Array, card: CardData, difficulty: int, gen: int = 2) -> int:
	var skills: Dictionary = skills_for(difficulty)
	if bool(skills.get("value_model", false)):
		return BotValue.best_slot(bot_board, card, gen, float(skills.get("foresight", 1.0)))
	var best_idx: int = -1
	var best_score: float = -INF
	for i: int in bot_board.size():
		var slot: Dictionary = bot_board[i] as Dictionary
		var techs: Array = slot.get("techs", []) as Array
		if techs.size() >= TECH_CAPACITY:
			continue
		var score: float = 0.0
		if bool(skills.get("optimize_aware", false)) and _would_trigger_optimize(slot, card):
			score += 6.0
		if best_idx == -1 or score > best_score:
			best_idx = i
			best_score = score
	return best_idx


# ── Scoring ────────────────────────────────────────────────────────────────────

static func _score_play(play: Dictionary, bot_board: Array, skills: Dictionary) -> float:
	var card: CardData = play["card"] as CardData
	var score: float = BotScoring.card_value(card)
	if not bool(skills.get("rich_valuation", false)):
		if play["type"] == "place_tech":
			var slot_idx: int = int(play.get("slot_idx", -1))
			if slot_idx >= 0 and slot_idx < bot_board.size():
				var slot: Dictionary = bot_board[slot_idx] as Dictionary
				var techs: Array = slot.get("techs", []) as Array
				if techs.size() + 1 >= TECH_CAPACITY:
					score += 5.0
		return score

	if play["type"] == "place_tech":
		var slot_idx: int = int(play.get("slot_idx", -1))
		if slot_idx >= 0 and slot_idx < bot_board.size():
			var slot: Dictionary = bot_board[slot_idx] as Dictionary
			score += _tech_effect_payoff(slot, card)
			if bool(skills.get("optimize_aware", false)) and _would_trigger_optimize(slot, card):
				score += 6.0
	elif play["type"] == "buy_sector" or play["type"] == "buy_adv_sector":
		if bool(skills.get("optimize_aware", false)):
			score += 0.5 * float(OptimizeLogic.max_optimizations(card, play["type"] == "buy_adv_sector"))
	elif play["type"] == "start_auction" and bool(skills.get("bid_ev", false)):
		# estimate_bid_value is a standalone worth estimate (same one decide_bid
		# uses to judge raises), not a bonus on top of card_value — replace the
		# base score rather than add to it. Discounted a bit versus a
		# guaranteed buy_sector/place_tech, since starting an auction risks
		# spending the turn's major action and still losing the card to a
		# higher bid.
		score = float(BotScoring.estimate_bid_value(card, false, bot_board)) * 0.8
	return score

# Simulates placing `card` on `slot` and estimates the resulting PlaceEffects payoff.
static func _tech_effect_payoff(slot: Dictionary, card: CardData) -> float:
	var sim: Dictionary = slot.duplicate()
	var sim_techs: Array = (slot.get("techs", []) as Array).duplicate()
	sim_techs.append(card)
	sim["techs"] = sim_techs
	var steps: Array[Dictionary] = PlaceEffects.get_steps_for_state(
		card, BotScoring.is_slot_new(sim), BotScoring.is_slot_complete(sim),
		BotScoring.is_slot_optimized(sim), BotScoring.slot_effective_placed_colors(sim))
	return BotScoring.effect_payoff(steps)

static func _would_trigger_optimize(slot: Dictionary, new_card: CardData) -> bool:
	var sector: CardData = slot.get("sector") as CardData
	if sector == null:
		return false
	var max_opt: int = int(slot.get("max_optimizations", 0))
	var cur_count: int = int(slot.get("optimize_count", 0))
	if max_opt <= 0 or cur_count >= max_opt:
		return false
	var effective_colors: Array[int] = BotScoring.slot_tech_colors(slot)   # tanks: placed cards only
	effective_colors.append(int(new_card.color))
	if infested(sector, bool(slot.get("is_advanced", false)), effective_colors):
		return false
	var triggered_copy: Array[bool] = (slot.get("triggered_levels", []) as Array[bool]).duplicate()
	var result: Dictionary = OptimizeLogic.update_optimize_state(
		sector, bool(slot.get("is_advanced", false)), effective_colors, cur_count, max_opt, triggered_copy)
	return int(result["optimize_count"]) > cur_count


# ── Candidate generation ───────────────────────────────────────────────────────

static func _all_sector_plays(market_sectors: Array[CardData], bot_board: Array) -> Array[Dictionary]:
	var plays: Array[Dictionary] = []
	if bot_board.size() >= MAX_SECTORS:
		return plays
	for card: CardData in market_sectors:
		plays.append({type = "buy_sector", card = card})
	return plays

static func _all_tech_plays(hand: Array[CardData], bot_board: Array) -> Array[Dictionary]:
	var plays: Array[Dictionary] = []
	for i: int in bot_board.size():
		var slot: Dictionary = bot_board[i] as Dictionary
		var techs: Array = slot.get("techs", []) as Array
		if techs.size() >= TECH_CAPACITY:
			continue
		for card: CardData in hand:
			if card.card_type != CardData.CardType.TECH:
				continue
			# the cost on this sector, with the bot's own discounts (Seasons/Day-Night only here)
			plays.append({type = "place_tech", card = card, slot_idx = i, cost = tech_cost(card, bot_board, i)})
	return plays

## Generation Fleet: the market's advanced sectors at their printed cost (+ Danger surcharges).
static func _all_adv_sector_plays(market_adv_sectors: Array[CardData], bot_board: Array) -> Array[Dictionary]:
	var plays: Array[Dictionary] = []
	if bot_board.size() >= MAX_SECTORS:
		return plays
	for card: CardData in market_adv_sectors:
		plays.append({type = "buy_adv_sector", card = card, color = int(card.adv_color),
				cost = maxi(0, card.adv_cost) + FleetRules.cost_increase(card, true)})
	return plays

## A tech's cost for a bot placing it on bot_board[slot_idx]: Board.get_purchase_discount over the
## bot's ship (Waste Management, the Academies, Cloning Lab, Skyhook anywhere; Day-Night Cycle /
## Seasons when on top of that sector), none under Totalitarianism, plus the Fleet surcharges.
static func tech_cost(card: CardData, bot_board: Array, slot_idx: int) -> int:
	var discount: int = 0
	if card.card_type == CardData.CardType.TECH and not FleetRules.always_effects_off():
		for i: int in bot_board.size():
			var techs: Array = (bot_board[i] as Dictionary).get("techs", []) as Array
			for j: int in techs.size():
				if not (techs[j] is CardData):
					continue   # a destroyed card has no effect
				var on_top: bool = i == slot_idx and j == techs.size() - 1
				match (techs[j] as CardData).card_name:
					"Waste Management":
						if card.color == CardData.SupplyColor.LIQUIDS:
							discount += 1
					"Industrial Academy":
						if card.color == CardData.SupplyColor.METALS:
							discount += 1
					"Cloning Lab":
						if card.color == CardData.SupplyColor.ORGANIX:
							discount += 1
					"Physics Academy":
						if card.color == CardData.SupplyColor.ELECTRIX:
							discount += 1
					"Skyhook":
						if card.is_star_card:
							discount += 1
					"Day-Night Cycle":
						if on_top:
							discount += 1
					"Seasons":
						if on_top:
							discount += 2
	return maxi(0, maxi(0, card.cost) - discount + FleetRules.cost_increase(card))

## How a bot pays cost of color, as Board._compute_payment: the colour itself first, then the higher
## supplies of its chain. {} when it can't (or when there's nothing to pay).
static func bot_payment(supplies: Dictionary, color: int, cost: int) -> Dictionary:
	var result: Dictionary = {}
	var remaining: int = cost
	for c: CardData.SupplyColor in CardData.valid_payment_colors(color as CardData.SupplyColor):
		if remaining <= 0:
			break
		var available: int = int(supplies.get(int(c), 0))
		if available <= 0:
			continue
		var take: int = mini(available, remaining)
		result[int(c)] = take
		remaining -= take
	if remaining > 0:
		return {}
	return result

static func can_pay(supplies: Dictionary, color: int, cost: int) -> bool:
	return cost <= 0 or not bot_payment(supplies, color, cost).is_empty()

## Takes cost of color out of supplies (in place) along the payment chain. Short of it (shouldn't
## happen: plays are checked with can_pay first), it takes what the colour itself has.
static func pay_supplies(supplies: Dictionary, color: int, cost: int) -> void:
	if cost <= 0:
		return
	var plan: Dictionary = bot_payment(supplies, color, cost)
	if plan.is_empty():
		supplies[color] = maxi(0, int(supplies.get(color, 0)) - cost)
		return
	for c: Variant in plan:
		supplies[int(c)] = int(supplies.get(int(c), 0)) - int(plan[c])

## Fleet: Infestation — no new optimize level on a sector with any Organix card: one on it (its tank
## colours) or the sector card itself on its Organix side (as Board._infested).
static func infested(sector: CardData, is_adv: bool, tank_colors: Array[int]) -> bool:
	if not FleetRules.blocks_optimize_with_organix():
		return false
	return tank_colors.has(int(CardData.SupplyColor.ORGANIX)) \
			or (sector != null and CardData.effective_color(sector, is_adv) == CardData.SupplyColor.ORGANIX)

static func _get_affordable_sector_plays(market_sectors: Array[CardData], supplies: Dictionary, bot_board: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for play: Dictionary in _all_sector_plays(market_sectors, bot_board):
		if _is_affordable(play, supplies):
			result.append(play)
	return result

static func _get_affordable_tech_plays(hand: Array[CardData], supplies: Dictionary, bot_board: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for play: Dictionary in _all_tech_plays(hand, bot_board):
		if _is_affordable(play, supplies):
			result.append(play)
	return result

# Expeditions attach to an existing sector's tech stack if won (mirrors Tech
# cards), so starting an auction is only offered as a candidate when there's
# actually somewhere to put the card — otherwise a won auction just spends
# the turn's major action on a card that gets recycled away for lack of room.
static func _all_auction_plays(market_expeditions: Array[CardData], bot_board: Array) -> Array[Dictionary]:
	var plays: Array[Dictionary] = []
	if not _any_slot_has_tech_room(bot_board):
		return plays
	for card: CardData in market_expeditions:
		plays.append({type = "start_auction", card = card})
	return plays

static func _any_slot_has_tech_room(bot_board: Array) -> bool:
	for slot_v: Variant in bot_board:
		var slot: Dictionary = slot_v as Dictionary
		var techs: Array = slot.get("techs", []) as Array
		if techs.size() < TECH_CAPACITY:
			return true
	return false

static func _get_affordable_auction_plays(market_expeditions: Array[CardData], supplies: Dictionary, bot_board: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for play: Dictionary in _all_auction_plays(market_expeditions, bot_board):
		if _is_affordable(play, supplies):
			result.append(play)
	return result

static func _is_affordable(play: Dictionary, supplies: Dictionary) -> bool:
	var card: CardData = play["card"] as CardData
	# Fleet: Barbarism — no Thrust card placed: expeditions (bought and placed in Fleet) and an
	# advanced sector's Thrust side included (as Board._refuse_fleet_blocked)
	if str(play.get("type", "")) in ["place_tech", "start_auction", "buy_adv_sector"] and FleetRules.blocks_place(_play_color(play)):
		return false
	var cost: int = int(play.get("cost", maxi(0, card.cost) + FleetRules.cost_increase(card)))
	return can_pay(supplies, _play_color(play), cost)

static func _play_color(play: Dictionary) -> int:
	return int(play.get("color", int((play["card"] as CardData).color)))
