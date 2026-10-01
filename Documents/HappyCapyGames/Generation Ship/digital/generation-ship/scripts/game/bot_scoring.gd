class_name BotScoring
extends RefCounted

# VP estimator against a lightweight Dictionary board model, decoupled from
# any live SectorSlot/Node3D scene tree — used for bot decision-making and
# the bot's end-game scoreboard line, and reused as the scoring core for the
# photo-scan feature (which reconstructs a board from a tableau photo with no
# live game session at all). Ports every formula from Scoring.gd, the
# authoritative scorer for a real Node3D board, so board_vp_lines()/board_vp()
# match Scoring.calculate() exactly for an equivalent board state.

# A "choice" step's option "steps" list is written as a plain Dictionary-
# literal array in place_effects.gd/score_effects.gd/etc. (e.g. `steps =
# [{type = "gain_supply", ...}]`), so at runtime it's an untyped Array even
# though every element is a Dictionary. GDScript's "as Array[Dictionary]"
# only succeeds when the source array already carries that type tag from
# creation — it errors on a plain Array, however uniform its contents —
# so callers must convert element-by-element instead of casting directly.
static func to_dict_array(raw: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Variant in raw:
		result.append(item as Dictionary)
	return result

const SECTOR_STORED_BONUS: Dictionary = {
	"Greenhouse": {"color": CardData.SupplyColor.LIQUIDS, "per": 1},
	"Astra Cultura": {"color": CardData.SupplyColor.THRUST, "per": 2},
}

const STACK_CAPACITY: int = 5  # matches SectorSlot's 5 tech-slot children

static func is_slot_new(slot: Dictionary) -> bool:
	return (slot.get("techs", []) as Array).size() == 1

static func is_slot_complete(slot: Dictionary) -> bool:
	return (slot.get("techs", []) as Array).size() >= STACK_CAPACITY

static func is_slot_optimized(slot: Dictionary) -> bool:
	var max_opt: int = int(slot.get("max_optimizations", 0))
	return max_opt > 0 and int(slot.get("optimize_count", 0)) >= max_opt

static func slot_total_stored(slot: Dictionary) -> int:
	var total: int = 0
	for count: Variant in (slot.get("stored_supply", {}) as Dictionary).values():
		total += int(count)
	return total

static func slot_effective_color(slot: Dictionary) -> int:
	var sector: CardData = slot.get("sector") as CardData
	if sector == null:
		return -1
	return int(CardData.effective_color(sector, bool(slot.get("is_advanced", false))))

# Effective colors (advanced sector's adv_color where relevant) of every card
# on the slot — matches PlaceEffects/SectorEffects' use of CardData.effective_color.
static func slot_effective_placed_colors(slot: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var sector: CardData = slot.get("sector") as CardData
	var is_adv: bool = bool(slot.get("is_advanced", false))
	if sector:
		result.append(int(CardData.effective_color(sector, is_adv)))
	for t: Variant in (slot.get("techs", []) as Array):
		if t is CardData:
			result.append(int((t as CardData).color))
	return result

static func slot_cards(slot: Dictionary) -> Array[CardData]:
	var result: Array[CardData] = []
	var sector: CardData = slot.get("sector") as CardData
	if sector:
		result.append(sector)
	for t: Variant in (slot.get("techs", []) as Array):
		if t is CardData:
			result.append(t as CardData)
	return result

static func _all_cards(board: Array) -> Array[CardData]:
	var result: Array[CardData] = []
	for entry: Variant in board:
		result.append_array(slot_cards(entry as Dictionary))
	return result

static func _count_by_color(cards: Array[CardData], color: int) -> int:
	var n: int = 0
	for cd: CardData in cards:
		if int(cd.color) == color:
			n += 1
	return n

# ── Board-wide VP ────────────────────────────────────────────────────────────

static func board_vp_lines(board: Array) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var all_cards: Array[CardData] = _all_cards(board)

	var stars: int = 0
	for cd: CardData in all_cards:
		if cd.stars > 0 and cd.card_type != CardData.CardType.SECTOR and not _is_conditional_tech(cd.card_name):
			stars += cd.stars
	_add(lines, "Stars", stars)

	var faceup_tuck: int = 0
	var facedown_tuck: int = 0
	for entry: Variant in board:
		for tuck: Variant in ((entry as Dictionary).get("tucked_cards", []) as Array):
			var t: Dictionary = tuck as Dictionary
			if bool(t.get("face_up", false)):
				var cd: CardData = t.get("data") as CardData
				if cd:
					faceup_tuck += cd.stars
			else:
				facedown_tuck += 1
	_add(lines, "Faceup archived", faceup_tuck)
	_add(lines, "Facedown archived", facedown_tuck)

	var stored_total: int = 0
	for entry: Variant in board:
		var slot: Dictionary = entry as Dictionary
		stored_total += slot_total_stored(slot)
		var sector: CardData = slot.get("sector") as CardData
		if sector:
			var name: String = sector.adv_name if (bool(slot.get("is_advanced", false)) and not sector.adv_name.is_empty()) else sector.card_name
			var bonus: Dictionary = SECTOR_STORED_BONUS.get(name, {})
			if not bonus.is_empty():
				var stored_supply: Dictionary = slot.get("stored_supply", {}) as Dictionary
				stored_total += stored_supply.get(int(bonus["color"]), 0) * int(bonus["per"])
	_add(lines, "Stored supply", stored_total)

	var expeditions: Array[CardData] = []
	for cd: CardData in all_cards:
		if cd.card_type == CardData.CardType.EXPEDITION:
			expeditions.append(cd)
	for cd: CardData in expeditions:
		_add(lines, cd.card_name, _expedition_vp(cd.card_name, cd.stars, board, all_cards, expeditions))

	for cd: CardData in all_cards:
		if cd.card_type == CardData.CardType.TECH and _is_conditional_tech(cd.card_name):
			_add(lines, cd.card_name, _tech_condition_vp(cd.card_name, board))

	return lines

static func board_vp(board: Array) -> int:
	var total: int = 0
	for line: Dictionary in board_vp_lines(board):
		total += int(line.get("vp", 0))
	return total

static func _add(lines: Array[Dictionary], label: String, vp: int) -> void:
	if vp > 0:
		lines.append({"label": label, "vp": vp})

static func _expedition_vp(name: String, fallback_stars: int, board: Array,
		all_cards: Array[CardData], expeditions: Array[CardData]) -> int:
	match name:
		"Exodus Fleets":
			return 2 * _count_by_color(all_cards, CardData.SupplyColor.THRUST)
		"Compatible World":
			return _count_by_color(all_cards, CardData.SupplyColor.ORGANIX)
		"Hive Mind":
			return _count_by_color(all_cards, CardData.SupplyColor.ELECTRIX)
		"Earth 2.0":
			var count: int = 0
			for cd: CardData in all_cards:
				if cd.is_star_card:
					count += 1
			return 2 * count
		"Pleasure Planet":
			var colors: Dictionary = {}
			for cd: CardData in expeditions:
				colors[int(cd.color)] = true
			return 3 * colors.size()
		"Aeon Ark":
			var colors: Dictionary = {}
			for entry: Variant in board:
				var c: int = slot_effective_color(entry as Dictionary)
				if c >= 0:
					colors[c] = true
			return 2 * colors.size()
		"Waterworld":
			var count: int = 0
			for entry: Variant in board:
				for cd: CardData in slot_cards(entry as Dictionary):
					if int(cd.color) == CardData.SupplyColor.LIQUIDS:
						count += 1
						break
			return 2 * count
		"Millions of Colonists":
			var count: int = 0
			for entry: Variant in board:
				if is_slot_complete(entry as Dictionary):
					count += 1
			return 2 * count
		"Lagrange Complex":
			var count: int = 0
			for entry: Variant in board:
				if is_slot_optimized(entry as Dictionary):
					count += 1
			return 2 * count
		"Cloud Colony":
			var count: int = 0
			for entry: Variant in board:
				var slot: Dictionary = entry as Dictionary
				if is_slot_complete(slot) and is_slot_optimized(slot):
					count += 1
			return 3 * count
		"Interstellar Trade Port":
			var count: int = 0
			for entry: Variant in board:
				if slot_total_stored(entry as Dictionary) >= 2:
					count += 1
			return 2 * count
		"Astrobio Propagation":
			var count: int = 0
			for entry: Variant in board:
				if ((entry as Dictionary).get("tucked_cards", []) as Array).size() >= 2:
					count += 1
			return 3 * count
		"Asteroid Colonies":
			var count: int = 0
			for entry: Variant in board:
				for tuck: Variant in ((entry as Dictionary).get("tucked_cards", []) as Array):
					if not bool((tuck as Dictionary).get("face_up", false)):
						count += 1
			return count

		"Equatorial Superloop":
			# Copy up to 6 VP from the top card in each sector (last entry of
			# slot_cards: the sector card itself, or its topmost placed tech).
			var total: int = 0
			for entry: Variant in board:
				var slot: Dictionary = entry as Dictionary
				var cards: Array[CardData] = slot_cards(slot)
				if not cards.is_empty():
					var top: CardData = cards[cards.size() - 1]
					var top_vp: int
					if top.card_type == CardData.CardType.EXPEDITION and top.card_name != "Equatorial Superloop":
						top_vp = _expedition_vp(top.card_name, top.stars, board, all_cards, expeditions)
					elif top.card_type == CardData.CardType.TECH and _is_conditional_tech(top.card_name):
						top_vp = _tech_condition_vp(top.card_name, board)
					elif top.card_type != CardData.CardType.EXPEDITION:
						top_vp = top.stars
					else:
						top_vp = 0
					total += mini(top_vp, 6)
			return total

		"Urbanized Planet":
			# 15 VP per complete set of all 6 stored supply colors.
			var totals: Dictionary = {}
			for entry: Variant in board:
				var stored: Dictionary = (entry as Dictionary).get("stored_supply", {}) as Dictionary
				for color: Variant in stored:
					totals[int(color)] = int(totals.get(int(color), 0)) + int(stored[color])
			var min_count: int = 9999
			var all_colors: Array[int] = [
				CardData.SupplyColor.DUST, CardData.SupplyColor.METALS,
				CardData.SupplyColor.LIQUIDS, CardData.SupplyColor.ORGANIX,
				CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST,
			]
			for color: int in all_colors:
				min_count = mini(min_count, int(totals.get(color, 0)))
			return 15 * (min_count if min_count < 9999 else 0)

		"Polar Planet":
			# 2 VP per different stored supply color on the best single sector.
			var best: int = 0
			for entry: Variant in board:
				var stored: Dictionary = (entry as Dictionary).get("stored_supply", {}) as Dictionary
				best = maxi(best, stored.size())
			return 2 * best

		"Self Replication":
			# 2 VP per Metals card in the best single sector (including self).
			var best: int = 0
			for entry: Variant in board:
				var count: int = 0
				for cd: CardData in slot_cards(entry as Dictionary):
					if int(cd.color) == CardData.SupplyColor.METALS:
						count += 1
				best = maxi(best, count)
			return 2 * best

		"Alliance":
			return 0  # multiplayer only

	return fallback_stars

static func _is_conditional_tech(name: String) -> bool:
	match name:
		"Tectonic Accelerator", "Magnetosphere", "Genesis Device", "Space Elevator", "Atmosphere Processor":
			return true
	return false

static func _tech_condition_vp(name: String, board: Array) -> int:
	match name:
		"Tectonic Accelerator":  # 6 fully optimized sectors
			var count: int = 0
			for entry: Variant in board:
				if is_slot_optimized(entry as Dictionary):
					count += 1
			return Scoring.CONDITIONAL_TECH_VP if count >= 6 else 0

		"Magnetosphere":  # 9+ tucked cards
			var count: int = 0
			for entry: Variant in board:
				count += ((entry as Dictionary).get("tucked_cards", []) as Array).size()
			return Scoring.CONDITIONAL_TECH_VP if count >= 9 else 0

		"Genesis Device":  # 6+ thrust cards
			var count: int = _count_by_color(_all_cards(board), CardData.SupplyColor.THRUST)
			return Scoring.CONDITIONAL_TECH_VP if count >= 6 else 0

		"Space Elevator":  # 9+ stored supply
			var total: int = 0
			for entry: Variant in board:
				total += slot_total_stored(entry as Dictionary)
			return Scoring.CONDITIONAL_TECH_VP if total >= 9 else 0

		"Atmosphere Processor":  # 6 complete sectors
			var count: int = 0
			for entry: Variant in board:
				if is_slot_complete(entry as Dictionary):
					count += 1
			return Scoring.CONDITIONAL_TECH_VP if count >= 6 else 0

	return 0

# ── Candidate-play valuation (used by BotAI) ──────────────────────────────────

static func card_value(cd: CardData) -> float:
	var v: float = float(cd.stars) * 2.0
	if cd.is_star_card:
		v += 3.0
	return v

# Exodus Fleets/Compatible World/Hive Mind's own printed text is explicit
# that their per-color count includes the card itself ("Gain X per <color>
# card (including this)"). board_vp_lines already gets this right for real,
# already-won cards, since a placed expedition sits in slot_cards() like any
# other card by the time end-game scoring runs — but a bid-time estimate
# has to add it in manually, since the card hasn't actually been won/placed
# yet. Without this, a bot with zero matching-colored cards so far always
# saw these three as worth exactly 0, and could never justify the very bid
# that would start building that color — a chicken-and-egg dead end, not a
# deliberate "not worth it" judgment.
const _INCLUDES_SELF_EXPEDITIONS: PackedStringArray = ["Exodus Fleets", "Compatible World", "Hive Mind"]

# Rough "what is winning this auction worth" estimate for bid EV. For
# expedition cards, reuses the same approximate VP formulas as the end-game
# estimate. For advanced sector cards, falls back to printed stars plus a
# rough optimize-potential bonus.
static func estimate_bid_value(cd: CardData, is_adv: bool, board: Array) -> int:
	if cd.card_type == CardData.CardType.EXPEDITION:
		var all_cards: Array[CardData] = _all_cards(board)
		if _INCLUDES_SELF_EXPEDITIONS.has(cd.card_name):
			all_cards.append(cd)
		var expeditions: Array[CardData] = []
		for c: CardData in all_cards:
			if c.card_type == CardData.CardType.EXPEDITION:
				expeditions.append(c)
		return _expedition_vp(cd.card_name, cd.stars, board, all_cards, expeditions)
	return int(card_value(cd)) + 3 * OptimizeLogic.max_optimizations(cd, is_adv)

# Rough point value of a resolved effect-step list — lets bots prefer plays
# whose card effects actually pay off, without simulating the whole turn.
static func effect_payoff(steps: Array[Dictionary]) -> float:
	var v: float = 0.0
	for step: Dictionary in steps:
		match String(step.get("type", "")):
			"draw", "draw_recycle_top", "draw_all_players":
				v += float(step.get("count", 1)) * 1.5
			"gain_supply", "gain_supply_per_stored", "gain_supply_per_sector_count":
				v += float(step.get("amount", 1)) * 1.0
			"store_on_slot", "store_on_any_sector", "store_per_card_here":
				v += float(step.get("amount", 1)) * 1.0
			"tuck":
				v += float(step.get("count", 1)) * (2.0 if bool(step.get("face_up", false)) else 1.0)
			"tuck_optional", "tuck_any_sector_optional":
				v += float(step.get("max", 1)) * 0.6
			"fuse_notice":
				v += float(step.get("count", 1)) * 0.5
			"recycle_optional":
				v += float(step.get("max", 1)) * 0.4
			"choice":
				var opts: Array = step.get("options", []) as Array
				if not opts.is_empty():
					v += effect_payoff(to_dict_array((opts[0] as Dictionary).get("steps", []) as Array))
	return v
