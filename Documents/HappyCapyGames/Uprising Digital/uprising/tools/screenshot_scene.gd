extends SceneTree

## Visual verification helper. Must run WITHOUT --headless (a null renderer
## produces a blank image) but doesn't need the full editor either:
##   godot --path . --script res://tools/screenshot_scene.gd --rendering-driver d3d12 -- --scene=res://scenes/GameBoard.tscn --out=user://board.png --frames=10
## Args after "--" are read via OS.get_cmdline_user_args().

func _initialize() -> void:
	await process_frame
	await process_frame

	var scene_path := "res://scenes/GameBoard.tscn"
	var out_path := "user://screenshot.png"
	var frames := 10

	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.substr(8)
		elif arg.begins_with("--out="):
			out_path = arg.substr(6)
		elif arg.begins_with("--frames="):
			frames = arg.substr(9).to_int()

	var packed: PackedScene = load(scene_path)
	if packed == null:
		printerr("screenshot_scene: could not load %s" % scene_path)
		quit(1)
		return

	var instance: Node = packed.instantiate()
	root.add_child(instance)

	for i: int in range(frames):
		await process_frame

	var img: Image = root.get_texture().get_image()
	var err: Error = img.save_png(out_path)
	if err != OK:
		printerr("screenshot_scene: save_png failed with error %d" % err)
		quit(1)
		return

	print("screenshot_scene: saved %s (%dx%d)" % [out_path, img.get_width(), img.get_height()])
	quit(0)
