extends SceneTree
## Temporary dev helper: drives GameBoard's interaction loop programmatically
## (select a hex, press the action buttons) to prove select -> enable ->
## act -> refresh actually works, without simulating real mouse events.
## Must run WITHOUT --headless (needs a real renderer for the screenshot).

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])
	print(("OK   " if ok else "FAIL "), label)


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/game_board.tscn")
	var board := scene.instantiate()
	root.add_child(board)
	for i in 5:
		await process_frame

	var player = board.state.get_player("Druwhn")
	var home: Vector2i = player.hero_hex
	var target := Vector2i(999999, 999999)  # sentinel "not found"
	for n in HexMath.neighbors(home):
		if board.state.get_hex(n) != null:
			target = n
			break
	_check("found an existing neighbor of home to move to", target != Vector2i(999999, 999999))
	var target_tile_before = board.state.get_hex(target)
	_check("target hex starts unexplored", target_tile_before != null and not target_tile_before.explored)

	# --- Select the neighbor hex, confirm Move becomes available ---
	board.selected_coord = target
	board._rebuild_hexes()
	board._update_hud()
	_check("move button enabled once a valid neighbor is selected", not board._move_button.disabled)

	# --- Move there ---
	board._on_move_pressed()
	for i in 5:
		await process_frame
	_check("hero actually moved to target", board.state.get_player("Druwhn").hero_hex == target)

	# --- Reselect the (now current) hex, Explore should become available ---
	board.selected_coord = board.state.get_player("Druwhn").hero_hex
	board._rebuild_hexes()
	board._update_hud()
	_check("explore button enabled on the hero's own unexplored hex", not board._explore_button.disabled)

	board._on_explore_pressed()
	for i in 5:
		await process_frame
	var tile = board.state.get_hex(target)
	_check("target hex is explored after pressing Explore", tile != null and tile.explored)

	# --- Trade for good measure ---
	var salt_before: int = board.state.get_player("Druwhn").salt
	board._on_trade_pressed()
	for i in 5:
		await process_frame
	_check("salt increased by 1 after Trade", board.state.get_player("Druwhn").salt == salt_before + 1)

	# --- Haven on the (now explored) hex the Hero is standing on ---
	board._update_hud()
	_check("haven button enabled on an explored, unclaimed, no-X hex", not board._haven_button.disabled)
	var plunder_before: int = board.state.get_player("Druwhn").plunder
	board._on_haven_pressed()
	for i in 5:
		await process_frame
	var haven_tile = board.state.get_hex(target)
	_check("target hex now has a Druwhn Haven", haven_tile != null and haven_tile.haven_faction == "Druwhn")
	_check("plunder decreased by 2 after Haven", board.state.get_player("Druwhn").plunder == plunder_before - 2)
	board._update_hud()
	_check("haven button disables again once the hex already has one", board._haven_button.disabled)

	# --- Command: select the now-empty home hex, gather back into it ---
	board.selected_coord = home
	board._rebuild_hexes()
	board._update_hud()
	_check("command button enabled on an explored, unclaimed-by-others hex", not board._command_button.disabled)
	var food_before: int = board.state.get_player("Druwhn").food
	board._on_command_pressed()
	for i in 5:
		await process_frame
	_check("hero moved to the Commanded hex", board.state.get_player("Druwhn").hero_hex == home)
	_check("food decreased by 1 after Command", board.state.get_player("Druwhn").food == food_before - 1)

	# --- Pass: Druwhn is done for this Actions Phase ---
	board._update_hud()
	_check("pass button enabled during Actions Phase", not board._pass_button.disabled)
	board._on_pass_pressed()
	for i in 5:
		await process_frame
	_check("has_passed set after pressing Pass", board.state.get_player("Druwhn").has_passed)
	board._update_hud()
	_check("pass button disables once already passed", board._pass_button.disabled)

	# --- End Phase: Krowh hasn't passed/run out of AP yet, so this must be
	# refused rather than silently skipping Krowh's turn. ---
	board._on_end_phase_pressed()
	for i in 5:
		await process_frame
	_check("End Phase refused while Krowh is still active", board.state.phase == GameState.Phase.ACTIONS)

	# --- Build Unit/Tower/Wall: force Build Phase to exercise the controls
	# directly (a full Chapter loop to actually reach Build is covered by
	# test_game_flow.gd's backend-level test, not needed again here -- this
	# is only checking the UI wiring). `target` already has a Druwhn Haven
	# from the earlier Haven action above. ---
	board.state.phase = GameState.Phase.BUILD
	board.selected_coord = target
	board._rebuild_hexes()
	board._update_hud()
	_check("build unit option lists Druwhn's Units", board._build_unit_option.item_count > 0)
	_check("build unit button enabled on your own Haven during Build Phase", not board._build_unit_button.disabled)

	var units_before: int = (board.state.get_hex(target).units.get("Druwhn", []) as Array).size()
	board._on_build_unit_pressed()
	for i in 5:
		await process_frame
	_check("a Unit was added to the hex", (board.state.get_hex(target).units.get("Druwhn", []) as Array).size() == units_before + 1)

	board._update_hud()
	_check("build tower button enabled on your own Haven", not board._build_tower_button.disabled)
	board._on_build_tower_pressed()
	for i in 5:
		await process_frame
	_check("hex now has a Tower", board.state.get_hex(target).has_tower)

	board._update_hud()
	_check("build wall button enabled on your own Haven", not board._build_wall_button.disabled)
	board._on_build_wall_pressed()
	for i in 5:
		await process_frame
	_check("hex now has a Wall", board.state.get_hex(target).has_wall)

	var all_ok := true
	for c in checks:
		if not c[1]:
			all_ok = false

	var img := root.get_texture().get_image()
	img.save_png("res://_board_after_actions.png")
	print("\nScreenshot saved to res://_board_after_actions.png")
	print("ALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
