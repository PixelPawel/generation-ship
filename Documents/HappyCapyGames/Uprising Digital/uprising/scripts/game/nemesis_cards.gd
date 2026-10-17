extends RefCounted

## Per-card powers of the 16 Core Legions and Hordes, transcribed from the
## Immediate / Combat / Bolt / On destroy columns of Legions.csv and
## Hordes.csv. Loaded by NemesisAI (preload, no class_name).
##
## Choices the cards leave to "the acting player" follow NemesisAI.pick_hex
## and the cheapest-loss rule CombatResolver uses. Feats aren't tracked as
## real cards yet, so effects that flip or discard Feats are logged only.

const QUEST_FLOW_PATH := "res://scripts/game/quest_flow.gd"
const CardAbilitiesRef := preload("res://scripts/game/card_abilities.gd")


# --- Immediate effects (resolved when the card enters play) -----------------

static func legion_immediate(state: GameState, card_db: Node, legion: LegionInstance) -> void:
	var target_player: PlayerFactionState = state.find_player(legion.target_faction)
	match legion.card_name:
		"The Courtesan":
			# Dark Lullaby: the player with her Target discards 1 AP for the rest of the game.
			if target_player != null:
				target_player.max_action_points = maxi(0, target_player.max_action_points - 1)
				target_player.action_points = maxi(0, target_player.action_points - 1)
				NemesisAI.log_line(state, "Dark Lullaby: %s loses 1 AP for the rest of the game" % target_player.faction)
		"The Warlock":
			# Netherwalker: the player with his Target flips all their Items.
			if target_player != null:
				for it: String in target_player.items_in_hand:
					if not target_player.flipped_items.has(it):
						target_player.flipped_items.append(it)
				NemesisAI.log_line(state, "Netherwalker: %s's Items are flipped" % target_player.faction)
		"The Spymaster":
			# Spy Network: flip the most expensive Market Items until he is destroyed.
			var top: int = -1
			for it: String in state.item_market:
				top = maxi(top, GameActions.item_cost(card_db, it))
			for it: String in state.item_market:
				if GameActions.item_cost(card_db, it) == top and not state.flipped_market.has(it):
					state.flipped_market.append(it)
			NemesisAI.log_line(state, "Spy Network: %s flipped on the Market" % [state.flipped_market])
		"The Assassin":
			# Imperial Bounty: the targeted player flips their starting Feats; 1 Activation Token on her.
			legion.activation_tokens += 1
			if target_player != null:
				for f: String in target_player.feats_in_play:
					if CardAbilitiesRef.START_FEATS.has(f):
						CardAbilitiesRef.flip(target_player, f)
				NemesisAI.log_line(state, "Imperial Bounty: %s flips their starting Feats" % target_player.faction)
		"The Imperial Guard":
			# Defensive Stance: 1 Garrison on every hex with a Garrison, except The Capital.
			var stacks: Array[Vector2i] = []
			for coord: Vector2i in state.hexes.keys():
				var t: HexTileState = state.hexes[coord]
				if t.garrison_level > 0 and t.role != "capital":
					stacks.append(coord)
			for coord2: Vector2i in stacks:
				NemesisAI.add_garrisons(state, coord2, 1)
		"The Mage Breaker":
			# Arcane Hunger: remove 1 Sea Tower (empty if possible); she stands there.
			var spot: Vector2i = remove_a_sea_tower(state, card_db)
			if spot != Vector2i.MIN:
				legion.coord = spot
		"The Executioner":
			# Come out and Play: every player sends 1 Elite Unit (play or reserve) to the Imperial Graveyard.
			for p: PlayerFactionState in state.players:
				send_unit_to_graveyard(state, p, "Empire", true)
		"The New Emperor":
			# Imperial March: activate EVERY Legion, no Activation Token needed.
			var all: Array = state.legions.duplicate()
			all.sort_custom(func(a: Variant, b: Variant) -> bool:
				return NemesisAI.initiative(a.card_name) < NemesisAI.initiative(b.card_name))
			for l: Variant in all:
				NemesisAI.activate_now(state, card_db, l)


static func horde_immediate(state: GameState, card_db: Node, horde: HordeInstance) -> void:
	match horde.card_name:
		"Lichqueen":
			# Demonic Stench: 1 Curse on her hex.
			NemesisAI.place_curse_on(state, card_db, horde.coord)
		"Coven of Yssat":
			# Nightmarish Waltz: every player parks 1 unused AP here until she is destroyed.
			for p: PlayerFactionState in state.players:
				if p.action_points > 0:
					p.action_points -= 1
					p.max_action_points = maxi(0, p.max_action_points - 1)
					state.coven_held_ap[p.faction] = int(state.coven_held_ap.get(p.faction, 0)) + 1
		"Counter of Omens":
			# Army of Bone: 2 Skeletons on his hex.
			NemesisAI.add_skeletons(state, card_db, horde.coord, 2)
		"Bloodwyrm":
			# Shattering Roar: 1 Curse on any hex with no X (an empty one, away from Havens).
			var spots: Array[Vector2i] = []
			for coord: Vector2i in state.hexes.keys():
				var t: HexTileState = state.hexes[coord]
				if NemesisAI.no_x(t) and not t.curse:
					spots.append(coord)
			var empties: Array[Vector2i] = []
			for c: Vector2i in spots:
				if EffectUtil.hex_is_empty(state, c):
					empties.append(c)
			var pick: Vector2i = NemesisAI.pick_hex(state, empties if not empties.is_empty() else spots)
			if pick != Vector2i.MIN:
				NemesisAI.place_curse_on(state, card_db, pick)
			else:
				state.chaos_vp += 1
		"Siren":
			# Call of the Wild: the Heroes with the lowest Guile stand on her hex
			# (True Solo: an allied Hero counts on its own - tied, both go).
			var lowest: int = 999
			for p: PlayerFactionState in state.players:
				lowest = mini(lowest, _attr(card_db, p, "guile"))
				if p.has_ally():
					p.swap_heroes()
					lowest = mini(lowest, _attr(card_db, p, "guile"))
					p.swap_heroes()
			for p2: PlayerFactionState in state.players:
				if _attr(card_db, p2, "guile") == lowest:
					p2.hero_coord = horde.coord
				if p2.has_ally():
					p2.swap_heroes()
					if _attr(card_db, p2, "guile") == lowest:
						p2.hero_coord = horde.coord
					p2.swap_heroes()
		"Banished":
			# Primordial Pleasures: Threat 5, then 1 Quest's failure effect.
			horde.threat = 5
			if not state.quest_row.is_empty():
				var quest_flow: GDScript = load(QUEST_FLOW_PATH)
				var acting: String = state.players[state.first_player_index % state.players.size()].faction if not state.players.is_empty() else ""
				quest_flow.resolve_failure(state, card_db, state.quest_row[0], acting)
		"False Messiah":
			# A Cult Rising: onto the Haven with the most Units; with no Units on
			# any Haven (the start of the game) onto a Sea Tower. Ties: the players choose.
			var most: int = 0
			var ties: Array[Vector2i] = []
			var coords: Array = state.hexes.keys()
			coords.sort()
			for coord: Vector2i in coords:
				var t: HexTileState = state.hexes[coord]
				if t.haven_faction.is_empty() or t.total_player_units() == 0:
					continue
				if t.total_player_units() > most:
					most = t.total_player_units()
					ties.clear()
				if t.total_player_units() == most:
					ties.append(coord)
			var best: Vector2i = Vector2i.MIN
			if not ties.is_empty():
				best = NemesisAI.choose_spawn_hex(state, ties, "The False Messiah goes to the Haven with the most Units: which one?")
			else:
				best = choose_sea_tower(state, true, "No Units on any Haven: put the False Messiah on a Sea Tower")
			if best != Vector2i.MIN:
				horde.coord = best
		"Oda the Fallen":
			# Doomsday: +2 Threat to Oda, +1 to every other Horde and Legion.
			NemesisAI.add_threat(state, horde, 2)
			for l: LegionInstance in state.legions:
				NemesisAI.add_threat(state, l, 1)
			for h: HordeInstance in state.hordes:
				if h != horde:
					NemesisAI.add_threat(state, h, 1)


## The Mage Breaker: "Every time she retargets, remove 1 Sea Tower from the game."
static func on_retarget(state: GameState, card_db: Node, legion: LegionInstance) -> void:
	if legion.card_name == "The Mage Breaker":
		remove_a_sea_tower(state, card_db)


# --- Helpers shared with combat and Events --------------------------------

## Removes one Sea Tower tile from the game - an empty one if possible -
## leaving a bare Region space; returns where, or Vector2i.MIN if none.
static func remove_a_sea_tower(state: GameState, card_db: Node) -> Vector2i:
	var spot: Vector2i = pick_sea_tower(state, true)
	if spot == Vector2i.MIN:
		return spot
	var tile: HexTileState = state.hexes[spot]
	NemesisAI.remove_haven(state, card_db, spot)
	tile.role = "outer"
	tile.hex_card_name = ""
	tile.explored = true
	tile.rotation = 0
	NemesisAI.log_line(state, "a Sea Tower on %s is removed from the game" % spot)
	return spot


## A Sea Tower hex, empty ones first when `prefer_empty`.
## A Sea Tower for a Horde or Legion - an empty one when `prefer_empty`
## and there is one - the players choosing which (decisions.gd).
static func choose_sea_tower(state: GameState, prefer_empty: bool, prompt: String) -> Vector2i:
	var towers: Array[Vector2i] = []
	var empty_towers: Array[Vector2i] = []
	for coord: Vector2i in state.hexes.keys():
		if (state.hexes[coord] as HexTileState).role == "sea_tower":
			towers.append(coord)
			if EffectUtil.hex_is_empty(state, coord):
				empty_towers.append(coord)
	var options: Array[Vector2i] = empty_towers if prefer_empty and not empty_towers.is_empty() else towers
	return NemesisAI.choose_spawn_hex(state, options, prompt)


static func pick_sea_tower(state: GameState, prefer_empty: bool) -> Vector2i:
	var towers: Array[Vector2i] = []
	var empty_towers: Array[Vector2i] = []
	for coord: Vector2i in state.hexes.keys():
		if (state.hexes[coord] as HexTileState).role == "sea_tower":
			towers.append(coord)
			if EffectUtil.hex_is_empty(state, coord):
				empty_towers.append(coord)
	if prefer_empty and not empty_towers.is_empty():
		return NemesisAI.pick_hex(state, empty_towers)
	return NemesisAI.pick_hex(state, towers)


## Puts one of `p`'s Units into a Graveyard ("Empire" = Imperial, "Chaos"):
## from the reserve if one is free, else the cheapest from play; Elites
## only when `elite`. Returns false if the faction had none to give.
static func send_unit_to_graveyard(state: GameState, p: PlayerFactionState, graveyard: String, elite: bool) -> bool:
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(p.faction)
	if board == null:
		return false
	var candidates: Array[PlayerboardTable.UnitEntry] = []
	for u: PlayerboardTable.UnitEntry in board.units:
		if u.is_basic() != elite:
			candidates.append(u)
	candidates.sort_custom(func(a: PlayerboardTable.UnitEntry, b: PlayerboardTable.UnitEntry) -> bool:
		return CombatResolver._cost_total(a.cost) < CombatResolver._cost_total(b.cost))
	for u: PlayerboardTable.UnitEntry in candidates:
		if reserve_left(state, p, u.name) > 0:
			_to_graveyard(state, p, u.name, graveyard)
			return true
	for u: PlayerboardTable.UnitEntry in candidates:
		for coord: Vector2i in state.hexes.keys():
			var t: HexTileState = state.hexes[coord]
			if int(t.unit_stack(p.faction).get(u.name, 0)) > 0:
				t.remove_unit(p.faction, u.name)
				_to_graveyard(state, p, u.name, graveyard)
				return true
	return false


static func _to_graveyard(state: GameState, p: PlayerFactionState, unit_name: String, graveyard: String) -> void:
	var yard: Dictionary = state.imperial_graveyard if graveyard == "Empire" else state.chaos_graveyard
	yard[p.faction] = int(yard.get(p.faction, 0)) + 1
	p.graveyard_units[unit_name] = int(p.graveyard_units.get(unit_name, 0)) + 1
	NemesisAI.log_line(state, "%s %s goes to the %s Graveyard" % [p.faction, unit_name, "Imperial" if graveyard == "Empire" else "Chaos"])


## Copies of a Unit type still in the faction's reserve: printed count minus
## those on the map, those in a Graveyard and those removed from the game.
static func reserve_left(state: GameState, p: PlayerFactionState, unit_name: String) -> int:
	var entry: PlayerboardTable.UnitEntry = PlayerboardTable.get_unit(p.faction, unit_name)
	if entry == null:
		return 0
	var used: int = int(p.graveyard_units.get(unit_name, 0)) + int(p.removed_units.get(unit_name, 0))
	for t: HexTileState in state.hexes.values():
		used += int(t.unit_stack(p.faction).get(unit_name, 0))
	return maxi(0, entry.reserve_size - used)


static func _attr(card_db: Node, p: PlayerFactionState, attr: String) -> int:
	return EffectUtil.hero_attr(card_db, p, attr)
