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


## Pointy-top axial -> world XZ position, matching how the map plane in
## scripts/main.gd lies flat on the ground (Y up).
static func to_world(coord: Vector2i, hex_size: float = 1.0) -> Vector3:
	var x := hex_size * (sqrt(3.0) * float(coord.x) + sqrt(3.0) / 2.0 * float(coord.y))
	var z := hex_size * (1.5 * float(coord.y))
	return Vector3(x, 0.0, z)


static func key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


static func from_key(k: String) -> Vector2i:
	var parts := k.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
