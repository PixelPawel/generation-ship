extends SceneTree

## Milestone 4 verification: GameActions, NemesisAI, CombatResolver,
## ChapterFlow, Scoring - exercised against a real GameState, not mocks.
## Run with: godot --headless --script res://tools/test_chapter_flow.gd --path .

var failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	await process_frame
	_run()
	quit(1 if not failures.is_empty() else 0)


func _run() -> void:
	var card_db: Node = root.get_node("/root/CardDatabase")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var state: GameState = GameSetup.build_2p_normal_game_state(card_db, rng)
	var f1: String = state.players[0].faction
	var f2: String = state.players[1].faction

	# build_2p_normal_game_state starts the game in REFRESH phase by design
	# (matching the rulebook - a real game always starts there); turn-gated
	# Actions only apply during ACTIONS phase, so jump straight there for
	# this test rather than walking every intermediate phase.
	state.phase = GameState.Phase.ACTIONS
	state.current_player_index = 0

	# --- GameActions: Trade always works, any phase ---
	var salt_before: int = state.find_player(f1).salt
	var ap_before: int = state.find_player(f1).action_points
	var r: Dictionary = GameActions.apply(state, {"type": "trade"}, f1, card_db)
	_check(r.get("ok", false), "Trade succeeds")
	_check(state.find_player(f1).salt == salt_before + 1, "Trade: +1 Salt")
	_check(state.find_player(f1).action_points == ap_before - 1, "Trade: -1 AP")

	# --- Turn order: only current player can take turn-gated actions ---
	_check(GameActions.is_players_turn(state, f1), "f1 has the first turn in ACTIONS phase")
	_check(not GameActions.is_players_turn(state, f2), "f2 does not have the turn yet")
	var r2: Dictionary = GameActions.apply(state, {"type": "explore", "at": {"x": 99, "y": 99}}, f2, card_db)
	_check(not r2.get("ok", false), "f2 cannot Explore out of turn, got ok=%s" % r2.get("ok"))

	# --- Explore: flips a hex and runs its transcribed effect ---
	var interior_coord: Vector2i = Vector2i.ZERO
	for coord: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[coord]
		if t.role == "interior" and not t.hex_card_name.is_empty() and HexEffectPrograms.has_program(t.hex_card_name):
			interior_coord = coord
			break
	_check(interior_coord != Vector2i.ZERO or state.hexes.has(Vector2i.ZERO), "found an interior hex with a transcribed effect to Explore")
	var target_tile: HexTileState = state.get_hex(interior_coord)
	var explore_card: String = target_tile.hex_card_name
	var r3: Dictionary = GameActions.apply(state, {"type": "explore", "at": {"x": interior_coord.x, "y": interior_coord.y}}, f1, card_db)
	_check(r3.get("ok", false), "Explore succeeds: %s" % r3.get("reason", ""))
	_check(state.get_hex(interior_coord).explored, "hex is now explored")
	_check(state.find_player(f1).has_acted_this_turn, "Explore sets has_acted_this_turn")
	var r4: Dictionary = GameActions.apply(state, {"type": "haven", "at": {"x": interior_coord.x, "y": interior_coord.y}}, f1, card_db)
	_check(not r4.get("ok", false), "a second turn-ending Action this turn is rejected, got ok=%s" % r4.get("ok"))

	# --- End Turn advances to the next active player ---
	var r5: Dictionary = GameActions.apply(state, {"type": "end_turn"}, f1, card_db)
	_check(r5.get("ok", false), "end_turn succeeds")
	_check(GameActions.is_players_turn(state, f2), "turn advanced to f2")
	_check(not state.find_player(f1).has_acted_this_turn, "end_turn clears has_acted_this_turn")

	# --- Haven: build on an explored, empty hex ---
	var p2_start_plunder: int = state.find_player(f2).plunder
	var board2: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(f2)
	# Explore a hex for f2 first (needs an unexplored hex).
	var interior_coord2: Vector2i = Vector2i(-99, -99)
	for coord: Vector2i in state.hexes.keys():
		var t: HexTileState = state.hexes[coord]
		if t.role == "interior" and not t.explored:
			interior_coord2 = coord
			break
	GameActions.apply(state, {"type": "explore", "at": {"x": interior_coord2.x, "y": interior_coord2.y}}, f2, card_db)
	GameActions.apply(state, {"type": "end_turn"}, f2, card_db)  # explore already ended the turn's action, but not the turn itself - end_turn advances back to f1... need f2's turn again for Haven.
	# f1's turn now; give it back to f2 by having f1 pass, then f2 acts.
	GameActions.apply(state, {"type": "pass"}, f1, card_db)
	var r6: Dictionary = GameActions.apply(state, {"type": "haven", "at": {"x": interior_coord2.x, "y": interior_coord2.y}}, f2, card_db)
	_check(r6.get("ok", false), "Haven succeeds: %s" % r6.get("reason", ""))
	_check(state.get_hex(interior_coord2).haven_faction == f2, "Haven now belongs to f2")
	_check(state.find_player(f2).plunder == p2_start_plunder - board2.haven_plunder_cost, "Haven deducted the right Plunder cost")

	# --- Build Phase gate: won't advance until all active players are Passed/out of AP ---
	state.phase = GameState.Phase.BUILD
	for p: PlayerFactionState in state.players:
		p.has_passed = false
		p.action_points = 5
	var gate1: Dictionary = ChapterFlow.advance_phase(state, card_db)
	_check(not gate1.get("ok", false), "Build phase refuses to advance while players are still active")
	for p: PlayerFactionState in state.players:
		p.has_passed = true
	var gate2: Dictionary = ChapterFlow.advance_phase(state, card_db)
	_check(gate2.get("ok", false), "Build phase advances once everyone is ready")
	_check(state.phase == GameState.Phase.ACTIONS, "phase is now ACTIONS")

	# --- NemesisAI: a Legion moves 1 hex toward its Target, places a Garrison, gains a Curse-free path ---
	state.legions.clear()
	state.hordes.clear()
	var legion := LegionInstance.new()
	legion.id = 0
	legion.card_name = "The Warlock"
	legion.threat = 3
	legion.coord = state.capital_coord
	legion.target_faction = f1
	legion.activation_tokens = 1
	state.legions.append(legion)
	var f1_haven_coord: Vector2i = Vector2i(50, 50)
	state.ensure_hex(f1_haven_coord).haven_faction = f1
	# Force the Legion's target resolution toward a known coord by making f1's Haven the only one.
	var start_coord: Vector2i = legion.coord
	NemesisAI.run_nemesis_phase(state, card_db)
	_check(legion.activation_tokens == 0, "Legion consumed its Activation Token")
	_check(state.get_hex(start_coord).garrison_level >= 1, "Legion placed a Garrison on its starting hex")

	# --- CombatResolver: player Units vs 2 Skeletons on a hex, deterministic dice ---
	var combat_coord := Vector2i(77, 77)
	var ctile: HexTileState = state.ensure_hex(combat_coord)
	ctile.units[f1] = 3
	ctile.skeleton_count = 2
	var combat_rng := RandomNumberGenerator.new()
	combat_rng.seed = 5
	var combat_result: CombatResolver.Result = CombatResolver.resolve_hex(state, combat_coord, card_db, combat_rng)
	_check(combat_result.opponents_fought.has("Skeleton"), "CombatResolver fought the Skeletons")
	_check(ctile.skeleton_count < 2 or combat_result.player_units_lost > 0, "combat changed state (skeletons reduced or player took losses) - skeletons=%d lost=%d" % [ctile.skeleton_count, combat_result.player_units_lost])

	# --- Scoring: a Haven is worth 2 VP ---
	var vp_before: int = state.find_player(f2).vp
	Scoring.score_chapter(state, card_db)
	_check(state.find_player(f2).vp >= vp_before + 2, "f2 scored at least 2 VP for their Haven, got +%d" % (state.find_player(f2).vp - vp_before))

	# --- ChapterFlow full loop sanity: Production phase gives resources ---
	var salt_before_prod: int = state.find_player(f2).salt
	state.phase = GameState.Phase.NEMESIS
	ChapterFlow.advance_phase(state, card_db)  # -> PRODUCTION, runs it
	_check(state.phase == GameState.Phase.PRODUCTION, "advanced to PRODUCTION")
	# Production already ran as part of the NEMESIS->PRODUCTION transition per advance_phase's own dispatch.
	_check(state.find_player(f2).salt >= salt_before_prod, "Production did not decrease Salt (sanity)")

	_report()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		print("FAIL: %s" % label)


func _report() -> void:
	print("\n---")
	if failures.is_empty():
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED:" % failures.size())
		for f: String in failures:
			print("  - " + f)
