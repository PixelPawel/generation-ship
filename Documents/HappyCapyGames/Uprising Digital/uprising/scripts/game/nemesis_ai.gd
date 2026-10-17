class_name NemesisAI
extends RefCounted

## The Empire and Chaos as the game runs them (rulebook p44-55): Legion/
## Horde activation, putting new Legions/Hordes/Garrisons/Skeletons/Curses
## on the map, and Legion Targets.
##
## Activation: Legions and Hordes activate together in ascending printed
## Initiative order (LegionHordeCombatTable.get_card(name).initiative),
## consuming Activation Tokens one at a time. Movement priority (A) Haven-
## fewest-Units > (B) enemy-hex-fewest-Units/Threat > (C) empty hex > (D)
## any hex on the shortest route is evaluated over immediate NEIGHBORS only
## (a greedy single-step choice) - per the rulebook's own "move 1 hex" step.
## Combat is resolved inside each activation, so a Legion that loses never
## strips the Haven, and later activations see the post-combat board.
## Distances are route lengths that never cross impassable terrain
## (GameState.route_distances), and no step crosses it either.
##
## Placement choices the rulebook leaves to "the acting player" (which
## empty hex, which faction gets a Target...) use pick_hex(): the hex
## farthest from every player Haven - the spot a player would pick to keep
## trouble away - with a stable tie-break. Cards' own immediate effects
## live in nemesis_cards.gd.
##
## Sea Towers (rulebook p18, p55): a Legion on an explored Sea Tower is
## adjacent to every hex and steps straight onto its Target; a Horde there
## may step to any hex not farther from The Capital (routes counted without
## the Sea Tower shortcut). The Warlock "is always adjacent to any hex".
## The Capital (p47): whenever only non-Imperial Units stand on it, a Legion
## is placed there, again and again; with no Legion left the Capital flips
## and the faction with Units on it gains 5 VP. Not modelled: the limited
## number of Garrison/Skeleton/Curse pieces in the box.

const NemesisCards := preload("res://scripts/game/nemesis_cards.gd")


static func run_nemesis_phase(state: GameState, card_db: Node) -> void:
	var all: Array = []
	all.append_array(state.legions)
	all.append_array(state.hordes)
	all.sort_custom(func(a: Variant, b: Variant) -> bool:
		return initiative(a.card_name) < initiative(b.card_name))

	for entry: Variant in all:
		while entry.activation_tokens > 0:
			# Destroyed earlier this phase (combat) - its tokens go with it.
			if not (state.legions.has(entry) or state.hordes.has(entry)):
				break
			entry.activation_tokens -= 1
			activate_now(state, card_db, entry)


static func initiative(card_name: String) -> int:
	var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(card_name)
	return card.initiative if card != null else 999


## One activation without spending a token ("You do not need an Activation
## Token to activate").
static func activate_now(state: GameState, card_db: Node, entry: Variant) -> void:
	if entry is LegionInstance and state.legions.has(entry):
		_activate_legion(state, entry as LegionInstance, card_db)
	elif entry is HordeInstance and state.hordes.has(entry):
		_activate_horde(state, entry as HordeInstance, card_db)


## Rulebook p54 "Activate a Legion", steps 1-5. Combat (step 3) is fought
## right here, before the next activation, not batched at phase end.
static func _activate_legion(state: GameState, legion: LegionInstance, card_db: Node) -> void:
	# Step 1: place 1 Garrison here, or +1 VP if already 3 (not The Capital).
	add_garrisons(state, legion.coord, 1)

	# Step 2: move 1 hex toward Target (not if already on it).
	var target_coord: Vector2i = legion.target_coord if legion.has_target else state.capital_coord
	if legion.coord != target_coord:
		legion.coord = _best_step(state, legion.coord, target_coord, true, "Empire", legion.card_name)

	# Step 3: combat with player or Chaos Units here.
	resolve_combat_at(state, card_db, legion.coord)
	if not state.legions.has(legion):
		return

	# Steps 4-5: survived -> remove any Haven here (retargets via remove_haven).
	var arrived_tile: HexTileState = state.ensure_hex(legion.coord)
	if not arrived_tile.haven_faction.is_empty() and arrived_tile.total_player_units() == 0:
		remove_haven(state, card_db, legion.coord)


## Rulebook p55 "Activate a Horde", steps 1-4.
static func _activate_horde(state: GameState, horde: HordeInstance, card_db: Node) -> void:
	# Druidic Prophetess (kept Quest): "When a Horde activates, place 1 Basic
	# Unit of any player on any of their Havens."
	for p: PlayerFactionState in state.players:
		if p.quests_in_play.has("Druidic Prophetess"):
			var haven: Vector2i = weakest_haven(state, p.faction)
			if haven != Vector2i.MIN:
				state.hexes[haven].add_units(p.faction, PlayerboardTable.default_unit(p.faction), 1)

	place_curse_on(state, card_db, horde.coord)

	horde.coord = _best_step(state, horde.coord, state.capital_coord, false, "Chaos", horde.card_name)

	resolve_combat_at(state, card_db, horde.coord)
	if not state.hordes.has(horde):
		return

	var arrived_tile: HexTileState = state.ensure_hex(horde.coord)
	if not arrived_tile.haven_faction.is_empty() and arrived_tile.total_player_units() == 0:
		remove_haven(state, card_db, horde.coord)


static func resolve_combat_at(state: GameState, card_db: Node, coord: Vector2i) -> void:
	if CombatResolver.hex_needs_combat(state, coord):
		var r: CombatResolver.Result = CombatResolver.resolve_hex(state, coord, card_db)
		log_line(state, "; ".join(r.log))
	if coord == state.capital_coord:
		check_capital(state, card_db)


## The Capital's ongoing effect (rulebook p47): "If there are ever ONLY
## non-Imperial Units on The Capital, place 1 Legion on The Capital
## immediately. This will repeat until there are no more Legions or no more
## non-Imperial Units. If you cannot draw a Legion, flip The Capital and
## give 5 VP to the faction with Units on it."
static func check_capital(state: GameState, card_db: Node) -> void:
	var c: Vector2i = state.capital_coord
	for _i: int in range(10):
		var tile: HexTileState = state.get_hex(c)
		if tile == null or state.capital_flipped:
			return
		var imperial: bool = tile.garrison_level > 0
		var chaos: bool = tile.skeleton_count > 0
		for n: Variant in EffectUtil.nemesis_at(state, c):
			if n is LegionInstance:
				imperial = true
			else:
				chaos = true
		var player: String = tile.player_faction_here()
		if imperial or (player.is_empty() and not chaos):
			return
		if state.legion_deck.is_empty():
			state.capital_flipped = true
			var p: PlayerFactionState = state.find_player(player)
			if p != null:
				p.vp += 5
			else:
				state.chaos_vp += 5
			log_line(state, "Uprising in the Capital! The Capital flips - %s gains 5 VP" % (player if not player.is_empty() else "Chaos"))
			return
		log_line(state, "only rebels and monsters hold The Capital - a Legion is placed there")
		spawn_legion(state, card_db, c, event_threat(state, card_db, "Legion"), {"no_combat": true})
		if CombatResolver.hex_needs_combat(state, c):
			var r: CombatResolver.Result = CombatResolver.resolve_hex(state, c, card_db)
			log_line(state, "; ".join(r.log))


static func log_line(state: GameState, text: String) -> void:
	if text.is_empty():
		return
	state.phase_log = text if state.phase_log.is_empty() else state.phase_log + " | " + text


# --- Havens and Targets ---------------------------------------------------

## Removes the Haven (and its Tower and Wall) on `coord`, then moves any
## Target that was on it (rulebook p47 "Retarget").
static func remove_haven(state: GameState, card_db: Node, coord: Vector2i) -> void:
	var tile: HexTileState = state.get_hex(coord)
	if tile == null or tile.haven_faction.is_empty():
		return
	var faction: String = tile.haven_faction
	tile.haven_faction = ""
	tile.tower = false
	tile.wall = false
	for l: LegionInstance in state.legions:
		if l.has_target and l.target_faction == faction and l.target_coord == coord:
			retarget(state, card_db, l)


## "Place the Target on another Haven of that faction with the fewest
## Units. If the faction has none left, place the Target on The Capital
## (where it will stay)."
static func retarget(state: GameState, card_db: Node, legion: LegionInstance) -> void:
	var haven: Vector2i = weakest_haven(state, legion.target_faction)
	if haven != Vector2i.MIN:
		legion.target_coord = haven
	else:
		legion.target_faction = "Capital"
		legion.target_coord = state.capital_coord
	NemesisCards.on_retarget(state, card_db, legion)


## The faction's Haven with the fewest Units, Vector2i.MIN if it has none.
static func weakest_haven(state: GameState, faction: String) -> Vector2i:
	var best: Vector2i = Vector2i.MIN
	var best_units: int = 999999
	var coords: Array = state.hexes.keys()
	coords.sort()
	for coord: Vector2i in coords:
		var t: HexTileState = state.hexes[coord]
		if t.haven_faction == faction and t.total_player_units() < best_units:
			best_units = t.total_player_units()
			best = coord
	return best


## "Choose one player faction with no Target. Then place the Target on one
## of that faction's Havens that has the fewest Units." With several
## candidates, the first in turn order that still has a Haven. Everyone
## targeted (or Haven-less) -> The Capital, for the rest of the game.
static func assign_target(state: GameState, legion: LegionInstance) -> void:
	var targeted: Dictionary = {}
	for l: LegionInstance in state.legions:
		if l != legion and l.has_target and l.target_faction != "Capital" and not l.target_faction.is_empty():
			targeted[l.target_faction] = true
	for p: PlayerFactionState in state.players:
		if targeted.has(p.faction):
			continue
		var haven: Vector2i = weakest_haven(state, p.faction)
		if haven != Vector2i.MIN:
			legion.target_faction = p.faction
			legion.target_coord = haven
			legion.has_target = true
			return
	legion.target_faction = "Capital"
	legion.target_coord = state.capital_coord
	legion.has_target = true


## Kept for older callers: the faction a new Legion would target.
static func assign_new_legion_target(state: GameState) -> String:
	var probe := LegionInstance.new()
	assign_target(state, probe)
	return probe.target_faction


# --- New Legions and Hordes -------------------------------------------------

## "Place a Legion" (rulebook p47, p52): draw the top Legion card, stand it
## on `coord` (The Capital unless told otherwise) at `threat`, place its
## Target, resolve its immediate effect, and only then any combat. Can't
## draw one -> The Empire gains 1 VP. opts: "target" = "auto" (default) |
## "capital" | "here" (fixed on `coord`, never retargets) | "fixed" with
## "target_coord"; "from_box" draws a Core Legion not in the deck or in
## play; "ignore_immediate"; "no_combat".
static func spawn_legion(state: GameState, card_db: Node, coord: Vector2i, threat: int, opts: Dictionary = {}) -> LegionInstance:
	var card_name: String = _draw_card(state, card_db, "Legion", bool(opts.get("from_box", false)))
	if card_name.is_empty():
		state.empire_vp += 1
		log_line(state, "no Legion left to place - The Empire gains 1 VP")
		return null
	var inst := LegionInstance.new()
	inst.id = next_nemesis_id(state)
	inst.card_name = card_name
	inst.threat = mini(threat, max_threat(card_name))
	inst.coord = coord
	inst.activation_tokens = state.legion_deck_tokens
	state.legion_deck_tokens = 0
	state.legions.append(inst)
	match str(opts.get("target", "auto")):
		"capital":
			inst.target_faction = "Capital"
			inst.target_coord = state.capital_coord
			inst.has_target = true
		"here":
			inst.target_faction = ""
			inst.target_coord = coord
			inst.has_target = true
		"fixed":
			inst.target_faction = ""
			inst.target_coord = opts.get("target_coord", coord)
			inst.has_target = true
		_:
			assign_target(state, inst)
	log_line(state, "Legion '%s' enters at Threat %d on %s" % [card_name, inst.threat, coord])
	if not bool(opts.get("ignore_immediate", false)):
		NemesisCards.legion_immediate(state, card_db, inst)
	if not bool(opts.get("no_combat", false)) and state.legions.has(inst):
		resolve_combat_at(state, card_db, inst.coord)
	return inst


## "Place a Horde" (rulebook p49, p53): like spawn_legion, with no Target.
## `threat` < 0 takes it from this Chapter's Event ("Horde at Threat N"),
## else 4. Can't draw one -> Chaos gains 1 VP.
static func spawn_horde(state: GameState, coord: Vector2i, card_db: Node = null, threat: int = -1, opts: Dictionary = {}) -> HordeInstance:
	var card_name: String = _draw_card(state, card_db, "Horde", bool(opts.get("from_box", false)))
	if card_name.is_empty():
		state.chaos_vp += 1
		log_line(state, "no Horde left to place - Chaos gains 1 VP")
		return null
	var inst := HordeInstance.new()
	inst.id = next_nemesis_id(state)
	inst.card_name = card_name
	inst.threat = mini(threat if threat > 0 else event_threat(state, card_db, "Horde"), max_threat(card_name))
	inst.coord = coord
	inst.activation_tokens = state.horde_deck_tokens
	state.horde_deck_tokens = 0
	state.hordes.append(inst)
	log_line(state, "Horde '%s' enters at Threat %d on %s" % [card_name, inst.threat, coord])
	if not bool(opts.get("ignore_immediate", false)):
		NemesisCards.horde_immediate(state, card_db, inst)
	if not bool(opts.get("no_combat", false)) and state.hordes.has(inst):
		resolve_combat_at(state, card_db, inst.coord)
	return inst


static func _draw_card(state: GameState, card_db: Node, kind: String, from_box: bool) -> String:
	var deck: Array[String] = state.legion_deck if kind == "Legion" else state.horde_deck
	if not from_box:
		return deck.pop_front() if not deck.is_empty() else ""
	if card_db == null:
		return ""
	var pool: Array[String] = []
	var cards: Array = card_db.legions if kind == "Legion" else card_db.hordes
	for c: Variant in cards:
		var name: String = c.card_name
		if deck.has(name) or _in_play(state, name):
			continue
		pool.append(name)
	if pool.is_empty():
		return ""
	pool.sort()
	return pool[(state.chapter * 7 + pool.size()) % pool.size()]


static func _in_play(state: GameState, card_name: String) -> bool:
	for l: LegionInstance in state.legions:
		if l.card_name == card_name:
			return true
	for h: HordeInstance in state.hordes:
		if h.card_name == card_name:
			return true
	return false


static func next_nemesis_id(state: GameState) -> int:
	var max_id: int = -1
	for l: LegionInstance in state.legions:
		max_id = maxi(max_id, l.id)
	for h: HordeInstance in state.hordes:
		max_id = maxi(max_id, h.id)
	return max_id + 1


static func max_threat(card_name: String) -> int:
	var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(card_name)
	return card.max_threat if card != null else 7


## Changes a Legion's or Horde's Threat; anything above its maximum scores
## its faction 1 VP per point instead (rulebook p45).
static func add_threat(state: GameState, entry: Variant, amount: int) -> void:
	var cap: int = max_threat(entry.card_name)
	var wanted: int = entry.threat + amount
	if wanted > cap:
		if entry is LegionInstance:
			state.empire_vp += wanted - cap
		else:
			state.chaos_vp += wanted - cap
		wanted = cap
	entry.threat = maxi(0, wanted)


## Default Threat for a Legion/Horde entering without one: the printed
## Threat of the latest revealed Event (rulebook p16, p45), 4 before any.
static func event_threat(state: GameState, _card_db: Node, _kind: String) -> int:
	var event_effects: GDScript = load("res://scripts/game/event_effects.gd")
	return int(event_effects.PRINTED_THREAT.get(state.latest_event, 4))


# --- Garrisons, Skeletons, Curses -----------------------------------------

## "Place N Garrisons here": each stacks one level; a 4th on a hex scores
## The Empire 1 VP instead - except on The Capital, where it goes to an
## empty hex with no X (rulebook p46-47, p50).
static func add_garrisons(state: GameState, coord: Vector2i, count: int) -> void:
	var tile: HexTileState = state.ensure_hex(coord)
	for _i: int in range(count):
		if tile.curse:
			state.empire_vp += 1  # a Cursed hex can't hold Garrisons
		elif tile.garrison_level < 3:
			tile.garrison_level += 1
		elif tile.role == "capital":
			place_garrison_on_empty_hex(state)
		else:
			state.empire_vp += 1


## "Place a Garrison on an empty hex with no X" (rulebook p47, p50): an
## empty hex has no Haven, Units or Curse; The Empire spreads out, so new
## hexes first (pick_hex), then a hex with a Legion, then stacking on
## another Garrison below 3. Can't -> The Empire gains 1 VP.
static func place_garrison_on_empty_hex(state: GameState) -> void:
	var empties: Array[Vector2i] = []
	for coord: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[coord]
		if no_x(t) and EffectUtil.hex_is_empty(state, coord):
			empties.append(coord)
	var best: Vector2i = pick_hex(state, empties)
	if best != Vector2i.MIN:
		state.hexes[best].garrison_level = 1
		return
	for coord2: Vector2i in state.hexes.keys():
		var t2: HexTileState = state.hexes[coord2]
		if no_x(t2) and t2.garrison_level == 0 and not t2.curse and t2.total_player_units() == 0 and t2.haven_faction.is_empty():
			for l: LegionInstance in state.legions:
				if l.coord == coord2:
					t2.garrison_level = 1
					return
	var stacks: Array = state.hexes.keys()
	stacks.sort()
	for coord3: Vector2i in stacks:
		var t3: HexTileState = state.hexes[coord3]
		if t3.garrison_level > 0 and t3.garrison_level < 3:
			t3.garrison_level += 1
			return
	state.empire_vp += 1


## Hexes that show no X: Haven-able spaces (not Region spaces, not The
## Capital).
static func no_x(tile: HexTileState) -> bool:
	return tile != null and tile.role != "outer" and tile.role != "capital"


## "Place 1 Curse here": a Curse destroys any Garrisons (to the Chaos
## Graveyard) and removes any Haven, Tower and Wall; an already Cursed hex
## scores Chaos 1 VP instead (rulebook p49).
static func place_curse_on(state: GameState, card_db: Node, coord: Vector2i) -> void:
	var tile: HexTileState = state.ensure_hex(coord)
	if tile.curse:
		state.chaos_vp += 1
		return
	place_curse(state, tile, card_db, coord)


static func place_curse(state: GameState, tile: HexTileState, card_db: Node = null, coord: Vector2i = Vector2i.MIN) -> void:
	tile.curse = true
	if tile.garrison_level > 0:
		state.chaos_graveyard["Empire"] = int(state.chaos_graveyard.get("Empire", 0)) + tile.garrison_level
		tile.garrison_level = 0
	if not tile.haven_faction.is_empty():
		if coord == Vector2i.MIN:
			for c: Vector2i in state.hexes.keys():
				if state.hexes[c] == tile:
					coord = c
		remove_haven(state, card_db, coord)


## "Place N Skeletons here" - 3 on one hex become a Horde (rulebook p48).
static func add_skeletons(state: GameState, card_db: Node, coord: Vector2i, count: int, in_combat: bool = false) -> void:
	var notes: Array[String] = []
	CombatResolver.add_skeletons(state, coord, count, notes, card_db, in_combat)
	log_line(state, "; ".join(notes))


## "Place 1 Skeleton with other Skeletons" (rulebook p51): onto a hex with
## 1 or 2 Skeletons - a hex with 1 first, so no Horde forms if avoidable -
## or an empty hex when there are none on the map.
static func place_skeleton_with_others(state: GameState, card_db: Node, count: int = 1) -> void:
	for _i: int in range(count):
		var ones: Array[Vector2i] = []
		var twos: Array[Vector2i] = []
		for coord: Vector2i in state.hexes.keys():
			var n: int = (state.hexes[coord] as HexTileState).skeleton_count
			if n == 1:
				ones.append(coord)
			elif n == 2:
				twos.append(coord)
		var target: Vector2i = pick_hex(state, ones)
		if target == Vector2i.MIN:
			target = pick_hex(state, twos)
		if target == Vector2i.MIN:
			target = pick_hex(state, empty_hexes(state))
		if target == Vector2i.MIN:
			state.chaos_vp += 1
			continue
		add_skeletons(state, card_db, target, 1)


## Empty hexes (no Haven, Units or Curse), optionally only those where
## `filter.call(coord, tile)` is true.
static func empty_hexes(state: GameState, filter: Callable = Callable()) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for coord: Vector2i in state.hexes.keys():
		if not EffectUtil.hex_is_empty(state, coord):
			continue
		if filter.is_valid() and not bool(filter.call(coord, state.hexes[coord])):
			continue
		out.append(coord)
	out.sort()
	return out


## The acting player's pick among `candidates`: farthest from any player
## Haven (keep the trouble away), ties to the first in sorted order.
## Vector2i.MIN when there is nothing to pick.
static func pick_hex(state: GameState, candidates: Array[Vector2i]) -> Vector2i:
	if candidates.is_empty():
		return Vector2i.MIN
	var havens: Array[Vector2i] = []
	for coord: Vector2i in state.hexes.keys():
		if not (state.hexes[coord] as HexTileState).haven_faction.is_empty():
			havens.append(coord)
	var sorted: Array[Vector2i] = candidates.duplicate()
	sorted.sort()
	var best: Vector2i = sorted[0]
	var best_score: int = -1
	for c: Vector2i in sorted:
		var nearest: int = 99
		for h: Vector2i in havens:
			nearest = mini(nearest, HexMath.distance(c, h))
		if nearest > best_score:
			best_score = nearest
			best = c
	return best


## True if any Haven is on or next to `coord`.
static func near_haven(state: GameState, coord: Vector2i) -> bool:
	var spots: Array[Vector2i] = [coord]
	spots.append_array(HexMath.neighbors(coord))
	for c: Vector2i in spots:
		var t: HexTileState = state.get_hex(c)
		if t != null and not t.haven_faction.is_empty():
			return true
	return false


# --- Movement -----------------------------------------------------------------

## Picks the best single step from `from` toward/away-from `target`,
## following the rulebook's priority tiers (p54-55): A) a Haven, fewest
## Units; B) a hex with enemy Units (player, or the other Nemesis
## faction), fewest Units/Threat; C) an empty hex (no Haven, Units or
## Curse); D) any remaining candidate. `toward` = true for Legions (must
## get strictly closer to target), false for Hordes (must not get farther
## from The Capital). "Closer" counts the route around impassable terrain.
static func _best_step(state: GameState, from: Vector2i, target: Vector2i, toward: bool, mover: String, mover_card: String = "") -> Vector2i:
	var here: HexTileState = state.get_hex(from)
	var on_tower: bool = here != null and here.role == "sea_tower" and here.explored
	# Adjacent to every hex: a Legion goes straight to its Target.
	if toward and (on_tower or mover_card == "The Warlock") and state.hexes.has(target):
		return target
	var routes: Dictionary = state.route_distances(target)
	var unreachable: int = 999999
	var current_dist: int = int(routes.get(from, unreachable))
	var candidates: Array[Vector2i] = []
	var steps: Array[Vector2i] = []
	if on_tower:
		for c: Vector2i in state.hexes.keys():
			if c != from:
				steps.append(c)
		steps.sort()
	else:
		steps = HexMath.neighbors(from)
	for n: Vector2i in steps:
		if not state.hexes.has(n) or (not on_tower and state.edge_blocked(from, n)):
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
		if EffectUtil.hex_is_empty(state, c):
			return c

	# Tier D: any candidate on the shortest route.
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
