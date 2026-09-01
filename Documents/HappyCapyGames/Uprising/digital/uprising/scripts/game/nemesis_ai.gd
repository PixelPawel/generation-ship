class_name NemesisAI
extends RefCounted
## Legion/Horde activation (rulebook p54-55): Garrison/Curse placement plus
## the movement-priority algorithm (A: into a Haven: B: into a hex with
## enemy Units; C: into an empty hex; D: any hex closer/not-farther).
##
## Scope boundary, deliberate: this automates placement and movement fully
## (pure state mutation, no dice needed), but stops at "combat should begin
## here" -- actual combat resolution needs Hero/Unit dice-face data that
## doesn't exist anywhere in the CSVs or rulebook text (same gap noted for
## Quest in game_actions.gd). When a move lands on a hex with enemy
## presence, this marks GameState.pending_combat_hex and returns without
## doing the p54/p55 steps 4-5 (Haven removal, Legion retarget) that only
## make sense once combat is actually resolved -- those pick back up once
## combat resolution exists.


## Activates one Legion by its `legion_id` (LegionInstance.id), consuming
## one Activation Token. Returns {"ok", "reason"} like GameActions.
static func activate_legion(state: GameState, legion_id: int) -> Dictionary:
	var legion := _find_legion(state, legion_id)
	if legion == null:
		return {"ok": false, "reason": "no such Legion"}
	if legion.activation_tokens < 1:
		return {"ok": false, "reason": "Legion has no Activation Tokens"}
	legion.activation_tokens -= 1

	_place_garrison_or_score(state, legion.coord)

	if legion.target_hex == LegionInstance.NO_TARGET or legion.coord == legion.target_hex:
		return {"ok": true, "reason": "no movement (no Target or already there)"}

	var dest := _choose_legion_move(state, legion.coord, legion.target_hex)
	if dest == legion.coord:
		return {"ok": true, "reason": "no closer hex available"}
	legion.coord = dest

	var dest_tile := state.get_hex(dest)
	if dest_tile != null and _has_enemy_of_empire(dest_tile):
		state.pending_combat_hex = dest
		return {"ok": true, "reason": "moved into combat at %s -- resolve manually" % dest}

	return {"ok": true, "reason": "moved to %s" % dest}


## Activates one Horde by its `horde_id`, consuming one Activation Token.
static func activate_horde(state: GameState, horde_id: int) -> Dictionary:
	var horde := _find_horde(state, horde_id)
	if horde == null:
		return {"ok": false, "reason": "no such Horde"}
	if horde.activation_tokens < 1:
		return {"ok": false, "reason": "Horde has no Activation Tokens"}
	horde.activation_tokens -= 1

	_place_curse_or_score(state, horde.coord)

	var dest := _choose_horde_move(state, horde.coord)
	if dest == horde.coord:
		return {"ok": true, "reason": "no valid move available"}
	horde.coord = dest

	var dest_tile := state.get_hex(dest)
	if dest_tile != null and _has_enemy_of_chaos(dest_tile):
		state.pending_combat_hex = dest
		return {"ok": true, "reason": "moved into combat at %s -- resolve manually" % dest}

	return {"ok": true, "reason": "moved to %s" % dest}


static func _find_legion(state: GameState, legion_id: int) -> LegionInstance:
	for l in state.legions:
		if l.id == legion_id:
			return l
	return null


static func _find_horde(state: GameState, horde_id: int) -> HordeInstance:
	for h in state.hordes:
		if h.id == horde_id:
			return h
	return null


## Rulebook p54 step 1: place a Garrison on the Legion's own hex, or give
## the Empire 1 VP if that hex already has 3 (and it's not The Capital).
static func _place_garrison_or_score(state: GameState, coord: Vector2i) -> void:
	var tile := state.get_hex(coord)
	if tile == null:
		return
	if tile.card_name == "The Capital":
		return
	if tile.garrison_level >= 3:
		state.empire_vp += 1
	else:
		tile.garrison_level += 1


## Rulebook p55 step 1: place a Curse on the Horde's own hex, or give Chaos
## 1 VP if that hex is already cursed.
static func _place_curse_or_score(state: GameState, coord: Vector2i) -> void:
	var tile := state.get_hex(coord)
	if tile == null:
		return
	if tile.has_curse:
		state.chaos_vp += 1
	else:
		tile.has_curse = true
		tile.garrison_level = 0
		tile.haven_faction = ""
		tile.has_wall = false
		tile.has_tower = false


static func _has_enemy_of_empire(tile: HexTile) -> bool:
	if tile.has_curse or tile.horde_id != -1 or tile.skeleton_count > 0:
		return true
	for faction in tile.units:
		if not (tile.units[faction] as Array).is_empty():
			return true
	return false


static func _has_enemy_of_chaos(tile: HexTile) -> bool:
	if tile.garrison_level > 0 or tile.legion_id != -1:
		return true
	for faction in tile.units:
		if not (tile.units[faction] as Array).is_empty():
			return true
	return false


static func _unit_count(tile: HexTile) -> int:
	var count := 0
	for faction in tile.units:
		count += (tile.units[faction] as Array).size()
	return count


## Rulebook p54 step 2 priority: A) into a Haven (fewest Units) B) into a
## hex with enemy Units (fewest enemy Units/Threat) C) into an empty hex
## (no Curse or Garrison) D) any hex closer to Target.
static func _choose_legion_move(state: GameState, from: Vector2i, target: Vector2i) -> Vector2i:
	var current_dist := HexMath.distance(from, target)
	var candidates: Array[Vector2i] = []
	for n in HexMath.neighbors(from):
		if state.get_hex(n) == null:
			continue
		if HexMath.distance(n, target) < current_dist:
			candidates.append(n)
	if candidates.is_empty():
		return from

	var havens: Array[Vector2i] = []
	var enemies: Array[Vector2i] = []
	var empties: Array[Vector2i] = []
	for c in candidates:
		var t := state.get_hex(c)
		if t.haven_faction != "":
			havens.append(c)
		elif _has_enemy_of_empire(t):
			enemies.append(c)
		elif not t.has_curse and t.garrison_level == 0:
			empties.append(c)

	if not havens.is_empty():
		return _pick_min(havens, func(c: Vector2i) -> int: return _unit_count(state.get_hex(c)))
	if not enemies.is_empty():
		return _pick_min(enemies, func(c: Vector2i) -> int: return _unit_count(state.get_hex(c)))
	if not empties.is_empty():
		return empties[0]
	return candidates[0]


## Rulebook p55 step 2 priority: A) into a Haven (fewest Units) B) into a
## hex with enemy Units, preferring the WEAKEST (fewest Units/Threat) C) an
## empty hex (no Curse or Skeletons) D) any hex not farther from The Capital.
static func _choose_horde_move(state: GameState, from: Vector2i) -> Vector2i:
	var current_dist := HexMath.distance(from, GameState.CAPITAL_COORD)
	var candidates: Array[Vector2i] = []
	for n in HexMath.neighbors(from):
		if state.get_hex(n) == null:
			continue
		if HexMath.distance(n, GameState.CAPITAL_COORD) <= current_dist:
			candidates.append(n)
	if candidates.is_empty():
		return from

	var havens: Array[Vector2i] = []
	var enemies: Array[Vector2i] = []
	var empties: Array[Vector2i] = []
	for c in candidates:
		var t := state.get_hex(c)
		if t.haven_faction != "":
			havens.append(c)
		elif _has_enemy_of_chaos(t):
			enemies.append(c)
		elif not t.has_curse and t.skeleton_count == 0:
			empties.append(c)

	if not havens.is_empty():
		return _pick_min(havens, func(c: Vector2i) -> int: return _unit_count(state.get_hex(c)))
	if not enemies.is_empty():
		return _pick_min(enemies, func(c: Vector2i) -> int: return _unit_count(state.get_hex(c)))
	if not empties.is_empty():
		return empties[0]
	return candidates[0]


static func _pick_min(coords: Array[Vector2i], score_fn: Callable) -> Vector2i:
	var best := coords[0]
	var best_score: int = score_fn.call(best)
	for c in coords:
		var s: int = score_fn.call(c)
		if s < best_score:
			best = c
			best_score = s
	return best
