extends SceneTree
## Dev helper: instantiates a scene, lets it render for a few frames, and
## saves a screenshot -- for visual sanity-checking a change without opening
## the editor or a full play session.
##
## Must run WITHOUT --headless (headless mode uses a null renderer, so the
## capture would just be blank):
##   godot --path . --script res://tools/screenshot_scene.gd
##   godot --path . --script res://tools/screenshot_scene.gd -- --scene=res://scenes/game_board.tscn --out=res://_board.png --frames=15
##
## Defaults to scenes/main.tscn if --scene isn't passed.

const DEFAULT_SCENE_PATH := "res://scenes/main.tscn"
const DEFAULT_OUTPUT_PATH := "res://_screenshot.png"
const DEFAULT_WARMUP_FRAMES := 5


func _initialize() -> void:
	var args := _parse_user_args()
	var scene_path: String = args.get("scene", DEFAULT_SCENE_PATH)
	var output_path: String = args.get("out", DEFAULT_OUTPUT_PATH)
	var warmup_frames: int = int(args.get("frames", DEFAULT_WARMUP_FRAMES))

	var scene: PackedScene = load(scene_path)
	var instance := scene.instantiate()
	root.add_child(instance)
	for i in warmup_frames:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(output_path)
	print("Screenshot saved to %s (scene=%s, frames=%d)" % [output_path, scene_path, warmup_frames])
	quit()


## Parses "--key=value" pairs from the args after "--" on the command line.
func _parse_user_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.substr(2).split("=", true, 1)
			result[kv[0]] = kv[1]
	return result
