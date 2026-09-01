class_name Scoring
extends RefCounted
## End-of-Chapter scoring (rulebook p30). Fully specified in the rulebook --
## unlike Combat/Quest resolution, nothing here is blocked on missing data.
##
## NOT included (deliberately): the "spend any 5 resources for 1 VP" option
## is a player choice, not an automatic calculation -- that belongs as a
## GameActions action type of its own, not something score_chapter() does
## for you.


## Computes and APPLIES this Chapter's scoring to `state` (VP totals are
## mutated in place, Graveyards are cleared per the rules -- "return to
## reserve" after scoring). Returns the VP deltas for display purposes.
static func score_chapter(state: GameState, card_db: Node) -> Dictionary:
	var empire_delta := _score_empire(state)
	var chaos_delta := _score_chaos(state)
	var player_deltas := {}
	for player in state.players:
		player_deltas[player.faction] = _score_player(state, player, card_db)

	state.empire_vp += empire_delta
	state.chaos_vp += chaos_delta
	for player in state.players:
		player.victory_points += int(player_deltas[player.faction])

	state.imperial_graveyard.clear()
	state.chaos_graveyard.clear()

	return {"empire": empire_delta, "chaos": chaos_delta, "players": player_deltas}


## Rulebook p30: 1 VP per hex with any Garrisons, 1 VP per Legion in play,
## 2 VP per player faction represented in the Imperial Graveyard.
static func _score_empire(state: GameState) -> int:
	var vp := 0
	for key in state.hexes:
		var t: HexTile = state.hexes[key]
		if t.garrison_level > 0:
			vp += 1
	vp += state.legions.size()
	vp += _factions_represented(state.imperial_graveyard) * 2
	return vp


## Rulebook p30: 1 VP per Curse on the map, 1 VP per Horde in play, 2 VP per
## player faction represented in the Chaos Graveyard.
static func _score_chaos(state: GameState) -> int:
	var vp := 0
	for key in state.hexes:
		var t: HexTile = state.hexes[key]
		if t.has_curse:
			vp += 1
	vp += state.hordes.size()
	vp += _factions_represented(state.chaos_graveyard) * 2
	return vp


static func _factions_represented(graveyard: Dictionary) -> int:
	var count := 0
	for faction in graveyard:
		if int(graveyard[faction]) > 0:
			count += 1
	return count


## Rulebook p30: 2 VP per Haven the faction has, plus any hex-printed VP
## bonus ("Special" column, e.g. "1 VP") for hexes where they have a Haven.
static func _score_player(state: GameState, player: PlayerFactionState, card_db: Node) -> int:
	var vp := player.havens.size() * 2
	for coord in player.havens:
		var tile := state.get_hex(coord)
		if tile != null:
			vp += _hex_vp_bonus(tile, card_db)
	return vp


static func _hex_vp_bonus(tile: HexTile, card_db: Node) -> int:
	if card_db == null or tile.card_name == "":
		return 0
	for h in card_db.hexes:
		if h.lang == "EN" and h.card_name == tile.card_name:
			return _parse_vp(h.special)
	return 0


## `special` is free text on the hex card ("1 VP", "1 VP to all", "1 Aether",
## "-"). Only extracts a literal "<N> VP" bonus; doesn't attempt to interpret
## qualifiers like "to all" (only ever seen once in the source data, not
## common enough to be confident about the exact intended rule).
static func _parse_vp(special: String) -> int:
	var regex := RegEx.new()
	regex.compile("(\\d+)\\s*VP")
	var m := regex.search(special)
	if m:
		return int(m.get_string(1))
	return 0
