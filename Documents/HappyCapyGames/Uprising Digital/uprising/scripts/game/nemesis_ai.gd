class_name NemesisAI
extends RefCounted

## Legion/Horde activation (rulebook p27, 44-55). Empire (Legions) resolves
## fully before Chaos (Hordes); within each, cards activate in ascending
## Initiative order (LegionHordeCombatTable.get_card(name).initiative),
## consuming Activation Tokens one at a time.
##
## Simplification, documented: movement priority (A) Haven-fewest-Units >
## (B) enemy-hex-fewest-Units/Threat > (C) empty hex > (D) any hex on the
## shortest path is evaluated over immediate NEIGHBORS only (a greedy
## single-step choice, not full pathfinding) - correct per the rulebook's
## own "move 1 hex" step, since only one step is ever taken per
## activation anyway. Impassable-edge terrain isn't enforced (HexTileState
## has no per-edge data, same boundary as GameActions).


static func run_nemesis_phase(state: GameState, card_db: Node) -> void:
	var all: Array = []
	all.append_array(state.legions)
	all.append_array(state.hordes)
	all.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _initiative(a.card_name) < _initiative(b.card_name))

	for entry: Variant in all:
		while entry.activation_tokens > 0:
			entry.activation_tokens -= 1
			if entry is LegionInstance:
				_activate_legion(state, entry as LegionInstance)
			else:
				_activate_horde(state, entry as HordeInstance)


static func _initiative(card_name: String) -> int:
	var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(card_name)
	return card.initiative if card != null else 999


static func _activate_legion(state: GameState, legion: LegionInstance) -> void:
	# Step 1: Garrison here, or +1 VP to Empire if already 3 (and not Capital).
	var tile: HexTileState = state.ensure_hex(legion.coord)
	if tile.role == "capital":
		tile.garrison_level = mini(3, tile.garrison_level + 1) if tile.garrison_level < 3 else tile.garrison_level
		if tile.garrison_level >= 3:
			state.empire_vp += 1
	elif tile.garrison_level >= 3:
		state.empire_vp += 1
	else:
		tile.garrison_level += 1

	# Step 2: move 1 hex toward Target (skip if already there).
	var target_coord: Vector2i = _resolve_target_coord(state, legion.target_faction)
	if legion.coord != target_coord:
		var next_coord: Vector2i = _best_step(state, legion.coord, target_coord, true)
		legion.coord = next_coord

	# Step 3: combat is resolved by the caller (ChapterFlow) once movement
	# for the whole phase settles - NemesisAI only flags it here.
	if _hex_has_enemy(state, legion.coord, "player"):
		state.phase_log += " | combat pending at %s" % legion.coord

	# Step 4/5: remove Haven there if it survives (assumed - actual combat
	# resolution, Milestone 4's CombatResolver, decides survival) and retarget.
	var arrived_tile: HexTileState = state.ensure_hex(legion.coord)
	if not arrived_tile.haven_faction.is_empty():
		var destroyed_faction: String = arrived_tile.haven_faction
		arrived_tile.haven_faction = ""
		if legion.target_faction == destroyed_faction:
			legion.target_faction = _retarget(state, destroyed_faction)


static func _activate_horde(state: GameState, horde: HordeInstance) -> void:
	var tile: HexTileState = state.ensure_hex(horde.coord)
	if tile.curse:
		state.chaos_vp += 1
	else:
		tile.curse = true
		if tile.garrison_level > 0:
			tile.garrison_level = 0  # Curse destroys any Garrisons there (-> Chaos Graveyard, not tracked per-unit here).

	var next_coord: Vector2i = _best_step(state, horde.coord, state.capital_coord, false)
	horde.coord = next_coord

	if _hex_has_enemy(state, horde.coord, "player"):
		state.phase_log += " | combat pending at %s" % horde.coord

	var arrived_tile: HexTileState = state.ensure_hex(horde.coord)
	if not arrived_tile.haven_faction.is_empty():
		arrived_tile.haven_faction = ""


## Picks the best single step from `from` toward/away-from `target`,
## following the rulebook's priority tiers (A>B>C>D). `toward` = true for
## Legions (must get strictly closer to target), false for Hordes (must
## not get farther from Capital).
static func _best_step(state: GameState, from: Vector2i, target: Vector2i, toward: bool) -> Vector2i:
	var current_dist: int = HexMath.distance(from, target)
	var candidates: Array[Vector2i] = []
	for n: Vector2i in HexMath.neighbors(from):
		var d: int = HexMath.distance(n, target)
		if toward and d < current_dist:
			candidates.append(n)
		elif not toward and d <= current_dist:
			candidates.append(n)
	if candidates.is_empty():
		return from  # no legal step (e.g. boxed in) - stay put.

	# Tier A: into a Haven, fewest Units.
	var best: Vector2i = Vector2i.MIN
	var best_units: int = 999999
	for c: Vector2i in candidates:
		var t: HexTileState = state.get_hex(c)
		if t != null and not t.haven_faction.is_empty():
			var units: int = _total_units(t)
			if units < best_units:
				best = c
				best_units = units
	if best != Vector2i.MIN:
		return best

	# Tier B: into a hex with enemy (player) Units, fewest Units/Threat.
	best_units = 999999
	for c: Vector2i in candidates:
		var t: HexTileState = state.get_hex(c)
		if t != null and _total_units(t) > 0:
			var units: int = _total_units(t)
			if units < best_units:
				best = c
				best_units = units
	if best != Vector2i.MIN:
		return best

	# Tier C: into an empty hex.
	for c: Vector2i in candidates:
		if EffectUtil.hex_is_empty_of_units(state, c):
			return c

	# Tier D: any candidate on the shortest path.
	return candidates[0]


static func _total_units(tile: HexTileState) -> int:
	var total: int = 0
	for v: Variant in tile.units.values():
		total += int(v)
	return total


static func _hex_has_enemy(state: GameState, coord: Vector2i, kind: String) -> bool:
	var tile: HexTileState = state.get_hex(coord)
	if tile == null:
		return false
	if kind == "player":
		return _total_units(tile) > 0
	return false


static func _resolve_target_coord(state: GameState, target_faction: String) -> Vector2i:
	if target_faction.is_empty() or target_faction == "Capital":
		return state.capital_coord
	var best_coord: Vector2i = state.capital_coord
	var best_units: int = 999999
	var found: bool = false
	for coord: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[coord]
		if t.haven_faction == target_faction:
			var units: int = _total_units(t)
			if units < best_units:
				best_units = units
				best_coord = coord
				found = true
	if not found:
		return state.capital_coord  # that faction has no Havens left - Capital.
	return best_coord


static func _retarget(state: GameState, destroyed_faction: String) -> String:
	for coord: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[coord]
		if t.haven_faction == destroyed_faction:
			return destroyed_faction  # still has another Haven somewhere.
	return "Capital"


## Assigns a new Legion's initial Target: the first player faction without
## a current Target, or "Capital" if all factions already have one.
static func assign_new_legion_target(state: GameState) -> String:
	var targeted: Dictionary = {}
	for l: LegionInstance in state.legions:
		if not l.target_faction.is_empty():
			targeted[l.target_faction] = true
	for p: PlayerFactionState in state.players:
		if not targeted.has(p.faction):
			return p.faction
	return "Capital"
