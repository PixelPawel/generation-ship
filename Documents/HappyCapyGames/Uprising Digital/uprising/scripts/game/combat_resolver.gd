class_name CombatResolver
extends RefCounted

## Combat sequence (rulebook p32-43, confirmed against the Combat Sequence
## reference card): Before Combat -> Archery Round (if any side has
## Archery dice) -> Clash Round(s), repeating until one side has no Units
## or a Legion/Horde hits 0 Threat -> After Combat.
##
## Deliberately scoped down for this first pass, each documented rather
## than silently assumed:
## - Only PLAYER-vs-NEMESIS combat is resolved. Empire-vs-Chaos combat
##   (when a Legion and Horde share a hex) is a real rulebook case but
##   genuinely rare in practice (both would have to path onto the same
##   hex) and is not implemented here - flagged, not silently dropped.
## - Per-Unit standee die color is a documented unresolved gap (see the
##   approved plan) - ALL player Units use a placeholder "blue" die and
##   contribute to BOTH Archery and Clash (the rulebook distinguishes
##   Archer-type Units from Warrior/Rider for the Archery round, but
##   HexTileState only tracks a per-faction Unit COUNT, not per-type -
##   same simplification PlaceUnitOp already uses).
## - Garrison per-level dice weren't found in this pass's source images
##   (Playeraid_Back.jpg turned out to be the Combat Sequence chart, not
##   a Garrison dice table) - Garrisons use 1 placeholder "white" die per
##   level pending that image being located.
## - Godpowers are not activated - a rolled Bolt always just cancels 1
##   enemy Shield (the OTHER of its two rulebook uses), never triggers a
##   Godpower, since Godpower text isn't parsed into executable effects
##   yet (same "triggered ability" boundary Milestone 3 already scoped out).
## - Terrain modifiers (reroll, Swamp red->white, Highlands 1-die-only,
##   Badlands rider bonus) are NOT applied - HexTileState doesn't carry a
##   terrain-type-to-modifier lookup wired up yet in this file.

class Result:
	var player_faction: String = ""
	var opponents_fought: Array[String] = []
	var player_units_lost: int = 0
	var vp_awarded: Dictionary = {}   # "self"/"Empire"/"Chaos" -> amount
	var log: Array[String] = []


static func resolve_hex(state: GameState, coord: Vector2i, card_db: Node, rng: RandomNumberGenerator = null) -> Result:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var result := Result.new()
	var tile: HexTileState = state.get_hex(coord)
	if tile == null:
		return result

	var player_faction: String = ""
	for f: Variant in tile.units.keys():
		if int(tile.units[f]) > 0:
			player_faction = str(f)
			break
	if player_faction.is_empty():
		return result
	result.player_faction = player_faction

	if tile.garrison_level > 0:
		_fight_garrison(state, tile, result, rng)
	if int(tile.units.get(player_faction, 0)) > 0 and tile.skeleton_count > 0:
		_fight_skeleton(state, tile, result, rng)

	var legions_here: Array[LegionInstance] = []
	for l: LegionInstance in state.legions:
		if l.coord == coord:
			legions_here.append(l)
	legions_here.sort_custom(func(a: LegionInstance, b: LegionInstance) -> bool:
		return _initiative(a.card_name) < _initiative(b.card_name))
	for l: LegionInstance in legions_here:
		if int(tile.units.get(player_faction, 0)) <= 0:
			break
		_fight_legion(state, tile, l, result, rng)

	var hordes_here: Array[HordeInstance] = []
	for h: HordeInstance in state.hordes:
		if h.coord == coord:
			hordes_here.append(h)
	hordes_here.sort_custom(func(a: HordeInstance, b: HordeInstance) -> bool:
		return _initiative(a.card_name) < _initiative(b.card_name))
	for h: HordeInstance in hordes_here:
		if int(tile.units.get(player_faction, 0)) <= 0:
			break
		_fight_horde(state, tile, h, result, rng)

	if int(tile.units.get(player_faction, 0)) <= 0 and not (tile.haven_faction.is_empty()):
		tile.haven_faction = ""
		tile.tower = false
		tile.wall = false

	return result


static func _initiative(card_name: String) -> int:
	var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(card_name)
	return card.initiative if card != null else 999


## Rolls one Archery + one-or-more Clash rounds between the player's Units
## at `tile` and an opponent dice pool that regenerates each Clash round
## (Garrison/Skeleton/Legion/Horde all roll the SAME pool every round per
## the rulebook - only Threat, which caps how many Skulls a Legion/Horde
## can absorb, changes round to round). Returns true if the opponent was
## destroyed.
static func _fight(state: GameState, tile: HexTileState, player_faction: String,
		opponent_archery: Array, opponent_clash: Array, opponent_threat: int,
		on_opponent_skull: Callable, result: Result, rng: RandomNumberGenerator) -> bool:
	var player_units: int = int(tile.units.get(player_faction, 0))
	var tower_bonus: int = 1 if tile.tower and player_units > 0 else 0
	var wall_bonus: int = 1 if tile.wall and player_units > 0 else 0

	# Archery round (once, only if either side has Archery dice).
	if not opponent_archery.is_empty() or tower_bonus > 0:
		var player_archery: Array = []
		for _i: int in range(player_units):
			player_archery.append("blue")  # placeholder Unit die color, see class doc
		for _i: int in range(tower_bonus):
			player_archery.append("white")
		var enemy_symbols: Dictionary = DiceModel.roll_pool(opponent_archery, rng)
		var player_symbols: Dictionary = DiceModel.roll_pool(player_archery, rng)
		var outcome: Dictionary = _apply_damage(state, tile, player_faction, player_units,
			player_symbols, enemy_symbols, opponent_threat, on_opponent_skull, result)
		player_units = outcome["player_units"]
		opponent_threat = outcome["opponent_threat"]
		if outcome["opponent_destroyed"]:
			return true
		if player_units <= 0:
			return false

	# Clash round(s), repeat until one side has no Units or opponent hits 0 Threat.
	var rounds: int = 0
	while player_units > 0 and opponent_threat > 0 and rounds < 20:  # safety cap, not a rule
		rounds += 1
		var player_clash: Array = []
		for _i: int in range(player_units):
			player_clash.append("blue")
		for _i: int in range(wall_bonus):
			player_clash.append("blue")
		for _i: int in range(tower_bonus):
			player_clash.append("white")
		var enemy_symbols: Dictionary = DiceModel.roll_pool(opponent_clash, rng)
		var player_symbols: Dictionary = DiceModel.roll_pool(player_clash, rng)
		var outcome: Dictionary = _apply_damage(state, tile, player_faction, player_units,
			player_symbols, enemy_symbols, opponent_threat, on_opponent_skull, result)
		player_units = outcome["player_units"]
		opponent_threat = outcome["opponent_threat"]
		if outcome["opponent_destroyed"]:
			return true

	return false


static func _apply_damage(state: GameState, tile: HexTileState, player_faction: String, player_units: int,
		player_symbols: Dictionary, enemy_symbols: Dictionary, opponent_threat: int,
		on_opponent_skull: Callable, result: Result) -> Dictionary:
	# Bolts cancel Shields (simplified - see class doc: Godpowers not activated).
	var enemy_shields: int = int(enemy_symbols.get("Shield", 0)) - int(player_symbols.get("Bolt", 0))
	var player_shields: int = int(player_symbols.get("Shield", 0)) - int(enemy_symbols.get("Bolt", 0))
	var skulls_on_player: int = maxi(0, int(enemy_symbols.get("Skull", 0)) - maxi(0, player_shields))
	var skulls_on_enemy: int = maxi(0, int(player_symbols.get("Skull", 0)) - maxi(0, enemy_shields))

	var lost: int = mini(player_units, skulls_on_player)
	player_units -= lost
	result.player_units_lost += lost
	tile.units[player_faction] = maxi(0, player_units)

	var opponent_destroyed: bool = false
	for _i: int in range(skulls_on_enemy):
		if opponent_threat <= 0:
			break
		opponent_threat -= 1
		if on_opponent_skull.is_valid():
			on_opponent_skull.call()
		if opponent_threat <= 0:
			opponent_destroyed = true
			break

	return {"player_units": player_units, "opponent_threat": opponent_threat, "opponent_destroyed": opponent_destroyed}


static func _fight_garrison(state: GameState, tile: HexTileState, result: Result, rng: RandomNumberGenerator) -> void:
	var level: int = tile.garrison_level
	var archery: Array = []
	var clash: Array = []
	for _i: int in range(level):
		archery.append("white")  # placeholder, see class doc
		clash.append("white")
	var on_skull := func() -> void:
		tile.garrison_level = maxi(0, tile.garrison_level - 1)
		result.vp_awarded["self"] = int(result.vp_awarded.get("self", 0)) + 1
		var p: PlayerFactionState = state.find_player(result.player_faction)
		if p != null:
			p.vp += 1
	var destroyed: bool = _fight(state, tile, result.player_faction, archery, clash, level, on_skull, result, rng)
	result.opponents_fought.append("Garrison")
	result.log.append("Fought Garrison (level %d), destroyed=%s" % [level, destroyed])


static func _fight_skeleton(state: GameState, tile: HexTileState, result: Result, rng: RandomNumberGenerator) -> void:
	var count: int = tile.skeleton_count
	var pool: Array = []
	for _i: int in range(count):
		pool.append("red")
	var on_skull := func() -> void:
		tile.skeleton_count = maxi(0, tile.skeleton_count - 1)
		var p: PlayerFactionState = state.find_player(result.player_faction)
		if p != null:
			p.vp += 1
	_fight(state, tile, result.player_faction, [], pool, count, on_skull, result, rng)
	result.opponents_fought.append("Skeleton")
	result.log.append("Fought %d Skeletons" % count)


static func _fight_legion(state: GameState, tile: HexTileState, legion: LegionInstance, result: Result, rng: RandomNumberGenerator) -> void:
	var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(legion.card_name)
	if card == null or card.copies_enemy_dice:
		result.log.append("Skipped combat dice for '%s' (no table or copy-enemy special ability, not automated)" % legion.card_name)
		return
	var row: Dictionary = card.dice.get(legion.threat, {"archery": [], "clash": []})
	var on_skull := func() -> void:
		legion.threat -= 1
	var destroyed: bool = _fight(state, tile, result.player_faction, row.get("archery", []), row.get("clash", []), legion.threat, on_skull, result, rng)
	if destroyed:
		state.legions.erase(legion)
		var p: PlayerFactionState = state.find_player(result.player_faction)
		if p != null:
			p.vp += card.on_destroy_vp
			result.vp_awarded["self"] = int(result.vp_awarded.get("self", 0)) + card.on_destroy_vp
	result.opponents_fought.append(legion.card_name)
	result.log.append("Fought Legion '%s', destroyed=%s" % [legion.card_name, destroyed])


static func _fight_horde(state: GameState, tile: HexTileState, horde: HordeInstance, result: Result, rng: RandomNumberGenerator) -> void:
	var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(horde.card_name)
	if card == null:
		result.log.append("Skipped combat dice for '%s' (no table found, not automated)" % horde.card_name)
		return
	var row: Dictionary = card.dice.get(horde.threat, {"archery": [], "clash": []})
	var archery: Array = [] if card.archery_skipped else row.get("archery", [])
	var on_skull := func() -> void:
		horde.threat -= 1
	var destroyed: bool = _fight(state, tile, result.player_faction, archery, row.get("clash", []), horde.threat, on_skull, result, rng)
	if destroyed:
		state.hordes.erase(horde)
		var p: PlayerFactionState = state.find_player(result.player_faction)
		if p != null:
			p.vp += card.on_destroy_vp
			result.vp_awarded["self"] = int(result.vp_awarded.get("self", 0)) + card.on_destroy_vp
	result.opponents_fought.append(horde.card_name)
	result.log.append("Fought Horde '%s', destroyed=%s" % [horde.card_name, destroyed])
