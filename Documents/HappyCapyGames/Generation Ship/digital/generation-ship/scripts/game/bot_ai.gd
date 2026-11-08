class_name BotAI
extends RefCounted
const FleetRules = preload("res://scripts/game/fleet_rules.gd")

enum Difficulty { EASY = 0, NORMAL = 1, HARD = 2 }

const TECH_CAPACITY: int = 5   # matches SectorSlot's 5 tech-slot children
const MAX_SECTORS: int = 6     # matches the "max 6 sectors" ship rule

# Skill flags per difficulty. Hard has every skill on with the richest
# valuation; Normal gets a reduced subset; Easy stays close to its original
# mostly-random, easily-beatable baseline. Rule resolution (card effects,
# optimize triggers) is NOT gated here — that happens uniformly for every
# bot in bot_turn.gd, since that's just playing the game correctly, not a
# difficulty-scaled skill.
static func skills_for(difficulty: int) -> Dictionary:
	match difficulty:
		Difficulty.HARD:
			return {
				rich_valuation = true, optimize_aware = true, fuse = "proactive",
				recycle = true, bid_ev = true, can_research = true, smart_research = true,
				randomness = 0.0,
			}
		Difficulty.NORMAL:
			return {
				rich_valuation = true, optimize_aware = true, fuse = "reactive",
				recycle = false, bid_ev = false, can_research = true, smart_research = false,
				randomness = 0.0,
			}
		_:
			return {
				rich_valuation = false, optimize_aware = false, fuse = "off",
				recycle = false, bid_ev = false, can_research = false, smart_research = false,
				randomness = 0.35,
			}

# Returns {type, card?, slot_idx?}
# type: "pass" | "research" | "buy_sector" | "place_tech" | "start_auction"
static func decide_action(
	difficulty: int,
	hand: Array[CardData],
	supplies: Dictionary,
	bot_board: Array,
	_round: int,
	market_sectors: Array[CardData],
	market_expeditions: Array[CardData],
	market_adv_sectors: Array[CardData] = []
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

	if candidates.is_empty():
		return _decide_research_or_pass(hand, supplies, skills)

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _score_play(a, bot_board, skills) > _score_play(b, bot_board, skills))
	return candidates[0]

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
	cost_color: int = -1
) -> int:
	# cost_color is the auction's actual payment color, which Wormhole
	# Surfing can change away from the card's own.
	var color: int = cost_color if cost_color >= 0 else int(card.adv_color if is_adv else card.color)
	# a bid can be paid with the higher supplies of the colour's chain too, as the humans' bids
	var budget: int = 0
	for c: CardData.SupplyColor in CardData.valid_payment_colors(color as CardData.SupplyColor):
		budget += int(supplies.get(int(c), 0))
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
	bot_board: Array, market_sectors: Array[CardData]
) -> Array[Dictionary]:
	var skills: Dictionary = skills_for(difficulty)
	var mode: String = String(skills.get("fuse", "off"))
	if mode == "off":
		return []
	var candidates: Array[Dictionary] = _all_sector_plays(market_sectors, bot_board)
	candidates.append_array(_all_tech_plays(hand, bot_board))
	if candidates.is_empty():
		return []
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
	bot_board: Array, market_sectors: Array[CardData]
) -> CardData:
	var skills: Dictionary = skills_for(difficulty)
	if not bool(skills.get("recycle", false)) or hand.is_empty():
		return null
	var candidates: Array[Dictionary] = _all_sector_plays(market_sectors, bot_board)
	candidates.append_array(_all_tech_plays(hand, bot_board))
	if candidates.is_empty():
		return null
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

static func pick_stack_slot(bot_board: Array, card: CardData, difficulty: int) -> int:
	var skills: Dictionary = skills_for(difficulty)
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
