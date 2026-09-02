class_name HexMath
extends RefCounted

## Flat-top axial hex-grid math, sized to match assets/images/3d/hex.obj.
##
## TILE_HEX_SIZE was measured directly from that file's own vertex data
## (Blender-exported OBJ, plain text): its outer ring has a vertex at
## "v 1.999956 0.000000 -0.000025" and its mirror at "v -1.999956 0.000000
## 0.000026" - i.e. a corner-to-corner width of ~4.0 along X, giving a
## circumradius of ~2.0. Two corners sit exactly on the X axis (0 deg/180 deg)
## rather than the Z axis, confirming flat-top orientation (flat-top hexes
## have corners at 0/60/120/180/240/300 degrees; pointy-top hexes would put
## corners at 30/90/150/210/270/330 degrees instead, with no corner on axis).
## If hex.obj is ever regenerated, re-measure rather than trust this comment
## blindly - a tool script for that is worth adding once the editor is
## actually driving imports (see Milestone 1 acceptance test).
const TILE_HEX_SIZE: float = 2.0

## The 6 axial neighbor offsets. These do NOT depend on flat-top vs
## pointy-top orientation - only the axial<->world pixel conversion below does.
const NEIGHBOR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


## Axial (q, r) -> world position (X/Z plane, Y left at 0 - callers stack
## tiles/standees on top as needed).
static func to_world(coord: Vector2i) -> Vector3:
	var q: float = float(coord.x)
	var r: float = float(coord.y)
	var x: float = TILE_HEX_SIZE * (1.5 * q)
	var z: float = TILE_HEX_SIZE * (sqrt(3.0) / 2.0 * q + sqrt(3.0) * r)
	return Vector3(x, 0.0, z)


## World position -> nearest axial hex coord (cube-round algorithm).
static func from_world(pos: Vector3) -> Vector2i:
	var q: float = (2.0 / 3.0 * pos.x) / TILE_HEX_SIZE
	var r: float = (-1.0 / 3.0 * pos.x + sqrt(3.0) / 3.0 * pos.z) / TILE_HEX_SIZE
	return _cube_round(q, r)


static func _cube_round(q: float, r: float) -> Vector2i:
	var x: float = q
	var z: float = r
	var y: float = -x - z

	var rx: float = round(x)
	var ry: float = round(y)
	var rz: float = round(z)

	var dx: float = abs(rx - x)
	var dy: float = abs(ry - y)
	var dz: float = abs(rz - z)

	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector2i(int(rx), int(rz))


static func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in NEIGHBOR_DIRS:
		out.append(coord + d)
	return out


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	var dy: int = -dq - dr
	return (abs(dq) + abs(dy) + abs(dr)) / 2


## All hexes at exactly `radius` steps from `center` (radius 0 = just center).
static func ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [center]
	var results: Array[Vector2i] = []
	var coord: Vector2i = center + NEIGHBOR_DIRS[4] * radius
	for i: int in range(6):
		for _step: int in range(radius):
			results.append(coord)
			coord += NEIGHBOR_DIRS[i]
	return results


## All hexes within `radius` steps of `center`, inclusive (a filled disk).
static func spiral(center: Vector2i, radius: int) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	for r: int in range(radius + 1):
		results.append_array(ring(center, r))
	return results
