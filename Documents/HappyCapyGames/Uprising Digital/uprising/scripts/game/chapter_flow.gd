class_name ChapterFlow
extends RefCounted

## The 7-phase Chapter sequencer (rulebook p10, 15-31): Refresh -> Events
## -> Build -> Actions -> Nemesis -> Production -> Scoring, looping for
## max_chapters, then game ends. advance_phase() is the single entry point
## - it enforces the readiness gates (Build/Actions don't advance until
## every active player is done) and calls the per-phase step functions.
##
## Events: Threat +2, then this Chapter's Event card (event_effects.gd),
## then Activation Tokens. Refresh deals 3 new Items and Quests (Quests'
## immediate effects resolve; Cleanse the Wastes and Imperial Inquisition
## stay until solved).

static func advance_phase(state: GameState, card_db: Node) -> Dictionary:
	match state.phase:
		GameState.Phase.REFRESH:
			_refresh_phase(state, card_db)
			state.phase = GameState.Phase.EVENTS
			return {"ok": true}
		GameState.Phase.EVENTS:
			_events_phase(state, card_db)
			state.phase = GameState.Phase.BUILD
			_start_build_phase(state)
			return {"ok": true}
		GameState.Phase.BUILD:
			if not GameActions.active_players(state).is_empty():
				return {"ok": false, "reason": "not every player is ready (still has AP and hasn't Passed)"}
			state.phase = GameState.Phase.ACTIONS
			_start_actions_phase(state)
			return {"ok": true}
		GameState.Phase.ACTIONS:
			if not GameActions.active_players(state).is_empty():
				return {"ok": false, "reason": "not every player is out of AP / has Passed"}
			state.phase = GameState.Phase.NEMESIS
			for tile: HexTileState in state.hexes.values():
				tile.orientable_by = ""
			_nemesis_phase(state, card_db)
			return {"ok": true}
		GameState.Phase.NEMESIS:
			state.phase = GameState.Phase.PRODUCTION
			_production_phase(state, card_db)
			return {"ok": true}
		GameState.Phase.PRODUCTION:
			state.phase = GameState.Phase.SCORING
			Scoring.score_chapter(state, card_db)
			return {"ok": true}
		GameState.Phase.SCORING:
			if state.chapter >= state.max_chapters:
				return {"ok": true, "game_over": true, "verdict": check_win_loss(state)}
			state.chapter += 1
			state.phase = GameState.Phase.REFRESH
			return {"ok": true}
	return {"ok": false, "reason": "unknown phase"}


static func _refresh_phase(state: GameState, card_db: Node = null) -> void:
	var gained: Array[String] = DruidConditions.apply_refresh_phase(state)
	for p: PlayerFactionState in state.players:
		p.action_points = p.max_action_points
		p.has_passed = false
		p.has_acted_this_turn = false
		p.flipped_items.clear()  # "Flip all your face-down cards back up"
	if state.players.size() > 0 and state.chapter > 1:
		state.first_player_index = (state.first_player_index + 1) % state.players.size()
	state.current_player_index = state.first_player_index
	deal_row(state.item_market, state.item_deck, state.item_discard, 3, state.flipped_market)
	_deal_quests(state, card_db)
	state.phase_log = "Refresh: Aether placed on %s" % [gained] if not gained.is_empty() else "Refresh: no Aether conditions met"


## Rulebook p15: "Deal 3 new Quests (discard the old ones, unless that
## Quest says not to) and resolve any immediate effects on the new Quests."
static func _deal_quests(state: GameState, card_db: Node) -> void:
	var quest_flow: GDScript = load("res://scripts/game/quest_flow.gd")
	var keep: Array[String] = []
	for q: String in state.quest_row:
		if quest_flow.STAY_UNTIL_SOLVED.has(q):
			keep.append(q)
		else:
			for item: Variant in (state.quest_items.get(q, []) as Array):
				state.item_discard.append(str(item))
			state.quest_items.erase(q)
	deal_row(state.quest_row, state.quest_deck, state.quest_discard, 3, keep)
	var first: String = state.players[state.first_player_index % state.players.size()].faction if not state.players.is_empty() else ""
	for q2: String in state.quest_row.duplicate():
		if not keep.has(q2):  # everything not kept was just dealt
			quest_flow.on_dealt(state, card_db, q2, first)


## Rulebook p15: discard the old face-up cards (except any in `keep`, e.g.
## Items The Spymaster flipped), then fill back up to `count`.
static func deal_row(row: Array[String], deck: Array[String], discard: Array[String], count: int, keep: Array[String] = []) -> void:
	var kept: Array[String] = []
	for card: String in row:
		if keep.has(card):
			kept.append(card)
		else:
			discard.append(card)
	row.clear()
	row.append_array(kept)
	refill_row(row, deck, discard, count)


## Tops a face-up row back up to `count`, reshuffling the discard pile into
## the deck if it runs dry.
static func refill_row(row: Array[String], deck: Array[String], discard: Array[String], count: int) -> void:
	while row.size() < count:
		if deck.is_empty():
			if discard.is_empty():
				return
			deck.append_array(discard)
			discard.clear()
			deck.shuffle()
		row.append(deck.pop_front())


static func _events_phase(state: GameState, card_db: Node = null) -> void:
	var overflow_vp_empire: int = 0
	var overflow_vp_chaos: int = 0
	for l: LegionInstance in state.legions:
		var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(l.card_name)
		var max_threat: int = card.max_threat if card != null else 7
		if l.threat + 2 > max_threat:
			overflow_vp_empire += (l.threat + 2 - max_threat)
			l.threat = max_threat
		else:
			l.threat += 2
	for h: HordeInstance in state.hordes:
		var card: LegionHordeCombatTable.CombatCard = LegionHordeCombatTable.get_card(h.card_name)
		var max_threat: int = card.max_threat if card != null else 7
		if h.threat + 2 > max_threat:
			overflow_vp_chaos += (h.threat + 2 - max_threat)
			h.threat = max_threat
		else:
			h.threat += 2
	state.empire_vp += overflow_vp_empire
	state.chaos_vp += overflow_vp_chaos

	# The first player reveals this Chapter's Event and resolves it, top to bottom.
	var event_name: String = str(state.chapter_events.get(state.chapter, ""))
	if not event_name.is_empty():
		var event_effects: GDScript = load("res://scripts/game/event_effects.gd")
		event_effects.resolve(state, card_db, event_name)

	var tokens_each: int = 2 if state.chapter >= state.max_chapters else 1
	for l: LegionInstance in state.legions:
		l.activation_tokens += tokens_each
	for h: HordeInstance in state.hordes:
		h.activation_tokens += tokens_each


static func _start_build_phase(state: GameState) -> void:
	for p: PlayerFactionState in state.players:
		p.has_passed = p.is_bot


static func _start_actions_phase(state: GameState) -> void:
	for p: PlayerFactionState in state.players:
		p.has_passed = p.is_bot or p.action_points <= 0
		p.has_acted_this_turn = false
	state.current_player_index = state.first_player_index


static func _nemesis_phase(state: GameState, card_db: Node) -> void:
	NemesisAI.run_nemesis_phase(state, card_db)
	# Combats normally happen during each activation (NemesisAI); this
	# sweep only catches hexes left contested some other way.
	for coord: Vector2i in state.hexes.keys().duplicate():
		if CombatResolver.hex_needs_combat(state, coord):
			CombatResolver.resolve_hex(state, coord, card_db)


## Rulebook p29: the player board's production for the current Haven
## count, plus each Haven hex's own printed resources (Hexes CSV
## Salt/Plunder/Food - Woods/Highlands 2 Plunder, Marshes/Badlands 2
## Food, Ice Waste 2 Salt, Home hexes 1 of each). Cursed hexes produce
## nothing.
static func _production_phase(state: GameState, card_db: Node) -> void:
	for p: PlayerFactionState in state.players:
		var haven_count: int = 0
		for tile: HexTileState in state.hexes.values():
			if tile.haven_faction == p.faction:
				haven_count += 1
		var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(p.faction)
		if board != null:
			var idx: int = mini(haven_count, board.production.size() - 1)
			var yield_: Dictionary = board.production[idx]
			p.salt += int(yield_.get("Salt", 0))
			p.plunder += int(yield_.get("Plunder", 0))
			p.food += int(yield_.get("Food", 0))
		for tile: HexTileState in state.hexes.values():
			if tile.haven_faction != p.faction:
				continue
			var bonus: Dictionary = EffectUtil.hex_production(tile, card_db)
			p.salt += int(bonus["Salt"])
			p.plunder += int(bonus["Plunder"])
			p.food += int(bonus["Food"])


static func check_win_loss(state: GameState) -> String:
	for p: PlayerFactionState in state.players:
		if state.empire_vp >= p.vp or state.chaos_vp >= p.vp:
			return "loss"
	return "win"
