extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_save_load.gd`

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	await process_frame
	var card_db := root.get_node("/root/CardDatabase")

	# Clean slate: remove any leftover save from a previous run.
	SaveLoad.delete_save("test_slot")

	_check("no save exists yet", not SaveLoad.list_saves().has("test_slot"))
	_check("loading a nonexistent slot returns null", SaveLoad.load_game("test_slot") == null)

	var pairs := [["Druwhn", "Fhayanor"], ["Krowh", "Kha'al"]]
	var original := GameSetup.build_new_game(card_db, pairs, "Veteran", 3)
	original.chapter = 2
	original.phase = GameState.Phase.ACTIONS
	original.players[0].salt = 42
	original.pending_combats = [Vector2i(3, -2)]

	var err := SaveLoad.save_game(original, "test_slot")
	_check("save_game returns OK", err == OK)
	_check("save now appears in list_saves", SaveLoad.list_saves().has("test_slot"))

	var loaded := SaveLoad.load_game("test_slot")
	_check("load_game returns a GameState", loaded != null)
	_check("chapter round-tripped", loaded.chapter == 2)
	_check("phase round-tripped", loaded.phase == GameState.Phase.ACTIONS)
	_check("hex count round-tripped", loaded.hexes.size() == original.hexes.size())
	_check("player count round-tripped", loaded.players.size() == original.players.size())
	_check("modified player stat round-tripped", loaded.get_player("Druwhn").salt == 42)
	_check("pending_combats round-tripped", loaded.pending_combats == [Vector2i(3, -2)])
	_check("market round-tripped", loaded.market == original.market)
	_check("druids round-tripped", loaded.druids_in_play == original.druids_in_play)

	var deleted := SaveLoad.delete_save("test_slot")
	_check("delete_save succeeds", deleted)
	_check("save no longer listed after delete", not SaveLoad.list_saves().has("test_slot"))

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
