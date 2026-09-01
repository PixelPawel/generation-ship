extends SceneTree
## Headless networking smoke test (host side). Run alongside test_client.gd:
##   godot --headless --script res://scripts/net/test_host.gd
##   godot --headless --script res://scripts/net/test_client.gd
## Verifies a real ENet round trip: client connects, receives initial state,
## submits an action, host applies+broadcasts, client sees the new state.

const PORT := 8910
const MAX_WAIT_FRAMES := 3600  # ~60s at 60fps


func _initialize() -> void:
	await process_frame
	var net_mgr := root.get_node("/root/NetworkManager")
	var card_db := root.get_node("/root/CardDatabase")

	var state := GameSetup.build_new_game(card_db, [["Krowh", "Kha'al"]], "Veteran", 3)
	state.phase = GameState.Phase.ACTIONS
	var starting_salt: int = state.get_player("Krowh").salt
	print("HOST starting Krowh salt: ", starting_salt)

	var err: Error = net_mgr.host_game(PORT)
	net_mgr.game_state = state
	print("host_game result: ", err, " (OK == 0)")

	# See test_client.gd for why this is a 1-element Array, not a plain bool.
	var got_action := [false]
	net_mgr.state_updated.connect(func(_s: GameState) -> void:
		var salt: int = net_mgr.game_state.get_player("Krowh").salt
		print("HOST saw state_updated, Krowh salt=", salt)
		got_action[0] = true
	)

	var frames := 0
	while frames < MAX_WAIT_FRAMES and not got_action[0]:
		await process_frame
		frames += 1

	var final_salt: int = net_mgr.game_state.get_player("Krowh").salt
	var ok: bool = got_action[0] and final_salt == starting_salt + 1
	print("HOST done. got_action=", got_action[0], " final_salt=", final_salt, " frames_waited=", frames)
	quit(0 if ok else 1)
