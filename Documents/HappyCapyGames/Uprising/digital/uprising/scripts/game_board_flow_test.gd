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

	# --- The game now always starts in Refresh Phase (the real first phase,
	# same as a Lobby-started game) rather than fast-forwarded straight to
	# Actions -- walk through Refresh -> Events -> Build -> Actions via the
	# same submit_advance_phase() a real player's "End Phase" button uses,
	# so this test exercises the real path instead of a shortcut. Accessed
	# via root.get_node() rather than the bare `NetworkManager` identifier --
	# autoload globals only resolve as bare identifiers in Node-derived
	# scripts, not in this SceneTree script (same pattern test_network_
	# manager.gd and friends already use). ---
	var net_mgr := root.get_node("/root/NetworkManager")
	_check("game starts in Refresh Phase", board.state.phase == GameState.Phase.REFRESH)
	net_mgr.submit_advance_phase()
	for i in 5:
		await process_frame
	_check("Refresh -> Events", board.state.phase == GameState.Phase.EVENTS)
	net_mgr.submit_advance_phase()
	for i in 5:
		await process_frame
	_check("Events -> Build", board.state.phase == GameState.Phase.BUILD)

	# --- Build -> Actions is gated on everyone declaring themselves ready
	# (Pass -- draw-2-keep-1 Feats and Building Units are both optional, so
	# this is a voluntary "I'm done" signal, not a hard requirement to have
	# actually drawn/built anything), same shape as the Actions -> Nemesis
	# gate. Confirm the refusal before satisfying it. ---
	net_mgr.submit_advance_phase()
	for i in 5:
		await process_frame
	_check("Build -> Actions refused before anyone is ready", board.state.phase == GameState.Phase.BUILD)

	board._update_hud()
	_check("Pass button reads 'Ready' during Build Phase", board._pass_button.text == "Ready (done building)")
	_check("Pass button enabled before Druwhn has Passed", not board._pass_button.disabled)
	board._on_pass_pressed()  # board.current_faction is "Druwhn"
	for i in 5:
		await process_frame
	_check("Druwhn marked ready via the real Pass button", board.state.get_player("Druwhn").has_passed)
	board._update_hud()
	_check("Pass button disables once Druwhn is ready", board._pass_button.disabled)

	net_mgr.submit_action({"type": "pass", "faction": "Krowh"})
	for i in 5:
		await process_frame
	net_mgr.submit_advance_phase()
	for i in 5:
		await process_frame
	_check("Build -> Actions once everyone's ready", board.state.phase == GameState.Phase.ACTIONS)

	var player = board.state.get_player("Druwhn")
	var home: Vector2i = player.hero_hex
	var target := Vector2i(999999, 999999)  # sentinel "not found"
	# Skip a cursed neighbor -- board generation isn't seeded, so occasionally
	# one lands right next to home, and Explore correctly refuses a cursed
	# hex (rulebook-accurate), which would otherwise cascade-fail every
	# check below that depends on `target` becoming explored/Havened.
	for n in HexMath.neighbors(home):
		var candidate: HexTile = board.state.get_hex(n)
		if candidate != null and not candidate.has_curse:
			target = n
			break
	_check("found an existing, uncursed neighbor of home to move to", target != Vector2i(999999, 999999))
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

	# --- Draw Feats / Choose Feat: still Build Phase from the forcing above.
	# Each action's state broadcast already triggers _update_hud() via
	# call_local RPC, but _update_hand_bar() clears old children with
	# queue_free() (not immediate free -- safe to do from inside a card
	# button's own "pressed" handler), so child-count checks wait a few
	# frames after the action rather than reading counts synchronously. ---
	_check("draw feats button enabled during Build Phase", not board._draw_feats_button.disabled)

	board._on_draw_feats_pressed()
	for i in 5:
		await process_frame
	var druwhn_player: PlayerFactionState = board.state.get_player("Druwhn")
	_check("2 Feats drawn into pending_feat_choice", druwhn_player.pending_feat_choice.size() == 2)
	_check("feat choice row shows 2 clickable cards", board._feat_choice_row.get_child_count() == 2)
	_check("draw feats button disables while a choice is pending", board._draw_feats_button.disabled)

	var picked_feat: String = druwhn_player.pending_feat_choice[0]
	board._on_choose_feat_pressed(picked_feat)
	for i in 5:
		await process_frame
	_check("chosen Feat now in feats_in_play", board.state.get_player("Druwhn").feats_in_play.has(picked_feat))
	_check("feat choice row clears once resolved", board._feat_choice_row.get_child_count() == 0)
	_check("hand row now shows the picked Feat's card", board._hand_row.get_child_count() == 1)

	# --- Pending Combat row: injected directly (Nemesis Phase itself is
	# covered by test_nemesis_ai.gd/test_game_flow.gd already) to check the
	# UI actually surfaces it and the Resolve button clears it. board.state
	# and NetworkManager.game_state are the SAME object here, not separate
	# copies -- _receive_full_state reassigns NetworkManager.game_state
	# then emits state_updated with that exact object, and Object-derived
	# values pass by reference through a signal, so _on_state_updated's
	# `state = new_state` aliases board.state right back onto it. One
	# append is enough; appending "to both" would just add the same
	# GameState's Array twice. ---
	var combat_coord := Vector2i(5, 5)
	board.state.pending_combats.append(combat_coord)
	board._update_hud()
	_check("pending combat row shows 1 Resolve button", board._combats_row.get_child_count() == 2)  # label + 1 button

	board._on_resolve_combat_pressed(combat_coord)
	for i in 5:
		await process_frame
	_check("Resolve clears the pending combat", not board.state.pending_combats.has(combat_coord))
	board._update_hud()
	_check("pending combat row empties once resolved", board._combats_row.get_child_count() == 0)

	# --- Events Phase: Spawn Legion/Spawn Horde buttons (place what a
	# resolved Event's text instructs -- ChapterFlow/NemesisAI's own logic
	# is covered by test_chapter_flow.gd/test_nemesis_ai.gd already, this
	# just checks the UI wiring: enabled only in EVENTS with a real hex
	# selected, and pressing it actually adds to state.legions/hordes). ---
	board.state.phase = GameState.Phase.ACTIONS
	board.selected_coord = target
	board._rebuild_hexes()
	board._update_hud()
	_check("spawn buttons disabled outside Events Phase", board._spawn_legion_button.disabled and board._spawn_horde_button.disabled)

	board.state.phase = GameState.Phase.EVENTS
	board._update_hud()
	_check("spawn buttons enabled in Events Phase with a hex selected", not board._spawn_legion_button.disabled and not board._spawn_horde_button.disabled)

	var legions_before: int = board.state.legions.size()
	board._spawn_threat_spin.value = 6
	board._on_spawn_legion_pressed()
	for i in 5:
		await process_frame
	_check("Spawn Legion adds a Legion to state.legions", board.state.legions.size() == legions_before + 1)
	_check("spawned Legion carries the SpinBox's Threat", board.state.legions[-1].threat == 6)
	_check("spawned Legion sits on the selected hex", board.state.legions[-1].coord == target)

	var hordes_before: int = board.state.hordes.size()
	board._on_spawn_horde_pressed()
	for i in 5:
		await process_frame
	_check("Spawn Horde adds a Horde to state.hordes", board.state.hordes.size() == hordes_before + 1)

	board._update_hud()
	_check("nemesis label lists the newly spawned Legion/Horde", board._nemesis_label.text.find("Threat 6") != -1)

	# --- Pause menu: a real InputEventKey (not a direct method call) to
	# prove the actual "ui_cancel" (Escape) binding triggers it, not just
	# that _toggle_pause_menu() itself works. ---
	_check("pause menu hidden by default", not board._pause_menu_layer.visible)
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	board._unhandled_input(escape_event)
	_check("Escape opens the pause menu", board._pause_menu_layer.visible)

	board._unhandled_input(escape_event)
	_check("pressing Escape again closes it", not board._pause_menu_layer.visible)

	board._unhandled_input(escape_event)
	board._on_resume_pressed()
	_check("Resume button closes it", not board._pause_menu_layer.visible)

	var all_ok := true
	for c in checks:
		if not c[1]:
			all_ok = false

	var img := root.get_texture().get_image()
	img.save_png("res://_board_after_actions.png")
	print("\nScreenshot saved to res://_board_after_actions.png")
	print("ALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
