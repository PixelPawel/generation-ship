class_name HexMath
extends RefCounted
## Axial hex-coordinate math. Coordinates are plain Vector2i(q, r) so they
## marshal natively over RPC and JSON without a custom type.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		result.append(coord + d)
	return result


static func distance(a: Vector2i, b: Vector2i) -> int:
	return (absi(a.x - b.x) + absi(a.x + a.y - b.x - b.y) + absi(a.y - b.y)) / 2


## Circumradius of assets/images/3d/hex.obj (point-to-point extent is 2x this).
## Use as the `hex_size` for to_world()/from_world() when placing that mesh
## so adjacent tiles sit flush with no gaps or overlaps.
const TILE_HEX_SIZE := 2.0

## Flat-top axial -> world XZ position (Y up, hex lying flat on the ground).
## "Flat-top" here matches assets/images/3d/hex.obj's actual shape: wider
## along X (point-to-point, 2*hex_size) than Z (flat-to-flat, sqrt(3)*hex_size).
## Getting this orientation right matters -- the pointy-top formula tiles
## with gaps against a flat-top mesh.
static func to_world(coord: Vector2i, hex_size: float = TILE_HEX_SIZE) -> Vector3:
	var x := hex_size * (1.5 * float(coord.x))
	var z := hex_size * (sqrt(3.0) / 2.0 * float(coord.x) + sqrt(3.0) * float(coord.y))
	return Vector3(x, 0.0, z)


## Inverse of to_world(): world XZ position -> nearest axial hex coordinate.
## Used for click/raycast hex picking.
static func from_world(pos: Vector3, hex_size: float = TILE_HEX_SIZE) -> Vector2i:
	var q := (2.0 / 3.0 * pos.x) / hex_size
	var r := (-1.0 / 3.0 * pos.x + sqrt(3.0) / 3.0 * pos.z) / hex_size
	return _round_axial(q, r)


## Cube-coordinate rounding so fractional (q, r) rounds to the actual nearest
## hex instead of just independently rounding q and r (which can pick the
## wrong hex near edges).
static func _round_axial(q: float, r: float) -> Vector2i:
	var x := q
	var z := r
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


static func key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


static func from_key(k: String) -> Vector2i:
	var parts := k.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


## All hex coordinates within `radius` rings of `center`, ring by ring
## (center first, then the 6 neighbors, then the 12 at distance 2, ...).
## Used by GameSetup to lay out the map without needing a fixed-size grid.
static func spiral(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = [center]
	for r in range(1, radius + 1):
		var coord := center + DIRECTIONS[4] * r  # start at direction index 4 ("-1,+1")
		for d in range(6):
			for _step in range(r):
				result.append(coord)
				coord += DIRECTIONS[d]
	return result
