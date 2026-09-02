extends SceneTree

## One-off visual check for PlayBoard's HUD, since screenshot_scene.gd
## alone can't set up a live GameState first. Run NOT headless:
##   godot --path . --script res://tools/screenshot_play_board.gd --rendering-driver d3d12

func _initialize() -> void:
	await process_frame
	await process_frame

	var card_db: Node = root.get_node("/root/CardDatabase")
	var net: Node = root.get_node("/root/NetworkManager")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var state: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	net.host_game(8957)
	net.assign_faction(1, state.players[0].faction)
	net.action_handler = Callable(net, "default_action_handler")
	net.set_initial_state(state)

	var packed: PackedScene = load("res://scenes/PlayBoard.tscn")
	var board: Node = packed.instantiate()
	root.add_child(board)

	for i: int in range(15):
		await process_frame

	var img: Image = root.get_texture().get_image()
	img.save_png("user://play_board.png")
	print("saved user://play_board.png")
	quit(0)
