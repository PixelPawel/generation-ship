extends SceneTree
# Compiles scripts with the autoloads registered (plain --check-only stops at the
# first autoload name, hiding every later error). Does not run the game:
#   godot --headless --path . --script res://tools/compile_check.gd -- res://a.gd res://b.gd
func _initialize() -> void:
	var paths: PackedStringArray = OS.get_cmdline_user_args()
	for p: String in paths:
		var s: Resource = load(p)
		print("CHECK ", p, " -> ", "ok" if s != null and (s as GDScript).can_instantiate() else "FAILED")
	quit()
