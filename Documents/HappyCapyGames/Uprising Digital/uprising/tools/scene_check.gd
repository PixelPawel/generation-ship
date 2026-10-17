extends SceneTree
# Loads scenes and instantiates them without adding them to the tree (no
# _ready, no game run) - catches .tscn parse/resource errors.
#   godot --headless --path . --script res://tools/scene_check.gd -- res://scenes/a.tscn
func _initialize() -> void:
	for p: String in OS.get_cmdline_user_args():
		var ps: PackedScene = load(p) as PackedScene
		var node: Node = ps.instantiate() if ps != null else null
		print("SCENE ", p, " -> ", "ok" if node != null else "FAILED")
		if node != null:
			node.free()
	quit()
