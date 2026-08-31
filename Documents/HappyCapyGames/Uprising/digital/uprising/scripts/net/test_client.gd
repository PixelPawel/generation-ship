extends SceneTree
## Headless networking smoke test (client side). See test_host.gd for usage.

const PORT := 8910
const MAX_WAIT_FRAMES := 3600  # ~60s at 60fps


func _initialize() -> void:
	await process_frame
	var net_mgr := root.get_node("/root/NetworkManager")

	var err: Error = net_mgr.join_game("127.0.0.1", PORT)
	print("join_game result: ", err, " (OK == 0)")

	# GDScript lambdas capture local primitives BY VALUE, not by reference, so
	# a plain `var update_count := 0` mutated inside the closure would never
	# be visible to the outer loop. Use a 1-element Array as a mutable cell.
	var update_count := [0]
	var submitted := false
	net_mgr.state_updated.connect(func(s: GameState) -> void:
		update_count[0] += 1
		print("CLIENT saw state_updated #%d, chapter=%d, hexes=%d" % [update_count[0], s.chapter, s.hexes.size()])
	)
	net_mgr.connection_failed.connect(func() -> void:
		print("CLIENT connection FAILED")
	)

	var frames := 0
	while frames < MAX_WAIT_FRAMES:
		if update_count[0] >= 1 and not submitted:
			print("CLIENT submitting test action...")
			net_mgr.submit_action({"type": "test_ping", "value": 42})
			submitted = true
		if update_count[0] >= 2:
			break
		await process_frame
		frames += 1

	var ok: bool = update_count[0] >= 2
	print("CLIENT done. update_count=", update_count[0], " frames_waited=", frames)
	quit(0 if ok else 1)
