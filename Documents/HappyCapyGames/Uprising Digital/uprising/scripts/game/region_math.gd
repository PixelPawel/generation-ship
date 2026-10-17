class_name RegionMath
extends RefCounted

## The 3 named Regions (rulebook p14): every space of the printed 37-hex
## board carries one of these names, is explored Ice Waste and can never
## gain a Haven. "Any region spaces covered by another hex tile are not part
## of the region" - so only uncovered spaces (HexTileState.role "outer")
## count when an effect names a Region.
##
## Wedges read off the printed board art (BOARDS_EN/Game+Board+4-Folder.jpg)
## space by space, then checked by drawing this function's output over that
## image - all 37 matched (2026-10-17): Screaming Sea is the north wedge plus
## the center space (13), Howling White the south-west wedge (12), Fog Grave
## the south-east wedge (12). North = world -z = "up" in the rulebook's p7
## setup diagrams, which GameSetup's TTS-derived coordinates match exactly
## (Sea Towers upper-left/lower-right, Garrisons upper-left/upper-right/below
## the Capital).
const REGIONS: Array[String] = ["Screaming Sea", "Howling White", "Fog Grave"]
const BOARD_RADIUS: int = 3

## The solo side of the map (True Solo Mode, rulebook p75-77): 28 spaces in
## three Regions of 9 plus The Howling Abyss at the southern tip, read off
## the printed solo map (TTS solo-mode-map-8000.jpg) space by space.
## Coordinates are relative to The Capital.
const SOLO_REGIONS: Array[String] = ["Obsidian Depths", "Wandering Sea", "Darkmirror", "The Howling Abyss"]
const SOLO_REGION_OF: Dictionary = {
	Vector2i(0, -2): "Obsidian Depths", Vector2i(0, -1): "Obsidian Depths", Vector2i(0, 0): "Obsidian Depths",
	Vector2i(-1, -1): "Obsidian Depths", Vector2i(-1, 0): "Obsidian Depths", Vector2i(1, -2): "Obsidian Depths",
	Vector2i(1, -1): "Obsidian Depths", Vector2i(-2, 0): "Obsidian Depths", Vector2i(2, -2): "Obsidian Depths",
	Vector2i(0, 1): "Wandering Sea", Vector2i(-1, 1): "Wandering Sea", Vector2i(-1, 2): "Wandering Sea",
	Vector2i(-1, 3): "Wandering Sea", Vector2i(-2, 1): "Wandering Sea", Vector2i(-2, 2): "Wandering Sea",
	Vector2i(-2, 3): "Wandering Sea", Vector2i(-3, 2): "Wandering Sea", Vector2i(-3, 3): "Wandering Sea",
	Vector2i(0, 2): "Darkmirror", Vector2i(1, 0): "Darkmirror", Vector2i(1, 1): "Darkmirror",
	Vector2i(1, 2): "Darkmirror", Vector2i(2, -1): "Darkmirror", Vector2i(2, 0): "Darkmirror",
	Vector2i(2, 1): "Darkmirror", Vector2i(3, -1): "Darkmirror", Vector2i(3, 0): "Darkmirror",
	Vector2i(0, 3): "The Howling Abyss",
}


## The Regions of the map this game is played on.
static func regions(state: GameState) -> Array[String]:
	return SOLO_REGIONS if state != null and state.solo else REGIONS


## Printed Region of a space on this game's map ("" off the board).
static func region_at(state: GameState, coord: Vector2i) -> String:
	var center: Vector2i = state.capital_coord if state != null else Vector2i.ZERO
	if state != null and state.solo:
		return str(SOLO_REGION_OF.get(coord - center, ""))
	return region_for(coord, center)


## Printed Region of a board space, "" if it lies off the 37-hex board.
## Pure geometry - whether a tile currently covers it is region_hexes()'s job.
static func region_for(coord: Vector2i, center: Vector2i = Vector2i.ZERO) -> String:
	var q: int = coord.x - center.x
	var r: int = coord.y - center.y
	var s: int = -q - r
	if maxi(absi(q), maxi(absi(r), absi(s))) > BOARD_RADIUS:
		return ""
	if q > 0 and s <= 0:
		return "Fog Grave"
	if r > 0 and q <= 0:
		return "Howling White"
	return "Screaming Sea"


## Uncovered board spaces that belong to `region`, in a stable order.
static func region_hexes(state: GameState, region: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for coord: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[coord]
		if t.role == "outer" and region_at(state, coord) == region:
			out.append(coord)
	out.sort()
	return out
