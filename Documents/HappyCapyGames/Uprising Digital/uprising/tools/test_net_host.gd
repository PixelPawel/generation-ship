extends SceneTree

## Milestone 2 networking verification, HOST side. Run as a real separate
## OS process alongside tools/test_net_client.gd (both --headless is fine
## here, unlike the visual screenshot tests - this is pure network/logic,
## no rendering needed):
##   godot --headless --script res://tools/test_net_host.gd --path .
## Since this and the client run as two independent processes, results are
## handed off via files under user:// (shared on disk for the same
## project on this machine, unlike in-memory state).

const PORT := 8955
const RESULT_PATH := "user://net_test_host_result.txt"
const TIMEOUT_FRAMES := 600  # ~10s at 60fps

var frames_waited := 0
var target_faction := ""
var expected_vp := 0


func _initialize() -> void:
	await process_frame
	await process_frame

	var card_db: Node = root.get_node("/root/CardDatabase")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var state: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	target_faction = state.players[0].faction
	expected_vp = state.players[0].vp + 3

	var net: Node = root.get_node("/root/NetworkManager")
	net.action_handler = Callable(self, "_handle_action")

	var err: Error = net.host_game(PORT)
	if err != OK:
		_write_result("FAIL: host_game error %d" % err)
		quit(1)
		return

	net.set_initial_state(state)
	print("HOST: listening on port %d, waiting for client action (target_faction=%s expected_vp=%d)..." % [PORT, target_faction, expected_vp])

	while frames_waited < TIMEOUT_FRAMES:
		await process_frame
		frames_waited += 1
		var p: PlayerFactionState = _find_player(net.current_state, target_faction)
		if p != null and p.vp == expected_vp:
			print("HOST: observed expected vp=%d on faction %s after %d frames" % [p.vp, target_faction, frames_waited])
			_write_result("PASS")
			quit(0)
			return

	_write_result("FAIL: timed out waiting for client action to land")
	quit(1)


func _handle_action(state: GameState, action: Dictionary, _sender_id: int) -> Dictionary:
	if action.get("type", "") != "test_add_vp":
		return {"ok": false, "reason": "unknown action type"}
	var p: PlayerFactionState = _find_player(state, str(action.get("faction", "")))
	if p == null:
		return {"ok": false, "reason": "faction not found"}
	p.vp += int(action.get("amount", 0))
	return {"ok": true}


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
	print("HOST RESULT: %s" % text)
