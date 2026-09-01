extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_chapter_flow.gd`

var checks: Array = []


func _check(label: String, ok: bool) -> void:
	checks.append([label, ok])


func _find_hex_name_for_terrain(card_db: Node, terrain: String) -> String:
	for h in card_db.hexes:
		if h.lang == "EN" and h.box == "Core" and h.terrain == terrain:
			return h.card_name
	return ""


func _initialize() -> void:
	await process_frame
	var card_db := root.get_node("/root/CardDatabase")

	# ---------------------------------------------------------------
	# refresh_phase
	# ---------------------------------------------------------------
	var pairs := [["Druwhn", "Fhayanor"], ["Krowh", "Kha'al"], ["Duerkhar", "Yanny"]]
	var state := GameSetup.build_new_game(card_db, pairs, "Veteran", 3)
	state.phase = GameState.Phase.ACTIONS
	for player in state.players:
		player.action_points = 0  # simulate a spent Chapter

	var old_first := state.first_player_index
	var old_market_size := state.market.size()
	var old_deck_size := state.item_deck.size()
	ChapterFlow.refresh_phase(state, 8)

	var ap_reset := true
	for player in state.players:
		if player.action_points != 8:
			ap_reset = false
	_check("refresh: AP reset to 8 for every player", ap_reset)
	_check("refresh: first player advanced", state.first_player_index == (old_first + 1) % state.players.size())
	_check("refresh: current_player_index matches new first player", state.current_player_index == state.first_player_index)
	_check("refresh: market refilled to 3", state.market.size() == 3)
	_check("refresh: old market went to discard", state.item_discard.size() == old_market_size)
	_check("refresh: item deck shrank by 3", state.item_deck.size() == old_deck_size - 3)
	_check("refresh: phase set to REFRESH", state.phase == GameState.Phase.REFRESH)

	# --- Reshuffle-from-discard when the deck runs dry ---
	var drain_state := GameState.new()
	drain_state.players.append(PlayerFactionState.new())
	drain_state.item_deck = ["A", "B"]
	drain_state.item_discard = ["C", "D", "E", "F"]
	drain_state.market = []
	ChapterFlow.refresh_phase(drain_state, 8)
	_check("refresh: reshuffles discard back into the deck when it runs dry",
		drain_state.market.size() == 3 and drain_state.item_deck.size() == 3)

	# ---------------------------------------------------------------
	# events_phase_threat_step
	# ---------------------------------------------------------------
	var estate := GameState.new()
	estate.chapter = 2
	estate.max_chapters = 3
	var legion := LegionInstance.new()
	legion.id = estate.next_nemesis_id()
	legion.threat = 3
	estate.legions.append(legion)
	var legion_overflow := LegionInstance.new()
	legion_overflow.id = estate.next_nemesis_id()
	legion_overflow.threat = 6  # +2 would be 8, over the max of 7
	estate.legions.append(legion_overflow)
	var horde := HordeInstance.new()
	horde.id = estate.next_nemesis_id()
	horde.threat = 4
	estate.hordes.append(horde)

	var empire_vp_before := estate.empire_vp
	ChapterFlow.events_phase_threat_step(estate, 7)
	_check("events: normal Legion threat +2", legion.threat == 5)
	_check("events: overflow Legion caps at max_threat", legion_overflow.threat == 7)
	_check("events: overflow grants Empire 1 VP (8-7)", estate.empire_vp == empire_vp_before + 1)
	_check("events: Horde threat +2", horde.threat == 6)
	_check("events: non-last-chapter places 1 token per unit", legion.activation_tokens == 1 and horde.activation_tokens == 1)
	_check("events: phase set to EVENTS", estate.phase == GameState.Phase.EVENTS)

	# --- Last Chapter should place 2 tokens ---
	var estate2 := GameState.new()
	estate2.chapter = 3
	estate2.max_chapters = 3
	var legion2 := LegionInstance.new()
	legion2.id = estate2.next_nemesis_id()
	estate2.legions.append(legion2)
	ChapterFlow.events_phase_threat_step(estate2, 7)
	_check("events: last Chapter places 2 tokens", legion2.activation_tokens == 2)

	# --- Token placement prefers whichever unit has fewest ---
	var estate3 := GameState.new()
	estate3.chapter = 1
	estate3.max_chapters = 3
	var la := LegionInstance.new()
	la.id = estate3.next_nemesis_id()
	la.activation_tokens = 2
	var lb := LegionInstance.new()
	lb.id = estate3.next_nemesis_id()
	lb.activation_tokens = 0
	estate3.legions.append(la)
	estate3.legions.append(lb)
	ChapterFlow.events_phase_threat_step(estate3, 7)
	_check("events: token goes to the Legion with fewest tokens", lb.activation_tokens == 1 and la.activation_tokens == 2)

	# ---------------------------------------------------------------
	# production_phase_haven_bonus
	# ---------------------------------------------------------------
	var pstate := GameState.new()
	var player := PlayerFactionState.new()
	player.faction = "Druwhn"
	pstate.players.append(player)

	var woods_name := _find_hex_name_for_terrain(card_db, "Woods")
	var marsh_name := _find_hex_name_for_terrain(card_db, "Marshes")
	var ice_name := _find_hex_name_for_terrain(card_db, "Ice Waste")
	_check("found a Core Woods hex to test with", woods_name != "")
	_check("found a Core Marshes hex to test with", marsh_name != "")
	_check("found a Core Ice Waste hex to test with", ice_name != "")

	var woods_tile := HexTile.new()
	woods_tile.coord = Vector2i(1, 0)
	woods_tile.card_name = woods_name
	pstate.set_hex(woods_tile)
	var marsh_tile := HexTile.new()
	marsh_tile.coord = Vector2i(2, 0)
	marsh_tile.card_name = marsh_name
	pstate.set_hex(marsh_tile)
	var ice_tile := HexTile.new()
	ice_tile.coord = Vector2i(3, 0)
	ice_tile.card_name = ice_name
	pstate.set_hex(ice_tile)
	player.havens = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]

	# Druwhn at 3 Havens: base production (FactionData) is 5 Salt/2 Plunder/
	# 1 Food, plus +2 Plunder (Woods), +2 Food (Marshes), +2 Salt (Ice Waste)
	# from the 3 Haven terrain bonuses above -> 7 Salt/4 Plunder/3 Food total.
	ChapterFlow.production_phase_haven_bonus(pstate, card_db)
	_check("production: base production applied for 3 Havens", player.salt == 7 and player.plunder == 4 and player.food == 3)
	_check("production: phase set to PRODUCTION", pstate.phase == GameState.Phase.PRODUCTION)

	# --- Zero Havens still produces the shared baseline (0/2/1) ---
	var pstate0 := GameState.new()
	var player0 := PlayerFactionState.new()
	player0.faction = "Krowh"
	pstate0.players.append(player0)
	ChapterFlow.production_phase_haven_bonus(pstate0, card_db)
	_check("production: 0 Havens still gives the baseline 0 Salt/2 Plunder/1 Food", player0.salt == 0 and player0.plunder == 2 and player0.food == 1)

	# ---------------------------------------------------------------
	# check_win_loss
	# ---------------------------------------------------------------
	var wstate := GameState.new()
	wstate.empire_vp = 10
	wstate.chaos_vp = 8
	var winner := PlayerFactionState.new()
	winner.faction = "Winner"
	winner.victory_points = 11
	var loser_to_empire := PlayerFactionState.new()
	loser_to_empire.faction = "LoserToEmpire"
	loser_to_empire.victory_points = 10  # equal to Empire -- rulebook: equal or more loses
	wstate.players.append(winner)
	wstate.players.append(loser_to_empire)

	var result := ChapterFlow.check_win_loss(wstate)
	_check("win-loss: player beating both scores a win", result["players"]["Winner"]["wins"] == true)
	_check("win-loss: player tied with Empire does not win", result["players"]["LoserToEmpire"]["wins"] == false)
	_check("win-loss: not all_players_win when one player loses", result["all_players_win"] == false)

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label)
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
