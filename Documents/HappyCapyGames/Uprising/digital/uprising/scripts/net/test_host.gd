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

	var state := GameState.new()
	state.chapter = 1
	var hex := HexTile.new()
	hex.coord = Vector2i(0, 0)
	hex.card_name = "Test Hex"
	state.set_hex(hex)

	var err: Error = net_mgr.host_game(state, PORT)
	print("host_game result: ", err, " (OK == 0)")

	# See test_client.gd for why this is a 1-element Array, not a plain bool.
	var got_action := [false]
	net_mgr.state_updated.connect(func(_s: GameState) -> void:
		print("HOST saw state_updated, chapter=", net_mgr.game_state.chapter)
		got_action[0] = true
	)

	var frames := 0
	while frames < MAX_WAIT_FRAMES and not got_action[0]:
		await process_frame
		frames += 1

	print("HOST done. got_action=", got_action[0], " frames_waited=", frames)
	print("HOST final chapter: ", net_mgr.game_state.chapter)
	quit(0 if got_action[0] else 1)
