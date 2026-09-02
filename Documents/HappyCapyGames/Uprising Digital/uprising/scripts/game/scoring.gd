class_name Scoring
extends RefCounted

## Scoring Phase (rulebook p30-31). Garrison/Skeleton-kill VP and Legion/
## Horde on-destroy VP are awarded immediately during combat
## (CombatResolver), not here - this only handles the once-per-Chapter
## tallies.

static func score_chapter(state: GameState, card_db: Node) -> void:
	_score_empire(state)
	_score_chaos(state)
	_score_players(state, card_db)


static func _score_empire(state: GameState) -> void:
	var hexes_with_garrison: int = 0
	for tile: HexTileState in state.hexes.values():
		if tile.garrison_level > 0:
			hexes_with_garrison += 1
	state.empire_vp += hexes_with_garrison
	state.empire_vp += state.legions.size()
	state.empire_vp += 2 * state.imperial_graveyard.size()
	state.imperial_graveyard.clear()


static func _score_chaos(state: GameState) -> void:
	var curse_count: int = 0
	for tile: HexTileState in state.hexes.values():
		if tile.curse:
			curse_count += 1
	state.chaos_vp += curse_count
	state.chaos_vp += state.hordes.size()
	state.chaos_vp += 2 * state.chaos_graveyard.size()
	state.chaos_graveyard.clear()


static func _score_players(state: GameState, card_db: Node) -> void:
	for p: PlayerFactionState in state.players:
		var haven_count: int = 0
		var bonus_vp: int = 0
		for tile: HexTileState in state.hexes.values():
			if tile.haven_faction != p.faction:
				continue
			haven_count += 1
			if _hex_has_bonus_vp(tile, card_db):
				bonus_vp += 1
		p.vp += 2 * haven_count + bonus_vp


## Parses the Hex CSV's free-text "Special" column (e.g. "1 VP", "1 VP to
## all") for a bonus-VP icon - simple substring check rather than a full
## EffectProgram, since this is a static per-hex-card property, not a
## triggered effect.
static func _hex_has_bonus_vp(tile: HexTileState, card_db: Node) -> bool:
	if tile.hex_card_name.is_empty():
		return false
	for h: HexCard in card_db.hexes_all:
		if h.card_name == tile.hex_card_name and h.lang == "EN":
			return h.special.findn("VP") != -1
	return false
