class_name DruidData
extends RefCounted
## Each Core Druid's "Refresh Phase" condition (assets/data/UPRISING _ FULL
## CARD DETAILS - Druids.csv, EN rows), hardcoded per-name -- the 9
## conditions are heterogeneous free text referencing different game facts,
## but each is just a boolean check -> fixed "+1 AETHER" effect, so this is
## the "structured enough to hardcode" exception to the project's default
## manual/assisted handling of card text.
##
## "equal or more VP than any player" (Faceless One/Shapeshifter) reads as
## EXISTENTIAL -- true as soon as Chaos/Empire is at or above the LOWEST
## player's VP -- as opposed to Silence's explicitly-capitalized "more VP
## than ALL players", a universal condition that must clear the HIGHEST
## player's VP. The deliberate any/ALL contrast within the same card set is
## the textual basis for reading "any" as "there exists" rather than "every".


static func check_condition(card_name: String, state: GameState) -> bool:
	match card_name:
		"Deep Dweller":
			return state.hordes.size() >= 1
		"Faceless One":
			for player in state.players:
				if state.chaos_vp >= player.victory_points:
					return true
			return false
		"Mountain Heart":
			return state.legions.size() >= 1
		"Red Hand":
			return _count_skeletons(state) >= 5
		"Shapeshifter":
			for player in state.players:
				if state.empire_vp >= player.victory_points:
					return true
			return false
		"Silence":
			var max_vp := _max_player_vp(state)
			return state.empire_vp > max_vp or state.chaos_vp > max_vp
		"Treemother":
			for player in state.players:
				if _count_units(state, player.faction) == 0:
					return true
			return false
		"Wanderer":
			return _count_curses(state) >= 5
		"Watcher":
			return _count_garrisons(state) >= 7
		_:
			return false


static func _max_player_vp(state: GameState) -> int:
	var max_vp := 0
	for player in state.players:
		max_vp = maxi(max_vp, player.victory_points)
	return max_vp


static func _count_skeletons(state: GameState) -> int:
	var total := 0
	for k in state.hexes:
		total += (state.hexes[k] as HexTile).skeleton_count
	return total


static func _count_curses(state: GameState) -> int:
	var total := 0
	for k in state.hexes:
		if (state.hexes[k] as HexTile).has_curse:
			total += 1
	return total


static func _count_garrisons(state: GameState) -> int:
	var total := 0
	for k in state.hexes:
		if (state.hexes[k] as HexTile).garrison_level > 0:
			total += 1
	return total


static func _count_units(state: GameState, faction: String) -> int:
	var total := 0
	for k in state.hexes:
		var tile := state.hexes[k] as HexTile
		total += (tile.units.get(faction, []) as Array).size()
	return total
