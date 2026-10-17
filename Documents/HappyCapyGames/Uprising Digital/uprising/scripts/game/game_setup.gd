class_name GameSetup
extends RefCounted

## Board setup, ground-truthed against the TTS mod's own embedded Lua setup
## script for the "2 Player Normal" button
## (Documents\My Games\Tabletop Simulator\Mods\Workshop\2092091239.json,
## object GUID e9c8b9, function setupNormal()) rather than guessed from the
## rulebook's setup-diagram IMAGE on p7 (not text-extractable).
##
## The raw TTS world coordinates use a different hex scale than this
## project's own hex.obj/HexMath (TILE_HEX_SIZE=2.0) - they were converted
## to this project's axial coordinates by fitting a hex_size that makes
## every known TTS coordinate round cleanly to an integer axial hex
## (best fit: TTS hex_size ~= 3.7867 raw units; Home Hex/Sea Tower/Garrison
## coordinates round to within ~0.001 of an integer axial coord, strong
## confirmation the fit is correct; Curse/Skeleton coordinates round with
## more slop, ~0.08-0.2, but still unambiguously to a single nearest coord).
##
## What the TTS script actually contains, read directly (not summarized):
## - A "void" bag (GUID cf6ca1, TTS-labeled "The Void") shuffled and dealt
##   face-down onto 10 positions for 2P. These are NOT Home Hexes - their
##   axial coords land on ALL 6 ring-1 hexes plus 4 of the 12 ring-2 hexes,
##   which only makes sense as the generic "remaining hexes placed randomly
##   face-down" pool (rulebook Setup step 4), not faction-specific Home Hex
##   tiles. Confirmed further below by elimination.
## - A "towers" bag dealt onto 2 ring-2 coords: (2,0) and (-2,0).
## - A "garrison" bag dealt onto 3 ring-1 coords: (1,-1), (0,1), (-1,0).
##   NOTE: the rulebook's own Setup step 6 says "3 Garrisons on The Capital
##   AND 1 Garrison each on 3 adjacent hexes" - the Capital's baseline 3
##   never appear as takeObject calls in this script, so they're presumed
##   to be a fixed/built-in feature of the Capital board piece itself, not
##   something this setup script places. capital_garrison_count below is
##   therefore hardcoded from the rulebook text, not read from TTS data.
## - A "curses" bag dealt onto (0,3) and (0,-3) - both ring-3, i.e. OUTSIDE
##   the 10 void positions (which only cover ring-1/ring-2). Left as an open
##   question (not blocking for M1) whether ring-3 here is legitimate
##   playable board for a 2-player game or the outer pre-explored "Region"
##   halo (rulebook p6,14,44) - RegionMath.region_for() is still a stub
##   pending exactly this kind of board-radius ground-truthing.
## - A "skeleton" bag dealt onto (0,3), (0,-3) (coinciding with the 2 Curse
##   hexes - legal, different piece types) and (2,-1) (a ring-2 hex that
##   is NOT one of the 10 void positions or the 2 Sea Tower positions).
##
## Of the 12 ring-2 hexes, 2 went to Sea Towers and 4 to the void/random
## pool, leaving 6 the script never touches directly:
##   (-2,2), (0,2), (2,-1), (2,-2), (0,-2), (-2,1)
## (2,-1) is claimed by a Skeleton placement above, leaving 5. Of those, the
## pair (0,2)/(0,-2) is the unique zero-horizontal-offset (same q, opposite
## r) pair - matching a description of "Home Hexes 2 steps from Capital,
## going up and down" (q=0 in this project's axial convention runs along
## the world Z axis at the Capital's own X). The 3 leftover ring-2 coords
## ((-2,2), (2,-2), (-2,1)) are presumed simply not part of a 2-player
## board's playable area. This elimination step is the one genuinely
## inferred (not directly read) piece of this layout - flagged here rather
## than silently treated as certain, same as the old project's own note on
## this exact ambiguity.
const HOME_COORDS_2P: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, -2)]

const VOID_COORDS_2P: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
	Vector2i(-1, -1), Vector2i(1, -2), Vector2i(-1, 2), Vector2i(1, 1),
]

const SEA_TOWER_COORDS_2P: Array[Vector2i] = [Vector2i(2, 0), Vector2i(-2, 0)]

const GARRISON_COORDS_NORMAL: Array[Vector2i] = [Vector2i(1, -1), Vector2i(0, 1), Vector2i(-1, 0)]

const CURSE_COORDS_2P_NORMAL: Array[Vector2i] = [Vector2i(0, 3), Vector2i(0, -3)]

const SKELETON_COORDS_2P: Array[Vector2i] = [Vector2i(0, 3), Vector2i(0, -3), Vector2i(2, -1)]

## Rulebook Setup step 6: the Capital always carries 3 Garrisons at every
## difficulty tier (the difficulty table only varies the count on adjacent
## hexes: 0/3/3/6 for Rebel/Veteran/Nightmare/Apocalypse) - not read from
## TTS data, see class doc comment above.
const CAPITAL_BASELINE_GARRISONS: int = 3

## Normal-difficulty layouts for 2, 3 and 4 factions, converted from the TTS
## mod's "N Player Normal" setup scripts (2092091239.json, objects e9c8b9 /
## 5df02f / a1921b) with q = x/5.68, r = z/6.56 - q/2 - the conversion that
## reproduces every 2-player constant above exactly. Home hexes are the
## ring-2 spaces those scripts never fill (one per faction, clockwise from
## the top for 3/4 players); all match the rulebook p7 setup diagrams.
## Curses sit on the same hexes as one of the Skeletons (cube rounding of
## the TTS positions; each Curse is placed 2 units off the Skeleton).
const LAYOUTS: Dictionary = {
	2: {
		"homes": [Vector2i(0, 2), Vector2i(0, -2)],
		"interior": [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -2), Vector2i(1, -1), Vector2i(-1, 0),
			Vector2i(-1, 1), Vector2i(-1, 2), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 1)],
		"towers": [Vector2i(2, 0), Vector2i(-2, 0)],
		"curses": [Vector2i(0, 3), Vector2i(0, -3)],
		"skeletons": [Vector2i(0, 3), Vector2i(0, -3), Vector2i(2, -1)],
	},
	3: {
		"homes": [Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 2)],
		"interior": [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -2), Vector2i(1, -1), Vector2i(-1, 0),
			Vector2i(-1, 1), Vector2i(-1, 2), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-2, 1), Vector2i(2, -1)],
		"towers": [Vector2i(-2, 0), Vector2i(0, 2), Vector2i(2, -2)],
		"curses": [Vector2i(0, -3), Vector2i(3, 0)],
		"skeletons": [Vector2i(0, -3), Vector2i(3, 0), Vector2i(-3, 3)],
	},
	4: {
		"homes": [Vector2i(1, -2), Vector2i(2, 0), Vector2i(-1, 2), Vector2i(-2, 0)],
		"interior": [Vector2i(0, -2), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(-2, 1),
			Vector2i(-2, 2), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 1), Vector2i(1, 0), Vector2i(1, -1), Vector2i(2, -1), Vector2i(2, -2)],
		"towers": [Vector2i(3, -2), Vector2i(1, 2), Vector2i(-3, 2), Vector2i(-1, -2)],
		"curses": [Vector2i(3, 0), Vector2i(2, -3)],
		"skeletons": [Vector2i(3, 0), Vector2i(2, -3), Vector2i(-2, 3)],
	},
}

## True Solo Mode, the solo side of the map (rulebook p76-77): The Capital,
## 8 random face-down hexes on its 6 neighbours and either side of the Home
## hex, 2 Sea Towers, the Home hex to the south. The other 16 of the 28
## spaces are printed explored Ice Waste (RegionMath.SOLO_REGION_OF).
## Curses, Garrisons and Skeletons per difficulty, from the p77 diagrams.
const SOLO_HOME: Vector2i = Vector2i(0, 2)
const SOLO_TOWERS: Array[Vector2i] = [Vector2i(-2, 2), Vector2i(2, 0)]
const SOLO_INTERIOR: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
	Vector2i(-1, 2), Vector2i(1, 1),
]
const SOLO_SKELETONS: Array[Vector2i] = [Vector2i(-2, 0), Vector2i(2, -2), Vector2i(0, 3)]
const SOLO_CURSES: Dictionary = {
	"Rebel": [],
	"Veteran": [Vector2i(0, -2), Vector2i(0, 3)],
	"Nightmare": [Vector2i(0, -2), Vector2i(3, 0), Vector2i(0, 3)],
	"Apocalypse": [Vector2i(0, -2), Vector2i(3, 0), Vector2i(0, 3)],
}
const SOLO_GARRISONS: Dictionary = {
	"Rebel": [],
	"Veteran": [Vector2i(1, -1), Vector2i(0, 1), Vector2i(-1, 0)],
	"Nightmare": [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)],
	"Apocalypse": [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)],
}
const SOLO_AP: int = 10
const SOLO_RESOURCES: int = 6
## "Not recommended for the True Solo Mode ... too powerful with only one
## player" (rulebook p78; only Rebel Council is in the Core deck).
const SOLO_EXCLUDED_QUESTS: Array[String] = ["Boon of the Fallen Comrades", "Rebel Council", "For the Greater Good"]

## Each Core faction's Home hex card (Hexes.csv, Type=Home).
const HOME_HEX_BY_FACTION: Dictionary = {
	"Druwhn": "Yfelskog", "Duerkhar": "Khatrak Kautil", "Krowh": "Pak Glandris", "Mohyar": "Winterholm",
}
const CORE_FACTIONS: Array[String] = ["Druwhn", "Duerkhar", "Krowh", "Mohyar"]


## Builds a 2-player, Normal-difficulty board layout. `faction_names` picks
## which 2 of the 4 Core factions get a Home Hex (defaults to the first 2
## found in CardDatabase, in CSV order) - the TTS data has no opinion on
## which factions are in play, only how many Home Hex slots exist.
## Board for the given factions (2-4, in seat order): Home hexes clockwise,
## the rest of the hex pool shuffled face-down, Sea Towers face-down,
## Normal-difficulty Garrisons, Curses and Skeletons.
static func build_layout(card_db: Node, factions: Array, rng: RandomNumberGenerator = null) -> BoardLayout:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var n: int = clampi(factions.size(), 2, 4)
	var spec: Dictionary = LAYOUTS[n]

	var layout := BoardLayout.new()
	layout.capital_coord = Vector2i.ZERO
	layout.capital_garrison_count = CAPITAL_BASELINE_GARRISONS

	var core_hexes: Array = card_db.hexes  # Array[HexCard], EN + Core only
	# The Capital's CSV row is typed "Normal" too - it is never a face-down hex.
	var normal_cards: Array = core_hexes.filter(func(h: HexCard) -> bool: return h.hex_type == "Normal" and h.card_name != "Capital")
	var sea_tower_cards: Array = core_hexes.filter(func(h: HexCard) -> bool: return h.hex_type == "Sea Tower")
	_shuffle(normal_cards, rng)
	_shuffle(sea_tower_cards, rng)

	var homes: Array = spec["homes"]
	for i: int in range(n):
		var coord: Vector2i = homes[i]
		var faction: String = str(factions[i])
		layout.home_coords.append(coord)
		layout.home_factions[coord] = faction
		for h: HexCard in core_hexes:
			if h.hex_type == "Home" and h.card_name == str(HOME_HEX_BY_FACTION.get(faction, "")):
				layout.home_hex_cards[coord] = h

	var interior: Array = spec["interior"]
	for i: int in range(interior.size()):
		var coord: Vector2i = interior[i]
		layout.interior_coords.append(coord)
		if i < normal_cards.size():
			layout.interior_hex_cards[coord] = normal_cards[i]

	var towers: Array = spec["towers"]
	for i: int in range(towers.size()):
		var coord: Vector2i = towers[i]
		layout.sea_tower_coords.append(coord)
		if i < sea_tower_cards.size():
			layout.sea_tower_hex_cards[coord] = sea_tower_cards[i]

	for coord: Vector2i in GARRISON_COORDS_NORMAL:
		layout.garrison_counts[coord] = 1
	for coord: Vector2i in (spec["curses"] as Array):
		layout.curse_coords.append(coord)
	for coord: Vector2i in (spec["skeletons"] as Array):
		layout.skeleton_counts[coord] = int(layout.skeleton_counts.get(coord, 0)) + 1
	return layout


## 2 random factions on the 2-player board (tests and the M1 showcase).
static func build_2p_normal_layout(card_db: Node, rng: RandomNumberGenerator = null) -> BoardLayout:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return build_layout(card_db, _random_factions(2, rng), rng)


static func _random_factions(count: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = CORE_FACTIONS.duplicate()
	_shuffle(pool, rng)
	return pool.slice(0, count)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


## Rulebook difficulty tiers are Rebel/Veteran/Nightmare/Apocalypse; the TTS
## mod's own setup buttons are labeled Easy/Normal/Nightmare/Apocalypse -
## Easy~Rebel, Normal~Veteran (matches: TTS "Normal" places exactly 3
## Garrisons on 3 ring-1 hexes, which is the rulebook's own Veteran-tier
## description "3+1-on-3-adjacent"). Starting resources for Veteran: 5/5/5
## (rulebook difficulty table: "6/5/5/5 each, Rebel gives extra").
const STARTING_RESOURCE_VETERAN: int = 5
const STARTING_AP: int = 8


## Builds a full, networkable GameState for a 2-player/Normal(=Veteran)
## game, using build_2p_normal_layout() for the board. Decks are shuffled
## but NOT yet dealt (item/quest hands, Chapter Event reveals, Legion/Horde
## spawns) - rulebook Setup ends with everything shuffled and placed face-
## down; the actual "deal 3 Items/Quests" etc. happens as the first
## Refresh Phase step, which is ChapterFlow's job (Milestone 4), not
## GameSetup's. GameState.phase starts at REFRESH to match (see the old
## project's own hard-learned fix: a real game must start in Refresh
## Phase, not have phases pre-advanced before the first broadcast).
static func build_2p_normal_game_state(card_db: Node, rng: RandomNumberGenerator = null) -> GameState:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var picks: Array = []
	for f: Variant in _random_factions(2, rng):
		var hero: HeroCard = _first_hero_for_faction(card_db, str(f))
		picks.append({"faction": str(f), "hero": hero.card_name if hero != null else ""})
	return build_game_state(card_db, picks, rng)


## A full game for 2-4 seats, each {"faction", "hero"}, in seat (= turn)
## order - what the lobby hands over.
static func build_game_state(card_db: Node, picks: Array, rng: RandomNumberGenerator = null) -> GameState:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var factions: Array = []
	for pick: Variant in picks:
		factions.append(str((pick as Dictionary).get("faction", "")))
	var layout: BoardLayout = build_layout(card_db, factions, rng)
	var state := GameState.new()
	state.phase = GameState.Phase.REFRESH
	state.chapter = 1
	state.max_chapters = 2
	state.difficulty = "Veteran"
	state.capital_coord = layout.capital_coord

	_place_hex(state, layout.capital_coord, "capital", "", true, "", layout.capital_garrison_count)
	for coord: Vector2i in layout.home_coords:
		var faction: String = layout.home_factions.get(coord, "")
		var card: HexCard = layout.home_hex_cards.get(coord)
		_place_hex(state, coord, "home", card.card_name if card else "", true, faction, 0)
		state.hexes[coord].haven_faction = faction  # rulebook Setup: Home Hex gets its faction's leftmost Haven immediately.
	for coord: Vector2i in layout.sea_tower_coords:
		var card: HexCard = layout.sea_tower_hex_cards.get(coord)
		_place_hex(state, coord, "sea_tower", card.card_name if card else "", false, "", 0)
	for coord: Vector2i in layout.interior_coords:
		var card: HexCard = layout.interior_hex_cards.get(coord)
		_place_hex(state, coord, "interior", card.card_name if card else "", false, "", 0)

	# Curse/Skeleton coords (ring-3 for 2P) sit OUTSIDE the 15 hexes placed
	# above (capital + 2 home + 2 sea tower + 10 interior only cover ring
	# 0-2) - see game_setup.gd's class doc comment on the still-open
	# question of whether this is legitimate playable board or the outer
	# Region halo. Either way a HexTileState must exist there before curse/
	# skeleton state can be set on it - ensure one rather than assuming
	# _place_hex already ran for it (a real bug once: this crashed with
	# "Invalid access to property or key" the first time GameState actually
	# got built and networked, since nothing upstream of this loop had
	# created these coords yet).
	for coord: Vector2i in layout.curse_coords:
		state.ensure_hex(coord, "outer")
	for coord: Vector2i in layout.skeleton_counts.keys():
		state.ensure_hex(coord, "outer")

	# Every other space of the printed 37-hex board is a bare Region space:
	# explored Ice Waste, no Haven ever (rulebook p7 "These hexes stay
	# empty. They are explored Ice Waste hexes", p14). Units, Heroes and the
	# Nemesis move through them like any hex.
	for coord: Vector2i in HexMath.spiral(layout.capital_coord, RegionMath.BOARD_RADIUS):
		state.ensure_hex(coord, "outer")
	for tile: HexTileState in state.hexes.values():
		if tile.role == "outer":
			tile.explored = true

	for coord: Vector2i in layout.garrison_counts.keys():
		state.hexes[coord].garrison_level = layout.garrison_counts[coord]
	for coord: Vector2i in layout.curse_coords:
		state.hexes[coord].curse = true
	for coord: Vector2i in layout.skeleton_counts.keys():
		state.hexes[coord].skeleton_count = layout.skeleton_counts[coord]

	for pick: Variant in picks:
		var faction: String = str((pick as Dictionary).get("faction", ""))
		var p := PlayerFactionState.new()
		p.faction = faction
		p.hero_name = str((pick as Dictionary).get("hero", ""))
		if p.hero_name.is_empty():
			var hero: HeroCard = _first_hero_for_faction(card_db, faction)
			p.hero_name = hero.card_name if hero else ""
		p.salt = STARTING_RESOURCE_VETERAN
		p.plunder = STARTING_RESOURCE_VETERAN
		p.food = STARTING_RESOURCE_VETERAN
		p.action_points = STARTING_AP
		p.max_action_points = STARTING_AP
		for home: Vector2i in layout.home_factions.keys():
			if layout.home_factions[home] == faction:
				p.hero_coord = home  # rulebook Setup: the Hero standee starts on its home hex.
		state.players.append(p)

	# 5 Legion + 5 Horde cards for 2 factions, +1 each per additional faction
	# (rulebook Setup).
	var deck_size: int = 3 + picks.size()
	var legion_names: Array[String] = []
	for l: LegionCard in card_db.legions:
		legion_names.append(l.card_name)
	_shuffle(legion_names, rng)
	state.legion_deck = legion_names.slice(0, min(deck_size, legion_names.size()))

	var horde_names: Array[String] = []
	for h: HordeCard in card_db.hordes:
		horde_names.append(h.card_name)
	_shuffle(horde_names, rng)
	state.horde_deck = horde_names.slice(0, min(deck_size, horde_names.size()))

	# 4 random Core Druids in play, 0 Aether each until a Refresh Phase
	# condition check places some (Milestone 4).
	var druid_names: Array[String] = []
	for d: DruidCard in card_db.druids:
		druid_names.append(d.card_name)
	_shuffle(druid_names, rng)
	for i: int in range(min(4, druid_names.size())):
		var di := DruidInstance.new()
		di.card_name = druid_names[i]
		state.druids_in_play.append(di)

	var item_names: Array[String] = []
	for it: ItemCard in card_db.items:
		item_names.append(it.card_name)
	_shuffle(item_names, rng)
	state.item_deck = item_names

	var quest_names: Array[String] = []
	for q: QuestCard in card_db.quests:
		quest_names.append(q.card_name)
	_shuffle(quest_names, rng)
	state.quest_deck = quest_names

	# Feat decks: START Feats into play, the rest shuffled (rulebook Setup).
	for fp: PlayerFactionState in state.players:
		GameActions.CardAbilities.setup_player(state, card_db, fp, rng)

	state.rng_seed = rng.randi()  # the game's own dice from here on
	# One face-down Event per Chapter (rulebook Setup).
	var event_effects: GDScript = load("res://scripts/game/event_effects.gd")
	event_effects.pick_chapter_events(state, card_db, rng)

	state.first_player_index = 0
	state.current_player_index = 0
	return state


## True Solo Mode (rulebook p74-79): one faction, its main Hero and an
## allied Hero from any faction (pick = {"faction", "hero", "ally"}), on the
## solo side of the map. 10 AP, 6 of each resource, 5 Legions and 5 Hordes
## (6 each on Nightmare/Apocalypse), the Feat decks of both Heroes - the
## ally's without Unit Feats - and 2 + 1 START Feats in play.
## Events: the 24 Solo Event cards aren't in the card data yet, so the
## regular Events stand in (resolved under the solo general rules).
static func build_solo_game_state(card_db: Node, pick: Dictionary, difficulty: String = "Veteran", rng: RandomNumberGenerator = null) -> GameState:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	if not SOLO_CURSES.has(difficulty):
		difficulty = "Veteran"
	var faction: String = str(pick.get("faction", ""))
	var state := GameState.new()
	state.solo = true
	state.phase = GameState.Phase.REFRESH
	state.chapter = 1
	state.max_chapters = 2
	state.difficulty = difficulty
	state.capital_coord = Vector2i.ZERO

	# Hex stack: the normal hexes split by the resource on their back (what
	# they produce), 3 drawn from each, shuffled together, 8 placed.
	var by_resource: Dictionary = {"Salt": [], "Plunder": [], "Food": []}
	for h: HexCard in card_db.hexes:
		if h.hex_type != "Normal" or h.card_name == "Capital":
			continue
		for res: String in ["Salt", "Plunder", "Food"]:
			if _hex_yield(h, res) > 0:
				(by_resource[res] as Array).append(h)
				break
	var stack: Array = []
	for res2: String in ["Salt", "Plunder", "Food"]:
		var pile: Array = by_resource[res2]
		_shuffle(pile, rng)
		stack.append_array(pile.slice(0, 3))
	_shuffle(stack, rng)
	var towers: Array = card_db.hexes.filter(func(h: HexCard) -> bool: return h.hex_type == "Sea Tower")
	_shuffle(towers, rng)

	_place_hex(state, state.capital_coord, "capital", "", true, "", CAPITAL_BASELINE_GARRISONS)
	var home_card: String = str(HOME_HEX_BY_FACTION.get(faction, ""))
	_place_hex(state, SOLO_HOME, "home", home_card, true, faction, 0)
	state.hexes[SOLO_HOME].haven_faction = faction
	for i: int in range(SOLO_TOWERS.size()):
		var tower: HexCard = towers[i] if i < towers.size() else null
		_place_hex(state, SOLO_TOWERS[i], "sea_tower", tower.card_name if tower != null else "", false, "", 0)
	for i2: int in range(SOLO_INTERIOR.size()):
		var hex: HexCard = stack[i2] if i2 < stack.size() else null
		_place_hex(state, SOLO_INTERIOR[i2], "interior", hex.card_name if hex != null else "", false, "", 0)
	for offset: Variant in RegionMath.SOLO_REGION_OF.keys():
		var tile: HexTileState = state.ensure_hex(state.capital_coord + (offset as Vector2i), "outer")
		if tile.role == "outer":
			tile.explored = true

	for g: Variant in (SOLO_GARRISONS[difficulty] as Array):
		state.hexes[g as Vector2i].garrison_level = 1
	for c: Variant in (SOLO_CURSES[difficulty] as Array):
		state.hexes[c as Vector2i].curse = true
	for s: Vector2i in SOLO_SKELETONS:
		state.hexes[s].skeleton_count += 1

	var p := PlayerFactionState.new()
	p.faction = faction
	p.hero_name = str(pick.get("hero", ""))
	if p.hero_name.is_empty():
		var first: HeroCard = _first_hero_for_faction(card_db, faction)
		p.hero_name = first.card_name if first != null else ""
	p.ally_hero_name = str(pick.get("ally", ""))
	p.salt = SOLO_RESOURCES
	p.plunder = SOLO_RESOURCES
	p.food = SOLO_RESOURCES
	p.action_points = SOLO_AP
	p.max_action_points = SOLO_AP
	p.hero_coord = SOLO_HOME
	p.ally_coord = SOLO_HOME
	state.players.append(p)

	var deck_size: int = 6 if difficulty == "Nightmare" or difficulty == "Apocalypse" else 5
	var legion_names: Array[String] = []
	for l: LegionCard in card_db.legions:
		legion_names.append(l.card_name)
	_shuffle(legion_names, rng)
	state.legion_deck = legion_names.slice(0, mini(deck_size, legion_names.size()))
	var horde_names: Array[String] = []
	for hc: HordeCard in card_db.hordes:
		horde_names.append(hc.card_name)
	_shuffle(horde_names, rng)
	state.horde_deck = horde_names.slice(0, mini(deck_size, horde_names.size()))

	var druid_names: Array[String] = []
	for d: DruidCard in card_db.druids:
		druid_names.append(d.card_name)
	_shuffle(druid_names, rng)
	for i3: int in range(mini(4, druid_names.size())):
		var di := DruidInstance.new()
		di.card_name = druid_names[i3]
		state.druids_in_play.append(di)

	var item_names: Array[String] = []
	for it: ItemCard in card_db.items:
		item_names.append(it.card_name)
	_shuffle(item_names, rng)
	state.item_deck = item_names
	var quest_names: Array[String] = []
	for q: QuestCard in card_db.quests:
		if not SOLO_EXCLUDED_QUESTS.has(q.card_name):
			quest_names.append(q.card_name)
	_shuffle(quest_names, rng)
	state.quest_deck = quest_names

	GameActions.CardAbilities.setup_player(state, card_db, p, rng)
	state.rng_seed = rng.randi()
	var event_effects: GDScript = load("res://scripts/game/event_effects.gd")
	event_effects.pick_chapter_events(state, card_db, rng)
	state.first_player_index = 0
	state.current_player_index = 0
	return state


## A hex's printed yield of `res` ("2", "-" or "").
static func _hex_yield(h: HexCard, res: String) -> int:
	var v: String = h.salt if res == "Salt" else (h.plunder if res == "Plunder" else h.food)
	return v.strip_edges().to_int() if v.strip_edges().is_valid_int() else 0


static func _place_hex(state: GameState, coord: Vector2i, role: String, card_name: String, explored: bool, owning_faction: String, garrison_level: int) -> void:
	var tile := HexTileState.new()
	tile.role = role
	tile.hex_card_name = card_name
	tile.explored = explored
	tile.owning_faction = owning_faction
	tile.garrison_level = garrison_level
	state.hexes[coord] = tile




static func _first_hero_for_faction(card_db: Node, faction: String) -> HeroCard:
	for h: HeroCard in card_db.heroes:
		if h.faction == faction:
			return h
	return null
