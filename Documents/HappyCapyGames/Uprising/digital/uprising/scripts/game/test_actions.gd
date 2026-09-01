extends SceneTree
## Headless smoke test: `godot --headless --script res://scripts/game/test_actions.gd`
## Exercises GameActions directly against a GameSetup-built state -- no
## networking involved, just the rules logic.

func _initialize() -> void:
	await process_frame
	var card_db := root.get_node("/root/CardDatabase")

	var pairs := [["Druwhn", "Fhayanor"], ["Krowh", "Kha'al"]]
	var state := GameSetup.build_new_game(card_db, pairs, "Veteran", 3)
	state.phase = GameState.Phase.ACTIONS

	var checks: Array = []
	var player := state.get_player("Druwhn")
	var starting_ap := player.action_points
	var starting_salt := player.salt

	# --- Trade ---
	var r := GameActions.apply(state, {"type": "trade", "faction": "Druwhn"}, -1, card_db)
	checks.append(["trade ok", r.get("ok", false)])
	checks.append(["trade: AP -1", player.action_points == starting_ap - 1])
	checks.append(["trade: salt +1", player.salt == starting_salt + 1])

	# --- Move to an adjacent hex ---
	var home := player.hero_hex
	var neighbor := HexMath.neighbors(home)[0]
	# Ensure the neighbor hex actually exists in the generated board.
	if state.get_hex(neighbor) == null:
		var filler := HexTile.new()
		filler.coord = neighbor
		filler.explored = false
		state.set_hex(filler)
	# A random Curse can legitimately land here (rules-correct rejection,
	# not a bug -- GameActions._explore refuses a cursed hex on purpose)
	# and would otherwise make this test flaky, since this section isn't
	# about testing that specific rule.
	state.get_hex(neighbor).has_curse = false

	var ap_before_move := player.action_points
	r = GameActions.apply(state, {"type": "move", "faction": "Druwhn", "to": [neighbor.x, neighbor.y]}, -1, card_db)
	checks.append(["move ok", r.get("ok", false)])
	checks.append(["move: hero_hex updated", player.hero_hex == neighbor])
	checks.append(["move: AP -1", player.action_points == ap_before_move - 1])

	# --- Move to a non-adjacent hex should fail ---
	var far := neighbor + Vector2i(10, 10)
	var far_tile := HexTile.new()
	far_tile.coord = far
	state.set_hex(far_tile)
	r = GameActions.apply(state, {"type": "move", "faction": "Druwhn", "to": [far.x, far.y]}, -1, card_db)
	checks.append(["move to far hex rejected", not r.get("ok", true)])

	# --- Explore the (unexplored) hex we just moved to ---
	var was_explored := state.get_hex(neighbor).explored
	checks.append(["neighbor starts unexplored", not was_explored])
	var ap_before_explore := player.action_points
	r = GameActions.apply(state, {"type": "explore", "faction": "Druwhn"}, -1, card_db)
	checks.append(["explore ok", r.get("ok", false)])
	checks.append(["explore: hex now explored", state.get_hex(neighbor).explored])
	checks.append(["explore: AP -1", player.action_points == ap_before_explore - 1])

	# --- Exploring an already-explored hex should fail ---
	player.has_acted_this_turn = false
	r = GameActions.apply(state, {"type": "explore", "faction": "Druwhn"}, -1, card_db)
	checks.append(["re-explore rejected", not r.get("ok", true)])

	# --- Haven on the Hero's current (now explored) hex -- has_acted_this_turn
	# reset directly as test scaffolding (this file tests each action's own
	# rules in isolation; the real turn-order machinery -- has_acted_this_turn
	# blocking a 2nd ending Action same turn, End Turn's rotation, etc -- gets
	# its own dedicated section below, exercised through the real actions). ---
	player.has_acted_this_turn = false
	var plunder_before := player.plunder
	var ap_before_haven := player.action_points
	r = GameActions.apply(state, {"type": "haven", "faction": "Druwhn"}, -1, card_db)
	checks.append(["haven ok", r.get("ok", false)])
	checks.append(["haven: hex now owned", state.get_hex(neighbor).haven_faction == "Druwhn"])
	checks.append(["haven: plunder -2", player.plunder == plunder_before - 2])
	checks.append(["haven: AP -1", player.action_points == ap_before_haven - 1])
	checks.append(["haven: added to player.havens", player.havens.has(neighbor)])

	# --- A second Haven on the same hex should fail ---
	player.has_acted_this_turn = false
	r = GameActions.apply(state, {"type": "haven", "faction": "Druwhn"}, -1, card_db)
	checks.append(["second haven on same hex rejected", not r.get("ok", true)])

	# --- Command: put a Unit on a hex adjacent to the target, then Command it in ---
	player.has_acted_this_turn = false
	var command_target := home  # move back to the (empty, explored) home hex
	var supply_hex := HexMath.neighbors(command_target)[0]
	if state.get_hex(supply_hex) == null:
		var supply_tile := HexTile.new()
		supply_tile.coord = supply_hex
		supply_tile.explored = true
		state.set_hex(supply_tile)
	state.get_hex(supply_hex).units["Druwhn"] = ["Rangers"]

	var food_before := player.food
	r = GameActions.apply(
		state, {"type": "command", "faction": "Druwhn", "to": [command_target.x, command_target.y]}, -1, card_db
	)
	checks.append(["command ok", r.get("ok", false)])
	checks.append(["command: hero moved to target", player.hero_hex == command_target])
	checks.append(["command: unit gathered onto target", state.get_hex(command_target).units.get("Druwhn", []).has("Rangers")])
	checks.append(["command: unit removed from supply hex", not state.get_hex(supply_hex).units.get("Druwhn", []).has("Rangers")])
	checks.append(["command: food -1", player.food == food_before - 1])

	# --- Market: buy a known-cheap, no-requirement Item ---
	player.has_acted_this_turn = false
	if not state.market.has("Abad Warpaint"):
		state.market.append("Abad Warpaint")
	var salt_before_market := player.salt
	var market_size_before := state.market.size()
	r = GameActions.apply(state, {"type": "market", "faction": "Druwhn", "item": "Abad Warpaint"}, -1, card_db)
	checks.append(["market ok", r.get("ok", false)])
	checks.append(["market: item in items_in_play", player.items_in_play.has("Abad Warpaint")])
	checks.append(["market: item removed from market", not state.market.has("Abad Warpaint")])
	checks.append(["market: salt decreased", player.salt < salt_before_market])
	checks.append(["market: market shrank by 1", state.market.size() == market_size_before - 1])

	# --- Market: an Item requiring more Might than the Hero has should fail ---
	# (has_acted_this_turn reset again -- otherwise this would trivially
	# reject on turn-order grounds instead of actually exercising the
	# attribute-requirement check it's meant to test.)
	player.has_acted_this_turn = false
	var high_req_item := "Axe of the Giants"  # requires Might 3; Fhayanor has Might 1
	if not state.market.has(high_req_item):
		state.market.append(high_req_item)
	r = GameActions.apply(state, {"type": "market", "faction": "Druwhn", "item": high_req_item}, -1, card_db)
	checks.append(["market rejects insufficient attribute", not r.get("ok", true)])

	# --- Market: unknown item should fail ---
	r = GameActions.apply(state, {"type": "market", "faction": "Druwhn", "item": "Not A Real Item"}, -1, card_db)
	checks.append(["market rejects unknown item", not r.get("ok", true)])

	# --- Quest: real dice-roll resolution ---
	player.has_acted_this_turn = false
	var quest_name := "A Deal with Demons"
	if not state.quests_available.has(quest_name):
		state.quests_available.append(quest_name)
	var ap_before_quest := player.action_points
	r = GameActions.apply(state, {"type": "quest", "faction": "Druwhn", "quest": quest_name}, -1, card_db)
	checks.append(["quest ok", r.get("ok", false)])
	checks.append(["quest: AP -1", player.action_points == ap_before_quest - 1])
	checks.append(["quest: result carries a dice tally", r.has("dice") and (r["dice"] as Dictionary).has("skulls")])
	checks.append(["quest: result carries goals_met for all 3 goals", (r.get("goals_met", {}) as Dictionary).size() == 3])
	checks.append(["quest: successes_needed echoes the card", r.get("successes_needed", -1) >= 0])
	var successes_match: bool = r.get("solved", null) == (r.get("successes", -1) >= r.get("successes_needed", 999))
	checks.append(["quest: solved matches successes >= successes_needed", successes_match])

	# --- Quest: rejects a Guile split that doesn't sum to the Hero's Guile ---
	player.has_acted_this_turn = false
	r = GameActions.apply(state, {"type": "quest", "faction": "Druwhn", "quest": quest_name, "guile_white": 99, "guile_yellow": 0}, -1, card_db)
	checks.append(["quest rejects mismatched guile split", not r.get("ok", true)])

	r = GameActions.apply(state, {"type": "quest", "faction": "Druwhn", "quest": "Not A Real Quest"}, -1, card_db)
	checks.append(["quest rejects unavailable quest", not r.get("ok", true)])

	# ---------------------------------------------------------------
	# Turn order (rulebook p18: "In clockwise order, players spend AP...
	# then next player goes"). Druwhn (index 0) has been the only actor so
	# far -- current_player_index is still 0.
	# ---------------------------------------------------------------
	var krowh: PlayerFactionState = state.get_player("Krowh")
	player.has_acted_this_turn = false
	krowh.action_points = 5

	if not state.market.has("Xyxrit Leaves"):
		state.market.append("Xyxrit Leaves")
	r = GameActions.apply(state, {"type": "market", "faction": "Krowh", "item": "Xyxrit Leaves"}, -1, card_db)
	checks.append(["turn-gated action rejected when it isn't your turn", not r.get("ok", true)])

	var krowh_salt_before := krowh.salt
	r = GameActions.apply(state, {"type": "trade", "faction": "Krowh"}, -1, card_db)
	checks.append(["Trade still works for Krowh even though it isn't their turn", r.get("ok", false) and krowh.salt == krowh_salt_before + 1])

	# --- Druwhn's one Action this turn, then a 2nd is blocked -- so is Move.
	# "Xyxrit Leaves" is still sitting in the market -- Krowh's attempt just
	# above was rejected for turn order, not actually purchased. ---
	r = GameActions.apply(state, {"type": "market", "faction": "Druwhn", "item": "Xyxrit Leaves"}, -1, card_db)
	checks.append(["Druwhn's own Market succeeds on their turn", r.get("ok", false)])
	checks.append(["has_acted_this_turn now true", player.has_acted_this_turn])

	if not state.quests_available.has(quest_name):
		state.quests_available.append(quest_name)
	r = GameActions.apply(state, {"type": "quest", "faction": "Druwhn", "quest": quest_name}, -1, card_db)
	checks.append(["a 2nd ending Action the same turn is rejected", not r.get("ok", true)])

	r = GameActions.apply(state, {"type": "move", "faction": "Druwhn", "to": [home.x, home.y]}, -1, card_db)
	checks.append(["Move is also blocked once this turn's Action is spent", not r.get("ok", true)])

	player.action_points = 5  # replenish -- AP has been draining all test long, this check is about has_acted_this_turn, not AP
	var druwhn_salt_before := player.salt
	r = GameActions.apply(state, {"type": "trade", "faction": "Druwhn"}, -1, card_db)
	checks.append(["Trade still works even after this turn's Action is spent", r.get("ok", false) and player.salt == druwhn_salt_before + 1])

	# --- end_turn: wrong player rejected, current player hands off ---
	r = GameActions.apply(state, {"type": "end_turn", "faction": "Krowh"}, -1, card_db)
	checks.append(["end_turn rejected for a player whose turn it isn't", not r.get("ok", true)])

	r = GameActions.apply(state, {"type": "end_turn", "faction": "Druwhn"}, -1, card_db)
	checks.append(["end_turn ok for the current player", r.get("ok", false)])
	checks.append(["turn advances to the next active player (Krowh)", state.players[state.current_player_index].faction == "Krowh"])
	checks.append(["has_acted_this_turn reset for the incoming player", not krowh.has_acted_this_turn])
	checks.append(["has_acted_this_turn also reset for the outgoing player", not player.has_acted_this_turn])

	r = GameActions.apply(state, {"type": "market", "faction": "Druwhn", "item": "Abad Warpaint"}, -1, card_db)
	checks.append(["Druwhn blocked once it's no longer their turn", not r.get("ok", true)])

	# --- end_turn skips players who've Passed or run out of AP, wrapping
	# around -- isolated 4-player fixture, same pattern as or_state/
	# any_state/feat_state below for testing a mechanic in isolation. ---
	var turn_state := GameState.new()
	turn_state.phase = GameState.Phase.ACTIONS
	var pa := PlayerFactionState.new()
	pa.faction = "A"
	pa.action_points = 5
	var pb := PlayerFactionState.new()
	pb.faction = "B"
	pb.action_points = 0  # out of AP -- should be skipped
	var pc := PlayerFactionState.new()
	pc.faction = "C"
	pc.has_passed = true  # already passed -- should be skipped
	var pd := PlayerFactionState.new()
	pd.faction = "D"
	pd.action_points = 3
	turn_state.players.append(pa)
	turn_state.players.append(pb)
	turn_state.players.append(pc)
	turn_state.players.append(pd)
	turn_state.current_player_index = 0  # A's turn

	r = GameActions.apply(turn_state, {"type": "end_turn", "faction": "A"}, -1, card_db)
	checks.append(["end_turn skips a 0-AP player and a Passed player, landing on D",
		r.get("ok", false) and turn_state.players[turn_state.current_player_index].faction == "D"])

	r = GameActions.apply(turn_state, {"type": "end_turn", "faction": "D"}, -1, card_db)
	checks.append(["end_turn wraps around back to A, skipping B/C again",
		r.get("ok", false) and turn_state.players[turn_state.current_player_index].faction == "A"])

	# --- Pass, when it's the current player's turn, also hands the turn along ---
	r = GameActions.apply(turn_state, {"type": "pass", "faction": "A"}, -1, card_db)
	checks.append(["Pass ok", r.get("ok", false)])
	checks.append(["Pass marks has_passed", pa.has_passed])
	checks.append(["Pass also advances the turn (it was A's) to D", turn_state.players[turn_state.current_player_index].faction == "D"])

	# --- If nobody is left active, end_turn still succeeds but current_player_index just stays put ---
	pd.action_points = 0
	r = GameActions.apply(turn_state, {"type": "end_turn", "faction": "D"}, -1, card_db)
	checks.append(["end_turn succeeds even when nobody is left active", r.get("ok", false)])
	checks.append(["current_player_index left unchanged with no active players", turn_state.players[turn_state.current_player_index].faction == "D"])

	# --- Unknown action type ---
	r = GameActions.apply(state, {"type": "not_a_real_action", "faction": "Druwhn"}, -1, card_db)
	checks.append(["unknown action rejected", not r.get("ok", true)])

	# --- Unknown faction ---
	r = GameActions.apply(state, {"type": "trade", "faction": "NotAFaction"}, -1, card_db)
	checks.append(["unknown faction rejected", not r.get("ok", true)])

	# --- Drain AP to 0, then Trade should be rejected ---
	player.action_points = 0
	r = GameActions.apply(state, {"type": "trade", "faction": "Druwhn"}, -1, card_db)
	checks.append(["trade with 0 AP rejected", not r.get("ok", true)])

	# --- Move outside the Actions Phase should be rejected ---
	state.phase = GameState.Phase.BUILD
	r = GameActions.apply(state, {"type": "move", "faction": "Krowh", "to": [0, 0]}, -1, card_db)
	checks.append(["move outside Actions Phase rejected", not r.get("ok", true)])

	# ---------------------------------------------------------------
	# build_unit / build_defense (Build Phase) -- `neighbor` already has a
	# Druwhn Haven from the earlier Haven test above.
	# ---------------------------------------------------------------
	player.salt = 10
	player.plunder = 10
	player.food = 10

	var units_before: int = (state.get_hex(neighbor).units.get("Druwhn", []) as Array).size()
	var salt_before_build := player.salt
	r = GameActions.apply(state, {"type": "build_unit", "faction": "Druwhn", "unit": "Sons of the Bow", "at": [neighbor.x, neighbor.y]}, -1, card_db)
	checks.append(["build_unit ok", r.get("ok", false)])
	checks.append(["build_unit: unit added to hex", (state.get_hex(neighbor).units.get("Druwhn", []) as Array).size() == units_before + 1])
	checks.append(["build_unit: salt -3", player.salt == salt_before_build - 3])

	r = GameActions.apply(state, {"type": "build_unit", "faction": "Druwhn", "unit": "Not A Real Unit", "at": [neighbor.x, neighbor.y]}, -1, card_db)
	checks.append(["build_unit rejects unknown unit", not r.get("ok", true)])

	r = GameActions.apply(state, {"type": "build_unit", "faction": "Druwhn", "unit": "Sons of the Bow", "at": [far.x, far.y]}, -1, card_db)
	checks.append(["build_unit rejects an invalid hex (unexplored / no Haven)", not r.get("ok", true)])

	# --- Reserve cap: Druwhn only has 2 Beastmasters total ---
	player.salt = 20
	player.food = 20
	r = GameActions.apply(state, {"type": "build_unit", "faction": "Druwhn", "unit": "Beastmasters", "at": [neighbor.x, neighbor.y]}, -1, card_db)
	checks.append(["build_unit: 1st Beastmasters ok", r.get("ok", false)])
	r = GameActions.apply(state, {"type": "build_unit", "faction": "Druwhn", "unit": "Beastmasters", "at": [neighbor.x, neighbor.y]}, -1, card_db)
	checks.append(["build_unit: 2nd Beastmasters ok", r.get("ok", false)])
	r = GameActions.apply(state, {"type": "build_unit", "faction": "Druwhn", "unit": "Beastmasters", "at": [neighbor.x, neighbor.y]}, -1, card_db)
	checks.append(["build_unit: 3rd Beastmasters rejected (reserve of 2 exhausted)", not r.get("ok", true)])

	var plunder_before_defense := player.plunder
	r = GameActions.apply(state, {"type": "build_defense", "faction": "Druwhn", "defense": "tower", "at": [neighbor.x, neighbor.y]}, -1, card_db)
	checks.append(["build_defense (tower) ok", r.get("ok", false)])
	checks.append(["build_defense: hex now has a Tower", state.get_hex(neighbor).has_tower])
	checks.append(["build_defense: plunder -1", player.plunder == plunder_before_defense - 1])

	r = GameActions.apply(state, {"type": "build_defense", "faction": "Druwhn", "defense": "tower", "at": [neighbor.x, neighbor.y]}, -1, card_db)
	checks.append(["build_defense rejects a 2nd Tower on the same Haven", not r.get("ok", true)])

	r = GameActions.apply(state, {"type": "build_defense", "faction": "Druwhn", "defense": "wall", "at": [neighbor.x, neighbor.y]}, -1, card_db)
	checks.append(["build_defense (wall) ok", r.get("ok", false)])
	checks.append(["build_defense: hex now has a Wall", state.get_hex(neighbor).has_wall])

	r = GameActions.apply(state, {"type": "build_defense", "faction": "Druwhn", "defense": "tower", "at": [far.x, far.y]}, -1, card_db)
	checks.append(["build_defense rejects a hex without your Haven", not r.get("ok", true)])

	# --- OR-cost Units: Duerkhar's Younglings can be paid with either option ---
	var or_state := GameState.new()
	var or_player := PlayerFactionState.new()
	or_player.faction = "Duerkhar"
	or_player.salt = 5
	or_player.plunder = 5
	or_state.players.append(or_player)
	or_state.phase = GameState.Phase.BUILD
	var or_tile := HexTile.new()
	or_tile.coord = Vector2i(0, 0)
	or_tile.explored = true
	or_tile.haven_faction = "Duerkhar"
	or_state.set_hex(or_tile)

	r = GameActions.apply(or_state, {"type": "build_unit", "faction": "Duerkhar", "unit": "Younglings", "at": [0, 0], "cost_choice": 1}, -1, card_db)
	checks.append(["build_unit: OR-cost choice 1 (Plunder) ok", r.get("ok", false)])
	checks.append(["build_unit: OR-cost paid with Plunder not Salt", or_player.plunder == 3 and or_player.salt == 5])

	# --- ANY-cost Units: Mohyar's Sellswords need an explicit any_alloc ---
	var any_state := GameState.new()
	var any_player := PlayerFactionState.new()
	any_player.faction = "Mohyar"
	any_player.salt = 5
	any_player.plunder = 5
	any_player.food = 5
	any_state.players.append(any_player)
	any_state.phase = GameState.Phase.BUILD
	var any_tile := HexTile.new()
	any_tile.coord = Vector2i(0, 0)
	any_tile.explored = true
	any_tile.haven_faction = "Mohyar"
	any_state.set_hex(any_tile)

	r = GameActions.apply(any_state, {"type": "build_unit", "faction": "Mohyar", "unit": "Sellswords", "at": [0, 0], "any_alloc": {"food": 1, "plunder": 1}}, -1, card_db)
	checks.append(["build_unit: ANY-cost with explicit allocation ok", r.get("ok", false)])
	checks.append(["build_unit: ANY-cost paid food+plunder not salt", any_player.food == 4 and any_player.plunder == 4 and any_player.salt == 5])

	r = GameActions.apply(any_state, {"type": "build_unit", "faction": "Mohyar", "unit": "Hunters", "at": [0, 0], "any_alloc": {"food": 1}}, -1, card_db)
	checks.append(["build_unit: ANY-cost rejects an allocation that doesn't sum to the cost", not r.get("ok", true)])

	# --- draw_feats / choose_feat ---
	var feat_state := GameState.new()
	var feat_player := PlayerFactionState.new()
	feat_player.faction = "Druwhn"
	feat_player.feat_deck = ["Ambush", "Assasins", "Beastmasters"]
	feat_state.players.append(feat_player)
	feat_state.phase = GameState.Phase.BUILD

	r = GameActions.apply(feat_state, {"type": "draw_feats", "faction": "Druwhn"}, -1, card_db)
	checks.append(["draw_feats ok", r.get("ok", false)])
	checks.append(["draw_feats: 2 cards drawn into pending_feat_choice", feat_player.pending_feat_choice.size() == 2])
	checks.append(["draw_feats: feat_deck shrank by 2", feat_player.feat_deck.size() == 1])

	r = GameActions.apply(feat_state, {"type": "draw_feats", "faction": "Druwhn"}, -1, card_db)
	checks.append(["draw_feats rejects a second draw before choosing", not r.get("ok", true)])

	var chosen_feat: String = feat_player.pending_feat_choice[0]
	var other_feat: String = feat_player.pending_feat_choice[1]
	r = GameActions.apply(feat_state, {"type": "choose_feat", "faction": "Druwhn", "feat": chosen_feat}, -1, card_db)
	checks.append(["choose_feat ok", r.get("ok", false)])
	checks.append(["choose_feat: chosen Feat now in feats_in_play", feat_player.feats_in_play.has(chosen_feat)])
	checks.append(["choose_feat: pending_feat_choice cleared", feat_player.pending_feat_choice.is_empty()])
	checks.append(["choose_feat: other Feat returned to feat_deck", feat_player.feat_deck.has(other_feat)])
	checks.append(["choose_feat: other Feat placed at the bottom of the deck", feat_player.feat_deck[0] == other_feat])

	r = GameActions.apply(feat_state, {"type": "choose_feat", "faction": "Druwhn", "feat": "Not A Real Feat"}, -1, card_db)
	checks.append(["choose_feat rejects a Feat that wasn't drawn", not r.get("ok", true)])

	# --- draw_feats with only 1 card left in the deck draws just that 1 ---
	feat_player.feat_deck = ["Teleport"]
	r = GameActions.apply(feat_state, {"type": "draw_feats", "faction": "Druwhn"}, -1, card_db)
	checks.append(["draw_feats with 1 card left draws just that 1", feat_player.pending_feat_choice == ["Teleport"]])
	r = GameActions.apply(feat_state, {"type": "choose_feat", "faction": "Druwhn", "feat": "Teleport"}, -1, card_db)
	checks.append(["choose_feat with only 1 drawn returns nothing to the deck", feat_player.feat_deck.is_empty()])

	# --- draw_feats with an empty deck should fail ---
	feat_player.feat_deck = []
	r = GameActions.apply(feat_state, {"type": "draw_feats", "faction": "Druwhn"}, -1, card_db)
	checks.append(["draw_feats rejects an empty deck", not r.get("ok", true)])

	# --- draw_feats outside Build Phase should fail ---
	feat_state.phase = GameState.Phase.ACTIONS
	feat_player.feat_deck = ["Ambush"]
	r = GameActions.apply(feat_state, {"type": "draw_feats", "faction": "Druwhn"}, -1, card_db)
	checks.append(["draw_feats outside Build Phase rejected", not r.get("ok", true)])

	# ---------------------------------------------------------------
	# destroy_unit -- Combat resolution stays manual/assisted (still
	# blocked on missing per-Unit dice-color data), but "move a destroyed
	# Unit into the graveyard that killed it" is the simple mechanical
	# step this reports. Scoring._score_empire/_score_chaos's graveyard
	# math is already covered by test_scoring.gd against hand-set
	# graveyard Dictionaries -- this tests what actually POPULATES them.
	# ---------------------------------------------------------------
	var dstate := GameState.new()
	var dplayer := PlayerFactionState.new()
	dplayer.faction = "Druwhn"
	dstate.players.append(dplayer)
	var dcoord := Vector2i(9, 9)
	var dtile := HexTile.new()
	dtile.coord = dcoord
	dtile.units["Druwhn"] = ["Rangers", "Rangers", "Swordsisters"]
	dstate.set_hex(dtile)

	r = GameActions.apply(dstate, {"type": "destroy_unit", "faction": "Druwhn", "unit": "Rangers", "at": [dcoord.x, dcoord.y], "graveyard": "imperial"}, -1, card_db)
	checks.append(["destroy_unit ok", r.get("ok", false)])
	checks.append(["destroy_unit: only 1 Rangers removed from the hex (2nd stays)", dtile.units["Druwhn"] == ["Rangers", "Swordsisters"]])
	checks.append(["destroy_unit: imperial_graveyard incremented for Druwhn", int(dstate.imperial_graveyard.get("Druwhn", 0)) == 1])
	checks.append(["destroy_unit: chaos_graveyard untouched", not dstate.chaos_graveyard.has("Druwhn")])

	r = GameActions.apply(dstate, {"type": "destroy_unit", "faction": "Druwhn", "unit": "Swordsisters", "at": [dcoord.x, dcoord.y], "graveyard": "chaos"}, -1, card_db)
	checks.append(["destroy_unit to the Chaos graveyard ok", r.get("ok", false)])
	checks.append(["destroy_unit: chaos_graveyard incremented for Druwhn", int(dstate.chaos_graveyard.get("Druwhn", 0)) == 1])
	checks.append(["destroy_unit: imperial_graveyard unaffected by the 2nd call", int(dstate.imperial_graveyard.get("Druwhn", 0)) == 1])

	r = GameActions.apply(dstate, {"type": "destroy_unit", "faction": "Druwhn", "unit": "Not A Real Unit", "at": [dcoord.x, dcoord.y], "graveyard": "imperial"}, -1, card_db)
	checks.append(["destroy_unit rejects a Unit that isn't on that hex", not r.get("ok", true)])

	r = GameActions.apply(dstate, {"type": "destroy_unit", "faction": "Druwhn", "unit": "Rangers", "at": [dcoord.x, dcoord.y], "graveyard": "not_a_side"}, -1, card_db)
	checks.append(["destroy_unit rejects an invalid graveyard value", not r.get("ok", true)])

	r = GameActions.apply(dstate, {"type": "destroy_unit", "faction": "Druwhn", "unit": "Rangers", "at": [999, 999], "graveyard": "imperial"}, -1, card_db)
	checks.append(["destroy_unit rejects a hex that doesn't exist", not r.get("ok", true)])

	var all_ok := true
	for c in checks:
		var label: String = c[0]
		var ok: bool = c[1]
		print(("OK   " if ok else "FAIL "), label, (" -- " + str(r.get("reason", "")) if not ok else ""))
		if not ok:
			all_ok = false

	print("\nALL CHECKS %s" % ("PASSED" if all_ok else "FAILED"))
	quit(0 if all_ok else 1)
