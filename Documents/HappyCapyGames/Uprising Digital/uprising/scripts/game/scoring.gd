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
	state.empire_vp += _graveyard_vp(state, state.imperial_graveyard)
	state.imperial_graveyard.clear()


static func _score_chaos(state: GameState) -> void:
	var curse_count: int = 0
	for tile: HexTileState in state.hexes.values():
		if tile.curse:
			curse_count += 1
	state.chaos_vp += curse_count
	state.chaos_vp += state.hordes.size()
	state.chaos_vp += _graveyard_vp(state, state.chaos_graveyard)
	state.chaos_graveyard.clear()
	# Units in either Graveyard return to their reserves.
	for p: PlayerFactionState in state.players:
		p.graveyard_units.clear()


## 2 VP per faction in the Graveyard; True Solo Mode (rulebook p79) counts
## Units instead - 1 VP each, 2 on Nightmare and Apocalypse.
static func _graveyard_vp(state: GameState, yard: Dictionary) -> int:
	if not state.solo:
		return 2 * yard.size()
	var units: int = 0
	for f: Variant in yard.keys():
		units += int(yard[f])
	var each: int = 2 if state.difficulty == "Nightmare" or state.difficulty == "Apocalypse" else 1
	return units * each


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
	if state.chapter >= state.max_chapters:
		_buy_vp_with_resources(state)


## "Players may now spend any 5 resources for 1 VP, without limit, and give
## each VP to any 1 faction. This is normally done on the last Chapter."
## Done automatically on the last Chapter: the richest player pays, the
## player with the fewest VP receives (everyone must beat the Nemesis).
static func _buy_vp_with_resources(state: GameState) -> void:
	for _guard: int in range(500):
		var payer: PlayerFactionState = null
		for p: PlayerFactionState in state.players:
			if p.salt + p.plunder + p.food >= 5 and (payer == null or p.salt + p.plunder + p.food > payer.salt + payer.plunder + payer.food):
				payer = p
		if payer == null:
			return
		for _i: int in range(5):
			if payer.salt >= payer.plunder and payer.salt >= payer.food and payer.salt > 0:
				payer.salt -= 1
			elif payer.plunder >= payer.food and payer.plunder > 0:
				payer.plunder -= 1
			else:
				payer.food -= 1
		var poorest: PlayerFactionState = state.players[0]
		for p2: PlayerFactionState in state.players:
			if p2.vp < poorest.vp:
				poorest = p2
		poorest.vp += 1


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
