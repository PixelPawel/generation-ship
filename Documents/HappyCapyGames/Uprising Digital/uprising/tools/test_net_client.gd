extends SceneTree

## Milestone 2 networking verification, CLIENT side - see test_net_host.gd
## for the full picture. Start the host FIRST, then this:
##   godot --headless --script res://tools/test_net_client.gd --path .

const PORT := 8955
const RESULT_PATH := "user://net_test_client_result.txt"
const CONNECT_TIMEOUT_FRAMES := 300
const STATE_TIMEOUT_FRAMES := 600

var got_initial_state := false


func _initialize() -> void:
	await process_frame
	await process_frame

	var net: Node = root.get_node("/root/NetworkManager")
	var err: Error = net.join_game("127.0.0.1", PORT)
	if err != OK:
		_write_result("FAIL: join_game error %d" % err)
		quit(1)
		return

	print("CLIENT: connecting to 127.0.0.1:%d ..." % PORT)

	var frames := 0
	while net.current_state == null and frames < CONNECT_TIMEOUT_FRAMES:
		await process_frame
		frames += 1

	if net.current_state == null:
		_write_result("FAIL: never received initial state (connection likely failed)")
		quit(1)
		return

	var initial: GameState = net.current_state
	print("CLIENT: received initial state - %d players, %d hexes, phase=%d" % [initial.players.size(), initial.hexes.size(), initial.phase])
	if initial.players.size() != 2:
		_write_result("FAIL: expected 2 players in synced state, got %d" % initial.players.size())
		quit(1)
		return
	# 15 "placed" hexes (capital + 2 home + 2 sea tower + 10 interior) + 3
	# curse/skeleton-only "outer" hexes outside that set (see game_setup.gd).
	if initial.hexes.size() != 18:
		_write_result("FAIL: expected 18 hexes in synced state, got %d" % initial.hexes.size())
		quit(1)
		return

	var target_faction: String = initial.players[0].faction
	var expected_vp: int = initial.players[0].vp + 3
	print("CLIENT: submitting test_add_vp action for faction=%s" % target_faction)
	net.submit_action({"type": "test_add_vp", "faction": target_faction, "amount": 3})

	frames = 0
	while frames < STATE_TIMEOUT_FRAMES:
		await process_frame
		frames += 1
		var p: PlayerFactionState = _find_player(net.current_state, target_faction)
		if p != null and p.vp == expected_vp:
			print("CLIENT: round trip confirmed - vp=%d after %d frames" % [p.vp, frames])
			_write_result("PASS")
			quit(0)
			return

	_write_result("FAIL: never observed the rebroadcast state with updated vp")
	quit(1)


func _find_player(state: GameState, faction: String) -> PlayerFactionState:
	if state == null:
		return null
	for p: PlayerFactionState in state.players:
		if p.faction == faction:
			return p
	return null


func _write_result(text: String) -> void:
	var f: FileAccess = FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	print("CLIENT RESULT: %s" % text)
