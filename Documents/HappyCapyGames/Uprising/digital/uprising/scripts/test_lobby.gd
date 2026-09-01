extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/test_lobby.gd`
## Drives the Lobby scene's Host/Join button logic directly and checks what
## it writes into the LobbyConfig autoload -- not a render check (see
## tools/screenshot_scene.gd for that), just "does pressing the buttons
## produce the config game_board.gd expects."

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	await process_frame
	# Autoload bare names only resolve inside a normal scene node's own
	# lifecycle -- a SceneTree script's _initialize() needs the explicit
	# node-path lookup instead (same gotcha noted in every other test here).
	var lobby_config := root.get_node("/root/LobbyConfig")
	var network_manager := root.get_node("/root/NetworkManager")

	var scene: PackedScene = load("res://scenes/lobby.tscn")
	var lobby := scene.instantiate()
	root.add_child(lobby)
	await process_frame

	_check("Lobby defaults to Host mode", lobby._host_panel.visible and not lobby._join_panel.visible)
	lobby._set_mode(false)
	_check("switching to Join mode hides Host panel and shows Join panel", not lobby._host_panel.visible and lobby._join_panel.visible)
	lobby._set_mode(true)

	# --- Start Hosting with the defaults (Druwhn + Krowh pre-checked) ---
	lobby._on_start_hosting_pressed()
	_check("LobbyConfig marked configured after Start Hosting", lobby_config.configured)
	_check("LobbyConfig.is_host true after Start Hosting", lobby_config.is_host)
	_check("2 faction/hero pairs chosen (Druwhn + Krowh pre-checked)", (lobby_config.faction_hero_pairs as Array).size() == 2)

	var factions_chosen: Array = []
	for pair in lobby_config.faction_hero_pairs:
		factions_chosen.append(pair[0])
	_check("chosen factions are Druwhn and Krowh", factions_chosen.has("Druwhn") and factions_chosen.has("Krowh"))

	var hero_names: Array = []
	for pair in lobby_config.faction_hero_pairs:
		hero_names.append(pair[1])
	_check("chosen Heroes are non-empty real names", hero_names.all(func(h: String) -> bool: return h != ""))

	_check("difficulty defaults to Veteran", lobby_config.difficulty == "Veteran")
	_check("chapters defaults to 3", lobby_config.max_chapters == 3)
	_check("port defaults to NetworkManager.DEFAULT_PORT", lobby_config.port == network_manager.DEFAULT_PORT)

	# --- Unchecking every faction should refuse to start (no players) ---
	lobby_config.configured = false
	for faction in lobby._faction_checks:
		(lobby._faction_checks[faction] as CheckBox).button_pressed = false
	lobby._on_start_hosting_pressed()
	_check("Start Hosting with no factions checked leaves LobbyConfig unconfigured", not lobby_config.configured)

	# --- A custom port should be picked up ---
	for faction in lobby._faction_checks:
		if faction == "Druwhn":
			(lobby._faction_checks[faction] as CheckBox).button_pressed = true
	lobby._host_port_edit.text = "12345"
	lobby._on_start_hosting_pressed()
	_check("custom host port captured", lobby_config.port == 12345)

	# --- Join mode ---
	lobby._join_address_edit.text = "192.168.1.50"
	lobby._join_port_edit.text = "9999"
	lobby._on_join_pressed()
	_check("LobbyConfig.is_host false after Join", not lobby_config.is_host)
	_check("join address captured", lobby_config.join_address == "192.168.1.50")
	_check("join port captured", lobby_config.join_port == 9999)

	# --- A non-numeric port falls back to the default instead of erroring ---
	lobby._join_port_edit.text = "not a number"
	lobby._on_join_pressed()
	_check("non-numeric join port falls back to the default", lobby_config.join_port == network_manager.DEFAULT_PORT)

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
