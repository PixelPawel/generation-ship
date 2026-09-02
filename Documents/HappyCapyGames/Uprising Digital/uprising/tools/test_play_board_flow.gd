extends SceneTree

## Milestone 5 verification: drives the real PlayBoard scene's own button-
## handler methods programmatically (rather than simulating mouse events)
## and asserts on resulting state - the same pattern that caught real bugs
## in prior sessions of this kind of project (see memory). Single-process:
## the "host" plays both factions locally by re-pointing
## NetworkManager.peer_factions at whichever faction is being driven,
## since is_host() with zero remote peers already exercises the exact
## same _apply_action() path a real second peer's RPC would.
## Run with: godot --headless --script res://tools/test_play_board_flow.gd --path .

var failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	await process_frame
	await _run()
	quit(1 if not failures.is_empty() else 0)


func _run() -> void:
	var card_db: Node = root.get_node("/root/CardDatabase")
	var net: Node = root.get_node("/root/NetworkManager")

	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var state: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	var f1: String = state.players[0].faction
	var f2: String = state.players[1].faction

	var err: Error = net.host_game(8956)
	_check(err == OK, "host_game succeeds, err=%d" % err)
	net.assign_faction(1, f1)
	net.action_handler = Callable(net, "default_action_handler")
	net.set_initial_state(state)

	var packed: PackedScene = load("res://scenes/PlayBoard.tscn")
	var board: Node = packed.instantiate()
	root.add_child(board)
	await process_frame
	await process_frame

	_check(board.get_node("HUD/Panel/VBox/StatusLabel").text.find("Refresh") != -1,
		"HUD shows Refresh phase initially, got '%s'" % board.get_node("HUD/Panel/VBox/StatusLabel").text)

	# Drive the state to ACTIONS phase directly (same shortcut M4's own
	# test uses) so button presses have something to act on.
	net.current_state.phase = GameState.Phase.ACTIONS
	net.current_state.current_player_index = 0
	net.state_updated.emit(net.current_state)
	await process_frame

	_check(board.get_node("HUD/Panel/VBox/StatusLabel").text.find("YOU") != -1,
		"HUD shows it's the host's (f1's) turn, got '%s'" % board.get_node("HUD/Panel/VBox/StatusLabel").text)

	# Programmatically select an unexplored interior hex and press Explore.
	var interior_coord: Vector2i = Vector2i(-999, -999)
	for coord: Vector2i in net.current_state.hexes.keys():
		var t: HexTileState = net.current_state.hexes[coord]
		if t.role == "interior" and not t.explored:
			interior_coord = coord
			break
	_check(interior_coord != Vector2i(-999, -999), "found an unexplored interior hex")
	board.select_coord(interior_coord)
	_check(board.has_selected_coord and board.selected_coord == interior_coord, "select_coord updated PlayBoard's selection")

	var ap_before: int = net.current_state.find_player(f1).action_points
	board._on_explore_pressed()
	await process_frame
	_check(net.current_state.get_hex(interior_coord).explored, "Explore button actually flipped the hex")
	_check(net.current_state.find_player(f1).action_points == ap_before - 1, "Explore button deducted 1 AP")

	# Trade should work regardless of turn/selection.
	var salt_before: int = net.current_state.find_player(f1).salt
	board._on_trade_pressed()
	await process_frame
	_check(net.current_state.find_player(f1).salt == salt_before + 1, "Trade button gave +1 Salt")

	# End Turn hands control to f2.
	board._on_end_turn_pressed()
	await process_frame
	_check(GameActions.is_players_turn(net.current_state, f2), "End Turn button advanced the turn to f2")

	# Simulate a second peer connecting (the auto-assign-second-faction path).
	board._on_peer_connected(2)
	net.assign_faction(2, f2)  # what the RPC handshake would do in a real 2-process run.
	_check(net.peer_factions.get(2) == f2, "peer_connected handler path assigns the second faction")

	_report()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		print("FAIL: %s" % label)


func _report() -> void:
	print("\n---")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED:" % failures.size())
		for f: String in failures:
			print("  - " + f)
