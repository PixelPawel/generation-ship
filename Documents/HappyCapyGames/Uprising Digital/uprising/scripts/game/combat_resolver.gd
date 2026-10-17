class_name CombatResolver
extends RefCounted

## Combat sequence (rulebook p32-43, confirmed against the Combat Sequence
## reference card): Before Combat -> Archery Round (if any side has
## Archery dice) -> Clash Round(s), repeating until one side has no Units
## or a Legion/Horde hits 0 Threat -> After Combat.
##
## Every fight is one Combatant against another Combatant. A Combatant is a player
## faction's Unit stack, a Garrison stack, a Skeleton group, or one
## Legion/Horde. resolve_hex() lines up the fights a hex needs:
## - player Units fight Garrison, then Skeletons, then Legions/Hordes in
##   Initiative order (rulebook p21, p41) - each a separate combat;
## - then, if both remain, The Empire (Garrison, then Legions) fights
##   Chaos (Skeletons, then Hordes) the same way (rulebook p36, p44).
##
## Dice (2026-10-17):
## - Player Units roll the die printed on their player board
##   (PlayerboardTable.UnitEntry.die). Archers roll in Archery AND Clash,
##   Riders also in Archery on Badlands, Warriors only in Clash. A Tower
##   adds 1 white die to Archery and Clash, a Wall 1 blue die to Clash -
##   both only while the owner has Units there (rulebook p36, p42).
## - Garrisons use the rulebook p46 table by level, Skeletons 1 red die
##   each in Clash only (p48), Legions/Hordes their card row at current
##   Threat (LegionHordeCombatTable). The Courtesan copies her enemy's
##   dice each round.
## - Terrain (p37, p42), applied to both sides for the whole combat:
##   Woods - up to 2 Archery dice rerolled once (Nemesis only rerolls
##   blanks; the player side does the same, the sensible choice);
##   Highlands - only 1 Archery die, best kept in the order black,
##   purple, red, blue, yellow, white; Marshes - red dice become white in
##   Archery and Clash; Badlands - Riders add their dice to Archery;
##   Curse - only Chaos may use Bolts. Unexplored hexes and The Capital
##   have no terrain (EffectUtil.combat_terrain).
## - Bolts: player Bolts cancel 1 enemy Shield each. Skeleton Bolts are
##   their Godpower: place 1 more Skeleton here After Damage, and 3
##   Skeletons become a Horde (p48). Legion/Horde Godpower TEXT is still
##   not executed (no triggered-ability engine yet), so their Bolts fall
##   back to cancelling Shields - flagged, not silently dropped. Druid
##   Godpowers and Aether rerolls are likewise not offered yet.
## - Losses: the player's cheapest Units go first (Basic before Elite,
##   then lowest total cost) - a stand-in for "you decide which of your
##   Units are destroyed" until the UI can ask. Player Units killed by The
##   Empire go to the Imperial Graveyard, by Chaos to the Chaos Graveyard;
##   Skeletons killed by The Empire go to the Imperial Graveyard (as
##   "Chaos"), Garrisons killed by Chaos to the Chaos Graveyard (as
##   "Empire") (p34, p42). Players score 1 VP per Garrison level or
##   Skeleton destroyed, plus a Legion/Horde's on-destroy VP; when The
##   Empire and Chaos destroy each other's Legion/Horde the winner takes
##   that VP (p36).
## - After Combat: if the player lost every Unit and enemies remain, their
##   Haven, Tower and Wall here are removed (p36).
##
## Not automated yet (flagged): Legion/Horde combat abilities and
## on-destroy extra effects (only the flat VP is applied), Feats/Items in
## combat, and the Capital's "only non-Imperial Units here -> place a
## Legion" rule.

const MAX_ROUNDS: int = 30  # safety cap, not a rule
const HIGHLANDS_PREFERENCE: Array[String] = ["black", "purple", "red", "blue", "yellow", "white"]
const GARRISON_DICE: Dictionary = {
	1: {"archery": ["white"], "clash": ["blue", "white"]},
	2: {"archery": ["white", "white"], "clash": ["blue", "yellow", "yellow", "white"]},
	3: {"archery": ["white", "white", "white"], "clash": ["blue", "blue", "yellow", "yellow", "white"]},
}


class Result:
	var player_faction: String = ""
	var opponents_fought: Array[String] = []
	var player_units_lost: int = 0
	var vp_awarded: Dictionary = {}   # "self"/"Empire"/"Chaos" -> amount
	var log: Array[String] = []


class Combatant:
	var kind: String = ""        # "player" | "garrison" | "skeleton" | "legion" | "horde"
	var faction: String = ""     # player faction, else "Empire" / "Chaos"
	var legion: LegionInstance = null
	var horde: HordeInstance = null

	func allegiance() -> String:
		match kind:
			"player":
				return "player"
			"garrison", "legion":
				return "Empire"
		return "Chaos"

	func label() -> String:
		match kind:
			"player":
				return faction
			"garrison":
				return "Garrison"
			"skeleton":
				return "Skeleton"
			"legion":
				return legion.card_name
		return horde.card_name

	func card() -> LegionHordeCombatTable.CombatCard:
		if kind == "legion":
			return LegionHordeCombatTable.get_card(legion.card_name)
		if kind == "horde":
			return LegionHordeCombatTable.get_card(horde.card_name)
		return null


static func resolve_hex(state: GameState, coord: Vector2i, card_db: Node, rng: RandomNumberGenerator = null) -> Result:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var result := Result.new()
	var tile: HexTileState = state.get_hex(coord)
	if tile == null:
		return result
	var terrain: String = EffectUtil.combat_terrain(tile, card_db)

	var player_faction: String = tile.player_faction_here()
	result.player_faction = player_faction
	if not player_faction.is_empty():
		var me := Combatant.new()
		me.kind = "player"
		me.faction = player_faction
		# Re-pick the next opponent after every fight: a Skeleton fight can
		# spawn a fresh Horde here that must be fought too.
		var guard: int = 0
		while _strength(state, tile, me) > 0 and guard < 20:
			guard += 1
			var foe: Combatant = _next_opponent(state, coord, tile, "player")
			if foe == null:
				break
			_fight(state, coord, tile, terrain, me, foe, result, rng, card_db)
		if _strength(state, tile, me) <= 0 and _next_opponent(state, coord, tile, "player") != null and not tile.haven_faction.is_empty():
			result.log.append("%s lost every Unit - Haven and Defenses removed" % player_faction)
			NemesisAI.remove_haven(state, card_db, coord)

	if tile.total_player_units() <= 0:
		var guard2: int = 0
		while guard2 < 20:
			guard2 += 1
			var empire: Combatant = _next_opponent(state, coord, tile, "Chaos")
			var chaos: Combatant = _next_opponent(state, coord, tile, "Empire")
			if empire == null or chaos == null:
				break
			_fight(state, coord, tile, terrain, empire, chaos, result, rng, card_db)
	return result


## True if a hex holds Units of two sides that must fight.
static func hex_needs_combat(state: GameState, coord: Vector2i) -> bool:
	var tile: HexTileState = state.get_hex(coord)
	if tile == null:
		return false
	var has_empire: bool = _next_opponent(state, coord, tile, "Chaos") != null
	var has_chaos: bool = _next_opponent(state, coord, tile, "Empire") != null
	if tile.total_player_units() > 0:
		return has_empire or has_chaos
	return has_empire and has_chaos


## Next enemy for `viewer` ("player", "Empire" or "Chaos") on this hex, in
## fighting order: Garrison/Skeleton first, then Legions/Hordes by
## Initiative. null when no enemy is left.
static func _next_opponent(state: GameState, coord: Vector2i, tile: HexTileState, viewer: String) -> Combatant:
	var want_empire: bool = viewer != "Empire"
	var want_chaos: bool = viewer != "Chaos"
	if want_empire and tile.garrison_level > 0:
		var g := Combatant.new()
		g.kind = "garrison"
		g.faction = "Empire"
		return g
	if want_chaos and tile.skeleton_count > 0:
		var s := Combatant.new()
		s.kind = "skeleton"
		s.faction = "Chaos"
		return s
	var best: Combatant = null
	var best_init: int = 99999
	if want_empire:
		for l: LegionInstance in state.legions:
			if l.coord == coord and l.threat > 0 and _initiative(l.card_name) < best_init:
				best_init = _initiative(l.card_name)
				best = Combatant.new()
				best.kind = "legion"
				best.faction = "Empire"
				best.legion = l
	if want_chaos:
		for h: HordeInstance in state.hordes:
			if h.coord == coord and h.threat > 0 and _initiative(h.card_name) < best_init:
				best_init = _initiative(h.card_name)
				best = Combatant.new()
				best.kind = "horde"
				best.faction = "Chaos"
				best.horde = h
	return best


static func _initiative(card_name: String) -> int:
	var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(card_name)
	return card.initiative if card != null else 999


static func _strength(state: GameState, tile: HexTileState, side: Combatant) -> int:
	match side.kind:
		"player":
			return tile.unit_count(side.faction)
		"garrison":
			return tile.garrison_level
		"skeleton":
			return tile.skeleton_count
		"legion":
			return side.legion.threat if state.legions.has(side.legion) else 0
		"horde":
			return side.horde.threat if state.hordes.has(side.horde) else 0
	return 0


## One full combat between two Combatants: one Archery round (if anyone has
## Archery dice), then Clash rounds until one side is gone.
static func _fight(state: GameState, coord: Vector2i, tile: HexTileState, terrain: String,
		a: Combatant, b: Combatant, result: Result, rng: RandomNumberGenerator, card_db: Node) -> void:
	result.opponents_fought.append(b.label() if a.kind == "player" else "%s vs %s" % [a.label(), b.label()])
	var start_a: int = _strength(state, tile, a)
	var start_b: int = _strength(state, tile, b)

	var a_arch: Array[String] = _dice(state, tile, a, "archery", terrain)
	var b_arch: Array[String] = _dice(state, tile, b, "archery", terrain)
	if _copies_enemy(a):
		a_arch = b_arch.duplicate()
	if _copies_enemy(b):
		b_arch = a_arch.duplicate()
	if not a_arch.is_empty() or not b_arch.is_empty():
		_round(state, coord, tile, terrain, a, b, a_arch, b_arch, "archery", result, rng, card_db)

	var rounds: int = 0
	while _strength(state, tile, a) > 0 and _strength(state, tile, b) > 0 and rounds < MAX_ROUNDS:
		rounds += 1
		var a_clash: Array[String] = _dice(state, tile, a, "clash", terrain)
		var b_clash: Array[String] = _dice(state, tile, b, "clash", terrain)
		if _copies_enemy(a):
			a_clash = b_clash.duplicate()
		if _copies_enemy(b):
			b_clash = a_clash.duplicate()
		_round(state, coord, tile, terrain, a, b, a_clash, b_clash, "clash", result, rng, card_db)

	result.log.append("%s (%d) vs %s (%d) on %s terrain: %s %d left, %s %d left" % [
		a.label(), start_a, b.label(), start_b, terrain if not terrain.is_empty() else "no",
		a.label(), _strength(state, tile, a), b.label(), _strength(state, tile, b)])


static func _copies_enemy(side: Combatant) -> bool:
	var card: LegionHordeCombatTable.CombatCard = side.card()
	return card != null and card.copies_enemy_dice


## The dice a Combatant gathers for one round, terrain-adjusted.
static func _dice(state: GameState, tile: HexTileState, side: Combatant, round_type: String, terrain: String) -> Array[String]:
	var pool: Array[String] = []
	match side.kind:
		"player":
			var stack: Dictionary = tile.unit_stack(side.faction)
			for unit_name: Variant in stack.keys():
				var entry: PlayerboardTable.UnitEntry = PlayerboardTable.get_unit(side.faction, str(unit_name))
				var die: String = entry.die if entry != null else "yellow"
				var rolls: bool = round_type == "clash"
				if round_type == "archery" and entry != null:
					rolls = entry.is_archer() or (entry.is_rider() and terrain == "Badlands")
				if rolls:
					for _i: int in range(int(stack[unit_name])):
						pool.append(die)
			if tile.unit_count(side.faction) > 0 and tile.haven_faction == side.faction:
				if tile.tower:
					pool.append("white")
				if tile.wall and round_type == "clash":
					pool.append("blue")
		"garrison":
			var row: Dictionary = GARRISON_DICE.get(clampi(tile.garrison_level, 1, 3), {})
			for c: Variant in (row.get(round_type, []) as Array):
				pool.append(str(c))
		"skeleton":
			if round_type == "clash":
				for _i: int in range(tile.skeleton_count):
					pool.append("red")
		"legion", "horde":
			var card: LegionHordeCombatTable.CombatCard = side.card()
			var threat: int = _strength(state, tile, side)
			if card != null and not (round_type == "archery" and card.archery_skipped):
				var row2: Dictionary = card.dice.get(threat, {})
				for c2: Variant in (row2.get(round_type, []) as Array):
					pool.append(str(c2))

	if terrain == "Marshes":
		for i: int in range(pool.size()):
			if pool[i] == "red":
				pool[i] = "white"
	if terrain == "Highlands" and round_type == "archery" and pool.size() > 1:
		var keep: String = pool[0]
		for color: String in HIGHLANDS_PREFERENCE:
			if pool.has(color):
				keep = color
				break
		pool = [keep]
	return pool


## Rolls both pools at once, applies Woods rerolls, Bolts, Shields and
## damage, then After-Damage effects (Skeleton Bolts).
static func _round(state: GameState, coord: Vector2i, tile: HexTileState, terrain: String, a: Combatant, b: Combatant,
		a_pool: Array[String], b_pool: Array[String], round_type: String, result: Result, rng: RandomNumberGenerator, card_db: Node) -> void:
	var a_faces: Array = _roll_faces(a_pool, rng)
	var b_faces: Array = _roll_faces(b_pool, rng)
	if terrain == "Woods" and round_type == "archery":
		_reroll_blanks(a_pool, a_faces, 2, rng)
		_reroll_blanks(b_pool, b_faces, 2, rng)
	var a_sym: Dictionary = _count(a_faces)
	var b_sym: Dictionary = _count(b_faces)

	# Bolts. Only Chaos may use them on a Curse (p42, p49).
	var a_bolts: int = _usable_bolts(a, a_sym, terrain)
	var b_bolts: int = _usable_bolts(b, b_sym, terrain)
	var a_new_skeletons: int = a_bolts if a.kind == "skeleton" else 0
	var b_new_skeletons: int = b_bolts if b.kind == "skeleton" else 0
	var a_cancel: int = 0 if a.kind == "skeleton" else a_bolts
	var b_cancel: int = 0 if b.kind == "skeleton" else b_bolts

	var a_shields: int = maxi(0, int(a_sym["Shield"]) - b_cancel)
	var b_shields: int = maxi(0, int(b_sym["Shield"]) - a_cancel)
	var dmg_on_a: int = maxi(0, int(b_sym["Skull"]) - a_shields)
	var dmg_on_b: int = maxi(0, int(a_sym["Skull"]) - b_shields)

	_take_hits(state, tile, a, b, dmg_on_a, result)
	_take_hits(state, tile, b, a, dmg_on_b, result)

	# After Damage: each Skeleton Bolt places 1 more Skeleton here.
	for side_and_count: Array in [[a, a_new_skeletons], [b, b_new_skeletons]]:
		var count: int = side_and_count[1]
		if count > 0 and tile.skeleton_count > 0:
			result.log.append("Skeleton Bolt x%d: +%d Skeleton" % [count, count])
			add_skeletons(state, coord, count, result.log, card_db, true)


static func _roll_faces(pool: Array[String], rng: RandomNumberGenerator) -> Array:
	var faces: Array = []
	for c: String in pool:
		faces.append(DiceModel.roll(c, rng))
	return faces


static func _reroll_blanks(pool: Array[String], faces: Array, max_rerolls: int, rng: RandomNumberGenerator) -> void:
	var done: int = 0
	for i: int in range(faces.size()):
		if done >= max_rerolls:
			return
		if (faces[i] as Array).is_empty():
			faces[i] = DiceModel.roll(pool[i], rng)
			done += 1


static func _count(faces: Array) -> Dictionary:
	var counts: Dictionary = {"Skull": 0, "Shield": 0, "Bolt": 0}
	for face: Variant in faces:
		for symbol: Variant in (face as Array):
			counts[str(symbol)] = int(counts.get(str(symbol), 0)) + 1
	return counts


static func _usable_bolts(side: Combatant, symbols: Dictionary, terrain: String) -> int:
	if terrain == "Curse" and side.allegiance() != "Chaos":
		return 0
	return int(symbols["Bolt"])


## Applies `n` unblocked Skulls to `victim`, dealt by `killer`.
static func _take_hits(state: GameState, tile: HexTileState, victim: Combatant, killer: Combatant, n: int, result: Result) -> void:
	if n <= 0:
		return
	match victim.kind:
		"player":
			for _i: int in range(n):
				var unit_name: String = _cheapest_unit(tile, victim.faction)
				if unit_name.is_empty():
					break
				tile.remove_unit(victim.faction, unit_name)
				result.player_units_lost += 1
				var graveyard: Dictionary = state.imperial_graveyard if killer.allegiance() == "Empire" else state.chaos_graveyard
				graveyard[victim.faction] = int(graveyard.get(victim.faction, 0)) + 1
				var owner: PlayerFactionState = state.find_player(victim.faction)
				if owner != null:
					owner.graveyard_units[unit_name] = int(owner.graveyard_units.get(unit_name, 0)) + 1
		"garrison":
			var levels: int = mini(n, tile.garrison_level)
			tile.garrison_level -= levels
			if killer.kind == "player":
				_award_player(state, killer.faction, levels, result)
			elif levels > 0:
				state.chaos_graveyard["Empire"] = int(state.chaos_graveyard.get("Empire", 0)) + levels
		"skeleton":
			var killed: int = mini(n, tile.skeleton_count)
			tile.skeleton_count -= killed
			if killer.kind == "player":
				_award_player(state, killer.faction, killed, result)
			elif killed > 0:
				state.imperial_graveyard["Chaos"] = int(state.imperial_graveyard.get("Chaos", 0)) + killed
		"legion", "horde":
			var card: LegionHordeCombatTable.CombatCard = victim.card()
			if victim.kind == "legion":
				victim.legion.threat = maxi(0, victim.legion.threat - n)
				if victim.legion.threat > 0:
					return
				state.legions.erase(victim.legion)
			else:
				victim.horde.threat = maxi(0, victim.horde.threat - n)
				if victim.horde.threat > 0:
					return
				state.hordes.erase(victim.horde)
			var vp: int = card.on_destroy_vp if card != null else 0
			result.log.append("%s destroyed (+%d VP to %s)" % [victim.label(), vp, killer.label() if killer.kind == "player" else killer.allegiance()])
			if killer.kind == "player":
				_award_player(state, killer.faction, vp, result)
			elif killer.allegiance() == "Empire":
				state.empire_vp += vp
				result.vp_awarded["Empire"] = int(result.vp_awarded.get("Empire", 0)) + vp
			else:
				state.chaos_vp += vp
				result.vp_awarded["Chaos"] = int(result.vp_awarded.get("Chaos", 0)) + vp


static func _award_player(state: GameState, faction: String, vp: int, result: Result) -> void:
	if vp <= 0:
		return
	var p: PlayerFactionState = state.find_player(faction)
	if p != null:
		p.vp += vp
	result.vp_awarded["self"] = int(result.vp_awarded.get("self", 0)) + vp


## Basic before Elite, then lowest total printed cost.
static func _cheapest_unit(tile: HexTileState, faction: String) -> String:
	var best: String = ""
	var best_score: int = 999999
	for unit_name: Variant in tile.unit_stack(faction).keys():
		var entry: PlayerboardTable.UnitEntry = PlayerboardTable.get_unit(faction, str(unit_name))
		var score: int = 500
		if entry != null:
			score = (0 if entry.is_basic() else 100) + _cost_total(entry.cost)
		if score < best_score:
			best_score = score
			best = str(unit_name)
	return best


static func _cost_total(cost: Dictionary) -> int:
	match str(cost.get("type", "fixed")):
		"any":
			return int(cost.get("amount", 0))
		"or":
			return mini(int(cost.get("Salt", 0)), int(cost.get("Plunder", 0)))
	return int(cost.get("Salt", 0)) + int(cost.get("Plunder", 0)) + int(cost.get("Food", 0))


## Places `count` Skeletons on `coord`; whenever 3 share the hex they are
## removed and become 1 new Horde there (rulebook p48). `in_combat`: the
## new Horde waits for the running combat loop to fight it.
static func add_skeletons(state: GameState, coord: Vector2i, count: int, log: Array[String], card_db: Node = null, in_combat: bool = false) -> void:
	var tile: HexTileState = state.ensure_hex(coord)
	for _i: int in range(count):
		tile.skeleton_count += 1
		if tile.skeleton_count >= 3:
			tile.skeleton_count -= 3
			var h: HordeInstance = NemesisAI.spawn_horde(state, coord, card_db, -1, {"no_combat": in_combat})
			if h != null:
				log.append("3 Skeletons on %s become Horde '%s'" % [coord, h.card_name])
			else:
				log.append("3 Skeletons on %s: no Horde left to draw, Chaos +1 VP" % coord)
