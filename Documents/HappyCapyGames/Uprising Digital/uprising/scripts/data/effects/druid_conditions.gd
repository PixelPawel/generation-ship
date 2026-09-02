class_name DruidConditions
extends RefCounted

## Hand-transcribed Refresh Phase Æther conditions for all 9 Core Druids
## (assets/data/UPRISING _ FULL CARD DETAILS - Druids.csv, "Refresh Phase"
## column, EN rows - quoted verbatim per Druid below). Rulebook p15: each
## Refresh Phase, check every in-play Druid's own condition and place 1
## Æther on it if met (stops once the shared 7-token pool is empty).
##
## Two Druids (Faceless One vs. Shapeshifter) use an EXISTENTIAL "equal or
## more VP than ANY one player" comparison, while a third (Silence) uses a
## different, stronger UNIVERSAL "more VP than ALL players" comparison -
## easy to conflate if not kept as explicit, separate predicate modes (see
## EffectUtil.nemesis_vp_meets_players's own doc comment on this).

static func check(card_name: String, state: GameState) -> bool:
	var predicate: Callable = _PREDICATES.get(card_name, Callable())
	if not predicate.is_valid():
		push_warning("DruidConditions: no condition transcribed for '%s'" % card_name)
		return false
	return bool(predicate.call(state))


static func has_condition(card_name: String) -> bool:
	return _PREDICATES.has(card_name)


## Refresh Phase step: check every in-play Druid, place 1 Æther on each
## whose condition is met, stopping once the shared pool is empty.
## Returns the list of Druid names that gained Æther (for logging/UI).
static func apply_refresh_phase(state: GameState) -> Array[String]:
	var gained: Array[String] = []
	for d: DruidInstance in state.druids_in_play:
		if state.aether_pool <= 0:
			break
		if check(d.card_name, state):
			d.aether += 1
			state.aether_pool -= 1
			gained.append(d.card_name)
	return gained


static var _PREDICATES: Dictionary = {
	# "If there is 1+ Horde in play, place 1 AETHER here."
	"Deep Dweller": func(state: GameState) -> bool: return state.hordes.size() >= 1,

	# "If Chaos has equal or more VP than any player place 1 AETHER here."
	"Faceless One": func(state: GameState) -> bool: return EffectUtil.nemesis_vp_meets_players(state.chaos_vp, state, "existential_gte"),

	# "If there is 1+ Legion in play, place 1 AETHER here."
	"Mountain Heart": func(state: GameState) -> bool: return state.legions.size() >= 1,

	# "If there are 5+ Skeletons on hexes place 1 AETHER here."
	"Red Hand": func(state: GameState) -> bool: return _total_skeletons(state) >= 5,

	# "If The Empire has equal or more VP than any player place 1 AETHER here."
	"Shapeshifter": func(state: GameState) -> bool: return EffectUtil.nemesis_vp_meets_players(state.empire_vp, state, "existential_gte"),

	# "If the Empire OR Chaos has more VP than ALL players, place 1 AETHER here."
	"Silence": func(state: GameState) -> bool:
		return EffectUtil.nemesis_vp_meets_players(state.empire_vp, state, "universal_gt") \
			or EffectUtil.nemesis_vp_meets_players(state.chaos_vp, state, "universal_gt"),

	# "If any player has ZERO Units in play, place 1 AETHER here."
	"Treemother": func(state: GameState) -> bool:
		for p: PlayerFactionState in state.players:
			if _total_units(state, p.faction) == 0:
				return true
		return false,

	# "If there are 5+ Curses on hexes, place 1 AETHER here."
	"Wanderer": func(state: GameState) -> bool: return _total_curses(state) >= 5,

	# "If there are 7+ hexes with Garrisons, place 1 AETHER here."
	"Watcher": func(state: GameState) -> bool: return _hexes_with_garrisons(state) >= 7,
}


static func _total_skeletons(state: GameState) -> int:
	var total: int = 0
	for tile: HexTileState in state.hexes.values():
		total += tile.skeleton_count
	return total


static func _total_curses(state: GameState) -> int:
	var total: int = 0
	for tile: HexTileState in state.hexes.values():
		if tile.curse:
			total += 1
	return total


static func _hexes_with_garrisons(state: GameState) -> int:
	var total: int = 0
	for tile: HexTileState in state.hexes.values():
		if tile.garrison_level > 0:
			total += 1
	return total


static func _total_units(state: GameState, faction: String) -> int:
	var total: int = 0
	for tile: HexTileState in state.hexes.values():
		total += int(tile.units.get(faction, 0))
	return total
