extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/net/test_network_manager.gd`
## Exercises NetworkManager's phase_advanced broadcast and pending-combat
## resolution directly as the host (is_host lets submit_advance_phase/
## submit_resolve_combat skip the RPC layer and hit the _apply_* handlers
## synchronously -- same pattern as test_lobby.gd).

const TEST_PORT := 8938

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	await process_frame
	var net_mgr := root.get_node("/root/NetworkManager")
	var card_db := root.get_node("/root/CardDatabase")

	net_mgr.host_game(TEST_PORT)
	var pairs := [["Druwhn", "Fhayanor"], ["Krowh", "Kha'al"]]
	net_mgr.game_state = GameSetup.build_new_game(card_db, pairs, "Veteran", 3)

	# --- phase_advanced broadcasts the advance_phase() result ---
	# 1-element Array: a lambda captures locals BY VALUE, so a plain `var
	# received := 0` mutated inside wouldn't be visible out here.
	var received: Array = []
	net_mgr.phase_advanced.connect(func(info: Dictionary) -> void: received.append(info))
	net_mgr.submit_advance_phase()
	for i in 5:
		await process_frame
	_check("phase_advanced fired", received.size() == 1)
	_check("phase_advanced carries the Event that was drawn", received.size() == 1 and received[0].get("event", "") != "")

	# --- resolve_combat clears a pending fight ---
	var coord := Vector2i(3, -1)
	net_mgr.game_state.pending_combats.append(coord)
	net_mgr.submit_resolve_combat(coord)
	for i in 5:
		await process_frame
	_check("resolve_combat clears the pending fight", not net_mgr.game_state.pending_combats.has(coord))

	# --- resolving a hex with no pending combat is rejected, not silently ignored ---
	var rejected := [false]
	net_mgr.action_rejected.connect(func(_reason: String) -> void: rejected[0] = true)
	net_mgr.submit_resolve_combat(Vector2i(99, 99))
	for i in 5:
		await process_frame
	_check("resolving a non-pending hex is rejected", rejected[0])

	# --- spawn_legion/spawn_horde -- what a resolved Event's placement text
	# instructs the player to do by hand, submitted through the same
	# is_host-shortcut RPC path as resolve_combat/advance_phase. ---
	var legions_before: int = net_mgr.game_state.legions.size()
	net_mgr.submit_spawn_legion(6, GameState.CAPITAL_COORD)
	for i in 5:
		await process_frame
	_check("submit_spawn_legion adds a Legion to game_state", net_mgr.game_state.legions.size() == legions_before + 1)
	_check("spawned Legion has the requested Threat", net_mgr.game_state.legions[-1].threat == 6)

	var hordes_before: int = net_mgr.game_state.hordes.size()
	net_mgr.submit_spawn_horde(4, GameState.CAPITAL_COORD)
	for i in 5:
		await process_frame
	_check("submit_spawn_horde adds a Horde to game_state", net_mgr.game_state.hordes.size() == hordes_before + 1)

	rejected[0] = false
	net_mgr.submit_spawn_legion(6, Vector2i(999, 999))
	for i in 5:
		await process_frame
	_check("spawning onto a nonexistent hex is rejected", rejected[0])

	net_mgr.disconnect_game()

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
