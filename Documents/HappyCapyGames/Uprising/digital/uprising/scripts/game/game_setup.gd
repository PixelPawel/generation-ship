class_name GameSetup
extends RefCounted
## Builds a fresh, fully-populated GameState from a difficulty + faction/Hero
## selection (rulebook p5-9). Targets Core box only for now (per project
## scope decision) -- Arch-Nemesis/Titans content stays in CardDatabase but
## is filtered out of decks/setup here.
##
## The exact printed board layout (the symmetric "petal" diagrams on p7)
## isn't digitized anywhere in the CSVs -- they're print artwork, not data.
## This generates a functionally equivalent layout instead: Capital at the
## center, one home hex per faction spread across directions, everything
## else filled from a shuffled pool of Core hexes on an expanding hex
## spiral. Adjacency/pathing/exploration all work correctly; it just won't
## visually match the physical board's exact arrangement.

## Core box home hex per faction, from CardDatabase.hexes (Type == "Home").
const HOME_HEX_BY_FACTION := {
	"Druwhn": "Yfelskog",
	"Duerkhar": "Khatrak Kautil",
	"Mohyar": "Winterholm",
	"Krowh": "Pak Glandris",
}

## Rulebook p9 difficulty table. Curse count and Garrison spread come
## straight from there; Skeleton count isn't printed as a single number in
## the rulebook (it's "indicated hexes" on the physical board) so this is a
## reasonable approximation, not a transcription.
const DIFFICULTY_TABLE := {
	"Rebel": {"resources": 6, "curses": 0, "skeletons": 0},
	"Veteran": {"resources": 5, "curses": 2, "skeletons": 2},
	"Nightmare": {"resources": 5, "curses": 3, "skeletons": 3},
	"Apocalypse": {"resources": 5, "curses": 3, "skeletons": 3},
}

const STARTING_AP := 8
const HOME_DISTANCE := 3
const SPIRAL_RADIUS := 6


## `faction_hero_pairs`: Array of [faction_name, hero_name], 1-4 entries.
## `card_db`: the CardDatabase autoload (passed in rather than referenced by
## global name, so this is testable from a plain --script harness too).
static func build_new_game(
	card_db: Node,
	faction_hero_pairs: Array,
	difficulty: String = "Veteran",
	max_chapters: int = 3
) -> GameState:
	var state := GameState.new()
	state.max_chapters = max_chapters
	var diff: Dictionary = DIFFICULTY_TABLE.get(difficulty, DIFFICULTY_TABLE["Veteran"])

	var used: Dictionary = {}  # HexMath.key -> true, for coords already spoken for

	_place_capital(state, used)
	var home_coords := _reserve_home_coords(faction_hero_pairs, used)
	_place_home_hexes_and_players(state, card_db, faction_hero_pairs, home_coords, diff)
	_place_capital_garrisons(state, used)

	var pool := _gather_core_hex_pool(card_db)
	var placements := _fill_board(state, pool, used)

	_place_curses(state, placements, diff.get("curses", 0))
	_place_skeletons(state, placements, diff.get("skeletons", 0))

	_build_decks(state, card_db)
	_pick_druids(state, card_db)

	return state


static func _place_capital(state: GameState, used: Dictionary) -> void:
	var capital := HexTile.new()
	capital.coord = GameState.CAPITAL_COORD
	capital.card_name = "The Capital"
	capital.explored = true
	capital.no_haven = true
	capital.garrison_level = 3
	state.set_hex(capital)
	used[HexMath.key(capital.coord)] = true


## One home coord per faction, spread across the 6 axial directions.
static func _reserve_home_coords(faction_hero_pairs: Array, used: Dictionary) -> Dictionary:
	var home_coords := {}
	for i in faction_hero_pairs.size():
		var dir: Vector2i = HexMath.DIRECTIONS[i % HexMath.DIRECTIONS.size()]
		var coord := GameState.CAPITAL_COORD + dir * HOME_DISTANCE
		var faction: String = faction_hero_pairs[i][0]
		home_coords[faction] = coord
		used[HexMath.key(coord)] = true
	return home_coords


## `faction_hero_pairs` entries are either the plain [faction, hero] form
## (every pre-Lobby caller, including all the tests) or the Lobby's richer
## [faction, hero, peer_id, is_bot] form -- peer_id defaults to -1
## (unclaimed/no controller) and is_bot to false when omitted, so both
## forms build an identical PlayerFactionState for a human pair.
static func _place_home_hexes_and_players(
	state: GameState, card_db: Node, faction_hero_pairs: Array, home_coords: Dictionary, diff: Dictionary
) -> void:
	for pair in faction_hero_pairs:
		var faction: String = pair[0]
		var hero_name: String = pair[1]
		var peer_id: int = int(pair[2]) if pair.size() > 2 else -1
		var is_bot: bool = bool(pair[3]) if pair.size() > 3 else false
		var coord: Vector2i = home_coords[faction]

		var tile := HexTile.new()
		tile.coord = coord
		tile.card_name = HOME_HEX_BY_FACTION.get(faction, "")
		tile.explored = true
		tile.haven_faction = faction
		state.set_hex(tile)

		var player := PlayerFactionState.new()
		player.faction = faction
		player.hero_name = hero_name
		player.controlled_by_peer_id = peer_id
		player.is_bot = is_bot
		player.salt = diff.get("resources", 5)
		player.plunder = diff.get("resources", 5)
		player.food = diff.get("resources", 5)
		player.action_points = STARTING_AP
		player.max_action_points = STARTING_AP
		player.havens = [coord]
		player.hero_hex = coord

		var hero_card := _find_hero(card_db, hero_name)
		if hero_card != null:
			player.might = hero_card.might
			player.magic = hero_card.magic
			player.leadership = hero_card.lead
			player.guile = hero_card.guile

		player.feat_deck = _build_feat_deck(card_db, faction)
		state.players.append(player)


## Rulebook p6: "Place 3 Garrisons on The Capital, 1 Garrison on 3 adjacent hexes."
static func _place_capital_garrisons(state: GameState, used: Dictionary) -> void:
	var placed := 0
	for n in HexMath.neighbors(GameState.CAPITAL_COORD):
		if placed >= 3:
			break
		if used.has(HexMath.key(n)):
			continue
		var tile := HexTile.new()
		tile.coord = n
		tile.explored = false
		tile.garrison_level = 1
		state.set_hex(tile)
		used[HexMath.key(n)] = true
		placed += 1


static func _find_hero(card_db: Node, hero_name: String) -> HeroCard:
	for h in card_db.heroes:
		if h.lang == "EN" and h.card_name == hero_name:
			return h
	return null


## Rulebook p13: 10 Feat cards per faction (CardDatabase.feats' "Faction"
## column, shared by both of that faction's Heroes -- only one is ever in
## play per game, so this is effectively that Hero's own deck). Shuffled
## and ready for GameActions.draw_feats/choose_feat during Build Phase.
static func _build_feat_deck(card_db: Node, faction: String) -> Array[String]:
	var names: Array[String] = []
	for f in card_db.feats:
		if f.lang == "EN" and f.faction == faction:
			names.append(f.card_name)
	names.shuffle()
	return names


## Core-box hex names, split into the Normal fill pool and Sea Towers.
static func _gather_core_hex_pool(card_db: Node) -> Dictionary:
	var normal: Array[String] = []
	var sea_tower: Array[String] = []
	for h in card_db.hexes:
		if h.lang != "EN" or h.box != "Core" or h.hex_type == "Home":
			continue
		if h.hex_type == "Sea Tower":
			sea_tower.append(h.card_name)
		else:
			normal.append(h.card_name)
	normal.shuffle()
	sea_tower.shuffle()
	return {"normal": normal, "sea_tower": sea_tower}


## Places every pooled hex (unexplored) on an expanding spiral around the
## Capital, skipping coords already claimed. Returns the list of coords used
## for fill hexes, for later Curse/Skeleton placement.
static func _fill_board(state: GameState, pool: Dictionary, used: Dictionary) -> Array[Vector2i]:
	var normal: Array = pool["normal"]
	var sea_tower: Array = pool["sea_tower"]
	var placements: Array[Vector2i] = []

	var candidates := HexMath.spiral(GameState.CAPITAL_COORD, SPIRAL_RADIUS)
	var i := 0
	for coord in candidates:
		if normal.is_empty() and sea_tower.is_empty():
			break
		var key := HexMath.key(coord)
		if used.has(key):
			continue
		i += 1

		var tile := HexTile.new()
		tile.coord = coord
		tile.explored = false
		if not sea_tower.is_empty() and i % 7 == 0:  # sprinkle Sea Towers in, not clustered
			tile.card_name = sea_tower.pop_back()
			tile.is_sea_tower = true
		elif not normal.is_empty():
			tile.card_name = normal.pop_back()
		else:
			tile.card_name = sea_tower.pop_back()
			tile.is_sea_tower = true

		state.set_hex(tile)
		used[key] = true
		placements.append(coord)

	return placements


static func _place_curses(state: GameState, placements: Array[Vector2i], count: int) -> void:
	var shuffled := placements.duplicate()
	shuffled.shuffle()
	var placed := 0
	for coord in shuffled:
		if placed >= count:
			break
		var tile := state.get_hex(coord)
		if tile == null or tile.no_haven:
			continue
		tile.has_curse = true
		placed += 1


static func _place_skeletons(state: GameState, placements: Array[Vector2i], count: int) -> void:
	var shuffled := placements.duplicate()
	shuffled.shuffle()
	var placed := 0
	for coord in shuffled:
		if placed >= count:
			break
		var tile := state.get_hex(coord)
		if tile == null or tile.has_curse:
			continue
		tile.skeleton_count = 1
		placed += 1


static func _build_decks(state: GameState, card_db: Node) -> void:
	var items: Array[String] = []
	for c in card_db.items:
		if c.lang == "EN" and c.box == "Core":
			items.append(c.card_name)
	items.shuffle()
	state.item_deck = items
	for _i in range(mini(3, state.item_deck.size())):
		state.market.append(state.item_deck.pop_back())

	var quests: Array[String] = []
	for c in card_db.quests:
		if c.lang == "EN" and c.box == "Core":
			quests.append(c.card_name)
	quests.shuffle()
	state.quest_deck = quests
	for _i in range(mini(3, state.quest_deck.size())):
		state.quests_available.append(state.quest_deck.pop_back())

	var legions: Array[String] = []
	for c in card_db.legions:
		if c.lang == "EN" and c.box == "Core":
			legions.append(c.card_name)
	legions.shuffle()
	state.legion_deck = legions

	var hordes: Array[String] = []
	for c in card_db.hordes:
		if c.lang == "EN" and c.box == "Core":
			hordes.append(c.card_name)
	hordes.shuffle()
	state.horde_deck = hordes

	# Events: one deck per Chapter ("One".."Four" in the CSV -> 1..4).
	const CHAPTER_LABELS := {"One": 1, "Two": 2, "Three": 3, "Four": 4}
	var by_chapter: Dictionary = {1: [], 2: [], 3: [], 4: []}
	for c in card_db.events:
		if c.lang != "EN" or c.box != "Core":
			continue
		var chap: int = CHAPTER_LABELS.get(c.chapter, 0)
		if chap > 0:
			by_chapter[chap].append(c.card_name)
	for chap in by_chapter:
		(by_chapter[chap] as Array).shuffle()
	state.event_deck_by_chapter = by_chapter


static func _pick_druids(state: GameState, card_db: Node) -> void:
	var names: Array[String] = []
	for c in card_db.druids:
		if c.lang == "EN":
			names.append(c.card_name)
	names.shuffle()
	var revealed := mini(4, names.size())
	state.druids_in_play = []
	for n in names.slice(0, revealed):
		var d := DruidInstance.new()
		d.card_name = n
		state.druids_in_play.append(d)
	state.druid_deck = names.slice(revealed)
