class_name EffectUtil
extends RefCounted

## Shared predicates/helpers used by multiple EffectOps - kept here rather
## than duplicated per-op.

## Rulebook p50: "empty" = no other Units at all (Garrison/Skeleton/Legion/
## Horde/player Units - Heroes don't count).
static func hex_is_empty_of_units(state: GameState, coord: Vector2i) -> bool:
	var tile: HexTileState = state.get_hex(coord)
	if tile != null:
		if not tile.units.is_empty():
			return false
		if tile.garrison_level > 0:
			return false
		if tile.skeleton_count > 0:
			return false
	for l: LegionInstance in state.legions:
		if l.coord == coord:
			return false
	for h: HordeInstance in state.hordes:
		if h.coord == coord:
			return false
	return true


static func card_count_in_play(state: GameState, category: String) -> int:
	match category:
		"Legion":
			return state.legions.size()
		"Horde":
			return state.hordes.size()
	return 0


## Existential ("has equal or more VP than ANY player") vs universal
## ("has more VP than ALL players") comparisons - the two Druid conditions
## (Faceless One vs Silence) use different modes of the SAME comparison,
## easy to conflate if not kept as explicit, separate modes.
static func nemesis_vp_meets_players(nemesis_vp: int, state: GameState, mode: String) -> bool:
	if state.players.is_empty():
		return false
	match mode:
		"existential_gte":  # equal-or-more than ANY one player
			for p: PlayerFactionState in state.players:
				if nemesis_vp >= p.vp:
					return true
			return false
		"universal_gt":     # strictly more than ALL players
			for p: PlayerFactionState in state.players:
				if nemesis_vp <= p.vp:
					return false
			return true
	push_error("nemesis_vp_meets_players: unknown mode '%s'" % mode)
	return false
