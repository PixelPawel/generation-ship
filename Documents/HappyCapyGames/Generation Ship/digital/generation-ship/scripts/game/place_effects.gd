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
#   tuck_optional(max, face_up)  — player picks 0-max, draws 1 per tuck (pass no_bonus_draw=true to suppress the bonus draw, e.g. when a prior step already drew cards for this same effect)
#   recycle_tuck(count)          — recycle N cards AND tuck them facedown, then draw N
#   interfleet_comms             — draw 1/player, pass-left pick sequence (network-synced); solo collapses to draw 1
#   draw_all_players(count)      — every player (and bot) independently draws N from their own deck (network-synced); solo collapses to draw N

static func get_steps(cd: CardData, slot: SectorSlot) -> Array[Dictionary]:
	var is_new: bool = slot.get_tech_count() == 1
	var is_complete: bool = slot.is_complete()
	var is_opt: bool = slot.is_optimized
	var placed_colors: Array[int] = _slot_placed_colors(slot)
	return get_steps_for_state(cd, is_new, is_complete, is_opt, placed_colors)

# Every card on the slot by its visible side's color — an advanced sector
# counts as its advanced color, not Dust.
static func _slot_placed_colors(slot: SectorSlot) -> Array[int]:
	var placed_colors: Array[int] = []
	for c: Node3D in slot.get_all_placed_cards():
		var cdata: CardData = c.get("card_data")
		if cdata:
			placed_colors.append(int(CardData.effective_color(cdata, bool(c.get("is_advanced")))))
	return placed_colors

# State-only entry point — no SectorSlot/Node3D required, so bots can resolve
# the exact same card effects a real player would without a live scene.
# placed_colors is every card currently on the slot (sector + techs) by its
# visible side's color (see _slot_placed_colors; bots pass
# BotScoring.slot_effective_placed_colors).
static func get_steps_for_state(cd: CardData, is_new: bool, is_complete: bool, is_opt: bool,
		placed_colors: Array[int]) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	_build(cd.card_name, cd, placed_colors, is_new, is_complete, is_opt, steps)
	return CardData.tag_effect_source(steps, cd.card_name)

static func _all_colors_choice(prompt: String, step_type: String) -> Dictionary:
	var options: Array = []
	for sc: int in 6:
		var c: CardData.SupplyColor = sc as CardData.SupplyColor
		options.append({label = CardData.color_name(c), tint = CardData.color_tint(c), color = c, steps = [{type = step_type, color = c}]})
	return {type = "choice", prompt = prompt, options = options}

static func _build(name: String, _cd: CardData, placed_colors: Array[int],
		is_new: bool, is_complete: bool, is_opt: bool,
		steps: Array[Dictionary]) -> void:
	match name:

		# ── Dust techs ────────────────────────────────────────────────────────

		"Gas Cloud":
			steps.append({type = "draw_all_players", count = 1})

		"Osmosis Filter":
			steps.append({type = "recycle", count = 1})
			steps.append({type = "draw", count = 1})

		"Passing Comet":
			steps.append({type = "draw_recycle_top"})

		"Atmospheric System":
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
						{label = "Organix",  tint = CardData.color_tint(CardData.SupplyColor.ORGANIX), color = CardData.SupplyColor.ORGANIX,  steps = [{type = "gain_supply", color = CardData.SupplyColor.ORGANIX,  amount = 1}]},
						{label = "Electrix", tint = CardData.color_tint(CardData.SupplyColor.ELECTRIX), color = CardData.SupplyColor.ELECTRIX, steps = [{type = "gain_supply", color = CardData.SupplyColor.ELECTRIX, amount = 1}]},
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

		"Transforming Hull":
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
			# "Archive 3 cards facedown under this sector. If this sector is fully
			# optimized, archive 1 faceup." — the face-up one comes on top (no "instead")
			steps.append({type = "tuck", count = 3, face_up = false})
			if is_opt:
				steps.append({type = "tuck", count = 1, face_up = true})

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
			var distinct: int = _count_distinct_colors(placed_colors)
			if distinct > 0:
				steps.append({type = "gain_supply", color = CardData.SupplyColor.ELECTRIX, amount = distinct})

		"Bio Printer":
			steps.append({type = "gain_supply", color = CardData.SupplyColor.ORGANIX, amount = 2 if is_opt else 1})

		"Mass Converter":
			steps.append({type = "fuse_notice", count = 4})

		"Interfleet Comms":
			steps.append({type = "interfleet_comms"})

		"Nanoassembly":
			steps.append({type = "fuse_notice", count = 6 if is_complete else 3})

		# ── Thrust techs ──────────────────────────────────────────────────────

		"Replicators":
			for color: int in placed_colors:
				steps.append({type = "store_on_slot", color = color, amount = 1})

		"Entangled Radio":
			steps.append({type = "recycle_tuck", count = 2})

		"Containers":
			steps.append({
				type = "choice",
				prompt = "Containers — store which supply?",
				options = [
					{label = "Dust",    tint = CardData.color_tint(CardData.SupplyColor.DUST), color = CardData.SupplyColor.DUST,    steps = [{type = "store_on_any_sector", color = CardData.SupplyColor.DUST,    amount = 1}]},
					{label = "Metals",  tint = CardData.color_tint(CardData.SupplyColor.METALS), color = CardData.SupplyColor.METALS,  steps = [{type = "store_on_any_sector", color = CardData.SupplyColor.METALS,  amount = 1}]},
					{label = "Liquids", tint = CardData.color_tint(CardData.SupplyColor.LIQUIDS), color = CardData.SupplyColor.LIQUIDS, steps = [{type = "store_on_any_sector", color = CardData.SupplyColor.LIQUIDS, amount = 1}]},
				],
			})

		# ── Promo techs ───────────────────────────────────────────────────────

		"Karma Chameleon":
			steps.append(_all_colors_choice(
				TranslationServer.translate("Karma Chameleon — count as which color?"), "placing_color"))

		"Ice 9":
			steps.append({type = "recycle_from_own_sector"})

		"Biodiversity":
			var seen: Dictionary = {}
			for color: int in placed_colors:
				if not seen.has(color):
					seen[color] = true
					steps.append({type = "gain_supply", color = color, amount = 1})

		"Earth Support":
			steps.append(_all_colors_choice(
				TranslationServer.translate("Earth Support — predict a color"), "earth_support"))

		"Wormhole Surfing":
			steps.append({type = "wormhole_surfing"})

		# ── Expedition place effects ──────────────────────────────────────────

		"Personality Library":
			steps.append({type = "draw", count = 6})
			steps.append({type = "tuck_any_sector_optional", max = 6, face_up = false, label = "Personality Library"})

		"DNA Sculpting":
			steps.append({type = "draw", count = 3})
			steps.append({type = "tuck_optional", max = 3, face_up = true, no_bonus_draw = true})

		"Terraformed Planet":
			steps.append({type = "recycle_tuck_store_choice", max = 4})

		"Caldera Colony":
			steps.append({type = "caldera_colony"})

static func _count_distinct_colors(placed_colors: Array[int]) -> int:
	var seen: Dictionary = {}
	for color: int in placed_colors:
		seen[color] = true
	return seen.size()
