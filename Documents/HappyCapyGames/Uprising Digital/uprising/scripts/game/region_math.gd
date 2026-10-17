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
		if t.role == "outer" and region_for(coord, state.capital_coord) == region:
			out.append(coord)
	out.sort()
	return out
