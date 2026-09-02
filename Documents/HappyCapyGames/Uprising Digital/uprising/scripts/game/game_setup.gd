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


## Builds a 2-player, Normal-difficulty board layout. `faction_names` picks
## which 2 of the 4 Core factions get a Home Hex (defaults to the first 2
## found in CardDatabase, in CSV order) - the TTS data has no opinion on
## which factions are in play, only how many Home Hex slots exist.
static func build_2p_normal_layout(card_db: Node, rng: RandomNumberGenerator = null) -> BoardLayout:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var layout := BoardLayout.new()
	layout.capital_coord = Vector2i.ZERO
	layout.capital_garrison_count = CAPITAL_BASELINE_GARRISONS

	var core_hexes: Array = card_db.hexes  # Array[HexCard], EN + Core only
	var home_cards: Array = core_hexes.filter(func(h: HexCard) -> bool: return h.hex_type == "Home")
	var normal_cards: Array = core_hexes.filter(func(h: HexCard) -> bool: return h.hex_type == "Normal")
	var sea_tower_cards: Array = core_hexes.filter(func(h: HexCard) -> bool: return h.hex_type == "Sea Tower")

	_shuffle(home_cards, rng)
	_shuffle(normal_cards, rng)
	_shuffle(sea_tower_cards, rng)

	# Home hexes - pair each of the 2 slots with a distinct Core faction's
	# Home hex card. HexCard doesn't carry a faction field directly, so the
	# faction is inferred from a fixed name->faction table built from the
	# 4 known Core Home hex names (verified against the CSV, not guessed).
	var home_hex_faction_by_name: Dictionary = {
		"Yfelskog": "Druwhn", "Khatrak Kautil": "Duerkhar",
		"Pak Glandris": "Krowh", "Winterholm": "Mohyar",
	}
	for i: int in range(min(HOME_COORDS_2P.size(), home_cards.size())):
		var coord: Vector2i = HOME_COORDS_2P[i]
		var card: HexCard = home_cards[i]
		layout.home_coords.append(coord)
		layout.home_hex_cards[coord] = card
		layout.home_factions[coord] = home_hex_faction_by_name.get(card.card_name, "Unknown")

	for i: int in range(VOID_COORDS_2P.size()):
		var coord: Vector2i = VOID_COORDS_2P[i]
		layout.interior_coords.append(coord)
		if i < normal_cards.size():
			layout.interior_hex_cards[coord] = normal_cards[i]

	for i: int in range(SEA_TOWER_COORDS_2P.size()):
		var coord: Vector2i = SEA_TOWER_COORDS_2P[i]
		layout.sea_tower_coords.append(coord)
		if i < sea_tower_cards.size():
			layout.sea_tower_hex_cards[coord] = sea_tower_cards[i]

	for coord: Vector2i in GARRISON_COORDS_NORMAL:
		layout.garrison_counts[coord] = 1

	for coord: Vector2i in CURSE_COORDS_2P_NORMAL:
		layout.curse_coords.append(coord)

	for coord: Vector2i in SKELETON_COORDS_2P:
		layout.skeleton_counts[coord] = layout.skeleton_counts.get(coord, 0) + 1

	return layout


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

	var layout: BoardLayout = build_2p_normal_layout(card_db, rng)
	var state := GameState.new()
	state.phase = GameState.Phase.REFRESH
	state.chapter = 1
	state.max_chapters = 2
	state.difficulty = "Veteran"

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
		_ensure_hex(state, coord, "outer")
	for coord: Vector2i in layout.skeleton_counts.keys():
		_ensure_hex(state, coord, "outer")

	for coord: Vector2i in layout.garrison_counts.keys():
		state.hexes[coord].garrison_level = layout.garrison_counts[coord]
	for coord: Vector2i in layout.curse_coords:
		state.hexes[coord].curse = true
	for coord: Vector2i in layout.skeleton_counts.keys():
		state.hexes[coord].skeleton_count = layout.skeleton_counts[coord]

	var faction_names: Array = layout.home_factions.values()
	for faction: String in faction_names:
		var p := PlayerFactionState.new()
		p.faction = faction
		var hero: HeroCard = _first_hero_for_faction(card_db, faction)
		p.hero_name = hero.card_name if hero else ""
		p.salt = STARTING_RESOURCE_VETERAN
		p.plunder = STARTING_RESOURCE_VETERAN
		p.food = STARTING_RESOURCE_VETERAN
		p.action_points = STARTING_AP
		p.max_action_points = STARTING_AP
		state.players.append(p)

	# 2-faction game: 5 Legion + 5 Horde cards staged face-down (rulebook
	# Setup: "+1 each per additional faction beyond 2").
	var legion_names: Array[String] = []
	for l: LegionCard in card_db.legions:
		legion_names.append(l.card_name)
	_shuffle(legion_names, rng)
	state.legion_deck = legion_names.slice(0, min(5, legion_names.size()))

	var horde_names: Array[String] = []
	for h: HordeCard in card_db.hordes:
		horde_names.append(h.card_name)
	_shuffle(horde_names, rng)
	state.horde_deck = horde_names.slice(0, min(5, horde_names.size()))

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

	state.first_player_index = 0
	state.current_player_index = 0
	return state


static func _place_hex(state: GameState, coord: Vector2i, role: String, card_name: String, explored: bool, owning_faction: String, garrison_level: int) -> void:
	var tile := HexTileState.new()
	tile.role = role
	tile.hex_card_name = card_name
	tile.explored = explored
	tile.owning_faction = owning_faction
	tile.garrison_level = garrison_level
	state.hexes[coord] = tile


static func _ensure_hex(state: GameState, coord: Vector2i, default_role: String) -> void:
	if not state.hexes.has(coord):
		var tile := HexTileState.new()
		tile.role = default_role
		state.hexes[coord] = tile


static func _first_hero_for_faction(card_db: Node, faction: String) -> HeroCard:
	for h: HeroCard in card_db.heroes:
		if h.faction == faction:
			return h
	return null
