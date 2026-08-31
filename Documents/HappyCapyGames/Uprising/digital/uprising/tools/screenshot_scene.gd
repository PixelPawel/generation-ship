extends SceneTree
## Dev helper: instantiates a scene, lets it render for a few frames, and
## saves a screenshot -- for visual sanity-checking a change without opening
## the editor or a full play session.
##
## Must run WITHOUT --headless (headless mode uses a null renderer, so the
## capture would just be blank):
##   godot --path . --script res://tools/screenshot_scene.gd
##
## Defaults to scenes/main.tscn; edit SCENE_PATH to point at another scene.

const SCENE_PATH := "res://scenes/main.tscn"
const OUTPUT_PATH := "res://_screenshot.png"
const WARMUP_FRAMES := 5


func _initialize() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	var instance := scene.instantiate()
	root.add_child(instance)
	for i in WARMUP_FRAMES:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(OUTPUT_PATH)
	print("Screenshot saved to %s" % OUTPUT_PATH)
	quit()
