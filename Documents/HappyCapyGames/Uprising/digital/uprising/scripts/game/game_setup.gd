class_name GameSetup
extends RefCounted
## Builds a fresh, fully-populated GameState from a difficulty + faction/Hero
## selection (rulebook p5-9). Targets Core box only for now (per project
## scope decision) -- Arch-Nemesis/Titans content stays in CardDatabase but
## is filtered out of decks/setup here.
##
## The printed p7 setup diagrams aren't digitized in any CSV (they're print
## artwork), so this pattern was extracted directly from the TTS mod's own
## "2/3/4 Player Normal" setup buttons instead: each one's Lua script has
## explicit void.takeObject / towers.takeObject / garrison.takeObject calls
## with literal world positions, converted here to axial coords (see
## GARRISON_COORDS_VETERAN / SETUP_BY_PLAYER_COUNT). That's exact data, not a
## transcription of a diagram -- and it turned out to NOT be one uniform
## formula: Sea Towers sit at hex-distance 2 from Capital for 2 and 3
## players, but distance 3 for 4 players. Garrisons are identical across
## all 3 counts. Home Hex coords were derived by elimination (whichever
## ring-2 coord the setup script never touches with a random hex or Sea
## Tower) -- exact for 3 and 4 players; for 2 players the raw data left 3
## symmetric candidate pairs, resolved using the user's own "2 steps away
## going up and down" description to pick the zero-horizontal-offset pair.
##
## Everything else fills from the shuffled Core pool, same as before, but
## only out to RegionMath.BOARD_RADIUS -- the board is a fixed 37-hex disk
## (also confirmed against the user's TTS board), not an arbitrarily large
## spiral. The Core pool (25 non-Home cards) doesn't fill all 37 -- 32 at
## most, and fewer once petals/garrisons consume some -- so some coords
## always end up with no HexTile at all. That's correct, not a shortfall:
## per rulebook p14, every hex belongs permanently to one of 3 Regions
## (Howling White/Fog Grave/Screaming Sea) whether or not it currently has
## a tile, and GameBoard renders a coord with no HexTile as its bare
## Region instead of a gap (see RegionMath, GameBoard._bare_region_tile).

## Core box home hex per faction, from CardDatabase.hexes (Type == "Home").
const HOME_HEX_BY_FACTION := {
	"Druwhn": "Yfelskog",
	"Duerkhar": "Khatrak Kautil",
	"Mohyar": "Winterholm",
	"Krowh": "Pak Glandris",
}

## Resources are the rulebook p9 table (unaffected by anything below);
## curses/skeletons/garrison_count come from extracting all 12 of the TTS
## mod's difficulty x player-count setup buttons (Easy/Normal/Nightmare/
## Apocalypse, matching Rebel/Veteran/Nightmare/Apocalypse here), same as
## SETUP_BY_PLAYER_COUNT below -- this replaced an earlier approximation
## that had real gaps: Skeleton count is a flat 3 at every difficulty AND
## player count (not scaled 0/2/3/3 as guessed before), Garrison count is
## difficulty-driven at 0/3/6 (not always 3 -- Easy has none, Nightmare/
## Apocalypse Garrison *every* ring-1 hex, not just half), and Curse count
## depends on player count too at the top 2 tiers (2 for 2 players, 3 for
## 3-4), not just difficulty.
const DIFFICULTY_TABLE := {
	"Rebel": {"resources": 6, "curses": 0, "skeletons": 3, "garrison_count": 0},
	"Veteran": {"resources": 5, "curses": 2, "skeletons": 3, "garrison_count": 3},
	"Nightmare": {"resources": 5, "curses": 2, "curses_3plus_players": 3, "skeletons": 3, "garrison_count": 6},
	"Apocalypse": {"resources": 5, "curses": 2, "curses_3plus_players": 3, "skeletons": 3, "garrison_count": 6},
}

const STARTING_AP := 8

## The Veteran-tier 3 Garrison coords -- the same 3 of Capital's 6 ring-1
## neighbors at every player count. Nightmare/Apocalypse Garrison all 6
## ring-1 neighbors instead (see _garrison_coords); Rebel Garrisons none.
const GARRISON_COORDS_VETERAN: Array[Vector2i] = [Vector2i(1, -1), Vector2i(0, 1), Vector2i(-1, 0)]

## Home Hex / Sea Tower coords per player count, index i going to
## faction_hero_pairs[i]. See the class doc comment for how these were
## extracted/derived.
const SETUP_BY_PLAYER_COUNT := {
	2: {
		"home": [Vector2i(0, -2), Vector2i(0, 2)],
		"sea_tower": [Vector2i(2, 0), Vector2i(-2, 0)],
	},
	3: {
		"home": [Vector2i(2, 0), Vector2i(0, -2), Vector2i(-2, 2)],
		"sea_tower": [Vector2i(-2, 0), Vector2i(0, 2), Vector2i(2, -2)],
	},
	4: {
		"home": [Vector2i(-2, 0), Vector2i(1, -2), Vector2i(-1, 2), Vector2i(2, 0)],
		"sea_tower": [Vector2i(3, -2), Vector2i(1, 2), Vector2i(-3, 2), Vector2i(-1, -2)],
	},
}


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
	var pool := _gather_core_hex_pool(card_db)

	_place_capital(state, used)
	var petals := _reserve_petal_coords(faction_hero_pairs, used)
	_place_home_hexes_and_players(state, card_db, faction_hero_pairs, petals, diff)
	_place_fixed_sea_towers(state, pool, petals)
	_place_capital_garrisons(state, pool, used, _garrison_coords(int(diff.get("garrison_count", 3))))

	var placements := _fill_board(state, pool, used)

	_place_curses(state, placements, _curse_count(diff, faction_hero_pairs.size()))
	_place_skeletons(state, placements, diff.get("skeletons", 3))

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


## 0/3/6 of Capital's ring-1 neighbors depending on difficulty (see the
## DIFFICULTY_TABLE doc comment) -- none, the fixed Veteran-tier 3, or all
## 6 ring-1 neighbors.
static func _garrison_coords(count: int) -> Array[Vector2i]:
	if count <= 0:
		return []
	if count >= 6:
		return HexMath.neighbors(GameState.CAPITAL_COORD)
	return GARRISON_COORDS_VETERAN


## Nightmare/Apocalypse Curse a 3rd hex once there are 3+ players in play
## (see the DIFFICULTY_TABLE doc comment); every other tier/player-count
## combination is just the tier's flat `curses` value.
static func _curse_count(diff: Dictionary, player_count: int) -> int:
	if player_count >= 3 and diff.has("curses_3plus_players"):
		return diff["curses_3plus_players"]
	return diff.get("curses", 0)


## One {"home": coord, "sea_tower": coord} pair per faction, using the
## exact TTS-derived coords for this player count (see SETUP_BY_PLAYER_
## COUNT and the class doc comment). Marks both used. Player counts
## outside 2-4 (solo with a single faction, in practice) fall back to the
## nearest supported layout, since there's no real board data for those.
static func _reserve_petal_coords(faction_hero_pairs: Array, used: Dictionary) -> Dictionary:
	var count: int = clampi(faction_hero_pairs.size(), 2, 4)
	var layout: Dictionary = SETUP_BY_PLAYER_COUNT[count]
	var homes: Array = layout["home"]
	var sea_towers: Array = layout["sea_tower"]
	var petals := {}
	for i in faction_hero_pairs.size():
		var faction: String = faction_hero_pairs[i][0]
		var home_coord: Vector2i = homes[i]
		var sea_tower_coord: Vector2i = sea_towers[i]
		petals[faction] = {"home": home_coord, "sea_tower": sea_tower_coord}
		used[HexMath.key(home_coord)] = true
		used[HexMath.key(sea_tower_coord)] = true
	return petals


## Places each faction's fixed Sea Tower (see _reserve_petal_coords) with a
## name popped from `pool`'s sea_tower list, so the random fill below
## doesn't also place it a second time.
static func _place_fixed_sea_towers(state: GameState, pool: Dictionary, petals: Dictionary) -> void:
	var sea_tower: Array = pool["sea_tower"]
	for faction in petals:
		if sea_tower.is_empty():
			break
		var tile := HexTile.new()
		tile.coord = petals[faction]["sea_tower"]
		tile.explored = false
		tile.card_name = sea_tower.pop_back()
		tile.is_sea_tower = true
		state.set_hex(tile)


## `faction_hero_pairs` entries are either the plain [faction, hero] form
## (every pre-Lobby caller, including all the tests) or the Lobby's richer
## [faction, hero, peer_id, is_bot] form -- peer_id defaults to -1
## (unclaimed/no controller) and is_bot to false when omitted, so both
## forms build an identical PlayerFactionState for a human pair.
static func _place_home_hexes_and_players(
	state: GameState, card_db: Node, faction_hero_pairs: Array, petals: Dictionary, diff: Dictionary
) -> void:
	for pair in faction_hero_pairs:
		var faction: String = pair[0]
		var hero_name: String = pair[1]
		var peer_id: int = int(pair[2]) if pair.size() > 2 else -1
		var is_bot: bool = bool(pair[3]) if pair.size() > 3 else false
		var coord: Vector2i = petals[faction]["home"]

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


## Rulebook p6's "Place 3 Garrisons on The Capital, 1 Garrison on 3
## adjacent hexes" is just the Veteran tier -- see _garrison_coords for how
## many ring-1 hexes actually get one at each difficulty. That ring-1 hex
## is still a random hex like any other unclaimed one (confirmed by the
## user against their TTS screenshots), just also carrying a Garrison, so
## it draws from the same `pool` _fill_board uses rather than being left
## card_name-less.
static func _place_capital_garrisons(
	state: GameState, pool: Dictionary, used: Dictionary, garrison_coords: Array[Vector2i]
) -> void:
	var normal: Array = pool["normal"]
	var sea_tower: Array = pool["sea_tower"]
	for coord in garrison_coords:
		if used.has(HexMath.key(coord)):
			continue
		var tile := HexTile.new()
		tile.coord = coord
		tile.explored = false
		tile.garrison_level = 1
		if not normal.is_empty():
			tile.card_name = normal.pop_back()
		elif not sea_tower.is_empty():
			tile.card_name = sea_tower.pop_back()
			tile.is_sea_tower = true
		state.set_hex(tile)
		used[HexMath.key(coord)] = true


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
##
## The board itself is the fixed 37-hex disk RegionMath knows about (1
## center + 3 rings) -- not a bigger arbitrary spiral -- so a board coord
## this doesn't reach stays without a HexTile entirely, and the caller can
## show RegionMath.region_for() there instead (rulebook p14's Regions: the
## permanent Howling White / Fog Grave / Screaming Sea labels every hex
## carries whether or not it currently has a tile).
static func _fill_board(state: GameState, pool: Dictionary, used: Dictionary) -> Array[Vector2i]:
	var normal: Array = pool["normal"]
	var sea_tower: Array = pool["sea_tower"]
	var placements: Array[Vector2i] = []

	var candidates := RegionMath.all_coords(GameState.CAPITAL_COORD)
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
