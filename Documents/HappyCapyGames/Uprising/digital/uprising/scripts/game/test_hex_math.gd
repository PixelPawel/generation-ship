extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_hex_math.gd`
## Verifies to_world()/from_world() round-trip correctly (including near
## tile edges, where naive q/r rounding would pick the wrong hex) and that
## neighbor distances land where expected in world space.

func _initialize() -> void:
	var checks: Array = []

	# --- Exact round-trip for every coord in a decent-sized spiral ---
	var coords := HexMath.spiral(Vector2i.ZERO, 5)
	var all_roundtrip_ok := true
	for c in coords:
		var world := HexMath.to_world(c)
		var back := HexMath.from_world(world)
		if back != c:
			all_roundtrip_ok = false
			print("  MISMATCH: ", c, " -> ", world, " -> ", back)
	checks.append(["exact round-trip for %d spiral coords" % coords.size(), all_roundtrip_ok])

	# --- Points slightly offset from center should still round to the same hex ---
	var jitter_ok := true
	for c in coords:
		var world := HexMath.to_world(c)
		for offset in [Vector3(0.3, 0, 0.2), Vector3(-0.4, 0, 0.1), Vector3(0.1, 0, -0.5)]:
			var back := HexMath.from_world(world + offset)
			if back != c:
				jitter_ok = false
	checks.append(["small jitter still resolves to same hex", jitter_ok])

	# --- Adjacent hexes should be roughly hex_size*sqrt(3) apart in world space ---
	var origin_world := HexMath.to_world(Vector2i.ZERO)
	var dist_ok := true
	for n in HexMath.neighbors(Vector2i.ZERO):
		var d := origin_world.distance_to(HexMath.to_world(n))
		var expected := HexMath.TILE_HEX_SIZE * sqrt(3.0)
		if absf(d - expected) > 0.01:
			dist_ok = false
			print("  BAD DISTANCE: neighbor ", n, " dist=", d, " expected=", expected)
	checks.append(["neighbor world-distance is hex_size*sqrt(3)", dist_ok])

	# --- A point roughly halfway between two hex centers should resolve to
	# one of those two hexes (not some unrelated third one). ---
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var midpoint := (HexMath.to_world(a) + HexMath.to_world(b)) * 0.5
	var mid_result := HexMath.from_world(midpoint)
	checks.append(["midpoint resolves to one of the two neighbors", mid_result == a or mid_result == b])

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
