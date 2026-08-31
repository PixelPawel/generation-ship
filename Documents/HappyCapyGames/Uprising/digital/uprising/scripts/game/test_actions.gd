extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_actions.gd`
## Exercises GameActions directly against a GameSetup-built state -- no
## networking involved, just the rules logic.

func _initialize() -> void:
	await process_frame
	var card_db := root.get_node("/root/CardDatabase")

	var pairs := [["Druwhn", "Fhayanor"], ["Krowh", "Kha'al"]]
	var state := GameSetup.build_new_game(card_db, pairs, "Veteran", 3)
	state.phase = GameState.Phase.ACTIONS

	var checks: Array = []
	var player := state.get_player("Druwhn")
	var starting_ap := player.action_points
	var starting_salt := player.salt

	# --- Trade ---
	var r := GameActions.apply(state, {"type": "trade", "faction": "Druwhn"}, -1)
	checks.append(["trade ok", r.get("ok", false)])
	checks.append(["trade: AP -1", player.action_points == starting_ap - 1])
	checks.append(["trade: salt +1", player.salt == starting_salt + 1])

	# --- Move to an adjacent hex ---
	var home := player.hero_hex
	var neighbor := HexMath.neighbors(home)[0]
	# Ensure the neighbor hex actually exists in the generated board.
	if state.get_hex(neighbor) == null:
		var filler := HexTile.new()
		filler.coord = neighbor
		filler.explored = false
		state.set_hex(filler)

	var ap_before_move := player.action_points
	r = GameActions.apply(state, {"type": "move", "faction": "Druwhn", "to": [neighbor.x, neighbor.y]}, -1)
	checks.append(["move ok", r.get("ok", false)])
	checks.append(["move: hero_hex updated", player.hero_hex == neighbor])
	checks.append(["move: AP -1", player.action_points == ap_before_move - 1])

	# --- Move to a non-adjacent hex should fail ---
	var far := neighbor + Vector2i(10, 10)
	var far_tile := HexTile.new()
	far_tile.coord = far
	state.set_hex(far_tile)
	r = GameActions.apply(state, {"type": "move", "faction": "Druwhn", "to": [far.x, far.y]}, -1)
	checks.append(["move to far hex rejected", not r.get("ok", true)])

	# --- Explore the (unexplored) hex we just moved to ---
	var was_explored := state.get_hex(neighbor).explored
	checks.append(["neighbor starts unexplored", not was_explored])
	var ap_before_explore := player.action_points
	r = GameActions.apply(state, {"type": "explore", "faction": "Druwhn"}, -1)
	checks.append(["explore ok", r.get("ok", false)])
	checks.append(["explore: hex now explored", state.get_hex(neighbor).explored])
	checks.append(["explore: AP -1", player.action_points == ap_before_explore - 1])

	# --- Exploring an already-explored hex should fail ---
	r = GameActions.apply(state, {"type": "explore", "faction": "Druwhn"}, -1)
	checks.append(["re-explore rejected", not r.get("ok", true)])

	# --- Unknown action type ---
	r = GameActions.apply(state, {"type": "not_a_real_action", "faction": "Druwhn"}, -1)
	checks.append(["unknown action rejected", not r.get("ok", true)])

	# --- Unknown faction ---
	r = GameActions.apply(state, {"type": "trade", "faction": "NotAFaction"}, -1)
	checks.append(["unknown faction rejected", not r.get("ok", true)])

	# --- Drain AP to 0, then Trade should be rejected ---
	player.action_points = 0
	r = GameActions.apply(state, {"type": "trade", "faction": "Druwhn"}, -1)
	checks.append(["trade with 0 AP rejected", not r.get("ok", true)])

	# --- Move outside the Actions Phase should be rejected ---
	state.phase = GameState.Phase.BUILD
	r = GameActions.apply(state, {"type": "move", "faction": "Krowh", "to": [0, 0]}, -1)
	checks.append(["move outside Actions Phase rejected", not r.get("ok", true)])

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label, (" -- " + str(r.get("reason", "")) if not ok else ""))
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
