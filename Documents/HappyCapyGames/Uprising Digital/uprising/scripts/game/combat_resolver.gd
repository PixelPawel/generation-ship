class_name CombatResolver
extends RefCounted

## Combat sequence (rulebook p32-43, confirmed against the Combat Sequence
## reference card): Before Combat -> Archery Round (if any side has
## Archery dice) -> Clash Round(s), repeating until one side has no Units
## or a Legion/Horde hits 0 Threat -> After Combat.
##
## Every fight is one Combatant against another Combatant. A Combatant is
## a player faction's Unit stack, a Garrison stack, a Skeleton group, or
## one Legion/Horde. resolve_hex() lines up the fights a hex needs:
## - player Units fight Garrison, then Skeletons, then Legions/Hordes in
##   Initiative order (rulebook p21, p41) - each a separate combat;
## - then, if both remain, The Empire (Garrison, then Legions) fights
##   Chaos (Skeletons, then Hordes) the same way (rulebook p36, p44).
##
## Dice:
## - Player Units roll the die printed on their player board
##   (PlayerboardTable.UnitEntry.die). Archers roll in Archery AND Clash,
##   Riders also in Archery on Badlands, Warriors only in Clash. A Tower
##   adds 1 white die to Archery and Clash, a Wall 1 blue die to Clash -
##   both only while the owner has Units there (rulebook p36, p42).
## - Garrisons use the rulebook p46 table by level, Skeletons 1 red die
##   each in Clash only (p48), Legions/Hordes their card row at current
##   Threat (LegionHordeCombatTable). The Courtesan copies her enemy's dice.
## - Terrain (p37, p42) for the whole combat: Woods - up to 2 Archery dice
##   rerolled once (blanks); Highlands - only 1 Archery die (black, purple,
##   red, blue, yellow, white preferred); Marshes - red dice become white;
##   Badlands - Riders add their dice to Archery; Curse - only Chaos may use
##   Bolts. Unexplored hexes and The Capital have no terrain.
##
## Card powers (Legions.csv / Hordes.csv Combat and Bolt columns):
## - Combat abilities: Assassin +2 red / Imperial Guard +1 red / New
##   Emperor +2 red in Archery on Badlands; Executioner +1 purple with a
##   Target on the hex; False Messiah +1 red in Clash on a hex with a Haven
##   or Garrison; Oda - no Archery round at all; Siren - her enemies can't
##   use Bolts; Spymaster - his enemies can't use Shields; Banished -
##   rerolls up to 2 blanks each round.
## - Godpowers: "Whenever they roll a Bolt, they will always activate their
##   Godpower"; once a once-per-round/-combat Godpower is spent, further
##   Bolts cancel the enemy's Shields (rulebook p40). "...or lose 2 Threat"
##   Godpowers hit a player (Item, Unit, Feats) or, against the other
##   Nemesis, its Threat. Skeleton Bolts add a Skeleton After Damage.
## - Player Bolts: a face-up Druid's Godpower when it pays off (Silence when
##   the hit would wipe the stack, Mountain Heart against a lethal die,
##   Treemother, Deep Dweller, Faceless One, Shapeshifter, Wanderer), else
##   cancel an enemy Shield. Red Hand, Watcher and Aether are not offered.
## - Kept Quest cards: Deepling Allies ignores Highlands, Tua Than Allies
##   +1 blue in Clash on Marshes, Ramparts lets a Wall/Tower take 1 hit per
##   round; Break the Shackles (face-up) pays 2 resources per Legion or
##   Garrison stack destroyed.
## - Losses: the player's cheapest Units go first (Basic before Elite, then
##   lowest cost). Graveyards per rulebook p34/p42. Players score 1 VP per
##   Garrison level or Skeleton destroyed; destroyed Legions/Hordes resolve
##   their bottom effect (destroy_nemesis).
## - After Combat: if the player lost every Unit and enemies remain, their
##   Haven, Tower and Wall here are removed (p36).
## Not automated: Feats and Items in combat.

const NemesisCards := preload("res://scripts/game/nemesis_cards.gd")

const MAX_ROUNDS: int = 30  # safety cap, not a rule
const HIGHLANDS_PREFERENCE: Array[String] = ["black", "purple", "red", "blue", "yellow", "white"]
const GARRISON_DICE: Dictionary = {
	1: {"archery": ["white"], "clash": ["blue", "white"]},
	2: {"archery": ["white", "white"], "clash": ["blue", "yellow", "yellow", "white"]},
	3: {"archery": ["white", "white", "white"], "clash": ["blue", "blue", "yellow", "yellow", "white"]},
}
## card -> [limit "none"|"round"|"combat", timing "before"|"after"]
const GODPOWERS: Dictionary = {
	"The Courtesan": ["round", "before"], "The Warlock": ["none", "after"], "The Spymaster": ["round", "before"],
	"The Assassin": ["round", "before"], "The Imperial Guard": ["round", "before"], "The Mage Breaker": ["round", "before"],
	"The Executioner": ["combat", "after"], "The New Emperor": ["round", "before"],
	"Lichqueen": ["round", "before"], "Coven of Yssat": ["combat", "before"], "Counter of Omens": ["round", "after"],
	"Bloodwyrm": ["combat", "after"], "Siren": ["combat", "after"], "Banished": ["round", "before"],
	"False Messiah": ["combat", "before"], "Oda the Fallen": ["none", "before"],
}
## Druid -> [limit, timing] for the Godpowers players can trigger with Bolts.
const DRUID_POWERS: Dictionary = {
	"Silence": ["combat", "before"], "Mountain Heart": ["round", "before"], "Treemother": ["round", "after"],
	"Deep Dweller": ["combat", "after"], "Faceless One": ["combat", "after"], "Shapeshifter": ["combat", "before"],
	"Wanderer": ["combat", "before"],
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
	var used_round: Dictionary = {}
	var used_combat: Dictionary = {}
	var escaped: bool = false

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

	func card_name() -> String:
		if kind == "legion":
			return legion.card_name
		if kind == "horde":
			return horde.card_name
		return ""

	func entry() -> Variant:
		return legion if kind == "legion" else horde

	func card() -> LegionHordeCombatTable.CombatCard:
		if kind == "legion":
			return LegionHordeCombatTable.get_card(legion.card_name)
		if kind == "horde":
			return LegionHordeCombatTable.get_card(horde.card_name)
		return null


## One side's view of a round in progress.
class RoundSide:
	var pool: Array[String] = []
	var faces: Array = []
	var skulls: int = 0
	var shields: int = 0
	var bolts: int = 0
	var extra_skulls: int = 0
	var extra_shields: int = 0
	var cancels: int = 0          # enemy Shields this side's Bolts cancel
	var new_skeletons: int = 0
	var after: Array[String] = [] # Godpowers resolving After Damage
	var ignore_skulls: bool = false
	var skull_reduction: int = 0  # Mountain Heart, on this side's dice


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
	if side.escaped:
		return 0
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


## One full combat between two sides: one Archery round (if anyone has
## Archery dice and Oda isn't involved), then Clash rounds until one side
## is gone.
static func _fight(state: GameState, coord: Vector2i, tile: HexTileState, terrain: String,
		a: Combatant, b: Combatant, result: Result, rng: RandomNumberGenerator, card_db: Node) -> void:
	result.opponents_fought.append(b.label() if a.kind == "player" else "%s vs %s" % [a.label(), b.label()])
	a.used_combat = {}
	b.used_combat = {}
	var start_a: int = _strength(state, tile, a)
	var start_b: int = _strength(state, tile, b)

	var skip_archery: bool = a.card_name() == "Oda the Fallen" or b.card_name() == "Oda the Fallen"
	if not skip_archery:
		var a_arch: Array[String] = _dice(state, tile, a, "archery", terrain, coord)
		var b_arch: Array[String] = _dice(state, tile, b, "archery", terrain, coord)
		if _copies_enemy(a):
			a_arch = b_arch.duplicate()
		if _copies_enemy(b):
			b_arch = a_arch.duplicate()
		if not a_arch.is_empty() or not b_arch.is_empty():
			_round(state, coord, tile, terrain, a, b, a_arch, b_arch, "archery", result, rng, card_db)

	var rounds: int = 0
	while _strength(state, tile, a) > 0 and _strength(state, tile, b) > 0 and rounds < MAX_ROUNDS:
		rounds += 1
		var a_clash: Array[String] = _dice(state, tile, a, "clash", terrain, coord)
		var b_clash: Array[String] = _dice(state, tile, b, "clash", terrain, coord)
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


static func _holds(state: GameState, faction: String, quest: String) -> bool:
	var p: PlayerFactionState = state.find_player(faction)
	return p != null and p.quests_in_play.has(quest)


## The dice a side gathers for one round, terrain-adjusted.
static func _dice(state: GameState, tile: HexTileState, side: Combatant, round_type: String, terrain: String, coord: Vector2i = Vector2i.MIN) -> Array[String]:
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
			if round_type == "clash" and terrain == "Marshes" and _holds(state, side.faction, "Tua Than Allies"):
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
			pool.append_array(_ability_dice(state, tile, side, round_type, terrain, coord))

	if terrain == "Marshes":
		for i: int in range(pool.size()):
			if pool[i] == "red":
				pool[i] = "white"
	var ignores_highlands: bool = side.kind == "player" and _holds(state, side.faction, "Deepling Allies")
	if terrain == "Highlands" and round_type == "archery" and pool.size() > 1 and not ignores_highlands:
		var keep: String = pool[0]
		for color: String in HIGHLANDS_PREFERENCE:
			if pool.has(color):
				keep = color
				break
		pool = [keep]
	return pool


## Combat-ability dice printed on Legion/Horde cards.
static func _ability_dice(state: GameState, tile: HexTileState, side: Combatant, round_type: String, terrain: String, coord: Vector2i) -> Array[String]:
	var out: Array[String] = []
	var badlands_archery: bool = round_type == "archery" and terrain == "Badlands"
	match side.card_name():
		"The Assassin", "The New Emperor":
			if badlands_archery:
				out.append_array(["red", "red"])
		"The Imperial Guard":
			if badlands_archery:
				out.append("red")
		"The Executioner":
			if coord == Vector2i.MIN:
				coord = _coord_of(state, tile)
			for l: LegionInstance in state.legions:
				if l.has_target and l.target_coord == coord:
					out.append("purple")
					break
		"False Messiah":
			if round_type == "clash" and (not tile.haven_faction.is_empty() or tile.garrison_level > 0):
				out.append("red")
	return out


static func _coord_of(state: GameState, tile: HexTileState) -> Vector2i:
	for c: Vector2i in state.hexes.keys():
		if state.hexes[c] == tile:
			return c
	return Vector2i.MIN


## Rolls both pools at once and resolves rerolls, Bolts (Godpowers or
## Shield cancels), Shields, damage and After-Damage effects.
static func _round(state: GameState, coord: Vector2i, tile: HexTileState, terrain: String, a: Combatant, b: Combatant,
		a_pool: Array[String], b_pool: Array[String], round_type: String, result: Result, rng: RandomNumberGenerator, card_db: Node) -> void:
	a.used_round = {}
	b.used_round = {}
	var sa := RoundSide.new()
	var sb := RoundSide.new()
	sa.pool = a_pool
	sb.pool = b_pool
	sa.faces = _roll_faces(a_pool, rng)
	sb.faces = _roll_faces(b_pool, rng)
	if terrain == "Woods" and round_type == "archery":
		_reroll_blanks(sa.pool, sa.faces, 2, rng)
		_reroll_blanks(sb.pool, sb.faces, 2, rng)
	if a.card_name() == "Banished":
		_reroll_blanks(sa.pool, sa.faces, 2, rng)
	if b.card_name() == "Banished":
		_reroll_blanks(sb.pool, sb.faces, 2, rng)
	_count_into(sa)
	_count_into(sb)

	_use_bolts(state, coord, tile, terrain, a, b, sa, sb, result, card_db, rng)
	_use_bolts(state, coord, tile, terrain, b, a, sb, sa, result, card_db, rng)

	# Shields; The Spymaster's enemies can't use them.
	var a_shields: int = 0 if b.card_name() == "The Spymaster" else maxi(0, sa.shields + sa.extra_shields - sb.cancels)
	var b_shields: int = 0 if a.card_name() == "The Spymaster" else maxi(0, sb.shields + sb.extra_shields - sa.cancels)
	var a_skulls: int = maxi(0, sa.skulls + sa.extra_skulls - sa.skull_reduction)
	var b_skulls: int = maxi(0, sb.skulls + sb.extra_skulls - sb.skull_reduction)
	if sa.ignore_skulls or sb.ignore_skulls:
		a_skulls = 0
		b_skulls = 0
	var dmg_on_a: int = maxi(0, b_skulls - a_shields)
	var dmg_on_b: int = maxi(0, a_skulls - b_shields)

	_take_hits(state, card_db, coord, tile, a, b, dmg_on_a, result)
	_take_hits(state, card_db, coord, tile, b, a, dmg_on_b, result)

	# After Damage.
	for pair: Array in [[a, b, sa], [b, a, sb]]:
		var side: Combatant = pair[0]
		var enemy: Combatant = pair[1]
		var rs: RoundSide = pair[2]
		for power: String in rs.after:
			_after_damage_power(state, card_db, coord, tile, side, enemy, power, result)
		if rs.new_skeletons > 0 and tile.skeleton_count > 0:
			result.log.append("Skeleton Bolt x%d: +%d Skeleton" % [rs.new_skeletons, rs.new_skeletons])
			add_skeletons(state, coord, rs.new_skeletons, result.log, card_db, true)


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


static func _count_into(rs: RoundSide) -> void:
	rs.skulls = 0
	rs.shields = 0
	rs.bolts = 0
	for face: Variant in rs.faces:
		for symbol: Variant in (face as Array):
			match str(symbol):
				"Skull":
					rs.skulls += 1
				"Shield":
					rs.shields += 1
				"Bolt":
					rs.bolts += 1


## Kept for callers that only need totals.
static func _count(faces: Array) -> Dictionary:
	var counts: Dictionary = {"Skull": 0, "Shield": 0, "Bolt": 0}
	for face: Variant in faces:
		for symbol: Variant in (face as Array):
			counts[str(symbol)] = int(counts.get(str(symbol), 0)) + 1
	return counts


static func _usable_bolts(side: Combatant, enemy: Combatant, bolts: int, terrain: String) -> int:
	if terrain == "Curse" and side.allegiance() != "Chaos":
		return 0
	if enemy.card_name() == "Siren":
		return 0
	return bolts


static func _limit_free(side: Combatant, power: String, limit: String) -> bool:
	match limit:
		"round":
			return not side.used_round.has(power)
		"combat":
			return not side.used_combat.has(power)
	return true


static func _mark(side: Combatant, power: String, limit: String) -> void:
	if limit == "round":
		side.used_round[power] = true
	elif limit == "combat":
		side.used_combat[power] = true


## Spends `side`'s Bolts for this round: Skeletons breed, Legions/Hordes
## fire their Godpower (spent limits -> cancel Shields), players use a
## Druid when it pays off, else cancel Shields.
static func _use_bolts(state: GameState, coord: Vector2i, tile: HexTileState, terrain: String, side: Combatant, enemy: Combatant,
		mine: RoundSide, theirs: RoundSide, result: Result, card_db: Node, rng: RandomNumberGenerator) -> void:
	var bolts: int = _usable_bolts(side, enemy, mine.bolts, terrain)
	if bolts <= 0:
		return
	match side.kind:
		"skeleton":
			mine.new_skeletons += bolts
		"legion", "horde":
			var spec: Array = GODPOWERS.get(side.card_name(), ["none", "none"])
			for _i: int in range(bolts):
				var limit: String = spec[0]
				if spec[1] == "none" or not _limit_free(side, side.card_name(), limit):
					mine.cancels += 1
					continue
				_mark(side, side.card_name(), limit)
				if spec[1] == "after":
					mine.after.append(side.card_name())
				else:
					_before_damage_power(state, card_db, coord, tile, side, enemy, mine, theirs, result)
		"player":
			for _j: int in range(bolts):
				_player_bolt(state, card_db, coord, tile, side, enemy, mine, theirs, result, rng)
		_:
			mine.cancels += bolts


## Legion/Horde Godpowers that resolve Before Damage (or have no timing).
static func _before_damage_power(state: GameState, card_db: Node, coord: Vector2i, tile: HexTileState, side: Combatant, enemy: Combatant,
		mine: RoundSide, theirs: RoundSide, result: Result) -> void:
	var name: String = side.card_name()
	match name:
		"The Courtesan":
			# Another Legion or Horde card with the fewest Activation Tokens.
			var others: Array = []
			others.append_array(state.legions)
			others.append_array(state.hordes)
			var pick: Variant = null
			for n: Variant in others:
				if n != side.entry() and (pick == null or n.activation_tokens < pick.activation_tokens):
					pick = n
			if pick != null:
				pick.activation_tokens += 1
		"The Spymaster":
			_hit_or_threat(state, card_db, coord, tile, side, enemy, "item", 2, result)
		"The Assassin":
			mine.extra_skulls += 2
		"The Imperial Guard":
			mine.extra_shields += 2
		"The Mage Breaker":
			mine.extra_skulls += mine.bolts + theirs.bolts
		"The New Emperor":
			state.empire_vp += 2
			result.vp_awarded["Empire"] = int(result.vp_awarded.get("Empire", 0)) + 2
		"Lichqueen":
			for h: HordeInstance in state.hordes:
				NemesisAI.add_threat(state, h, 1)
		"Coven of Yssat":
			_hit_or_threat(state, card_db, coord, tile, side, enemy, "flip", 2, result)
		"Banished":
			_hit_or_threat(state, card_db, coord, tile, side, enemy, "unit", 2, result)
		"False Messiah":
			var most: int = 0
			var who: String = ""
			for p: PlayerFactionState in state.players:
				var havens: int = 0
				for t: HexTileState in state.hexes.values():
					if t.haven_faction == p.faction:
						havens += 1
				if havens > most:
					most = havens
					who = p.faction
			if not who.is_empty():
				var weakest: Vector2i = NemesisAI.weakest_haven(state, who)
				NemesisAI.remove_haven(state, card_db, weakest)
				result.log.append("False Messiah: %s removes a Haven at %s" % [who, weakest])
		"Oda the Fallen":
			mine.extra_skulls += 2
	result.log.append("%s Godpower" % name)


## Legion/Horde Godpowers that resolve After Damage.
static func _after_damage_power(state: GameState, card_db: Node, coord: Vector2i, tile: HexTileState, side: Combatant, enemy: Combatant,
		power: String, result: Result) -> void:
	if _strength(state, tile, side) <= 0:
		return  # destroyed this round
	match power:
		"The Warlock":
			if enemy.kind == "player":
				if tile.wall:
					tile.wall = false
				elif tile.tower:
					tile.tower = false
				elif not tile.haven_faction.is_empty():
					NemesisAI.remove_haven(state, card_db, coord)
			else:
				_threat_loss(state, card_db, coord, side, enemy, 1, result)
		"The Executioner":
			_hit_or_threat(state, card_db, coord, tile, side, enemy, "remove_unit", 2, result)
		"Counter of Omens":
			var spot: Vector2i = NemesisAI.pick_hex(state, NemesisAI.empty_hexes(state))
			if spot != Vector2i.MIN:
				add_skeletons(state, spot, 2, result.log, card_db)
		"Bloodwyrm":
			NemesisAI.place_curse_on(state, card_db, coord)
		"Siren":
			var nearest: Vector2i = Vector2i.MIN
			var best_d: int = 999
			for c: Vector2i in NemesisAI.empty_hexes(state):
				if HexMath.distance(c, coord) < best_d:
					best_d = HexMath.distance(c, coord)
					nearest = c
			if nearest != Vector2i.MIN:
				side.horde.coord = nearest
				side.escaped = true
				result.log.append("Siren slips away to %s" % nearest)
		"Treemother", "Deep Dweller", "Faceless One":
			_druid_after(state, card_db, coord, tile, side, enemy, power, result)
	result.log.append("%s Godpower (after damage)" % power)


## "<cost to a player>, or lose N Threat": against a player the cost
## ("item" = discard the most expensive Item, "flip" = flip all Items,
## "unit" = destroy the most expensive Unit here, "remove_unit" = remove the
## most expensive Unit from the game, reserve first); against the other
## Nemesis, that Legion/Horde loses Threat.
static func _hit_or_threat(state: GameState, card_db: Node, coord: Vector2i, tile: HexTileState, side: Combatant, enemy: Combatant,
		cost: String, threat: int, result: Result) -> void:
	if enemy.kind != "player":
		if enemy.kind == "legion" or enemy.kind == "horde":
			_threat_loss(state, card_db, coord, side, enemy, threat, result)
		return
	var p: PlayerFactionState = state.find_player(enemy.faction)
	if p == null:
		return
	match cost:
		"item":
			var item: String = ""
			var top: int = -1
			for it: String in p.items_in_hand:
				if GameActions.item_cost(card_db, it) > top:
					top = GameActions.item_cost(card_db, it)
					item = it
			if not item.is_empty():
				p.items_in_hand.erase(item)
				state.item_discard.append(item)
				result.log.append("%s discards '%s'" % [p.faction, item])
		"flip":
			for it2: String in p.items_in_hand:
				if not p.flipped_items.has(it2):
					p.flipped_items.append(it2)
		"unit":
			var unit: String = _priciest_unit(tile, p.faction)
			if not unit.is_empty():
				tile.remove_unit(p.faction, unit)
				result.player_units_lost += 1
				var yard: Dictionary = state.imperial_graveyard if side.allegiance() == "Empire" else state.chaos_graveyard
				yard[p.faction] = int(yard.get(p.faction, 0)) + 1
				p.graveyard_units[unit] = int(p.graveyard_units.get(unit, 0)) + 1
		"remove_unit":
			var unit2: String = _priciest_type(p)
			if unit2.is_empty():
				return
			if NemesisCards.reserve_left(state, p, unit2) <= 0:
				for c: Vector2i in state.hexes.keys():
					if int((state.hexes[c] as HexTileState).unit_stack(p.faction).get(unit2, 0)) > 0:
						(state.hexes[c] as HexTileState).remove_unit(p.faction, unit2)
						break
			p.removed_units[unit2] = int(p.removed_units.get(unit2, 0)) + 1
			result.log.append("%s loses 1 %s for the rest of the game" % [p.faction, unit2])


static func _threat_loss(state: GameState, card_db: Node, coord: Vector2i, side: Combatant, enemy: Combatant, amount: int, result: Result) -> void:
	var target: Variant = enemy.entry()
	if target == null:
		return
	target.threat = maxi(0, target.threat - amount)
	if target.threat <= 0:
		destroy_nemesis(state, card_db, target, side.faction if side.kind == "player" else side.allegiance(), coord, result)


## A player Bolt: a face-up Druid's Godpower when it pays off, else cancel
## an enemy Shield.
static func _player_bolt(state: GameState, card_db: Node, coord: Vector2i, tile: HexTileState, side: Combatant, enemy: Combatant,
		mine: RoundSide, theirs: RoundSide, result: Result, rng: RandomNumberGenerator) -> void:
	var units: int = tile.unit_count(side.faction)
	var incoming: int = maxi(0, theirs.skulls + theirs.extra_skulls - theirs.skull_reduction - (mine.shields + mine.extra_shields))
	if incoming >= units and units > 0 and _druid_ready(state, side, "Silence"):
		_use_druid(side, "Silence")
		mine.ignore_skulls = true
		result.log.append("Silence: nobody takes Skulls this round")
		return
	if incoming > 0 and _druid_ready(state, side, "Mountain Heart"):
		var worst: int = 0
		for face: Variant in theirs.faces:
			var n: int = 0
			for s: Variant in (face as Array):
				if str(s) == "Skull":
					n += 1
			worst = maxi(worst, n)
		if worst > 0:
			_use_druid(side, "Mountain Heart")
			theirs.skull_reduction += worst
			result.log.append("Mountain Heart: ignore %d Skull(s) on one die" % worst)
			return
	if theirs.shields + theirs.extra_shields - mine.cancels > 0 and mine.skulls + mine.extra_skulls > 0:
		mine.cancels += 1
		return
	for power: String in ["Treemother", "Deep Dweller", "Faceless One", "Shapeshifter", "Wanderer"]:
		if not _druid_ready(state, side, power):
			continue
		if power == "Treemother" and (tile.unit_count(side.faction) >= HexTileState.MAX_UNITS or _cheapest_reserve(state, side.faction).is_empty()):
			continue
		if power == "Deep Dweller" and _graveyard_unit(state, side.faction).is_empty():
			continue
		_use_druid(side, power)
		var timing: String = (DRUID_POWERS[power] as Array)[1]
		if timing == "after":
			mine.after.append(power)
		else:
			_druid_before(state, card_db, coord, tile, side, power, result, rng)
		return
	mine.cancels += 1


static func _druid_ready(state: GameState, side: Combatant, power: String) -> bool:
	var face_up: bool = false
	for d: DruidInstance in state.druids_in_play:
		if d.card_name == power and not d.face_down:
			face_up = true
	if not face_up:
		return false
	var limit: String = (DRUID_POWERS.get(power, ["combat", "before"]) as Array)[0]
	return _limit_free(side, "druid:" + power, limit)


static func _use_druid(side: Combatant, power: String) -> void:
	_mark(side, "druid:" + power, (DRUID_POWERS[power] as Array)[0])


static func _druid_before(state: GameState, card_db: Node, _coord: Vector2i, _tile: HexTileState, side: Combatant, power: String, result: Result, _rng: RandomNumberGenerator) -> void:
	var p: PlayerFactionState = state.find_player(side.faction)
	if p == null:
		return
	match power:
		"Shapeshifter":
			p.vp += 1
			result.log.append("Shapeshifter: %s gains 1 VP" % p.faction)
		"Wanderer":
			if state.item_deck.is_empty():
				return
			var item: String = state.item_deck.pop_front()
			if GameActions.hero_can_use_item(card_db, p, item):
				p.items_in_hand.append(item)
			else:
				state.item_discard.append(item)
			result.log.append("Wanderer: %s draws '%s'" % [p.faction, item])


static func _druid_after(state: GameState, _card_db: Node, coord: Vector2i, tile: HexTileState, side: Combatant, enemy: Combatant, power: String, result: Result) -> void:
	var p: PlayerFactionState = state.find_player(side.faction)
	if p == null:
		return
	match power:
		"Treemother":
			var unit: String = _cheapest_reserve(state, side.faction)
			if not unit.is_empty() and tile.add_units(side.faction, unit, 1) > 0:
				result.log.append("Treemother: 1 %s joins the fight" % unit)
		"Deep Dweller":
			var back: String = _graveyard_unit(state, side.faction)
			var spot: Vector2i = NemesisAI.weakest_haven(state, side.faction)
			if back.is_empty() or spot == Vector2i.MIN or spot == coord:
				return
			if state.hexes[spot].add_units(side.faction, back, 1) > 0:
				p.graveyard_units[back] = int(p.graveyard_units.get(back, 0)) - 1
				result.log.append("Deep Dweller: 1 %s returns from the Graveyard" % back)
		"Faceless One":
			if enemy.allegiance() == "Empire":
				state.empire_vp -= 1
			else:
				state.chaos_vp -= 1
			result.log.append("Faceless One: %s loses 1 VP" % enemy.allegiance())


static func _cheapest_reserve(state: GameState, faction: String) -> String:
	var p: PlayerFactionState = state.find_player(faction)
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(faction)
	if p == null or board == null:
		return ""
	var best: String = ""
	var best_cost: int = 999
	for u: PlayerboardTable.UnitEntry in board.units:
		if NemesisCards.reserve_left(state, p, u.name) > 0 and _cost_total(u.cost) < best_cost:
			best_cost = _cost_total(u.cost)
			best = u.name
	return best


static func _graveyard_unit(state: GameState, faction: String) -> String:
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return ""
	var best: String = ""
	var best_cost: int = -1
	for u: Variant in p.graveyard_units.keys():
		if int(p.graveyard_units[u]) <= 0:
			continue
		var e: PlayerboardTable.UnitEntry = PlayerboardTable.get_unit(faction, str(u))
		var cost: int = _cost_total(e.cost) if e != null else 0
		if cost > best_cost:
			best_cost = cost
			best = str(u)
	return best


## Applies `n` unblocked Skulls to `victim`, dealt by `killer`.
static func _take_hits(state: GameState, card_db: Node, coord: Vector2i, tile: HexTileState, victim: Combatant, killer: Combatant, n: int, result: Result) -> void:
	if n <= 0 or _strength(state, tile, victim) <= 0:
		return
	match victim.kind:
		"player":
			# Ramparts: a Wall or Tower here may take 1 hit per round instead of a Unit.
			if n > 0 and _holds(state, victim.faction, "Ramparts") and tile.haven_faction == victim.faction and (tile.wall or tile.tower) and not victim.used_round.has("Ramparts"):
				victim.used_round["Ramparts"] = true
				if tile.wall:
					tile.wall = false
				else:
					tile.tower = false
				n -= 1
				result.log.append("Ramparts: a Defense takes the hit")
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
				if tile.garrison_level == 0 and levels > 0:
					_break_the_shackles(state, killer.faction, result)
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
			var target: Variant = victim.entry()
			target.threat = maxi(0, target.threat - n)
			if target.threat <= 0:
				destroy_nemesis(state, card_db, target, killer.faction if killer.kind == "player" else killer.allegiance(), coord, result)


## A Legion/Horde destroyed - in combat or by a card effect. `killer` is a
## player faction, "Empire" or "Chaos". Its bottom effect (Legions.csv /
## Hordes.csv On destroy) resolves for a player; another Nemesis faction
## only takes the VP (rulebook p36). Clean-up that the card's own
## presence caused (the Spymaster's flipped Market Items, AP held by the
## Coven) is undone whoever destroyed it.
static func destroy_nemesis(state: GameState, card_db: Node, entry: Variant, killer: String, coord: Vector2i, result: Result = null) -> void:
	if not (state.legions.has(entry) or state.hordes.has(entry)):
		return
	state.legions.erase(entry)
	state.hordes.erase(entry)
	var name: String = entry.card_name
	var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(name)
	var vp: int = card.on_destroy_vp if card != null else 0
	var notes: Array[String] = []
	match name:
		"The Spymaster":
			for it: String in state.flipped_market:
				state.item_market.erase(it)
				state.item_discard.append(it)
			state.flipped_market.clear()
			ChapterFlow.refill_row(state.item_market, state.item_deck, state.item_discard, 3)
		"Coven of Yssat":
			for p0: PlayerFactionState in state.players:
				var held: int = int(state.coven_held_ap.get(p0.faction, 0))
				p0.max_action_points += held
				p0.action_points += held
			state.coven_held_ap.clear()
	var p: PlayerFactionState = state.find_player(killer)
	if p == null:
		if killer == "Empire":
			state.empire_vp += vp
		elif killer == "Chaos":
			state.chaos_vp += vp
		notes.append("%s destroyed by %s (+%d VP)" % [name, killer, vp])
	else:
		var hero: HeroCard = EffectUtil.hero_card(card_db, p.hero_name)
		match name:
			"The Courtesan":
				var rng := RandomNumberGenerator.new()
				rng.randomize()
				vp += int(DiceModel.roll_pool(DiceModel.hero_pool(hero, "yellow"), rng)["Skull"])
			"The Mage Breaker":
				vp += hero.magic if hero != null else 0
				for it2: String in state.item_market:
					if not state.flipped_market.has(it2):
						state.item_discard.append(it2)
				state.item_market.clear()
				state.item_market.append_array(state.flipped_market)
				ChapterFlow.refill_row(state.item_market, state.item_deck, state.item_discard, 3)
			"Siren":
				vp += hero.guile if hero != null else 0
			"The New Emperor":
				NemesisAI.add_garrisons(state, state.capital_coord, 2)
			"The Imperial Guard":
				# Passing Bell: destroy 1 non-Empire Unit or Threat here.
				var tile: HexTileState = state.get_hex(coord)
				if tile != null and tile.unit_count(p.faction) > 0:
					var unit: String = _cheapest_unit(tile, p.faction)
					tile.remove_unit(p.faction, unit)
					state.imperial_graveyard[p.faction] = int(state.imperial_graveyard.get(p.faction, 0)) + 1
					p.graveyard_units[unit] = int(p.graveyard_units.get(unit, 0)) + 1
			"Counter of Omens":
				add_skeletons(state, coord, 2, notes, card_db, true)
			"Banished":
				if not state.banished_returned:
					state.banished_returned = true
					state.horde_deck.append("Banished")
		p.vp += vp
		if result != null:
			result.vp_awarded["self"] = int(result.vp_awarded.get("self", 0)) + vp
		if entry is LegionInstance:
			_break_the_shackles(state, p.faction, result)
		notes.append("%s destroyed (+%d VP to %s)" % [name, vp, p.faction])
	if result != null:
		result.log.append_array(notes)
	else:
		NemesisAI.log_line(state, "; ".join(notes))


## Break the Shackles (face-up Quest): "if you destroy any Legions or
## Garrisons, gain 2 resources."
static func _break_the_shackles(state: GameState, faction: String, result: Result) -> void:
	if not state.quest_row.has("Break the Shackles"):
		return
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return
	var ctx := EffectContext.new()
	ctx.state = state
	ctx.acting_faction = faction
	GainResourceOp.new("Any", 2).execute(ctx)
	if result != null:
		result.log.append("Break the Shackles: %s gains 2 resources" % faction)


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


## The most expensive Unit standing on this hex.
static func _priciest_unit(tile: HexTileState, faction: String) -> String:
	var best: String = ""
	var best_cost: int = -1
	for unit_name: Variant in tile.unit_stack(faction).keys():
		var entry: PlayerboardTable.UnitEntry = PlayerboardTable.get_unit(faction, str(unit_name))
		var cost: int = _cost_total(entry.cost) if entry != null else 0
		if cost > best_cost:
			best_cost = cost
			best = str(unit_name)
	return best


## The faction's most expensive Unit type it still has (reserve or map).
static func _priciest_type(p: PlayerFactionState) -> String:
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(p.faction)
	if board == null:
		return ""
	var best: String = ""
	var best_cost: int = -1
	for u: PlayerboardTable.UnitEntry in board.units:
		if u.reserve_size - int(p.removed_units.get(u.name, 0)) <= 0:
			continue
		if _cost_total(u.cost) > best_cost:
			best_cost = _cost_total(u.cost)
			best = u.name
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
