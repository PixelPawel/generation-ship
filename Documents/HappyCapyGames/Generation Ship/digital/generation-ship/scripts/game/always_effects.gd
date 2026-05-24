class_name AlwaysEffects
extends RefCounted

# Returns extra effect steps triggered by "Always" cards already in a slot
# when a new card is placed there.
# Called AFTER the card is registered in the slot.
#
# Handled Always effects:
#   Biodomes           — draw 1 per Biodomes present when any card is placed
#   Insects            — store 1 of placed card's color when it's a new color for this sector
#   Crops              — gain 1 Organix per star on the placed card (per Crops present)
#   Living Hull        — draw 1 per star on the placed card (per Living Hull present)
#   Quantum Archives   — store 1 of placed card's color per star (simplified: player has no choice)
#
# Board-wide Always effects (use get_board_wide_steps):
#   1-G Thrust         — gain 1 Thrust per 1-G Thrust on the ENTIRE board when any sector completes

static func get_colocated_steps(placed_card: CardData, slot: SectorSlot) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for card_node: Node3D in slot.get_all_placed_cards():
		var cd: CardData = card_node.get("card_data")
		if cd == null:
			continue
		match cd.card_name:
			"Biodomes":
				if placed_card.color == CardData.SupplyColor.LIQUIDS:
					steps.append({type = "draw", count = 1})
			"Insects":
				if _is_new_color(placed_card, slot):
					steps.append({type = "store_on_slot", color = placed_card.color, amount = 1})
			"Crops":
				if placed_card.stars > 0:
					steps.append({type = "gain_supply", color = CardData.SupplyColor.ORGANIX, amount = placed_card.stars})
			"Living Hull":
				if placed_card.stars > 0:
					steps.append({type = "draw", count = placed_card.stars})
			"Quantum Archives":
				for _i: int in placed_card.stars:
					steps.append(CardData.color_store_choice("Quantum Archives — store which supply?", true))
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
				steps.append({type = "gain_supply", color = CardData.SupplyColor.THRUST, amount = 1})
	return steps

# Checks all placed expedition cards for board-wide Always triggers.
# placed_card: the card just placed; placed_expeditions: all expeditions on board (including placed_card if it is one).
static func get_global_expedition_steps(placed_card: CardData, placed_expeditions: Array[CardData]) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for exp: CardData in placed_expeditions:
		match exp.card_name:
			"Einstein-Rosen Portal":
				# Store 1 supply of the placed card's color on its sector (handled via _effect_slot)
				if placed_card.is_star_card:
					var portal_color: CardData.SupplyColor = placed_card.adv_color if placed_card.card_type == CardData.CardType.SECTOR else placed_card.color
					steps.append({type = "store_on_slot", color = portal_color, amount = 1})
			"Galactic Capital":
				# Draw 1 when you buy an expedition
				if placed_card.card_type == CardData.CardType.EXPEDITION:
					steps.append({type = "draw", count = 1})
			"Galacttic Museum":
				# Tuck 1 card faceup or facedown when you buy an expedition
				if placed_card.card_type == CardData.CardType.EXPEDITION:
					steps.append({
						type = "choice",
						prompt = "Tuck 1 card — choose face direction:",
						options = [
							{label = "Faceup",   steps = [{type = "tuck", count = 1, face_up = true}]},
							{label = "Facedown", steps = [{type = "tuck", count = 1, face_up = false}]},
						],
					})
			"Industrial Cradle":
				# Gain 1 Electrix when you buy an expedition
				if placed_card.card_type == CardData.CardType.EXPEDITION:
					steps.append({type = "gain_supply", color = CardData.SupplyColor.ELECTRIX, amount = 1})
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
