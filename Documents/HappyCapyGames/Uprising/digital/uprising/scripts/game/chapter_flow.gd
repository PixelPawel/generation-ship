class_name ChapterFlow
extends RefCounted
## The parts of the Chapter/Phase cycle (rulebook p15-31) that are fully
## automatable. Phases not covered here (Events' actual card text, Feat
## draw/choice, Nemesis activation, Actions) are handled elsewhere or stay
## manual; Build's Unit/Defense purchases live in GameActions
## (build_unit/build_defense), not here, since they're player-submitted
## actions rather than an automatic phase step.


## Rulebook p15: reset AP, discard+refill the Market and Quest slots
## (reshuffling each discard pile back in if its deck runs dry), pass the
## first-player token. Always call this between Chapters -- GameSetup's
## output already represents a "post-refresh" Chapter 1, matching the
## rulebook's explicit "ignore Pass First Player Token on Chapter 1".
static func refresh_phase(state: GameState, starting_ap: int = 8) -> void:
	for player in state.players:
		player.action_points = starting_ap

	state.item_discard.append_array(state.market)
	state.market.clear()
	_refill(state.item_deck, state.item_discard, state.market, 3)

	state.quest_discard.append_array(state.quests_available)
	state.quests_available.clear()
	_refill(state.quest_deck, state.quest_discard, state.quests_available, 3)

	if not state.players.is_empty():
		state.first_player_index = (state.first_player_index + 1) % state.players.size()
	state.current_player_index = state.first_player_index
	state.phase = GameState.Phase.REFRESH


static func _refill(deck: Array, discard: Array, slot: Array, count: int) -> void:
	for _i in range(count):
		if deck.is_empty():
			if discard.is_empty():
				break
			deck.append_array(discard)
			discard.clear()
			deck.shuffle()
		if not deck.is_empty():
			slot.append(deck.pop_back())


## Rulebook p16 step 1 + step 3 (the mechanical parts -- resolving the actual
## Event card's text stays manual/assisted). Adds 2 Threat to every Legion/
## Horde in play, converting overflow past `max_threat` into VP for that
## faction, then places 1 Activation Token on whichever Legion/Horde card
## currently has the fewest (twice, on the last Chapter).
static func events_phase_threat_step(state: GameState, max_threat: int = 7) -> void:
	for legion in state.legions:
		var overflow: int = legion.threat + 2 - max_threat
		if overflow > 0:
			state.empire_vp += overflow
			legion.threat = max_threat
		else:
			legion.threat += 2

	for horde in state.hordes:
		var overflow: int = horde.threat + 2 - max_threat
		if overflow > 0:
			state.chaos_vp += overflow
			horde.threat = max_threat
		else:
			horde.threat += 2

	var rounds := 2 if state.chapter == state.max_chapters else 1
	for _i in range(rounds):
		_add_token_to_fewest(state.legions)
		_add_token_to_fewest(state.hordes)

	state.phase = GameState.Phase.EVENTS


## Rulebook p16 step 2: draws the top Event card for the current Chapter
## (GameSetup already split the deck by Chapter number) and records it on
## state.current_event so the UI actually has something to show -- nothing
## else surfaces this once drawn, and resolving its printed text stays
## manual/assisted like every other card-text effect in this project.
## Returns the drawn name ("" if that Chapter's deck is already empty).
static func draw_event_card(state: GameState) -> String:
	var deck: Array = state.event_deck_by_chapter.get(state.chapter, [])
	if deck.is_empty():
		state.current_event = ""
		return ""
	var drawn_name: String = deck.pop_back()
	state.current_event = drawn_name
	return drawn_name


static func _add_token_to_fewest(units: Array) -> void:
	if units.is_empty():
		return
	var target = units[0]
	for u in units:
		if u.activation_tokens < target.activation_tokens:
			target = u
	target.activation_tokens += 1


## Rulebook p29: gain the base production for your current Haven count (the
## player board's "highest production uncovered" row, transcribed into
## FactionData -- previously blocked on that being print artwork with no
## digitized source, same gap DiceModel filled for dice faces), plus a bonus
## from EACH Haven's terrain (Woods/Highlands -> +2 Plunder, Marshes/
## Badlands -> +2 Food, Ice Waste -> +2 Salt).
static func production_phase_haven_bonus(state: GameState, card_db: Node) -> void:
	for player in state.players:
		var base := FactionData.get_production(player.faction, player.havens.size())
		player.salt += base["salt"]
		player.plunder += base["plunder"]
		player.food += base["food"]

		for coord in player.havens:
			var tile := state.get_hex(coord)
			if tile == null or tile.card_name == "":
				continue
			var hex_card := _find_hex_card(card_db, tile.card_name)
			if hex_card == null:
				continue
			match hex_card.terrain:
				"Woods", "Highlands":
					player.plunder += 2
				"Marshes", "Badlands":
					player.food += 2
				"Ice Waste":
					player.salt += 2
	state.phase = GameState.Phase.PRODUCTION


static func _find_hex_card(card_db: Node, name: String) -> HexCard:
	for h in card_db.hexes:
		if h.lang == "EN" and h.card_name == name:
			return h
	return null


## Rulebook p31: every player must individually have more VP than BOTH
## Empire and Chaos. Meaningful only after the final Chapter's Scoring --
## calling it mid-game just tells you where things currently stand.
static func check_win_loss(state: GameState) -> Dictionary:
	var player_results := {}
	var all_players_win := true
	for player in state.players:
		var beats_empire := player.victory_points > state.empire_vp
		var beats_chaos := player.victory_points > state.chaos_vp
		var wins := beats_empire and beats_chaos
		player_results[player.faction] = {
			"wins": wins, "beats_empire": beats_empire, "beats_chaos": beats_chaos
		}
		if not wins:
			all_players_win = false
	return {"all_players_win": all_players_win, "players": player_results}
