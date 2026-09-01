extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_nemesis_data.gd`
## Verifies NemesisData.get_initiative against the exact values read off
## each of the 8 Core Legions' and 8 Core Hordes' own card art (top-left
## starburst number) -- not the CSV, which has no Initiative column at all.

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	var expected := {
		"The Courtesan": 2,
		"The Lich Queen": 3,
		"The Warlock": 5,
		"The Spymaster": 8,
		"Coven of Yssat": 9,
		"The Assassin": 10,
		"The Imperial Guard": 12,
		"Counter of Omens": 13,
		"The Mage Breaker": 18,
		"The Executioner": 20,
		"Bloodwyrm": 21,
		"The Siren": 25,
		"The Banished": 26,
		"The False Messiah": 28,
		"The New Emperor": 29,
		"Oda the Fallen": 30,
	}
	for card_name in expected:
		_check("%s has Initiative %d" % [card_name, expected[card_name]],
			NemesisData.get_initiative(card_name) == expected[card_name])

	var seen_initiatives := {}
	for v in expected.values():
		seen_initiatives[v] = true
	_check("all 16 Core Legion/Horde Initiative values are unique", seen_initiatives.size() == expected.size())

	_check("unknown card name falls back to a high (last-sorting) value, not an error",
		NemesisData.get_initiative("Not A Real Card") == 999)

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
