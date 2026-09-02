class_name ChapterFlow
extends RefCounted

## The 7-phase Chapter sequencer (rulebook p10, 15-31): Refresh -> Events
## -> Build -> Actions -> Nemesis -> Production -> Scoring, looping for
## max_chapters, then game ends. advance_phase() is the single entry point
## - it enforces the readiness gates (Build/Actions don't advance until
## every active player is done) and calls the per-phase step functions.
##
## Scope for this pass, documented: Event card effect TEXT is not
## resolved (no EventEffectPrograms exist yet - Milestone 3's
## transcription order was Hexes first; Events/Quests/Feats/Items are
## follow-up work) - only the mechanical Threat+2 and Activation-Token
## steps run automatically. The "deal 3 new Items/Quests" Refresh Phase
## step is skipped since GameState has no separate "market row"/"quest
## board" concept yet (GameActions.market/quest already documented this
## same gap).

static func advance_phase(state: GameState, card_db: Node) -> Dictionary:
	match state.phase:
		GameState.Phase.REFRESH:
			_refresh_phase(state)
			state.phase = GameState.Phase.EVENTS
			return {"ok": true}
		GameState.Phase.EVENTS:
			_events_phase(state)
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
			_nemesis_phase(state, card_db)
			return {"ok": true}
		GameState.Phase.NEMESIS:
			state.phase = GameState.Phase.PRODUCTION
			_production_phase(state)
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


static func _refresh_phase(state: GameState) -> void:
	var gained: Array[String] = DruidConditions.apply_refresh_phase(state)
	for p: PlayerFactionState in state.players:
		p.action_points = p.max_action_points
		p.has_passed = false
		p.has_acted_this_turn = false
	if state.players.size() > 0 and state.chapter > 1:
		state.first_player_index = (state.first_player_index + 1) % state.players.size()
	state.current_player_index = state.first_player_index
	state.phase_log = "Refresh: Aether placed on %s" % [gained] if not gained.is_empty() else "Refresh: no Aether conditions met"


static func _events_phase(state: GameState) -> void:
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

	# TODO (Milestone 4 follow-up): reveal + resolve state.chapter's Event
	# card here once EventEffectPrograms exist (Milestone 3 transcribed
	# Hexes only). Event-triggered Legion/Horde spawns are also deferred.

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
	# Resolve combat at every hex where a player faction shares space with
	# Garrison/Skeleton/Legion/Horde (NemesisAI flags these via
	# phase_log during movement, but the authoritative check is simply
	# "any hex with both player Units and Nemesis presence").
	for coord: Vector2i in state.hexes.keys().duplicate():
		var tile: HexTileState = state.hexes.get(coord)
		if tile == null:
			continue
		var has_player: bool = false
		for v: Variant in tile.units.values():
			if int(v) > 0:
				has_player = true
				break
		if not has_player:
			continue
		var has_nemesis: bool = tile.garrison_level > 0 or tile.skeleton_count > 0
		if not has_nemesis:
			for l: LegionInstance in state.legions:
				if l.coord == coord:
					has_nemesis = true
					break
		if not has_nemesis:
			for h: HordeInstance in state.hordes:
				if h.coord == coord:
					has_nemesis = true
					break
		if has_nemesis:
			CombatResolver.resolve_hex(state, coord, card_db)


static func _production_phase(state: GameState) -> void:
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
			if tile.haven_faction != p.faction or tile.curse:
				continue
			p.salt += _terrain_bonus(tile, "Salt")
			p.plunder += _terrain_bonus(tile, "Plunder")
			p.food += _terrain_bonus(tile, "Food")


## Rulebook: Woods/Highlands -> 2 Plunder, Marsh/Badlands -> 2 Food,
## Ice Waste -> 2 Salt (per-hex bonus, verified against the sampled Hexes
## CSV's own Terrain column values during Milestone 3, not hardcoded
## blind - hex_card_name lookup is needed for the real terrain, but
## HexTileState doesn't carry terrain directly; this is a placeholder
## no-op until terrain is threaded through HexTileState (Milestone 4
## follow-up) rather than silently guessing.
static func _terrain_bonus(_tile: HexTileState, _resource: String) -> int:
	return 0


static func check_win_loss(state: GameState) -> String:
	for p: PlayerFactionState in state.players:
		if state.empire_vp >= p.vp or state.chaos_vp >= p.vp:
			return "loss"
	return "win"
