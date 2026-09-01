extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_faction_data.gd`

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	var factions := ["Druwhn", "Duerkhar", "Krowh", "Mohyar"]

	# --- Structural: every faction has exactly 4 Units and 6 production rows ---
	var all_four_units := true
	var all_six_rows := true
	for f in factions:
		if FactionData.get_units(f).size() != 4:
			all_four_units = false
		if (FactionData.PRODUCTION[f] as Array).size() != 6:
			all_six_rows = false
	_check("every faction has exactly 4 purchasable Units", all_four_units)
	_check("every faction has exactly 6 production rows (0-5 Havens)", all_six_rows)

	# --- All 4 factions share the same 0-Haven baseline (2 Plunder, 1 Food, 0 Salt) ---
	var baseline_shared := true
	for f in factions:
		var p := FactionData.get_production(f, 0)
		if p["salt"] != 0 or p["plunder"] != 2 or p["food"] != 1:
			baseline_shared = false
	_check("all factions share the 0-Haven baseline (0/2/1)", baseline_shared)

	# --- Spot-check specific transcribed values ---
	_check("Druwhn 3-Haven production is 5 Salt/2 Plunder/1 Food", FactionData.get_production("Druwhn", 3) == {"salt": 5, "plunder": 2, "food": 1})
	_check("Duerkhar 5-Haven production is 2 Salt/5 Plunder/2 Food", FactionData.get_production("Duerkhar", 5) == {"salt": 2, "plunder": 5, "food": 2})
	_check("Krowh 2-Haven production is 1 Salt/1 Plunder/4 Food", FactionData.get_production("Krowh", 2) == {"salt": 1, "plunder": 1, "food": 4})
	_check("Mohyar 4-Haven production is 3 Salt/3 Plunder/3 Food", FactionData.get_production("Mohyar", 4) == {"salt": 3, "plunder": 3, "food": 3})

	# --- Haven count above 5 clamps to the 5-Haven row ---
	_check("Haven count of 9 clamps to the 5-Haven row", FactionData.get_production("Druwhn", 9) == FactionData.get_production("Druwhn", 5))

	# --- Unknown faction returns a zeroed production row, not an error ---
	_check("unknown faction returns zeroed production", FactionData.get_production("NotAFaction", 2) == {"salt": 0, "plunder": 0, "food": 0})

	# --- Unit lookups ---
	var swordsisters := FactionData.find_unit("Druwhn", "Swordsisters")
	_check("Druwhn Swordsisters: count 4, Basic Warrior", swordsisters.get("count") == 4 and swordsisters.get("type") == "Basic Warrior")
	_check("Druwhn Swordsisters cost is 1 Salt + 1 Plunder", swordsisters.get("cost_options") == [{"salt": 1, "plunder": 1}])

	var younglings := FactionData.find_unit("Duerkhar", "Younglings")
	_check("Duerkhar Younglings has an OR cost (2 options)", (younglings.get("cost_options") as Array).size() == 2)

	var sellswords := FactionData.find_unit("Mohyar", "Sellswords")
	_check("Mohyar Sellswords costs ANY 2", sellswords.get("cost_options") == [{"any": 2}])

	_check("unknown unit returns an empty dict", FactionData.find_unit("Druwhn", "Not A Real Unit") == {})

	# --- Tower/Wall cost shared across factions ---
	_check("Tower/Wall cost is 1 Plunder", FactionData.TOWER_WALL_COST == {"plunder": 1})

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
