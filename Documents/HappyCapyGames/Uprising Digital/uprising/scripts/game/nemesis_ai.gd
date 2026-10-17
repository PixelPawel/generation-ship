class_name NemesisAI
extends RefCounted

## Legion/Horde activation (rulebook p27, 44-55). Legions and Hordes
## activate together in ascending printed Initiative order
## (LegionHordeCombatTable.get_card(name).initiative), consuming
## Activation Tokens one at a time.
##
## Movement priority (A) Haven-fewest-Units > (B) enemy-hex-fewest-
## Units/Threat > (C) empty hex > (D) any hex on the shortest path is
## evaluated over immediate NEIGHBORS only (a greedy single-step choice) -
## per the rulebook's own "move 1 hex" step. Combat is resolved inside
## each activation (2026-10-17), so a Legion that loses never strips the
## Haven, and later activations see the post-combat board.
## Distances are route lengths that never cross impassable terrain
## (GameState.route_distances), and no step crosses it either. Not yet
## modelled: Legions/Hordes using an explored Sea Tower's "adjacent to any
## hex" effect (rulebook p18).


static func run_nemesis_phase(state: GameState, card_db: Node) -> void:
	var all: Array = []
	all.append_array(state.legions)
	all.append_array(state.hordes)
	all.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _initiative(a.card_name) < _initiative(b.card_name))

	for entry: Variant in all:
		while entry.activation_tokens > 0:
			# Destroyed earlier this phase (combat) - its tokens go with it.
			if not (state.legions.has(entry) or state.hordes.has(entry)):
				break
			entry.activation_tokens -= 1
			if entry is LegionInstance:
				_activate_legion(state, entry as LegionInstance, card_db)
			else:
				_activate_horde(state, entry as HordeInstance, card_db)


static func _initiative(card_name: String) -> int:
	var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(card_name)
	return card.initiative if card != null else 999


## Rulebook p54 "Activate a Legion", steps 1-5. Combat (step 3) is fought
## right here, before the next activation, not batched at phase end.
static func _activate_legion(state: GameState, legion: LegionInstance, card_db: Node) -> void:
	# Step 1: place 1 Garrison here, or +1 VP if already 3 (not The Capital).
	var tile: HexTileState = state.ensure_hex(legion.coord)
	if tile.garrison_level < 3:
		tile.garrison_level += 1
	elif tile.role == "capital":
		place_garrison_on_empty_hex(state)
	else:
		state.empire_vp += 1

	# Step 2: move 1 hex toward Target (not if already on it).
	var target_coord: Vector2i = _resolve_target_coord(state, legion.target_faction)
	if legion.coord != target_coord:
		legion.coord = _best_step(state, legion.coord, target_coord, true, "Empire")

	# Step 3: combat with player or Chaos Units here.
	if CombatResolver.hex_needs_combat(state, legion.coord):
		var r: CombatResolver.Result = CombatResolver.resolve_hex(state, legion.coord, card_db)
		state.phase_log += " | " + "; ".join(r.log)
	if not state.legions.has(legion):
		return

	# Steps 4-5: survived -> remove any Haven here, retarget if it was the Target.
	var arrived_tile: HexTileState = state.ensure_hex(legion.coord)
	if not arrived_tile.haven_faction.is_empty() and arrived_tile.total_player_units() == 0:
		var destroyed_faction: String = arrived_tile.haven_faction
		_remove_haven(arrived_tile)
		if legion.target_faction == destroyed_faction:
			legion.target_faction = _retarget(state, destroyed_faction)


## Rulebook p55 "Activate a Horde", steps 1-4.
static func _activate_horde(state: GameState, horde: HordeInstance, card_db: Node) -> void:
	var tile: HexTileState = state.ensure_hex(horde.coord)
	if tile.curse:
		state.chaos_vp += 1
	else:
		place_curse(state, tile)

	horde.coord = _best_step(state, horde.coord, state.capital_coord, false, "Chaos")

	if CombatResolver.hex_needs_combat(state, horde.coord):
		var r: CombatResolver.Result = CombatResolver.resolve_hex(state, horde.coord, card_db)
		state.phase_log += " | " + "; ".join(r.log)
	if not state.hordes.has(horde):
		return

	var arrived_tile: HexTileState = state.ensure_hex(horde.coord)
	if not arrived_tile.haven_faction.is_empty() and arrived_tile.total_player_units() == 0:
		_remove_haven(arrived_tile)


static func _remove_haven(tile: HexTileState) -> void:
	tile.haven_faction = ""
	tile.tower = false
	tile.wall = false


## Rulebook p49: a Curse destroys any Garrisons here (to the Chaos
## Graveyard) and removes any Haven, Tower and Wall.
static func place_curse(state: GameState, tile: HexTileState) -> void:
	tile.curse = true
	if tile.garrison_level > 0:
		state.chaos_graveyard["Empire"] = int(state.chaos_graveyard.get("Empire", 0)) + tile.garrison_level
		tile.garrison_level = 0
	_remove_haven(tile)


## "Place a Garrison on an empty hex with no X" (rulebook p47, p50): an
## empty hex has no Haven, Units or Curse. Several qualify -> the one
## nearest The Capital (stand-in for the acting player's choice). None ->
## stack on another Garrison below 3. Can't -> The Empire gains 1 VP.
static func place_garrison_on_empty_hex(state: GameState) -> void:
	var best: Vector2i = Vector2i.MIN
	var best_dist: int = 99999
	for coord: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[coord]
		if t.role == "capital" or t.role == "outer" or t.curse or not t.haven_faction.is_empty():
			continue
		if not EffectUtil.hex_is_empty_of_units(state, coord):
			continue
		var d: int = HexMath.distance(coord, state.capital_coord)
		if d < best_dist:
			best_dist = d
			best = coord
	if best != Vector2i.MIN:
		(state.hexes[best] as HexTileState).garrison_level = 1
		return
	for coord2: Vector2i in state.hexes.keys():
		var t2: HexTileState = state.hexes[coord2]
		if t2.garrison_level > 0 and t2.garrison_level < 3:
			t2.garrison_level += 1
			return
	state.empire_vp += 1


## Draws the top Horde card and places it on `coord` (e.g. 3 Skeletons
## merging, rulebook p48). Initial Threat comes from the current Chapter's
## Event card ("Horde at Threat N"), defaulting to 4 when it doesn't say.
## Its immediate effect is not executed yet. No card left -> Chaos +1 VP.
static func spawn_horde(state: GameState, coord: Vector2i, card_db: Node = null) -> HordeInstance:
	if state.horde_deck.is_empty():
		state.chaos_vp += 1
		return null
	var inst := HordeInstance.new()
	var max_id: int = -1
	for l: LegionInstance in state.legions:
		max_id = maxi(max_id, l.id)
	for h: HordeInstance in state.hordes:
		max_id = maxi(max_id, h.id)
	inst.id = max_id + 1
	inst.card_name = state.horde_deck.pop_front()
	inst.threat = event_threat(state, card_db, "Horde")
	inst.coord = coord
	state.hordes.append(inst)
	return inst


## "Place 1 Legion/Horde at Threat N" from this Chapter's Event card text.
static func event_threat(state: GameState, card_db: Node, kind: String) -> int:
	var event_name: String = str(state.chapter_events.get(state.chapter, ""))
	if card_db == null or event_name.is_empty():
		return 4
	var re := RegEx.new()
	re.compile(kind + "\\s+at\\s+Threat\\s+(\\d)")
	for e: EventCard in card_db.events_all:
		if e.card_name == event_name and e.lang == "EN":
			var m: RegExMatch = re.search(e.effect_1 + "\n" + e.effect_2)
			if m != null:
				return m.get_string(1).to_int()
	return 4


## Picks the best single step from `from` toward/away-from `target`,
## following the rulebook's priority tiers (p54-55): A) a Haven, fewest
## Units; B) a hex with enemy Units (player, or the other Nemesis
## faction), fewest Units/Threat; C) an empty hex (no Haven, Units or
## Curse); D) any remaining candidate. `toward` = true for Legions (must
## get strictly closer to target), false for Hordes (must not get farther
## from The Capital). "Closer" counts the route around impassable terrain.
static func _best_step(state: GameState, from: Vector2i, target: Vector2i, toward: bool, mover: String) -> Vector2i:
	var routes: Dictionary = state.route_distances(target)
	var unreachable: int = 999999
	var current_dist: int = int(routes.get(from, unreachable))
	var candidates: Array[Vector2i] = []
	for n: Vector2i in HexMath.neighbors(from):
		if not state.hexes.has(n) or state.edge_blocked(from, n):
			continue
		var d: int = int(routes.get(n, unreachable))
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
			var units: int = t.total_player_units()
			if units < best_units:
				best = c
				best_units = units
	if best != Vector2i.MIN:
		return best

	# Tier B: into a hex with enemy Units, fewest Units/Threat.
	best_units = 999999
	for c: Vector2i in candidates:
		var strength: int = _enemy_strength(state, c, mover)
		if strength > 0 and strength < best_units:
			best = c
			best_units = strength
	if best != Vector2i.MIN:
		return best

	# Tier C: into an empty hex.
	for c: Vector2i in candidates:
		var t2: HexTileState = state.get_hex(c)
		if (t2 == null or (not t2.curse and t2.haven_faction.is_empty())) and EffectUtil.hex_is_empty_of_units(state, c):
			return c

	# Tier D: any candidate on the shortest path.
	return candidates[0]


## Sum of enemy Units/levels/Threat on `coord` from `mover`'s point of
## view ("Empire" or "Chaos").
static func _enemy_strength(state: GameState, coord: Vector2i, mover: String) -> int:
	var t: HexTileState = state.get_hex(coord)
	if t == null:
		return 0
	var total: int = t.total_player_units()
	if mover == "Empire":
		total += t.skeleton_count
		for h: HordeInstance in state.hordes:
			if h.coord == coord:
				total += h.threat
	else:
		total += t.garrison_level
		for l: LegionInstance in state.legions:
			if l.coord == coord:
				total += l.threat
	return total


static func _resolve_target_coord(state: GameState, target_faction: String) -> Vector2i:
	if target_faction.is_empty() or target_faction == "Capital":
		return state.capital_coord
	var best_coord: Vector2i = state.capital_coord
	var best_units: int = 999999
	var found: bool = false
	for coord: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[coord]
		if t.haven_faction == target_faction:
			var units: int = t.total_player_units()
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
