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
