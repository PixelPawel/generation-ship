extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_dice_model.gd`

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	# --- Structural: every color has exactly 6 faces ---
	var all_six_faces := true
	for color in DiceModel.FACES:
		if (DiceModel.FACES[color] as Array).size() != 6:
			all_six_faces = false
	_check("every die color has exactly 6 faces", all_six_faces)

	# --- Spot-check specific faces against the source image transcription ---
	_check("White face 0 is Skull+Shield", DiceModel.FACES["White"][0] == [DiceModel.Symbol.SKULL, DiceModel.Symbol.SHIELD])
	_check("White face 3 is blank", DiceModel.FACES["White"][3] == [])
	_check("Red face 0 is double-Skull", DiceModel.FACES["Red"][0] == [DiceModel.Symbol.SKULL, DiceModel.Symbol.SKULL])
	_check("Black face 0 is triple-Skull", DiceModel.FACES["Black"][0] == [DiceModel.Symbol.SKULL, DiceModel.Symbol.SKULL, DiceModel.Symbol.SKULL])
	_check("Black face 5 is a Bolt", DiceModel.FACES["Black"][5] == [DiceModel.Symbol.BOLT])
	_check("Purple face 0 is a Bolt", DiceModel.FACES["Purple"][0] == [DiceModel.Symbol.BOLT])

	# --- Cross-check against rulebook p34: 3 Blue dice rolled blank+Skull+Shield ---
	# All three of those results must be faces that actually exist on Blue.
	var blue_has_blank := false
	var blue_has_single_skull := false
	var blue_has_single_shield := false
	for face in DiceModel.FACES["Blue"]:
		if face == []:
			blue_has_blank = true
		if face == [DiceModel.Symbol.SKULL]:
			blue_has_single_skull = true
		if face == [DiceModel.Symbol.SHIELD]:
			blue_has_single_shield = true
	_check("rulebook p34 cross-check: Blue can roll blank", blue_has_blank)
	_check("rulebook p34 cross-check: Blue can roll a single Skull", blue_has_single_skull)
	_check("rulebook p34 cross-check: Blue can roll a single Shield", blue_has_single_shield)

	# --- Deterministic rolling: same seed -> same result ---
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 12345
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 12345
	var roll_a := DiceModel.roll("Red", 10, rng_a)
	var roll_b := DiceModel.roll("Red", 10, rng_b)
	_check("same seed produces the same roll result", roll_a == roll_b)

	# --- Statistical sanity: 6000 White rolls should land close to the
	# expected symbol counts. White = [Skull+Shield, Skull, Shield, blank,
	# blank, blank] -- 2 of 6 faces produce a Skull, 2 of 6 produce a Shield
	# (they overlap on face 0), so both are expected around 6000*(2/6)=2000.
	# Generous tolerance since this is inherently random, not meant to pin
	# down an exact value.
	var stat_rng := RandomNumberGenerator.new()
	stat_rng.seed = 42
	var big_roll := DiceModel.roll("White", 6000, stat_rng)
	var skulls_in_range: bool = big_roll["skulls"] > 1600 and big_roll["skulls"] < 2400
	var shields_in_range: bool = big_roll["shields"] > 1600 and big_roll["shields"] < 2400
	_check("statistical sanity: White skull count in expected range over 6000 rolls", skulls_in_range)
	_check("statistical sanity: White shield count in expected range over 6000 rolls", shields_in_range)

	# --- roll_mixed sums correctly ---
	var mixed_rng := RandomNumberGenerator.new()
	mixed_rng.seed = 7
	var mixed := DiceModel.roll_mixed({"Red": 0, "White": 0}, mixed_rng)
	_check("roll_mixed with zero counts returns an empty tally", mixed["skulls"] == 0 and mixed["shields"] == 0 and mixed["bolts"] == 0)

	# --- Unknown color returns an empty tally instead of erroring ---
	var unknown := DiceModel.roll("Rainbow", 5)
	_check("unknown color returns empty tally, no error", unknown["skulls"] == 0 and unknown["shields"] == 0 and unknown["bolts"] == 0)

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
