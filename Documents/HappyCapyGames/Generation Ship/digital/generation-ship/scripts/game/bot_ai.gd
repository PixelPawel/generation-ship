class_name BotAI
extends RefCounted

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
	market_expeditions: Array[CardData]
) -> Dictionary:
	var skills: Dictionary = skills_for(difficulty)
	var candidates: Array[Dictionary] = _get_affordable_sector_plays(market_sectors, supplies, bot_board)
	candidates.append_array(_get_affordable_tech_plays(hand, supplies, bot_board))
	candidates.append_array(_get_affordable_auction_plays(market_expeditions, supplies, bot_board))

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
	bot_board: Array
) -> int:
	var skills: Dictionary = skills_for(difficulty)
	var color: int = int(card.adv_color if is_adv else card.color)
	var budget: int = supplies.get(color, 0) as int
	if not bool(skills.get("bid_ev", false)):
		match difficulty:
			Difficulty.NORMAL:
				return current_bid + 1 if current_bid < budget / 2.0 else 0
		return 0  # Easy never bids
	# Hard: keep raising while the next bid is both affordable and still
	# within what the card looks like it's actually worth.
	var next_bid: int = current_bid + 1
	if next_bid > budget - 1:
		return 0
	var worth: int = BotScoring.estimate_bid_value(card, is_adv, bot_board)
	return next_bid if next_bid <= worth else 0


# ── Fuse & recycle (free actions, called before the main action) ────────────

# Returns an ordered list of {source, target} 2:1 fuses (SupplyUI.FUSE_MAP)
# worth performing before deciding the main action — reactive (Normal) only
# fuses toward the single best candidate play; proactive (Hard) will also
# fuse toward lower-ranked candidates if the top one can't be unlocked, up
# to a higher cap. Only ever chases a direct (one-hop) fuse per candidate —
# it won't chain e.g. Dust→Metals→Electrix to reach a two-tier-away color.
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
	var working: Dictionary = supplies.duplicate()
	var fuses: Array[Dictionary] = []
	for _op: int in max_ops:
		var progressed: bool = false
		for i: int in mini(scan_limit, candidates.size()):
			var cand: Dictionary = candidates[i]
			if _is_affordable(cand, working):
				continue
			var f: Dictionary = _find_fuse_toward(_play_color(cand), working)
			if f.is_empty():
				continue
			working[int(f["source"])] = (working.get(int(f["source"]), 0) as int) - 2
			working[int(f["target"])] = (working.get(int(f["target"]), 0) as int) + 1
			fuses.append(f)
			progressed = true
			break
		if not progressed:
			break
	return fuses

static func _find_fuse_toward(target_color: int, supplies: Dictionary) -> Dictionary:
	var best_source: int = -1
	var best_amount: int = 1  # need at least 2 to fuse
	for source: int in SupplyUI.FUSE_MAP:
		var dsts: Array = SupplyUI.FUSE_MAP[source] as Array
		if not dsts.has(target_color):
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
	for play: Dictionary in candidates:
		if _is_affordable(play, supplies):
			continue
		var needed: int = _play_color(play)
		for card: CardData in hand:
			if int(card.color) == needed and card != play.get("card"):
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
	elif play["type"] == "buy_sector":
		if bool(skills.get("optimize_aware", false)):
			score += 0.5 * float(OptimizeLogic.max_optimizations(card, false))
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
	var raw_colors: Array[int] = BotScoring.slot_raw_placed_colors(sim)
	var steps: Array[Dictionary] = PlaceEffects.get_steps_for_state(
		card, BotScoring.is_slot_new(sim), BotScoring.is_slot_complete(sim),
		BotScoring.is_slot_optimized(sim), raw_colors)
	return BotScoring.effect_payoff(steps)

static func _would_trigger_optimize(slot: Dictionary, new_card: CardData) -> bool:
	var sector: CardData = slot.get("sector") as CardData
	if sector == null:
		return false
	var max_opt: int = int(slot.get("max_optimizations", 0))
	var cur_count: int = int(slot.get("optimize_count", 0))
	if max_opt <= 0 or cur_count >= max_opt:
		return false
	var effective_colors: Array[int] = BotScoring.slot_effective_placed_colors(slot)
	effective_colors.append(int(new_card.color))
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
			plays.append({type = "place_tech", card = card, slot_idx = i})
	return plays

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
	var avail: int = supplies.get(int(card.color), 0) as int
	return avail >= max(0, card.cost)

static func _play_color(play: Dictionary) -> int:
	return int((play["card"] as CardData).color)
