extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/data/test_model_database.gd`

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	# --- Every Core Hero has a matching extracted standee model ---
	var core_heroes := ["Fhayanor", "Syndra", "Dugpa", "Kha'al", "Baranth", "Yanny", "Hanzo", "Ronja"]
	var all_found := true
	for h in core_heroes:
		var path := ModelDatabase.find_model_path(h)
		if path == "" or not ResourceLoader.exists(path):
			all_found = false
			print("MISSING model for Hero '%s'" % h)
	_check("every Core Hero resolves to a real, loadable model path", all_found)

	_check(
		"exact path for Fhayanor",
		ModelDatabase.find_model_path("Fhayanor") == "res://assets/models/Druwhn/fhayanor/Fhayanor.obj"
	)

	# --- Apostrophes/casing in CardDatabase names don't survive into folder
	# names ("Kha'al" -> "khaal") -- normalization must bridge that. ---
	_check(
		"apostrophe in \"Kha'al\" is normalized away to match the \"khaal\" folder",
		ModelDatabase.find_model_path("Kha'al") != ""
	)
	_check(
		"lookup is case-insensitive",
		ModelDatabase.find_model_path("FHAYANOR") == ModelDatabase.find_model_path("Fhayanor")
	)

	# --- An entity with no extracted model returns "", not an error ---
	_check("unknown entity returns an empty path", ModelDatabase.find_model_path("Not A Real Hero") == "")

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
