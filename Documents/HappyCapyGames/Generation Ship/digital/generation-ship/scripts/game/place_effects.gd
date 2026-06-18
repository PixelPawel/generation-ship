class_name PlaceEffects
extends RefCounted

# Returns ordered list of effect steps for a card just placed on a slot.
# Each step is a Dictionary consumed by main.gd's effect processor.
#
# Step types:
#   draw(count)                  — draw N cards from tech deck
#   draw_recycle_top             — draw 1 from deck, gain its supply, don't add to hand
#   gain_supply(color, amount)   — add to player supply pool
#   store_on_slot(color, amount) — store on the sector where card was placed
#   store_per_card_here          — store 1 of each placed card's color (Replicators)
#   fuse_notice(count)           — show hint: player may fuse N times
#   recycle(count)               — player picks exactly N hand cards to recycle (mandatory)
#   recycle_optional(max)        — player picks 0-max, draws 1 per recycle
#   tuck(count, face_up)         — player picks exactly N hand cards to tuck on slot
#   tuck_optional(max, face_up)  — player picks 0-max, draws 1 per tuck
#   recycle_tuck(count)          — recycle N cards AND tuck them facedown, then draw N

static func get_steps(cd: CardData, slot: SectorSlot) -> Array[Dictionary]:
	var is_new: bool = slot.get_tech_count() == 1
	var is_complete: bool = slot.is_complete()
	var is_opt: bool = slot.is_optimized
	var steps: Array[Dictionary] = []
	_build(cd.card_name, cd, slot, is_new, is_complete, is_opt, steps)
	return steps

static func _build(name: String, _cd: CardData, slot: SectorSlot,
		is_new: bool, is_complete: bool, is_opt: bool,
		steps: Array[Dictionary]) -> void:
	match name:

		# ── Dust techs ────────────────────────────────────────────────────────

		"Gas Cloud":
			steps.append({type = "draw", count = 1})

		"Osmosis Filter":
			steps.append({type = "recycle", count = 1})
			steps.append({type = "draw", count = 1})

		"Passing Comet":
			steps.append({type = "draw_recycle_top"})

		"Atmospheric Control System":
			if is_new:
				steps.append({type = "draw", count = 1})

		"Hangars":
			if is_new:
				steps.append({type = "gain_supply", color = CardData.SupplyColor.DUST, amount = 3})

		"Ancient Airlock":
			steps.append({type = "reveal_sector", may_bid = true, gain_supply = true})
			steps.append({type = "offer_bid_pool"})

		"Cargo Drones":
			steps.append({type = "cargo_drones"})

		"Chemical Synthesizer":
			steps.append({type = "tuck", count = 1, face_up = false})
			steps.append({type = "draw", count = 1})

		"Asteroid Capture":
			steps.append({type = "fuse_notice", count = 2})
			if is_new:
				steps.append({type = "draw", count = 1})

		"Printed Library":
			steps.append({type = "tuck", count = 1, face_up = false})
			if is_opt:
				steps.append({type = "draw", count = 2})

		"Chemlabs":
			steps.append({type = "fuse_notice", count = 2})
			if is_opt:
				steps.append({type = "gain_supply", color = CardData.SupplyColor.DUST, amount = 2})

		# ── Metals techs ──────────────────────────────────────────────────────

		"Magnetized Hull":
			if is_complete:
				steps.append({
					type = "choice",
					prompt = "Magnetized Hull — gain which supply?",
					options = [
						{label = "Organix",  tint = CardData.color_tint(CardData.SupplyColor.ORGANIX),  steps = [{type = "gain_supply", color = CardData.SupplyColor.ORGANIX,  amount = 1}]},
						{label = "Electrix", tint = CardData.color_tint(CardData.SupplyColor.ELECTRIX), steps = [{type = "gain_supply", color = CardData.SupplyColor.ELECTRIX, amount = 1}]},
					],
				})

		"Hydrogen Cell":
			if is_new:
				steps.append({type = "fuse_notice", count = 2})

		"Smelter":
			steps.append({type = "fuse_notice", count = 3})
			if is_opt:
				steps.append({type = "store_on_slot", color = CardData.SupplyColor.METALS, amount = 1})

		"Fusion Synthesizer":
			steps.append({type = "fuse_dust_1to1"})

		"Cleaning Robot":
			# "Recycle 1 but gain the supply twice" — player picks 1, gains double supply
			steps.append({type = "recycle_double", count = 1})

		"Deep Space Radar":
			steps.append({type = "reveal_expedition", may_bid = true})
			steps.append({type = "reveal_expedition", may_bid = true})
			steps.append({type = "offer_bid_pool"})

		"Robotic Workforce":
			if is_new:
				steps.append({type = "recycle_optional", max = 2})

		"Transformable Hull":
			steps.append({type = "reveal_sector", may_bid = true, gain_supply = true})
			steps.append({type = "offer_bid_pool"})

		"Radiation Absorber":
			if is_complete:
				steps.append({type = "recycle_optional", max = 3})

		# ── Liquids techs ─────────────────────────────────────────────────────

		"Medical Hub":
			steps.append({type = "draw", count = 2})
			steps.append({type = "recycle", count = 1, restrict_to_drawn = true})

		"Ice Mining":
			steps.append({type = "reveal_expedition", may_bid = true})
			steps.append({type = "offer_bid_pool"})

		"Ice Shield":
			steps.append({type = "draw", count = 3 if is_complete else 2})

		"Inflatable Hull":
			steps.append({type = "reveal_sector", may_free_gain = true})
			steps.append({type = "reveal_sector", may_free_gain = true})
			steps.append({type = "reveal_sector", may_free_gain = true})
			steps.append({type = "offer_free_sector_gain"})

		"Black Hole Encounter":
			steps.append({type = "black_hole_encounter"})

		"Day-Night Cycle":
			pass  # Always effect, not Place

		"Seasons":
			pass  # Always effect, not Place

		"Reflectors":
			steps.append({type = "reflectors_choice"})

		"Cryogenics":
			steps.append({type = "tuck_optional", max = 2, face_up = false})

		# ── Organix techs ─────────────────────────────────────────────────────

		"Lab Meats":
			if is_opt:
				steps.append({type = "gain_supply", color = CardData.SupplyColor.DUST, amount = 6})

		"Artists' Quarter":
			if is_opt:
				steps.append({type = "tuck", count = 1, face_up = true})
			else:
				steps.append({type = "tuck", count = 3, face_up = false})

		"Seedbanks":
			steps.append({type = "seedbanks"})

		"PC-Mind-Link":
			steps.append({type = "draw", count = 4 if is_complete else 2})

		"Earth Laser":
			steps.append({type = "draw", count = 3})
			steps.append({type = "tuck", count = 1, face_up = false, restrict_to_drawn = true})

		"Fungi":
			var fungi_count: int = 2 if is_complete else 1
			for _i: int in fungi_count:
				steps.append(CardData.color_store_choice("Fungi — store which supply?", true))

		# ── Electrix techs ────────────────────────────────────────────────────

		"Nanohull", "Nanobots":
			var distinct: int = _count_distinct_tech_colors(slot)
			if distinct > 0:
				steps.append({type = "gain_supply", color = CardData.SupplyColor.ELECTRIX, amount = distinct})

		"Bio Printer":
			steps.append({type = "gain_supply", color = CardData.SupplyColor.ORGANIX, amount = 2 if is_opt else 1})

		"Mass Converter":
			steps.append({type = "fuse_notice", count = 4})

		"Interfleet Comms":
			# "Draw 1 per player, keep 1" → solo: draw 1
			steps.append({type = "draw", count = 1})

		"Nanoassembly":
			steps.append({type = "fuse_notice", count = 6 if is_complete else 3})

		# ── Thrust techs ──────────────────────────────────────────────────────

		"Replicators":
			for c: Node3D in slot.get_all_placed_cards():
				var cdata: CardData = c.get("card_data")
				if cdata:
					steps.append({type = "store_on_slot", color = cdata.color, amount = 1})

		"Quantum Entangled Radio":
			steps.append({type = "recycle_tuck", count = 2})

		"Containers":
			steps.append({
				type = "choice",
				prompt = "Containers — store which supply?",
				options = [
					{label = "Dust",    tint = CardData.color_tint(CardData.SupplyColor.DUST),    steps = [{type = "store_on_any_sector", color = CardData.SupplyColor.DUST,    amount = 1}]},
					{label = "Metals",  tint = CardData.color_tint(CardData.SupplyColor.METALS),  steps = [{type = "store_on_any_sector", color = CardData.SupplyColor.METALS,  amount = 1}]},
					{label = "Liquids", tint = CardData.color_tint(CardData.SupplyColor.LIQUIDS), steps = [{type = "store_on_any_sector", color = CardData.SupplyColor.LIQUIDS, amount = 1}]},
				],
			})

		# ── Expedition place effects ──────────────────────────────────────────

		"Personality Library":
			steps.append({type = "draw", count = 6})
			steps.append({type = "tuck_any_sector_optional", max = 6, face_up = false, label = "Personality Library"})

		"DNA Sculpting":
			steps.append({type = "draw", count = 3})
			steps.append({type = "tuck_optional", max = 3, face_up = true})

		"Terraformed Planet":
			steps.append({type = "recycle_tuck_store_choice", max = 4})

		"Caldera Colony":
			steps.append({type = "caldera_colony"})

static func _count_distinct_tech_colors(slot: SectorSlot) -> int:
	var seen: Dictionary = {}
	for c: Node3D in slot.get_all_placed_cards():
		var cdata: CardData = c.get("card_data")
		if cdata:
			seen[int(cdata.color)] = true
	return seen.size()
