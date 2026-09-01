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
	var r := GameActions.apply(state, {"type": "trade", "faction": "Druwhn"}, -1, card_db)
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
	r = GameActions.apply(state, {"type": "move", "faction": "Druwhn", "to": [neighbor.x, neighbor.y]}, -1, card_db)
	checks.append(["move ok", r.get("ok", false)])
	checks.append(["move: hero_hex updated", player.hero_hex == neighbor])
	checks.append(["move: AP -1", player.action_points == ap_before_move - 1])

	# --- Move to a non-adjacent hex should fail ---
	var far := neighbor + Vector2i(10, 10)
	var far_tile := HexTile.new()
	far_tile.coord = far
	state.set_hex(far_tile)
	r = GameActions.apply(state, {"type": "move", "faction": "Druwhn", "to": [far.x, far.y]}, -1, card_db)
	checks.append(["move to far hex rejected", not r.get("ok", true)])

	# --- Explore the (unexplored) hex we just moved to ---
	var was_explored := state.get_hex(neighbor).explored
	checks.append(["neighbor starts unexplored", not was_explored])
	var ap_before_explore := player.action_points
	r = GameActions.apply(state, {"type": "explore", "faction": "Druwhn"}, -1, card_db)
	checks.append(["explore ok", r.get("ok", false)])
	checks.append(["explore: hex now explored", state.get_hex(neighbor).explored])
	checks.append(["explore: AP -1", player.action_points == ap_before_explore - 1])

	# --- Exploring an already-explored hex should fail ---
	r = GameActions.apply(state, {"type": "explore", "faction": "Druwhn"}, -1, card_db)
	checks.append(["re-explore rejected", not r.get("ok", true)])

	# --- Haven on the Hero's current (now explored) hex ---
	var plunder_before := player.plunder
	var ap_before_haven := player.action_points
	r = GameActions.apply(state, {"type": "haven", "faction": "Druwhn"}, -1, card_db)
	checks.append(["haven ok", r.get("ok", false)])
	checks.append(["haven: hex now owned", state.get_hex(neighbor).haven_faction == "Druwhn"])
	checks.append(["haven: plunder -2", player.plunder == plunder_before - 2])
	checks.append(["haven: AP -1", player.action_points == ap_before_haven - 1])
	checks.append(["haven: added to player.havens", player.havens.has(neighbor)])

	# --- A second Haven on the same hex should fail ---
	r = GameActions.apply(state, {"type": "haven", "faction": "Druwhn"}, -1, card_db)
	checks.append(["second haven on same hex rejected", not r.get("ok", true)])

	# --- Command: put a Unit on a hex adjacent to the target, then Command it in ---
	var command_target := home  # move back to the (empty, explored) home hex
	var supply_hex := HexMath.neighbors(command_target)[0]
	if state.get_hex(supply_hex) == null:
		var supply_tile := HexTile.new()
		supply_tile.coord = supply_hex
		supply_tile.explored = true
		state.set_hex(supply_tile)
	state.get_hex(supply_hex).units["Druwhn"] = ["Rangers"]

	var food_before := player.food
	r = GameActions.apply(
		state, {"type": "command", "faction": "Druwhn", "to": [command_target.x, command_target.y]}, -1, card_db
	)
	checks.append(["command ok", r.get("ok", false)])
	checks.append(["command: hero moved to target", player.hero_hex == command_target])
	checks.append(["command: unit gathered onto target", state.get_hex(command_target).units.get("Druwhn", []).has("Rangers")])
	checks.append(["command: unit removed from supply hex", not state.get_hex(supply_hex).units.get("Druwhn", []).has("Rangers")])
	checks.append(["command: food -1", player.food == food_before - 1])

	# --- Market: buy a known-cheap, no-requirement Item ---
	if not state.market.has("Abad Warpaint"):
		state.market.append("Abad Warpaint")
	var salt_before_market := player.salt
	var market_size_before := state.market.size()
	r = GameActions.apply(state, {"type": "market", "faction": "Druwhn", "item": "Abad Warpaint"}, -1, card_db)
	checks.append(["market ok", r.get("ok", false)])
	checks.append(["market: item in items_in_play", player.items_in_play.has("Abad Warpaint")])
	checks.append(["market: item removed from market", not state.market.has("Abad Warpaint")])
	checks.append(["market: salt decreased", player.salt < salt_before_market])
	checks.append(["market: market shrank by 1", state.market.size() == market_size_before - 1])

	# --- Market: an Item requiring more Might than the Hero has should fail ---
	var high_req_item := "Axe of the Giants"  # requires Might 3; Fhayanor has Might 1
	if not state.market.has(high_req_item):
		state.market.append(high_req_item)
	r = GameActions.apply(state, {"type": "market", "faction": "Druwhn", "item": high_req_item}, -1, card_db)
	checks.append(["market rejects insufficient attribute", not r.get("ok", true)])

	# --- Market: unknown item should fail ---
	r = GameActions.apply(state, {"type": "market", "faction": "Druwhn", "item": "Not A Real Item"}, -1, card_db)
	checks.append(["market rejects unknown item", not r.get("ok", true)])

	# --- Quest: AP-only stub ---
	var quest_name := "A Deal with Demons"
	if not state.quests_available.has(quest_name):
		state.quests_available.append(quest_name)
	var ap_before_quest := player.action_points
	r = GameActions.apply(state, {"type": "quest", "faction": "Druwhn", "quest": quest_name}, -1, card_db)
	checks.append(["quest ok", r.get("ok", false)])
	checks.append(["quest: AP -1", player.action_points == ap_before_quest - 1])

	r = GameActions.apply(state, {"type": "quest", "faction": "Druwhn", "quest": "Not A Real Quest"}, -1, card_db)
	checks.append(["quest rejects unavailable quest", not r.get("ok", true)])

	# --- Unknown action type ---
	r = GameActions.apply(state, {"type": "not_a_real_action", "faction": "Druwhn"}, -1, card_db)
	checks.append(["unknown action rejected", not r.get("ok", true)])

	# --- Unknown faction ---
	r = GameActions.apply(state, {"type": "trade", "faction": "NotAFaction"}, -1, card_db)
	checks.append(["unknown faction rejected", not r.get("ok", true)])

	# --- Drain AP to 0, then Trade should be rejected ---
	player.action_points = 0
	r = GameActions.apply(state, {"type": "trade", "faction": "Druwhn"}, -1, card_db)
	checks.append(["trade with 0 AP rejected", not r.get("ok", true)])

	# --- Move outside the Actions Phase should be rejected ---
	state.phase = GameState.Phase.BUILD
	r = GameActions.apply(state, {"type": "move", "faction": "Krowh", "to": [0, 0]}, -1, card_db)
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
