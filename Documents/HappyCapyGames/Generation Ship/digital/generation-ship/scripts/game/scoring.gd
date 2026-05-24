class_name Scoring
extends RefCounted

# Returns the VP a single expedition card would score given the current board state.
static func get_expedition_vp(card_name: String, sector_row: Node3D) -> int:
	var slots: Array = _occupied_slots(sector_row)
	var all_cards: Array = _all_placed_cards(slots)
	var expeditions: Array = _by_type(all_cards, CardData.CardType.EXPEDITION)
	return _expedition_vp(card_name, slots, expeditions, all_cards)

# Returns Array of {label: String, vp: int}, one entry per scoring source with vp > 0.
static func calculate(sector_row: Node3D) -> Array[Dictionary]:
	var slots: Array = _occupied_slots(sector_row)
	var all_cards: Array = _all_placed_cards(slots)
	var expeditions: Array = _by_type(all_cards, CardData.CardType.EXPEDITION)
	var lines: Array[Dictionary] = []
	_score_stars(lines, all_cards)
	_score_faceup_tucked(lines, slots)
	_score_facedown_tucked(lines, slots)
	_score_stored_supply_base(lines, slots)
	_score_sector_stored(lines, slots)
	_score_expeditions(lines, slots, expeditions, all_cards)
	_score_tech_conditions(lines, slots, all_cards)
	return lines

# ── helpers ──────────────────────────────────────────────────────────────────

static func _occupied_slots(sector_row: Node3D) -> Array:
	var result: Array = []
	for child: Node in sector_row.get_children():
		var slot := child as SectorSlot
		if slot != null and slot.occupied:
			result.append(slot)
	return result

static func _all_placed_cards(slots: Array) -> Array:
	var result: Array = []
	for slot: SectorSlot in slots:
		for card: Node3D in slot.get_all_placed_cards():
			result.append(card)
	return result

static func _by_type(cards: Array, type: CardData.CardType) -> Array:
	var result: Array = []
	for card: Node3D in cards:
		var cd: CardData = card.get("card_data")
		if cd != null and cd.card_type == type:
			result.append(card)
	return result

# Resolves the supply color of a card, respecting is_advanced on sector cards.
static func _card_color(card: Node3D) -> CardData.SupplyColor:
	var cd: CardData = card.get("card_data")
	if cd == null:
		return CardData.SupplyColor.DUST
	return CardData.effective_color(cd, bool(card.get("is_advanced")))

static func _add_line(lines: Array[Dictionary], label: String, vp: int) -> void:
	if vp > 0:
		lines.append({"label": label, "vp": vp})

# ── tucked cards ─────────────────────────────────────────────────────────────

static func _score_faceup_tucked(lines: Array[Dictionary], slots: Array) -> void:
	var total: int = 0
	for slot: SectorSlot in slots:
		for tuck: Dictionary in slot.tucked_cards:
			if tuck.get("face_up", false):
				var cd: CardData = tuck.get("data") as CardData
				if cd:
					total += cd.stars
	_add_line(lines, "Faceup tucked (⭐)", total)

static func _score_facedown_tucked(lines: Array[Dictionary], slots: Array) -> void:
	var total: int = 0
	for slot: SectorSlot in slots:
		for tuck: Dictionary in slot.tucked_cards:
			if not tuck.get("face_up", false):
				total += 1
	_add_line(lines, "Facedown tucked (1 VP each)", total)

# ── base stored-supply VP (1 VP per stored supply on any sector) ─────────────

static func _score_stored_supply_base(lines: Array[Dictionary], slots: Array) -> void:
	var total: int = 0
	for slot: SectorSlot in slots:
		total += slot.get_total_stored_supply()
	_add_line(lines, "Stored supply (1 VP each)", total)

# ── sector stored-supply VP ───────────────────────────────────────────────────

static func _score_sector_stored(lines: Array[Dictionary], slots: Array) -> void:
	for slot: SectorSlot in slots:
		if not slot.placed_card or not slot.placed_card.card_data:
			continue
		var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
		var name: String = slot.placed_card.card_data.adv_name if is_adv else slot.placed_card.card_data.card_name
		match name:
			"Greenhouses":
				# +1 bonus VP per stored Liquids (base gives another 1 VP = 2 VP total per Liquids)
				var vp: int = slot.get_stored_supply(CardData.SupplyColor.LIQUIDS)
				_add_line(lines, "Greenhouses (Liquids bonus)", vp)
			"Astra Cultura":
				# +2 bonus VP per stored Thrust (base gives 1 VP = 3 VP total per Thrust)
				var vp: int = slot.get_stored_supply(CardData.SupplyColor.THRUST) * 2
				_add_line(lines, "Astra Cultura (Thrust bonus)", vp)

# ── stars ─────────────────────────────────────────────────────────────────────

static func _score_stars(lines: Array[Dictionary], all_cards: Array) -> void:
	var total: int = 0
	for card: Node3D in all_cards:
		var cd: CardData = card.get("card_data")
		if cd != null and cd.stars > 0 and cd.card_type != CardData.CardType.SECTOR:
			total += cd.stars
	_add_line(lines, "Stars (⭐)", total)

# ── expedition scoring ────────────────────────────────────────────────────────

static func _score_expeditions(lines: Array[Dictionary], slots: Array, expeditions: Array, all_cards: Array) -> void:
	for card: Node3D in expeditions:
		var cd: CardData = card.get("card_data")
		if cd == null:
			continue
		var vp: int = _expedition_vp(cd.card_name, slots, expeditions, all_cards)
		_add_line(lines, cd.card_name, vp)

static func _expedition_vp(name: String, slots: Array, expeditions: Array, all_cards: Array) -> int:
	match name:
		"Earth 2.0":
			# 2 VP per non-tucked card with printed stars
			var count: int = 0
			for card: Node3D in all_cards:
				var cd: CardData = card.get("card_data")
				if cd != null and cd.is_star_card:
					count += 1
			return 2 * count

		"Exodus Fleets":
			# 2 VP per Thrust card (including self)
			var count: int = 0
			for card: Node3D in all_cards:
				if _card_color(card) == CardData.SupplyColor.THRUST:
					count += 1
			return 2 * count

		"Equatorial Superloop":
			# Copy up to 6 VP from the top card in each sector.
			# For tech top cards use printed stars (or conditional result); for expedition top cards use their current VP.
			var total: int = 0
			for slot: SectorSlot in slots:
				var all: Array[Node3D] = slot.get_all_placed_cards()
				if not all.is_empty():
					var top: Node3D = all[all.size() - 1]
					var cd: CardData = top.get("card_data")
					if cd:
						var top_vp: int
						if cd.card_type == CardData.CardType.EXPEDITION and cd.card_name != "Equatorial Superloop":
							top_vp = _expedition_vp(cd.card_name, slots, expeditions, all_cards)
						elif cd.card_type == CardData.CardType.TECH and _is_conditional_tech(cd.card_name):
							top_vp = _tech_condition_vp(cd.card_name, slots, all_cards)
						elif cd.card_type != CardData.CardType.EXPEDITION:
							top_vp = cd.stars
						else:
							top_vp = 0
						total += mini(top_vp, 6)
			return total

		"Pleasure Planet":
			# 3 VP per unique expedition color
			var colors: Dictionary = {}
			for card: Node3D in expeditions:
				colors[_card_color(card)] = true
			return 3 * colors.size()

		"Bio-Compatible World":
			# 1 VP per Organix card placed (including self)
			var count: int = 0
			for card: Node3D in all_cards:
				if _card_color(card) == CardData.SupplyColor.ORGANIX:
					count += 1
			return count

		"Astrobio Propagation":
			# 3 VP per sector with 2+ tucked cards
			var count: int = 0
			for slot: SectorSlot in slots:
				if slot.tucked_cards.size() >= 2:
					count += 1
			return 3 * count

		"Aeon Ark":
			# 2 VP per unique placed sector color
			var colors: Dictionary = {}
			for slot: SectorSlot in slots:
				if slot.placed_card != null:
					colors[_card_color(slot.placed_card)] = true
			return 2 * colors.size()

		"Cloud Colony":
			# 3 VP per complete AND fully optimized sector
			var count: int = 0
			for slot: SectorSlot in slots:
				if slot.is_complete() and slot.is_optimized:
					count += 1
			return 3 * count

		"Hive Mind":
			# 1 VP per Electrix card placed (including self)
			var count: int = 0
			for card: Node3D in all_cards:
				if _card_color(card) == CardData.SupplyColor.ELECTRIX:
					count += 1
			return count

		"Asteroid Colonies":
			# 1 VP per facedown tucked card
			var count: int = 0
			for slot: SectorSlot in slots:
				for tuck: Dictionary in slot.tucked_cards:
					if not tuck.get("face_up", true):
						count += 1
			return count

		"Urbanized Planet":
			# 15 VP per complete set of all 6 stored supply colors
			var totals: Dictionary = {}
			for slot: SectorSlot in slots:
				for color: int in slot.stored_supply:
					totals[color] = totals.get(color, 0) + slot.stored_supply[color]
			var min_count: int = 9999
			var all_colors: Array[CardData.SupplyColor] = [
				CardData.SupplyColor.DUST, CardData.SupplyColor.METALS,
				CardData.SupplyColor.LIQUIDS, CardData.SupplyColor.ORGANIX,
				CardData.SupplyColor.ELECTRIX, CardData.SupplyColor.THRUST,
			]
			for color: CardData.SupplyColor in all_colors:
				min_count = mini(min_count, totals.get(color, 0))
			return 15 * (min_count if min_count < 9999 else 0)

		"Millions of Colonists":
			# 2 VP per complete sector
			var count: int = 0
			for slot: SectorSlot in slots:
				if slot.is_complete():
					count += 1
			return 2 * count

		"Alliance":
			return 0  # multiplayer only

		"Polar Planet":
			# 2 VP per different stored supply color on the best single sector
			var best: int = 0
			for slot: SectorSlot in slots:
				best = maxi(best, slot.stored_supply.size())
			return 2 * best

		"Waterworld":
			# 2 VP per sector containing at least one Liquids card
			var count: int = 0
			for slot: SectorSlot in slots:
				for card: Node3D in slot.get_all_placed_cards():
					if _card_color(card) == CardData.SupplyColor.LIQUIDS:
						count += 1
						break
			return 2 * count

		"Self Replication":
			# 2 VP per Metals card in best single sector (including self)
			var best: int = 0
			for slot: SectorSlot in slots:
				var count: int = 0
				for card: Node3D in slot.get_all_placed_cards():
					if _card_color(card) == CardData.SupplyColor.METALS:
						count += 1
				best = maxi(best, count)
			return 2 * best

		"Lagrange Complex":
			# 2 VP per fully optimized sector
			var count: int = 0
			for slot: SectorSlot in slots:
				if slot.is_optimized:
					count += 1
			return 2 * count

		"Interstellar Trade Port":
			# 2 VP per sector with 2+ stored supplies
			var count: int = 0
			for slot: SectorSlot in slots:
				if slot.get_total_stored_supply() >= 2:
					count += 1
			return 2 * count

	return 0

# ── tech conditional scoring ──────────────────────────────────────────────────

static func _score_tech_conditions(lines: Array[Dictionary], slots: Array, all_cards: Array) -> void:
	for card: Node3D in all_cards:
		var cd: CardData = card.get("card_data")
		if cd == null or cd.card_type != CardData.CardType.TECH:
			continue
		var vp: int = _tech_condition_vp(cd.card_name, slots, all_cards)
		_add_line(lines, cd.card_name, vp)

static func _is_conditional_tech(name: String) -> bool:
	match name:
		"Tectonic Accelarator", "Magnetosphere", "Genesis Device", "Space Elevator", "Atmosphere Processor":
			return true
	return false

static func _tech_condition_vp(name: String, slots: Array, all_cards: Array) -> int:
	match name:
		"Tectonic Accelarator":  # note: typo preserved from CSV
			var count: int = 0
			for slot: SectorSlot in slots:
				if slot.is_optimized:
					count += 1
			return 9 if count >= 6 else 0

		"Magnetosphere":
			var count: int = 0
			for slot: SectorSlot in slots:
				count += slot.tucked_cards.size()
			return 6 if count >= 9 else 0

		"Genesis Device":
			var count: int = 0
			for card: Node3D in all_cards:
				if _card_color(card) == CardData.SupplyColor.THRUST:
					count += 1
			return 6 if count >= 6 else 0

		"Space Elevator":
			var total: int = 0
			for slot: SectorSlot in slots:
				total += slot.get_total_stored_supply()
			return 6 if total >= 12 else 0

		"Atmosphere Processor":
			var count: int = 0
			for slot: SectorSlot in slots:
				if slot.is_complete():
					count += 1
			return 9 if count >= 6 else 0

	return 0
