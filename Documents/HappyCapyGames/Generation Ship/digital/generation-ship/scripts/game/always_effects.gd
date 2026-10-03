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

static func get_colocated_steps(placed_card: CardData, placed_card_node: Node3D, slot: SectorSlot) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var placed: Array[Node3D] = slot.get_all_placed_cards()
	# "the next card placed here" (Crops, Living Hull, Quantum Archives) is only
	# the card placed directly on top of it — the one just below the new card
	var at: int = placed.find(placed_card_node)
	var just_below: Node3D = placed[at - 1] if at > 0 else null
	for card_node: Node3D in placed:
		var cd: CardData = card_node.get("card_data")
		if cd == null:
			continue
		var is_next: bool = card_node == just_below
		match cd.card_name:
			"Pollinators":
				if _is_new_color(placed_card, slot):
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
			if cd and cd.card_name == "1-G Thrust":
				steps.append({type = "gain_supply", color = CardData.SupplyColor.THRUST, amount = 1, _source_name = "1-G Thrust"})
	return steps

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
			if cd and cd.card_name == "Biodomes":
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
static func get_global_expedition_steps(placed_card: CardData, placed_expeditions: Array[CardData]) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for expedition: CardData in placed_expeditions:
		match expedition.card_name:
			"Einstein-Rosen Portal":
				# Store 1 supply of the placed card's color on its sector (handled via _effect_slot)
				if placed_card.is_star_card:
					var portal_color: CardData.SupplyColor = placed_card.adv_color if placed_card.card_type == CardData.CardType.SECTOR else placed_card.color
					steps.append({type = "store_on_slot", color = portal_color, amount = 1, _source_name = "Einstein-Rosen Portal"})
			"Galactic Capital":
				# Draw 1 when you buy an expedition
				if placed_card.card_type == CardData.CardType.EXPEDITION:
					steps.append({type = "draw", count = 1, _source_name = "Galactic Capital"})
			"Galactic Museum":
				# Tuck 1 card faceup or facedown when you buy an expedition
				if placed_card.card_type == CardData.CardType.EXPEDITION:
					steps.append(CardData.tag_step_source({
						type = "choice",
						prompt = "Archive 1 card — choose face direction:",
						options = [
							{label = "Faceup",   steps = [{type = "tuck", count = 1, face_up = true}]},
							{label = "Facedown", steps = [{type = "tuck", count = 1, face_up = false}]},
						],
					}, "Galactic Museum"))
			"Industrial Cradle":
				# Gain 1 Electrix when you buy an expedition
				if placed_card.card_type == CardData.CardType.EXPEDITION:
					steps.append({type = "gain_supply", color = CardData.SupplyColor.ELECTRIX, amount = 1, _source_name = "Industrial Cradle"})
	return steps

static func _is_new_color(placed_card: CardData, slot: SectorSlot) -> bool:
	for card_node: Node3D in slot.get_all_placed_cards():
		var cd: CardData = card_node.get("card_data")
		if cd == null or cd == placed_card:
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
