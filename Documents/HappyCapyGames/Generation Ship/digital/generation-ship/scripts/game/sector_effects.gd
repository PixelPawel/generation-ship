class_name SectorEffects
extends RefCounted

# Returns the list of effect steps when the player optimizes a sector slot.
# The slot's placed_card must be set before calling.
#
# New step types introduced here (handled by main.gd):
#   gain_supply_per_stored(color, multiplier)  — gain (stored count × multiplier) of color
#   gain_supply_per_sector_count(color)        — gain 1 per occupied sector on the board

static func get_optimize_steps(slot: SectorSlot) -> Array[Dictionary]:
	if not slot.placed_card:
		return []
	var cd: CardData = slot.placed_card.card_data
	if not cd:
		return []
	var is_adv: bool = bool(slot.placed_card.get("is_advanced"))
	var name: String = cd.adv_name if is_adv else cd.card_name
	var steps: Array[Dictionary] = []
	_build(name, slot, steps)
	return steps

static func _build(name: String, slot: SectorSlot, steps: Array[Dictionary]) -> void:
	match name:

		# ── Dust sector optimize effects ──────────────────────────────────────

		"Hibernators":
			steps.append({type = "store_on_any_sector", color = CardData.SupplyColor.DUST, amount = 3})

		"Simulators":
			steps.append({type = "draw", count = 2})

		"Bioreactor":
			# Recycle up to 4, draw that many
			steps.append({type = "recycle_optional", max = 4})

		"Habitation Ring":
			steps.append({type = "gain_supply", color = CardData.SupplyColor.DUST, amount = 8})

		"Operations":
			steps.append({type = "reveal_expedition", gain_supply = true, may_bid = true})
			steps.append({type = "offer_bid_pool"})

		"Cargo Bays":
			steps.append({type = "reveal_sector", may_bid = true})
			steps.append({type = "reveal_sector", may_bid = true})
			steps.append({type = "reveal_sector", may_bid = true})
			steps.append({type = "offer_bid_pool"})

		# ── Advanced sector optimize effects ──────────────────────────────────

		"Central Transport":
			# Fuse 1:1 for each Metals and Electrix card here (including this sector)
			var fuse_count: int = 0
			for card_node: Node3D in slot.get_all_placed_cards():
				var cdata: CardData = card_node.get("card_data")
				if cdata:
					var col: CardData.SupplyColor = CardData.effective_color(cdata, bool(card_node.get("is_advanced")))
					if col == CardData.SupplyColor.METALS or col == CardData.SupplyColor.ELECTRIX:
						fuse_count += 1
			if fuse_count > 0:
				steps.append({type = "fuse_notice", count = fuse_count})

		"Fabrication":
			steps.append({
				type = "choice",
				prompt = "Fabrication — choose one:",
				options = [
					{label = "Gain 6 Dust", tint = CardData.color_tint(CardData.SupplyColor.DUST), steps = [{type = "gain_supply", color = CardData.SupplyColor.DUST, amount = 6}]},
					{label = "Fuse 1:1 ×3", steps = [{type = "fuse_notice", count = 3}]},
				],
			})

		"Preservation":
			var colors: Dictionary = {}
			for card_node: Node3D in slot.get_all_placed_cards():
				var cdata: CardData = card_node.get("card_data")
				if cdata:
					colors[int(CardData.effective_color(cdata, bool(card_node.get("is_advanced"))))] = true
			if not colors.is_empty():
				steps.append({type = "gain_supply", color = CardData.SupplyColor.DUST, amount = 2 * colors.size()})

		"Space Bazaar":
			# Recycle up to 3, draw that many
			steps.append({type = "recycle_optional", max = 3})

		"Greenhouses":
			steps.append({type = "store_on_slot", color = CardData.SupplyColor.LIQUIDS, amount = 1})

		"Academies":
			steps.append({type = "draw", count = 3})

		"Exosampling":
			# Tuck 1 card faceup here (faceup tucked cards score their printed stars)
			steps.append({type = "tuck", count = 1, face_up = true})

		"Parliament":
			# Draw equal to the printed cost of the last tech card placed here
			var draw_count: int = slot.last_placed_tech_cost
			if draw_count > 0:
				steps.append({type = "draw", count = draw_count})

		"Cultivation":
			steps.append({type = "draw", count = 4})
			steps.append({type = "tuck_any_sector_optional", max = 4, face_up = false, label = "Cultivation"})

		"Holoprinters":
			steps.append(CardData.color_store_choice("Store 1st supply — choose color:", true))
			steps.append(CardData.color_store_choice("Store 2nd supply — choose color:", true))

		"Probe Launcher":
			steps.append({type = "reveal_expedition", may_bid = true})
			steps.append({type = "offer_bid_pool"})

		"Engines":
			steps.append({type = "gain_supply_per_sector_count", color = CardData.SupplyColor.ELECTRIX})

		"Astrogation":
			steps.append({type = "gain_supply", color = CardData.SupplyColor.THRUST, amount = 2})

		"Astra Cultura":
			steps.append({type = "store_on_slot", color = CardData.SupplyColor.THRUST, amount = 2})

		"Central AI":
			steps.append({type = "draw", count = 3})

