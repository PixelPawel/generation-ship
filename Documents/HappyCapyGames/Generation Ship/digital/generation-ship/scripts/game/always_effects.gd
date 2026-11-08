class_name AlwaysEffects
extends RefCounted

# Returns extra effect steps triggered by "Always" cards already in a slot
# when a new card is placed there.
# Called AFTER the card is registered in the slot.
#
# Handled Always effects:
#   Insects            — store 1 of placed card's color when it's a new color for this sector
#   Crops              — gain 1 Organix per star on the placed card (per Crops present)
#   Living Hull        — draw 1 per star on the placed card (per Living Hull present)
#   Quantum Archives   — store 1 of placed card's color per star (simplified: player has no choice)
#
# Board-wide Always effects (use get_board_wide_steps / get_board_wide_placement_steps):
#   1-G Thrust         — gain 1 Thrust per 1-G Thrust on the ENTIRE board when any sector completes
#   Biodomes           — draw 1 per Biodomes anywhere on the board when any Liquids card is placed
#
# A Fleet-destroyed (face-down) card has no effect any more (FleetRules.DESTROYED_META).
# get_bot_steps: the same triggers for a bot's ship (BotTurn's board entries).
const FleetRules = preload("res://scripts/game/fleet_rules.gd")

static func get_colocated_steps(placed_card: CardData, placed_card_node: Node3D, slot: SectorSlot) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var placed: Array[Node3D] = slot.get_all_placed_cards()
	# "the next card placed here" (Crops, Living Hull, Quantum Archives) is only
	# the card placed directly on top of it — the one just below the new card
	var at: int = placed.find(placed_card_node)
	var just_below: Node3D = placed[at - 1] if at > 0 else null
	var new_color: bool = _is_new_color(placed_card, slot)
	for card_node: Node3D in placed:
		var cd: CardData = card_node.get("card_data")
		if cd == null or card_node.has_meta(FleetRules.DESTROYED_META):
			continue
		steps.append_array(_colocated_steps_of(cd.card_name, placed_card, card_node == just_below, new_color))
	return steps

# The steps one Always card in a sector gives for the card just placed there (humans and bots).
static func _colocated_steps_of(name: String, placed_card: CardData, is_next: bool, new_color: bool) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	match name:
		"Pollinators":
			if new_color:
				steps.append({type = "store_on_slot", color = placed_card.color, amount = 1, _source_name = "Pollinators"})
		"Crops":
			if is_next and placed_card.stars > 0:
				steps.append({type = "gain_supply", color = CardData.SupplyColor.ORGANIX, amount = placed_card.stars, _source_name = "Crops"})
		"Living Hull":
			if is_next and placed_card.stars > 0:
				steps.append({type = "draw", count = placed_card.stars, _source_name = "Living Hull"})
		"Quantum Archives":
			if is_next:
				for _i: int in placed_card.stars:
					steps.append(CardData.tag_step_source(CardData.color_store_choice("Quantum Archives — store which supply?", true), "Quantum Archives"))
	return steps

# Checks all sector slots for board-wide Always triggers when a sector completes.
# Call this after get_colocated_steps; pass the slot just completed and every sector slot on the board.
static func get_board_wide_steps(completed_slot: SectorSlot, all_slots: Array[SectorSlot]) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	if not completed_slot.is_complete():
		return steps
	for s: SectorSlot in all_slots:
		for card_node: Node3D in s.get_all_placed_cards():
			var cd: CardData = card_node.get("card_data")
			if cd and cd.card_name == "1-G Thrust" and not card_node.has_meta(FleetRules.DESTROYED_META):
				steps.append(_one_g_thrust_step())
	return steps

static func _one_g_thrust_step() -> Dictionary:
	return {type = "gain_supply", color = CardData.SupplyColor.THRUST, amount = 1, _source_name = "1-G Thrust"}

# Checks the entire board for Biodomes when any card is placed anywhere.
# placed_node: the Node3D that was just placed (used to read card_data + is_advanced).
static func get_board_wide_placement_steps(placed_node: Node3D, all_slots: Array[SectorSlot]) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	if not _is_liquids_card(placed_node):
		return steps
	var biodome_count: int = 0
	for s: SectorSlot in all_slots:
		for card_node: Node3D in s.get_all_placed_cards():
			var cd: CardData = card_node.get("card_data")
			if cd and cd.card_name == "Biodomes" and not card_node.has_meta(FleetRules.DESTROYED_META):
				biodome_count += 1
	for _i: int in biodome_count:
		steps.append({type = "draw", count = 1, _source_name = "Biodomes"})
	return steps

static func _is_liquids_card(card_node: Node3D) -> bool:
	var cd: CardData = card_node.get("card_data")
	if cd == null:
		return false
	if cd.card_type == CardData.CardType.SECTOR:
		var is_adv: bool = bool(card_node.get("is_advanced"))
		return (cd.adv_color if is_adv else cd.color) == CardData.SupplyColor.LIQUIDS
	return cd.color == CardData.SupplyColor.LIQUIDS

# Checks all placed expedition cards for board-wide Always triggers.
# placed_card: the card just placed; placed_expeditions: all expeditions on board (including placed_card if it is one).
static func get_global_expedition_steps(placed_card: CardData, placed_expeditions: Array[CardData],
		placed_is_advanced: bool = false) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for expedition: CardData in placed_expeditions:
		steps.append_array(_expedition_steps_of(expedition.card_name, placed_card, placed_is_advanced))
	return steps

# The steps one placed expedition's Always effect gives for the card just placed (humans and bots).
static func _expedition_steps_of(name: String, placed_card: CardData, placed_is_advanced: bool) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	match name:
		"Einstein-Rosen Portal":
			# Store 1 supply of the placed card's color on its sector (handled via _effect_slot);
			# a grey (Dust-side) sector is no star card, whatever its back shows
			if CardData.side_is_star_card(placed_card, placed_is_advanced):
				var portal_color: CardData.SupplyColor = CardData.effective_color(placed_card, placed_is_advanced)
				steps.append({type = "store_on_slot", color = portal_color, amount = 1, _source_name = "Einstein-Rosen Portal"})
		"Galactic Capital":
			# Draw 1 when you buy an expedition
			if placed_card.card_type == CardData.CardType.EXPEDITION:
				steps.append({type = "draw", count = 1, _source_name = "Galactic Capital"})
		"Galactic Museum":
			# Tuck 1 card faceup or facedown when you buy an expedition
			if placed_card.card_type == CardData.CardType.EXPEDITION:
				# mandatory: "Archive 1 card" is no "may" (for the tuck step to honour; label stays English,
				# it is localized where it is shown)
				steps.append(CardData.tag_step_source({
					type = "choice",
					prompt = "Archive 1 card — choose face direction:",
					options = [
						# under any of your sectors (rule book: "under one of your sector cards"), not
						# only the one the expedition went onto
						{label = "Faceup",   steps = [{type = "tuck_any_sector_optional", max = 1, face_up = true, label = "Galactic Museum", mandatory = true}]},
						{label = "Facedown", steps = [{type = "tuck_any_sector_optional", max = 1, face_up = false, label = "Galactic Museum", mandatory = true}]},
					],
				}, "Galactic Museum"))
		"Industrial Cradle":
			# Gain 1 Electrix when you buy an expedition
			if placed_card.card_type == CardData.CardType.EXPEDITION:
				steps.append({type = "gain_supply", color = CardData.SupplyColor.ELECTRIX, amount = 1, _source_name = "Industrial Cradle"})
	return steps

## The same triggers as Main._on_card_placed's four calls above, for a bot's ship: board is
## BotTurn's board entries with placed_card already appended to board[slot_idx]'s techs (a sector
## placement: the new entry, its techs empty). A destroyed card is a {destroyed, data} marker there
## and has no effect. The caller checks FleetRules.always_effects_off() (Totalitarianism) first.
static func get_bot_steps(board: Array, slot_idx: int, placed_card: CardData, placed_is_advanced: bool) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	if slot_idx < 0 or slot_idx >= board.size() or placed_card == null:
		return steps
	var slot: Dictionary = board[slot_idx] as Dictionary
	var techs: Array = slot.get("techs", []) as Array
	var on_stack: bool = placed_card.card_type != CardData.CardType.SECTOR and not techs.is_empty()
	# colocated (get_colocated_steps): the cards in this sector, the new one on top
	if on_stack:
		var top: int = techs.size() - 1
		var new_color: bool = _bot_is_new_color(slot, top, placed_card)
		for i: int in techs.size():
			if techs[i] is CardData:
				steps.append_array(_colocated_steps_of((techs[i] as CardData).card_name, placed_card, i == top - 1, new_color))
	# Biodomes (get_board_wide_placement_steps): any Liquids card placed, a sector by its side
	var liquids: bool = CardData.effective_color(placed_card, placed_is_advanced) == CardData.SupplyColor.LIQUIDS
	# 1-G Thrust (get_board_wide_steps): this placement completed the sector
	var completed: bool = on_stack and BotScoring.is_slot_complete(slot)
	var biodomes: int = 0
	var thrusts: int = 0
	var expeditions: Array[CardData] = []
	for entry: Variant in board:
		for t: Variant in ((entry as Dictionary).get("techs", []) as Array):
			if not (t is CardData):
				continue
			var cd: CardData = t as CardData
			if cd.card_name == "Biodomes":
				biodomes += 1
			elif cd.card_name == "1-G Thrust":
				thrusts += 1
			if cd.card_type == CardData.CardType.EXPEDITION:
				expeditions.append(cd)
	if liquids:
		for _i: int in biodomes:
			steps.append({type = "draw", count = 1, _source_name = "Biodomes"})
	if completed:
		for _i: int in thrusts:
			steps.append(_one_g_thrust_step())
	steps.append_array(get_global_expedition_steps(placed_card, expeditions, placed_is_advanced))
	return steps

# Pollinators for a bot's sector: no other live card there (the sector by its side) has the colour.
static func _bot_is_new_color(slot: Dictionary, placed_idx: int, placed_card: CardData) -> bool:
	var sector: CardData = slot.get("sector") as CardData
	if sector and CardData.effective_color(sector, bool(slot.get("is_advanced", false))) == placed_card.color:
		return false
	var techs: Array = slot.get("techs", []) as Array
	for i: int in techs.size():
		if i != placed_idx and techs[i] is CardData and (techs[i] as CardData).color == placed_card.color:
			return false
	return true

static func _is_new_color(placed_card: CardData, slot: SectorSlot) -> bool:
	for card_node: Node3D in slot.get_all_placed_cards():
		var cd: CardData = card_node.get("card_data")
		if cd == null or cd == placed_card or card_node.has_meta(FleetRules.DESTROYED_META):
			continue
		var existing_color: CardData.SupplyColor
		if cd.card_type == CardData.CardType.SECTOR:
			var is_adv: bool = bool(card_node.get("is_advanced"))
			existing_color = cd.adv_color if is_adv else cd.color
		else:
			existing_color = cd.color
		if existing_color == placed_card.color:
			return false
	return true
