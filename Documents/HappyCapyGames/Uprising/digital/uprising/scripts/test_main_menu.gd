extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/test_main_menu.gd`
## Covers the Settings autoload's persistence and the main menu's panel
## navigation. Restores whatever Settings values it changes so a real run
## afterward doesn't inherit test values in user://settings.cfg.

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	await process_frame
	# Autoload bare names only resolve inside a normal scene node's own
	# lifecycle -- see the same gotcha noted in every other test here.
	var settings := root.get_node("/root/Settings")

	var original_fullscreen: bool = settings.fullscreen
	var original_volume: float = settings.master_volume

	# --- Settings persistence: save, then reload from disk to prove it
	# actually wrote (not just held the value in memory) ---
	settings.set_fullscreen(true)
	settings.set_master_volume(0.42)
	settings.load_settings()
	_check("fullscreen persisted through save/load", settings.fullscreen == true)
	_check("master_volume persisted through save/load", is_equal_approx(settings.master_volume, 0.42))

	settings.set_fullscreen(original_fullscreen)
	settings.set_master_volume(original_volume)

	# --- Main menu panel navigation ---
	var scene: PackedScene = load("res://scenes/main_menu.tscn")
	var menu := scene.instantiate()
	root.add_child(menu)
	await process_frame

	_check("menu panel visible by default", menu._menu_panel.visible)
	_check("settings panel hidden by default", not menu._settings_panel.visible)

	menu._show_settings()
	_check("settings panel visible after Settings pressed", menu._settings_panel.visible)
	_check("menu panel hidden while in Settings", not menu._menu_panel.visible)

	_check("fullscreen checkbox reflects the current Settings value", menu._fullscreen_check.button_pressed == original_fullscreen)
	_check("volume slider reflects the current Settings value", is_equal_approx(menu._volume_slider.value, original_volume))

	menu._on_fullscreen_toggled(not original_fullscreen)
	_check("fullscreen checkbox drives the Settings autoload", settings.fullscreen == (not original_fullscreen))
	settings.set_fullscreen(original_fullscreen)

	menu._on_volume_changed(0.75)
	_check("volume slider drives the Settings autoload", is_equal_approx(settings.master_volume, 0.75))
	settings.set_master_volume(original_volume)

	menu._show_menu()
	_check("Back returns to the menu panel", menu._menu_panel.visible and not menu._settings_panel.visible)

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
