class_name BotAI
extends RefCounted

enum Difficulty { EASY = 0, NORMAL = 1, HARD = 2 }

const _TECH_CAPACITY: int = 3

# Returns {type, card?, slot_idx?}
# type: "pass" | "research" | "place_sector" | "place_tech"
static func decide_action(
	difficulty: int,
	hand: Array[CardData],
	supplies: Dictionary,
	bot_board: Array,
	_round: int
) -> Dictionary:
	var sectors: Array[Dictionary] = _get_affordable_sector_plays(hand, supplies)
	var techs: Array[Dictionary] = _get_affordable_tech_plays(hand, supplies, bot_board)

	match difficulty:
		Difficulty.EASY:
			return _decide_easy(sectors, techs, hand)
		Difficulty.NORMAL:
			return _decide_normal(sectors, techs, hand, bot_board)
		Difficulty.HARD:
			return _decide_hard(sectors, techs, hand, bot_board)
	return {type = "pass"}


static func decide_bid(
	difficulty: int,
	current_bid: int,
	supplies: Dictionary,
	card: CardData,
	is_adv: bool
) -> int:
	var color: int = int(card.adv_color if is_adv else card.color)
	var budget: int = supplies.get(color, 0) as int
	match difficulty:
		Difficulty.EASY:
			return 0
		Difficulty.NORMAL:
			return current_bid + 1 if current_bid < budget / 2 else 0
		Difficulty.HARD:
			return current_bid + 1 if current_bid < budget - 1 else 0
	return 0


# ── Difficulty strategies ──────────────────────────────────────────────────────

static func _decide_easy(sectors: Array[Dictionary], techs: Array[Dictionary], _hand: Array[CardData]) -> Dictionary:
	var all: Array[Dictionary] = sectors + techs
	if all.is_empty() or randf() < 0.35:
		return {type = "pass"}
	return all[randi() % all.size()]


static func _decide_normal(
	sectors: Array[Dictionary], techs: Array[Dictionary],
	_hand: Array[CardData], bot_board: Array
) -> Dictionary:
	var all: Array[Dictionary] = sectors + techs
	if all.is_empty():
		return {type = "pass"}
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _score_play(a, bot_board, false) > _score_play(b, bot_board, false))
	return all[0]


static func _decide_hard(
	sectors: Array[Dictionary], techs: Array[Dictionary],
	hand: Array[CardData], bot_board: Array
) -> Dictionary:
	var all: Array[Dictionary] = sectors + techs
	if all.is_empty():
		# Research: discard lowest-cost card if we have options
		if hand.size() > 1:
			var sorted: Array[CardData] = hand.duplicate()
			sorted.sort_custom(func(a: CardData, b: CardData) -> bool: return a.cost < b.cost)
			return {type = "research", card = sorted[0]}
		return {type = "pass"}
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _score_play(a, bot_board, true) > _score_play(b, bot_board, true))
	return all[0]


# ── Scoring ────────────────────────────────────────────────────────────────────

static func _score_play(play: Dictionary, bot_board: Array, advanced: bool) -> float:
	var card: CardData = play["card"] as CardData
	var score: float = float(card.stars) * 2.0
	if card.is_star_card:
		score += 3.0 if not advanced else 3.0
	if play["type"] == "place_tech":
		var slot_idx: int = play["slot_idx"] as int
		if slot_idx >= 0 and slot_idx < bot_board.size():
			var slot: Dictionary = bot_board[slot_idx] as Dictionary
			var techs: Array = slot.get("techs", []) as Array
			if techs.size() + 1 >= _TECH_CAPACITY:
				score += 8.0 if advanced else 5.0
	return score


# ── Candidate generation ───────────────────────────────────────────────────────

static func _get_affordable_sector_plays(hand: Array[CardData], supplies: Dictionary) -> Array[Dictionary]:
	var plays: Array[Dictionary] = []
	for card: CardData in hand:
		if card.card_type != CardData.CardType.SECTOR:
			continue
		var avail: int = supplies.get(int(card.color), 0) as int
		if avail >= max(0, card.cost):
			plays.append({type = "place_sector", card = card})
	return plays


static func _get_affordable_tech_plays(
	hand: Array[CardData], supplies: Dictionary, bot_board: Array
) -> Array[Dictionary]:
	var plays: Array[Dictionary] = []
	for i: int in bot_board.size():
		var slot: Dictionary = bot_board[i] as Dictionary
		var techs: Array = slot.get("techs", []) as Array
		if techs.size() >= _TECH_CAPACITY:
			continue
		for card: CardData in hand:
			if card.card_type != CardData.CardType.TECH:
				continue
			var avail: int = supplies.get(int(card.color), 0) as int
			if avail >= max(0, card.cost):
				plays.append({type = "place_tech", card = card, slot_idx = i})
				break  # one play per slot per card is enough
	return plays
