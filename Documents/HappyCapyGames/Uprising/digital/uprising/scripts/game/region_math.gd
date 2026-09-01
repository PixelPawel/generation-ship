class_name RegionMath
extends RefCounted
## The 3 named Regions from rulebook p14 (Howling White, Fog Grave,
## Screaming Sea) that permanently label every hex on the board,
## independent of whatever explorable hex tile (if any) is placed there --
## "Any region spaces covered by another hex tile are not part of the
## region" (p14), so a tile can come and go without the region itself
## changing.
##
## Confirmed against the user's own TTS reference board: the whole map is a
## fixed 1-hex center + 3 rings (37 hexes total, BOARD_RADIUS 3), split into
## 3 equal 120-degree wedges of 12 hexes each (2 ring-1 + 4 ring-2 + 6
## ring-3), with Screaming Sea's wedge also owning the center hex (13 --
## "the same amount of hexes, except Screaming Sea has 1 extra").
##
## Each wedge is 2 consecutive "sides" of HexMath.spiral's ring walk (a
## ring's 6r hexes split into 6 sides of r hexes each, one per
## HexMath.DIRECTIONS entry) rather than a closed-form angle formula, so
## the wedge boundaries automatically stay correct at any radius.

const BOARD_RADIUS := 3

const REGIONS := ["Screaming Sea", "Howling White", "Fog Grave"]


## The center hex is Screaming Sea; every other hex out to BOARD_RADIUS
## resolves through which ring and which side of that ring it's on.
## Returns "" for a coord outside the board entirely.
static func region_for(coord: Vector2i, center: Vector2i = Vector2i.ZERO) -> String:
	if coord == center:
		return REGIONS[0]
	var r := HexMath.distance(coord, center)
	if r < 1 or r > BOARD_RADIUS:
		return ""
	var side := _ring_side(coord, center, r)
	return REGIONS[side / 2]


## Which of the 6 HexMath.spiral ring "sides" (0-5) `coord` falls on, by
## walking the same ring construction spiral() itself uses.
static func _ring_side(coord: Vector2i, center: Vector2i, r: int) -> int:
	var walker := center + HexMath.DIRECTIONS[4] * r
	for d in range(6):
		for _step in range(r):
			if walker == coord:
				return d
			walker += HexMath.DIRECTIONS[d]
	return -1  # unreachable for a coord actually at distance r


## Every board coordinate (center included) out to BOARD_RADIUS -- the
## fixed, always-present 37-hex map.
static func all_coords(center: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	return HexMath.spiral(center, BOARD_RADIUS)
