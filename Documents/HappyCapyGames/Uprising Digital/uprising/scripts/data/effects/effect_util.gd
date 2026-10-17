class_name EffectUtil
extends RefCounted

## Shared predicates/helpers used by multiple EffectOps - kept here rather
## than duplicated per-op.

## Rulebook p50: "empty" = no other Units at all (Garrison/Skeleton/Legion/
## Horde/player Units - Heroes don't count).
static func hex_is_empty_of_units(state: GameState, coord: Vector2i) -> bool:
	var tile: HexTileState = state.get_hex(coord)
	if tile != null:
		if tile.total_player_units() > 0:
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


## EN HexCard for a hex's card name, null if unknown (e.g. "" for an
## unrevealed region hex).
static func hex_card(card_db: Node, card_name: String) -> HexCard:
	if card_db == null or card_name.is_empty():
		return null
	for h: HexCard in card_db.hexes_all:
		if h.card_name == card_name and h.lang == "EN":
			return h
	return null


## Terrain that applies to combat on this hex (rulebook p14, p42, p49):
## "" when it has none - unexplored hexes show no terrain, The Capital has
## no terrain type - and "Curse" when Cursed, which replaces the printed
## terrain. Otherwise the HexCard's Terrain column ("Woods", "Highlands",
## "Marshes", "Badlands", "Ice Waste"). Outer region hexes carry no card
## but are pre-explored Ice Waste.
static func combat_terrain(tile: HexTileState, card_db: Node) -> String:
	if tile == null:
		return ""
	if tile.curse:
		return "Curse"
	if tile.role == "capital":
		return ""
	if tile.role == "outer":
		return "Ice Waste"
	if not tile.explored:
		return ""
	var card: HexCard = hex_card(card_db, tile.hex_card_name)
	if card == null or card.terrain == "Capital":
		return ""
	return card.terrain


## Bonus resources a Haven on this hex yields in the Production Phase
## (rulebook p29), read from the Hexes CSV's Salt/Plunder/Food columns
## ("-" = 0): e.g. Woods/Highlands 2 Plunder, Home hexes 1/1/1, Sea
## Towers 2 Salt. A Cursed hex never produces.
static func hex_production(tile: HexTileState, card_db: Node) -> Dictionary:
	var out: Dictionary = {"Salt": 0, "Plunder": 0, "Food": 0}
	if tile == null or tile.curse:
		return out
	var card: HexCard = hex_card(card_db, tile.hex_card_name)
	if card == null:
		return out
	out["Salt"] = card.salt.to_int() if card.salt.is_valid_int() else 0
	out["Plunder"] = card.plunder.to_int() if card.plunder.is_valid_int() else 0
	out["Food"] = card.food.to_int() if card.food.is_valid_int() else 0
	return out


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
