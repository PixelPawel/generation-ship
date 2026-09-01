extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_game_flow.gd`
## Drives a full Chapter loop through GameFlow.advance_phase(), start to
## finish across 2 Chapters, checking each phase transition and the gates
## that hold up Actions -> Nemesis.

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _initialize() -> void:
	await process_frame
	var card_db := root.get_node("/root/CardDatabase")

	var pairs := [["Druwhn", "Fhayanor"], ["Krowh", "Kha'al"]]
	var state := GameSetup.build_new_game(card_db, pairs, "Veteran", 2)
	_check("GameSetup output starts in REFRESH (post-refresh Chapter 1)", state.phase == GameState.Phase.REFRESH)

	# --- REFRESH -> EVENTS ---
	var r := GameFlow.advance_phase(state, card_db)
	_check("REFRESH -> EVENTS ok", r.get("ok", false))
	_check("phase is now EVENTS", state.phase == GameState.Phase.EVENTS)
	_check("an Event card was drawn (Chapter 1 has a real deck from GameSetup)", r.get("event", "") != "")
	_check("the drawn Event is recorded on state.current_event", state.current_event == r.get("event", ""))

	# --- EVENTS -> BUILD ---
	r = GameFlow.advance_phase(state, card_db)
	_check("EVENTS -> BUILD ok", r.get("ok", false))
	_check("phase is now BUILD", state.phase == GameState.Phase.BUILD)
	_check("nobody has Passed yet at the start of Build", GameFlow.active_players(state).size() == state.players.size())

	# --- BUILD gate: nobody has declared themselves ready, so advancing is refused ---
	r = GameFlow.advance_phase(state, card_db)
	_check("BUILD -> ACTIONS refused while players aren't ready", not r.get("ok", true))
	_check("phase still BUILD after the refused advance", state.phase == GameState.Phase.BUILD)
	_check("refusal names the not-yet-ready factions", (r.get("waiting_on", []) as Array).has("Druwhn"))

	# --- Both players declare themselves ready (Pass has no AP cost, works in any phase) ---
	GameActions.apply(state, {"type": "pass", "faction": "Druwhn"}, 0)
	GameActions.apply(state, {"type": "pass", "faction": "Krowh"}, 0)
	_check("both players' Feats/Units are untouched by Pass", state.get_player("Druwhn").action_points == 8)

	# --- BUILD -> ACTIONS ---
	r = GameFlow.advance_phase(state, card_db)
	_check("BUILD -> ACTIONS ok once everyone's ready", r.get("ok", false))
	_check("phase is now ACTIONS", state.phase == GameState.Phase.ACTIONS)
	_check("current_player_index reset to first_player_index", state.current_player_index == state.first_player_index)
	_check("has_passed reset for real Actions-Phase gating, not left over from Build", not state.get_player("Druwhn").has_passed and not state.get_player("Krowh").has_passed)

	# --- ACTIONS gate: everyone still has AP, so advancing should be refused ---
	_check("active_players lists everyone at the start of Actions", GameFlow.active_players(state).size() == state.players.size())
	r = GameFlow.advance_phase(state, card_db)
	_check("ACTIONS -> NEMESIS refused while players are still active", not r.get("ok", true))
	_check("phase still ACTIONS after the refused advance", state.phase == GameState.Phase.ACTIONS)
	_check("refusal names the still-active factions", (r.get("waiting_on", []) as Array).has("Druwhn"))

	# --- One player passes, the other drains to 0 AP ---
	state.get_player("Druwhn").has_passed = true
	state.get_player("Krowh").action_points = 0
	_check("active_players is empty once everyone's done", GameFlow.active_players(state).is_empty())

	# --- Inject a Legion + Horde with multiple Activation Tokens, sitting on
	# The Capital (always exists, never gets a Garrison, no target_hex means
	# no movement) so Nemesis draining is tested in isolation from movement. ---
	var legion := LegionInstance.new()
	legion.id = state.next_nemesis_id()
	legion.coord = GameState.CAPITAL_COORD
	legion.activation_tokens = 2
	state.legions.append(legion)
	var horde := HordeInstance.new()
	horde.id = state.next_nemesis_id()
	horde.coord = GameState.CAPITAL_COORD
	horde.activation_tokens = 1
	state.hordes.append(horde)

	# --- ACTIONS -> NEMESIS ---
	r = GameFlow.advance_phase(state, card_db)
	_check("ACTIONS -> NEMESIS ok once everyone's done", r.get("ok", false))
	_check("phase is now NEMESIS", state.phase == GameState.Phase.NEMESIS)
	_check("Legion's 2 Activation Tokens both drained", legion.activation_tokens == 0)
	_check("Horde's 1 Activation Token drained", horde.activation_tokens == 0)

	# --- NEMESIS -> PRODUCTION ---
	var druwhn_salt_before := state.get_player("Druwhn").salt
	r = GameFlow.advance_phase(state, card_db)
	_check("NEMESIS -> PRODUCTION ok", r.get("ok", false))
	_check("phase is now PRODUCTION", state.phase == GameState.Phase.PRODUCTION)
	_check("Production actually granted resources", state.get_player("Druwhn").salt >= druwhn_salt_before)

	# --- PRODUCTION -> SCORING ---
	r = GameFlow.advance_phase(state, card_db)
	_check("PRODUCTION -> SCORING ok", r.get("ok", false))
	_check("phase is now SCORING", state.phase == GameState.Phase.SCORING)
	_check("scoring result carries empire/chaos/players deltas", r.has("scoring") and (r["scoring"] as Dictionary).has("empire"))

	# --- SCORING -> next Chapter's REFRESH (max_chapters is 2, so Chapter 1 -> 2) ---
	var chapter_before := state.chapter
	r = GameFlow.advance_phase(state, card_db)
	_check("SCORING -> next Chapter ok", r.get("ok", false))
	_check("chapter incremented", state.chapter == chapter_before + 1)
	_check("phase reset to REFRESH for the new Chapter", state.phase == GameState.Phase.REFRESH)
	_check("AP reset for the new Chapter", state.get_player("Druwhn").action_points == state.get_player("Druwhn").max_action_points)
	_check("not game_over yet (more Chapters remain)", not r.get("game_over", false))

	# --- Fast-forward through Chapter 2 (the final Chapter, max_chapters=2) to SCORING ---
	GameFlow.advance_phase(state, card_db)  # REFRESH -> EVENTS
	_check("Threat step ran again -- Legion/Horde from Chapter 1 gained more Threat", legion.threat > 0 and horde.threat > 0)
	_check("Threat step alone still doesn't touch tokens", legion.activation_tokens == 0 and horde.activation_tokens == 0)
	GameFlow.advance_phase(state, card_db)  # EVENTS -> BUILD
	_check("Events Phase token step doubles on the final Chapter (2 == max_chapters)", legion.activation_tokens == 2 and horde.activation_tokens == 2)
	_check("has_passed reset for the new Build Phase, not left over from Chapter 1", not state.get_player("Druwhn").has_passed and not state.get_player("Krowh").has_passed)
	GameActions.apply(state, {"type": "pass", "faction": "Druwhn"}, 0)
	GameActions.apply(state, {"type": "pass", "faction": "Krowh"}, 0)
	GameFlow.advance_phase(state, card_db)  # BUILD -> ACTIONS
	for p in state.players:
		p.has_passed = true
	GameFlow.advance_phase(state, card_db)  # ACTIONS -> NEMESIS
	GameFlow.advance_phase(state, card_db)  # NEMESIS -> PRODUCTION
	GameFlow.advance_phase(state, card_db)  # PRODUCTION -> SCORING
	_check("reached SCORING in the final Chapter", state.phase == GameState.Phase.SCORING)

	# --- SCORING on the final Chapter ends the game instead of looping ---
	r = GameFlow.advance_phase(state, card_db)
	_check("final SCORING advance reports game_over", r.get("game_over", false))
	_check("game_over result carries a win/loss verdict", (r.get("result", {}) as Dictionary).has("all_players_win"))
	_check("chapter did NOT advance past max_chapters", state.chapter == state.max_chapters)

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
