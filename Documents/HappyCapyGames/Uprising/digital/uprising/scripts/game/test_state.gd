extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_state.gd`
## Builds a small GameState, round-trips it through to_dict/from_dict AND
## through JSON (proving it's safe for both save files and RPC transport),
## and checks the reconstructed state matches.

func _initialize() -> void:
	var state := GameState.new()
	state.chapter = 2
	state.phase = GameState.Phase.ACTIONS
	state.max_chapters = 3

	var hex_a := HexTile.new()
	hex_a.coord = Vector2i(0, 0)
	hex_a.card_name = "Pak Glandris"
	hex_a.explored = true
	hex_a.haven_faction = "Krowh"
	hex_a.units = {"Krowh": ["Tribesmen", "Tribesmen"]}
	state.set_hex(hex_a)

	var hex_b := HexTile.new()
	hex_b.coord = Vector2i(1, 0)
	hex_b.card_name = "New Winterholm"
	hex_b.explored = true
	hex_b.garrison_level = 2
	state.set_hex(hex_b)

	var player := PlayerFactionState.new()
	player.faction = "Krowh"
	player.hero_name = "Kha'al"
	player.salt = 5
	player.plunder = 3
	player.food = 4
	player.action_points = 6
	player.might = 3
	player.havens = [Vector2i(0, 0)]
	state.players.append(player)

	var legion := LegionInstance.new()
	legion.id = state.next_nemesis_id()
	legion.card_name = "The Butcher"
	legion.threat = 5
	legion.coord = Vector2i(0, 0)
	legion.target_faction = "Krowh"
	legion.target_hex = Vector2i(0, 0)
	state.legions.append(legion)

	var horde := HordeInstance.new()
	horde.id = state.next_nemesis_id()
	horde.card_name = "Lichqueen"
	horde.threat = 4
	horde.coord = Vector2i(1, 0)
	state.hordes.append(horde)

	state.market = ["Abad Warpaint", "Blackfire"]
	state.quests_available = ["A Deal with Demons"]

	# --- Round-trip through plain Dictionary ---
	var d := state.to_dict()
	var restored := GameState.from_dict(d)

	# --- Round-trip through JSON, proving it's transport/save-safe ---
	var json_text := JSON.stringify(d)
	var json_back: Dictionary = JSON.parse_string(json_text)
	var restored_from_json := GameState.from_dict(json_back)

	var checks := [
		["chapter", restored.chapter == 2],
		["phase", restored.phase == GameState.Phase.ACTIONS],
		["hex count", restored.hexes.size() == 2],
		["hex A haven", restored.get_hex(Vector2i(0, 0)).haven_faction == "Krowh"],
		["hex A units", restored.get_hex(Vector2i(0, 0)).units.get("Krowh", []).size() == 2],
		["hex B garrison", restored.get_hex(Vector2i(1, 0)).garrison_level == 2],
		["player count", restored.players.size() == 1],
		["player salt", restored.players[0].salt == 5],
		["player havens", restored.players[0].havens[0] == Vector2i(0, 0)],
		["legion count", restored.legions.size() == 1],
		["legion target_hex", restored.legions[0].target_hex == Vector2i(0, 0)],
		["horde count", restored.hordes.size() == 1],
		["horde threat", restored.hordes[0].threat == 4],
		["market", restored.market.size() == 2],
		["JSON hex count", restored_from_json.hexes.size() == 2],
		["JSON legion target_hex", restored_from_json.legions[0].target_hex == Vector2i(0, 0)],
		["JSON player salt", restored_from_json.players[0].salt == 5],
	]

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
