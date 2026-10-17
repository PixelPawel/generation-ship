class_name GameActions
extends RefCounted

## Per-Action rules dispatcher, deliberately separate from NetworkManager
## so rules logic is testable without any networking (NetworkManager's
## action_handler just wraps GameActions.apply once a peer_id->faction
## lookup exists - Milestone 5's job). apply() returns {ok:bool,
## reason:String} matching NetworkManager's expected action_handler shape.
##
## Impassable terrain (rulebook p14, p20): Command never moves Units across
## an impassable edge (GameState.edge_blocked); Units on an explored Sea
## Tower count as adjacent to every hex, Netherwood's to every Sea Tower.
## The exploring player orients a freshly flipped hex with "orient" until
## their turn ends. Heroes may cross impassable terrain, but Hero position
## isn't tracked yet (see _move).

const AP_COST := 1
## Haven tokens on a player board (its production track runs 0-5 Havens).
const MAX_HAVENS := 5
const QUEST_FLOW_PATH := "res://scripts/game/quest_flow.gd"
const CardAbilities := preload("res://scripts/game/card_abilities.gd")
## Actions a single Hero takes. In True Solo Mode action["hero_slot"] =
## "ally" has the allied Hero take them; use_card always follows whoever
## owns the card.
const HERO_ACTIONS: Array[String] = ["move", "explore", "haven", "market", "quest", "pick_feat", "build_unit", "trade"]


static func apply(state: GameState, action: Dictionary, faction: String, card_db: Node) -> Dictionary:
	var actor: PlayerFactionState = state.find_player(faction)
	if actor == null or not actor.has_ally() or not _ally_acts(actor, action):
		return _apply(state, action, faction, card_db)
	# The allied Hero acts: swap it into the main Hero's fields for the
	# action, and whatever cards it gains on the way are its own.
	var before: Dictionary = {}
	for f: String in actor.feats_in_play:
		before[f] = true
	for it: String in actor.items_in_hand:
		before[it] = true
	actor.swap_heroes()
	var result: Dictionary = _apply(state, action, faction, card_db)
	for f2: String in actor.feats_in_play:
		if not before.has(f2):
			actor.claim_card(f2)
	for it2: String in actor.items_in_hand:
		if not before.has(it2):
			actor.claim_card(it2)
	actor.swap_heroes()
	return result


static func _ally_acts(p: PlayerFactionState, action: Dictionary) -> bool:
	var type: String = str(action.get("type", ""))
	if type == "use_card":
		return not p.card_is_acting_heros(str(action.get("card", "")))
	return HERO_ACTIONS.has(type) and str(action.get("hero_slot", "")) == "ally"


static func _apply(state: GameState, action: Dictionary, faction: String, card_db: Node) -> Dictionary:
	var type: String = str(action.get("type", ""))
	match type:
		"move":
			return _move(state, action, faction)
		"trade":
			return _trade(state, action, faction, card_db)
		"exchange":
			return _exchange(state, action, faction)
		"command":
			return _command(state, action, faction, card_db)
		"explore":
			return _explore(state, action, faction, card_db)
		"orient":
			return _orient(state, action, faction)
		"use_card":
			var user: PlayerFactionState = state.find_player(faction)
			if user == null:
				return {"ok": false, "reason": "unknown faction"}
			return CardAbilities.use_card(state, card_db, user, str(action.get("card", "")), action)
		"pick_feat":
			var picker: PlayerFactionState = state.find_player(faction)
			if picker == null or not CardAbilities.pick_feat(state, card_db, picker, str(action.get("feat", ""))):
				return {"ok": false, "reason": "pick one of the 2 Feats you drew"}
			return {"ok": true}
		"haven":
			return _haven(state, action, faction)
		"market":
			return _market(state, action, faction, card_db)
		"quest":
			return _quest(state, action, faction, card_db)
		"build_unit":
			return _build_unit(state, action, faction)
		"build_defense":
			return _build_defense(state, action, faction)
		"end_turn":
			return _end_turn(state, faction)
		"pass":
			return _pass(state, faction)
		"end_phase":
			# Any player may request the phase advance - ChapterFlow itself
			# enforces the real readiness gates (Build/Actions won't move
			# until every active player is done), so this isn't a
			# privilege-escalation risk despite not checking whose turn it is.
			return ChapterFlow.advance_phase(state, card_db)
	return {"ok": false, "reason": "unknown action type '%s'" % type}


static func is_players_turn(state: GameState, faction: String) -> bool:
	if state.phase != GameState.Phase.ACTIONS:
		return false
	if state.players.is_empty():
		return false
	var idx: int = state.current_player_index % state.players.size()
	return state.players[idx].faction == faction


static func active_players(state: GameState) -> Array[PlayerFactionState]:
	var out: Array[PlayerFactionState] = []
	for p: PlayerFactionState in state.players:
		if p.action_points > 0 and not p.has_passed:
			out.append(p)
	return out


# --- Move: 1 AP/hex, your turn only, does NOT end your turn. ---
## Rulebook p18: the Hero steps onto an adjacent hex - even an unexplored
## one, one with enemy Units, or across impassable terrain (Heroes may
## cross it, and never start combat). From an explored Sea Tower the Hero
## may move to any hex.
static func _move(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	var free: bool = p.wiles_ready
	if p.action_points < AP_COST and not free:
		return {"ok": false, "reason": "not enough AP"}
	var to: Vector2i = _coord(action, "to")
	if not state.hexes.has(to) or to == p.hero_coord:
		return {"ok": false, "reason": "pick another hex on the board"}
	var here: HexTileState = state.get_hex(p.hero_coord)
	var from_sea_tower: bool = here != null and here.role == "sea_tower" and here.explored
	var anywhere: bool = from_sea_tower or CardAbilities.hero_adjacent_everywhere(p)
	if HexMath.distance(p.hero_coord, to) != 1 and not anywhere:
		return {"ok": false, "reason": "your Hero can only Move to an adjacent hex"}
	p.hero_coord = to
	if free:
		p.wiles_ready = false  # Wiles: no AP
	else:
		p.action_points -= AP_COST
	state.phase_log = "%s moves their Hero to %s" % [faction, to]
	return {"ok": true}


# --- Trade: 1 AP -> 1 Salt, ALWAYS usable, any phase, doesn't end turn. ---
## Rulebook p19: "Gain 1 Salt. Heros here may give or take resources from
## each other, as well as any Item the receiving Hero could use."
## Optional: action["with"] = another faction whose Hero shares this hex,
## "give"/"take" = {"Salt": n, "Plunder": n, "Food": n}, "give_items"/
## "take_items" = [item names].
static func _trade(state: GameState, action: Dictionary, faction: String, card_db: Node = null) -> Dictionary:
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return {"ok": false, "reason": "unknown faction"}
	if p.action_points < AP_COST:
		return {"ok": false, "reason": "not enough AP"}
	var partner: PlayerFactionState = null
	if action.has("with"):
		partner = state.find_player(str(action["with"]))
		var near: bool = partner != null and (partner.hero_coord == p.hero_coord or (CardAbilities.trades_adjacent(p) and HexMath.distance(partner.hero_coord, p.hero_coord) == 1))
		if partner == null or partner == p or not near:
			return {"ok": false, "reason": "you can only trade with a Hero on your hex"}
		var give: Dictionary = action.get("give", {})
		var take: Dictionary = action.get("take", {})
		for res: String in ["Salt", "Plunder", "Food"]:
			if _res(p, res) < int(give.get(res, 0)) or _res(partner, res) < int(take.get(res, 0)):
				return {"ok": false, "reason": "not enough %s to trade" % res}
		for it: Variant in (action.get("give_items", []) as Array):
			if not p.items_in_hand.has(str(it)) or not hero_can_use_item(card_db, partner, str(it)):
				return {"ok": false, "reason": "'%s' can't be given" % it}
		for it2: Variant in (action.get("take_items", []) as Array):
			if not partner.items_in_hand.has(str(it2)) or not hero_can_use_item(card_db, p, str(it2)):
				return {"ok": false, "reason": "'%s' can't be taken" % it2}
		for res2: String in ["Salt", "Plunder", "Food"]:
			var n: int = int(give.get(res2, 0)) - int(take.get(res2, 0))
			_add_res(p, res2, -n)
			_add_res(partner, res2, n)
		for it3: Variant in (action.get("give_items", []) as Array):
			p.items_in_hand.erase(str(it3))
			partner.items_in_hand.append(str(it3))
		for it4: Variant in (action.get("take_items", []) as Array):
			partner.items_in_hand.erase(str(it4))
			p.items_in_hand.append(str(it4))
	# True Solo: hand Items between your own two Heroes ("swap_items").
	var handed: Array = action.get("swap_items", [])
	if not handed.is_empty():
		var together: bool = p.hero_coord == p.ally_coord or (CardAbilities.trades_adjacent(p) and HexMath.distance(p.hero_coord, p.ally_coord) == 1)
		if not p.has_ally() or not together:
			return {"ok": false, "reason": "your two Heroes must share a hex to hand over Items"}
		for it5: Variant in handed:
			if not p.items_in_hand.has(str(it5)):
				return {"ok": false, "reason": "'%s' isn't one of your Items" % it5}
			p.swap_heroes()  # the receiving Hero must be able to use it
			var usable: bool = hero_can_use_item(card_db, p, str(it5))
			p.swap_heroes()
			if not usable:
				return {"ok": false, "reason": "your other Hero can't use '%s'" % it5}
		for it6: Variant in handed:
			if p.ally_cards.has(str(it6)):
				p.ally_cards.erase(str(it6))
			else:
				p.ally_cards[str(it6)] = true
	p.action_points -= AP_COST
	p.salt += 1 + CardAbilities.trade_bonus(p)
	state.phase_log = "%s Trades%s" % [faction, " with %s" % partner.faction if partner != null else ""]
	return {"ok": true}


## "You may ALWAYS exchange 3 of the same resource for 1 other resource.
## This costs zero AP." (player boards, rulebook p17)
static func _exchange(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	var p: PlayerFactionState = state.find_player(faction)
	var give: String = str(action.get("give", ""))
	var get_res: String = str(action.get("get", ""))
	var kinds: Array[String] = ["Salt", "Plunder", "Food"]
	if p == null or not kinds.has(give) or not kinds.has(get_res) or give == get_res:
		return {"ok": false, "reason": "exchange 3 of one resource for 1 of another"}
	if _res(p, give) < 3:
		return {"ok": false, "reason": "you need 3 %s" % give}
	_add_res(p, give, -3)
	_add_res(p, get_res, 1)
	state.phase_log = "%s exchanges 3 %s for 1 %s" % [faction, give, get_res]
	return {"ok": true}


static func _res(p: PlayerFactionState, res: String) -> int:
	match res:
		"Salt":
			return p.salt
		"Plunder":
			return p.plunder
	return p.food


static func _add_res(p: PlayerFactionState, res: String, n: int) -> void:
	match res:
		"Salt":
			p.salt += n
		"Plunder":
			p.plunder += n
		"Food":
			p.food += n


# --- Command: 1 AP + 1 Food, gathers adjacent Units/Hero into target hex, ends turn. ---
## Rulebook p20-21: target must be explored and free of another player's
## Haven/Units; at most 5 Units end up there. Optional action["units"] =
## [{"from": {x,y}, "unit": name, "count": n}, ...] picks exactly what
## moves; without it every Unit on a neighboring hex moves in (Elites
## first) until the hex is full - never across impassable terrain, and
## Sea Tower Units only when picked explicitly. Entering a hex with
## enemies starts combat at once.
static func _command(state: GameState, action: Dictionary, faction: String, card_db: Node) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.has_acted_this_turn:
		return {"ok": false, "reason": "already took your one Action this turn"}
	var free_cmd: bool = p.wiles_ready
	var food_cost: int = 0 if free_cmd else CardAbilities.command_food_cost(p)
	if not free_cmd and (p.action_points < AP_COST or p.food < food_cost):
		return {"ok": false, "reason": "not enough AP/Food"}
	var compass: bool = bool(action.get("compass", false)) and CardAbilities.active(p, "Nethersea Compass")
	var target: Vector2i = _coord(action, "to")
	var target_tile: HexTileState = state.get_hex(target)
	if target_tile == null or not (target_tile.explored or target_tile.role == "outer"):
		return {"ok": false, "reason": "target hex is unexplored"}
	var other: String = target_tile.player_faction_here()
	if (not other.is_empty() and other != faction) or (not target_tile.haven_faction.is_empty() and target_tile.haven_faction != faction):
		return {"ok": false, "reason": "another faction's Haven/Units are there"}

	var moves: Array = []  # [coord, unit, count]
	if action.has("units"):
		for m: Variant in (action["units"] as Array):
			var md: Dictionary = m
			moves.append([_coord(md, "from"), str(md.get("unit", "")), int(md.get("count", 1))])
	else:
		for neighbor: Vector2i in HexMath.neighbors(target):
			var nt: HexTileState = state.get_hex(neighbor)
			if nt == null or state.edge_blocked(neighbor, target):
				continue
			var stack: Dictionary = nt.unit_stack(faction)
			var names: Array = stack.keys()
			names.sort_custom(func(x: Variant, y: Variant) -> bool:
				return _is_elite(faction, str(x)) and not _is_elite(faction, str(y)))
			for unit_name: Variant in names:
				moves.append([neighbor, str(unit_name), int(stack[unit_name])])

	for mv: Array in moves:
		if not compass and not can_command_from(state, mv[0], target):
			return {"ok": false, "reason": "Units on %s can't reach %s (not adjacent, or impassable terrain)" % [mv[0], target]}

	var moved: int = 0
	for mv: Array in moves:
		var from: Vector2i = mv[0]
		var ft: HexTileState = state.get_hex(from)
		if ft == null:
			continue
		var want: int = mini(int(mv[2]), int(ft.unit_stack(faction).get(mv[1], 0)))
		var added: int = target_tile.add_units(faction, mv[1], want)
		ft.remove_unit(faction, mv[1], added)
		moved += added

	# "...and/or your adjacent Hero" - only when asked (action["hero"]).
	var hero_moves: bool = bool(action.get("hero", false)) and p.hero_coord != target
	if hero_moves:
		var ht: HexTileState = state.get_hex(p.hero_coord)
		var hero_on_tower: bool = ht != null and ht.role == "sea_tower" and ht.explored
		if HexMath.distance(p.hero_coord, target) == 1 or hero_on_tower:
			p.hero_coord = target
		else:
			hero_moves = false
	# True Solo: Command can bring both Heroes into the hex (rulebook p78).
	var ally_moves: bool = bool(action.get("ally_hero", false)) and p.has_ally() and p.ally_coord != target
	if ally_moves:
		var at: HexTileState = state.get_hex(p.ally_coord)
		var ally_on_tower: bool = at != null and at.role == "sea_tower" and at.explored
		if HexMath.distance(p.ally_coord, target) == 1 or ally_on_tower:
			p.ally_coord = target
		else:
			ally_moves = false
	if ally_moves:
		hero_moves = true  # for the log line

	if free_cmd:
		p.wiles_ready = false
	else:
		p.action_points -= AP_COST
		p.food -= food_cost
	if compass:
		CardAbilities.discard(state, p, "Nethersea Compass")
	p.has_acted_this_turn = true
	state.phase_log = "%s Commands %d Unit(s)%s to %s" % [faction, moved, " and their Hero" if hero_moves else "", target]
	NemesisAI.resolve_combat_at(state, card_db, target)  # also The Capital's ongoing effect
	return {"ok": true}


## Can a player's Units on `from` be Commanded into `to`? Neighbors not
## separated by impassable terrain; Units on an explored Sea Tower are
## adjacent to any hex (rulebook p18, p21), Units on an explored
## Netherwood to any Sea Tower (its ongoing effect).
static func can_command_from(state: GameState, from: Vector2i, to: Vector2i) -> bool:
	var ft: HexTileState = state.get_hex(from)
	if ft == null or from == to:
		return false
	if ft.role == "sea_tower" and ft.explored:
		return true
	var tt: HexTileState = state.get_hex(to)
	if ft.explored and ft.hex_card_name == "Netherwood" and tt != null and tt.role == "sea_tower":
		return true
	return HexMath.distance(from, to) == 1 and not state.edge_blocked(from, to)


static func _is_elite(faction: String, unit_name: String) -> bool:
	var e: PlayerboardTable.UnitEntry = PlayerboardTable.get_unit(faction, unit_name)
	return e != null and not e.is_basic()


# --- Explore: 1 AP, flips an unexplored hex under the Hero, ends turn. ---
static func _explore(state: GameState, action: Dictionary, faction: String, card_db: Node) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.has_acted_this_turn:
		return {"ok": false, "reason": "already took your one Action this turn"}
	if p.action_points < AP_COST:
		return {"ok": false, "reason": "not enough AP"}
	var coord: Vector2i = p.hero_coord  # rulebook p22: "When your Hero is on an unexplored hex"
	if action.has("at") and _coord(action, "at") != coord:
		return {"ok": false, "reason": "your Hero must stand on the hex to Explore it"}
	var tile: HexTileState = state.get_hex(coord)
	if tile == null:
		return {"ok": false, "reason": "no hex there"}
	if tile.explored:
		return {"ok": false, "reason": "already explored"}
	if tile.curse:
		return {"ok": false, "reason": "cannot Explore a Cursed hex"}

	tile.explored = true
	tile.rotation = posmod(int(action.get("rotation", 0)), 6)
	if HexTileState.IMPASSABLE_ART_EDGES.has(tile.hex_card_name):
		tile.orientable_by = faction
	p.action_points -= AP_COST
	p.has_acted_this_turn = true
	if tile.bonus_salt > 0:  # Aezhers Essence: "If you flip that hex, gain it."
		p.salt += tile.bonus_salt
		tile.bonus_salt = 0

	if not tile.hex_card_name.is_empty() and HexEffectPrograms.has_program(tile.hex_card_name):
		var ctx := EffectContext.new()
		ctx.state = state
		ctx.card_db = card_db
		ctx.rng = RandomNumberGenerator.new()
		ctx.rng.randomize()
		ctx.acting_faction = faction
		ctx.hex_coord = coord
		ctx.has_hex_coord = true
		EffectInterpreter.run(HexEffectPrograms.get_program(tile.hex_card_name), ctx)
		state.phase_log = "%s explores '%s': %s" % [faction, tile.hex_card_name, "; ".join(ctx.log_lines)]
	else:
		state.phase_log = "%s explores '%s' (no automated effect)" % [faction, tile.hex_card_name]
	return {"ok": true}


# --- Orient: free, turn a hex you just explored (rulebook p22). ---
## action = {"at": {x,y}, "rotation": 0-5 clockwise steps}. Only the
## explorer, only until their turn ends, only hexes with impassable
## terrain (orientation doesn't matter for any other hex).
static func _orient(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	var coord: Vector2i = _coord(action, "at")
	var tile: HexTileState = state.get_hex(coord)
	if tile == null or tile.orientable_by != faction:
		return {"ok": false, "reason": "you can only orient a hex you explored this turn"}
	tile.rotation = posmod(int(action.get("rotation", 0)), 6)
	state.phase_log = "%s orients '%s' (rotation %d)" % [faction, tile.hex_card_name, tile.rotation]
	return {"ok": true}


static func _clear_orientable(state: GameState, faction: String) -> void:
	for tile: HexTileState in state.hexes.values():
		if tile.orientable_by == faction:
			tile.orientable_by = ""


# --- Haven: 1 AP + faction-specific Plunder cost, ends turn. ---
static func _haven(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.has_acted_this_turn:
		return {"ok": false, "reason": "already took your one Action this turn"}
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(faction)
	var cost: int = board.haven_plunder_cost if board != null else 2
	var free_haven: bool = p.wiles_ready
	if not free_haven and (p.action_points < AP_COST or p.plunder < cost):
		return {"ok": false, "reason": "not enough AP/Plunder"}
	var coord: Vector2i = p.hero_coord  # rulebook p22: "in your Hero's explored hex"
	if action.has("at") and _coord(action, "at") != coord:
		return {"ok": false, "reason": "your Hero must stand on the hex to build a Haven there"}
	var tile: HexTileState = state.get_hex(coord)
	if tile == null or not tile.explored:
		return {"ok": false, "reason": "hex must be explored"}
	if tile.curse:
		return {"ok": false, "reason": "cannot build a Haven on a Cursed hex"}
	if not tile.haven_faction.is_empty():
		return {"ok": false, "reason": "hex already has a Haven"}
	if tile.total_player_units() > tile.unit_count(faction) or tile.garrison_level > 0 or tile.skeleton_count > 0:
		return {"ok": false, "reason": "enemy Units are here"}
	for l: LegionInstance in state.legions:
		if l.coord == coord:
			return {"ok": false, "reason": "a Legion is here"}
	for h: HordeInstance in state.hordes:
		if h.coord == coord:
			return {"ok": false, "reason": "a Horde is here"}
	if tile.role == "outer" or tile.role == "capital":
		return {"ok": false, "reason": "a hex with an X can never gain a Haven"}
	var havens: int = 0
	for t: HexTileState in state.hexes.values():
		if t.haven_faction == faction:
			havens += 1
	if havens >= MAX_HAVENS:
		return {"ok": false, "reason": "all %d of your Havens are on the map" % MAX_HAVENS}

	tile.haven_faction = faction
	if free_haven:
		p.wiles_ready = false
	else:
		p.action_points -= AP_COST
		p.plunder -= cost
	if CardAbilities.active(p, "Asheforge"):
		p.asheforge_coord = coord  # "When you place a Haven, you may build Units and Defenses here."
	p.has_acted_this_turn = true
	state.phase_log = "%s builds a Haven at %s" % [faction, coord]
	return {"ok": true}


# --- Market: 1 AP + the Item's Salt cost, ends turn. ---
## Buys one of the 3 face-up Items (GameState.item_market, dealt in
## Refresh) at its Items CSV Salt cost, 1 less while the Hero stands on an
## explored Sea Tower (its ongoing effect). The Hero must be able to use
## the Item - attributes at least those printed on it (rulebook p24) - and
## the Market refills at once ("The market is always full").
static func _market(state: GameState, action: Dictionary, faction: String, card_db: Node) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.has_acted_this_turn:
		return {"ok": false, "reason": "already took your one Action this turn"}
	var item_name: String = str(action.get("item", ""))
	if not state.item_market.has(item_name) or state.flipped_market.has(item_name):
		return {"ok": false, "reason": "item not available in the Market"}
	if not hero_can_use_item(card_db, p, item_name):
		return {"ok": false, "reason": "your Hero lacks the attributes to use '%s'" % item_name}
	var cost: int = item_cost(card_db, item_name) - CardAbilities.item_discount(p)
	var here: HexTileState = state.get_hex(p.hero_coord)
	if here != null and here.role == "sea_tower" and here.explored:
		cost -= 1
	cost = maxi(0, cost)
	if p.action_points < AP_COST or p.salt < cost:
		return {"ok": false, "reason": "not enough AP/Salt"}

	state.item_market.erase(item_name)
	ChapterFlow.refill_row(state.item_market, state.item_deck, state.item_discard, 3)
	p.items_in_hand.append(item_name)
	CardAbilities.enforce_limit(state, p, card_db)
	p.action_points -= AP_COST
	p.salt -= cost
	p.has_acted_this_turn = true
	state.phase_log = "%s buys Item '%s' for %d Salt" % [faction, item_name, cost]
	return {"ok": true}


static func hero_can_use_item(card_db: Node, p: PlayerFactionState, item_name: String) -> bool:
	if card_db == null or p == null or CardAbilities.ignores_item_requirements(p):
		return true
	for it: ItemCard in card_db.items:
		if it.card_name == item_name:
			var ok: bool = EffectUtil.hero_attr(card_db, p, "might") >= it.might and EffectUtil.hero_attr(card_db, p, "magic") >= it.magic
			return ok and EffectUtil.hero_attr(card_db, p, "lead") >= it.lead and EffectUtil.hero_attr(card_db, p, "guile") >= it.guile
	return true


static func item_cost(card_db: Node, item_name: String) -> int:
	if card_db == null:
		return 0
	for it: ItemCard in card_db.items:
		if it.card_name == item_name:
			return it.cost.strip_edges().to_int() if it.cost.strip_edges().is_valid_int() else 0
	return 0


# --- Quest: 1 AP, roll the Hero Dice against a face-up Quest, ends turn. ---
## Resolution (goals, rewards, solve/failure effects, what happens to the
## card) lives in quest_flow.gd.
static func _quest(state: GameState, action: Dictionary, faction: String, card_db: Node) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.has_acted_this_turn:
		return {"ok": false, "reason": "already took your one Action this turn"}
	if p.action_points < AP_COST:
		return {"ok": false, "reason": "not enough AP"}
	var quest_name: String = str(action.get("quest", ""))
	if not state.quest_row.has(quest_name):
		return {"ok": false, "reason": "quest not face-up"}
	var quest_flow: GDScript = load(QUEST_FLOW_PATH)
	var r: Dictionary = quest_flow.attempt(state, card_db, faction, quest_name, {})
	if not r.get("ok", false):
		return r
	p.action_points -= AP_COST
	p.has_acted_this_turn = true
	state.phase_log = str(r.get("log", ""))
	return {"ok": true, "solved": r.get("solved", false)}


## Building outside the Build Phase: right after an Asheforge Haven (on
## that hex) or while Survivors is open ("Every player may build...").
static func _build_window_open(state: GameState, p: PlayerFactionState, coord: Vector2i) -> bool:
	if state.phase == GameState.Phase.BUILD or state.open_build_until_turn_end:
		return true
	return state.phase == GameState.Phase.ACTIONS and p != null and p.asheforge_coord == coord


static func _build_unit(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return {"ok": false, "reason": "unknown faction"}
	if not _build_window_open(state, p, _coord(action, "at")):
		return {"ok": false, "reason": "can only build during the Build Phase"}
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(faction)
	if board == null:
		return {"ok": false, "reason": "no playerboard data for faction"}
	var unit_name: String = str(action.get("unit", ""))
	var entry: PlayerboardTable.UnitEntry = null
	for u: PlayerboardTable.UnitEntry in board.units:
		if u.name == unit_name:
			entry = u
			break
	if entry == null:
		return {"ok": false, "reason": "unknown unit '%s' for %s" % [unit_name, faction]}
	var coord: Vector2i = _coord(action, "at")
	var tile: HexTileState = state.get_hex(coord)
	if tile == null:
		return {"ok": false, "reason": "no hex there"}
	if tile.haven_faction != faction and not _homeless_build_ok(state, p, coord):
		return {"ok": false, "reason": "must build on your own Haven"}
	if tile.unit_count(faction) >= HexTileState.MAX_UNITS:
		return {"ok": false, "reason": "hex already has 5 Units"}
	if NemesisAI.NemesisCards.reserve_left(state, p, unit_name) <= 0:
		return {"ok": false, "reason": "no %s left in your reserve (on the map or in a Graveyard)" % unit_name}

	var pay_result: Dictionary = _pay_cost(p, entry.cost, action)
	if not pay_result.get("ok", false):
		return pay_result

	tile.add_units(faction, unit_name)
	if tile.haven_faction != faction:
		p.hero_coord = coord  # homeless build: the Hero goes where the Units appear
	state.phase_log = "%s builds a %s at %s" % [faction, unit_name, coord]
	return {"ok": true}


## Rulebook p17: "If you have no Havens, place your Hero on any explored
## empty hex and build Units there."
static func _homeless_build_ok(state: GameState, p: PlayerFactionState, coord: Vector2i) -> bool:
	for t: HexTileState in state.hexes.values():
		if t.haven_faction == p.faction:
			return false
	var tile: HexTileState = state.get_hex(coord)
	if tile == null or tile.role == "outer" or not tile.explored or tile.curse or not tile.haven_faction.is_empty():
		return false
	if coord != p.hero_coord and tile.unit_count(p.faction) > 0:
		return false  # Units already gathered under the Hero elsewhere
	var others: int = tile.total_player_units() - tile.unit_count(p.faction)
	return others == 0 and tile.garrison_level == 0 and tile.skeleton_count == 0 and EffectUtil.nemesis_at(state, coord).is_empty()


static func _build_defense(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return {"ok": false, "reason": "unknown faction"}
	if not _build_window_open(state, p, _coord(action, "at")):
		return {"ok": false, "reason": "can only build during the Build Phase"}
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(faction)
	var kind: String = str(action.get("kind", "Tower"))  # "Tower" | "Wall"
	var coord: Vector2i = _coord(action, "at")
	var tile: HexTileState = state.get_hex(coord)
	if tile == null or tile.haven_faction != faction:
		return {"ok": false, "reason": "must build on your own Haven"}
	if kind == "Tower":
		if tile.tower:
			return {"ok": false, "reason": "already has a Tower"}
		if p.plunder < 1:
			return {"ok": false, "reason": "not enough Plunder"}
		p.plunder -= 1
		tile.tower = true
	elif kind == "Wall":
		if tile.wall:
			return {"ok": false, "reason": "already has a Wall"}
		if p.plunder < 1:
			return {"ok": false, "reason": "not enough Plunder"}
		p.plunder -= 1
		tile.wall = true
	else:
		return {"ok": false, "reason": "unknown defense kind '%s'" % kind}
	state.phase_log = "%s builds a %s at %s" % [faction, kind, coord]
	return {"ok": true}


static func _pay_cost(p: PlayerFactionState, cost: Dictionary, action: Dictionary) -> Dictionary:
	match str(cost.get("type", "fixed")):
		"fixed":
			var need_salt: int = int(cost.get("Salt", 0))
			var need_plunder: int = int(cost.get("Plunder", 0))
			var need_food: int = int(cost.get("Food", 0))
			if p.salt < need_salt or p.plunder < need_plunder or p.food < need_food:
				return {"ok": false, "reason": "not enough resources"}
			p.salt -= need_salt
			p.plunder -= need_plunder
			p.food -= need_food
			return {"ok": true}
		"or":
			var choice: String = str(action.get("or_choice", "Salt"))
			var amount: int = int(cost.get(choice, 0))
			if amount <= 0:
				return {"ok": false, "reason": "invalid OR-cost choice '%s'" % choice}
			if choice == "Salt" and p.salt >= amount:
				p.salt -= amount
				return {"ok": true}
			if choice == "Plunder" and p.plunder >= amount:
				p.plunder -= amount
				return {"ok": true}
			return {"ok": false, "reason": "not enough %s" % choice}
		"any":
			var amount_any: int = int(cost.get("amount", 0))
			var alloc: Dictionary = action.get("any_allocation", {})
			var salt_pay: int = int(alloc.get("Salt", 0))
			var plunder_pay: int = int(alloc.get("Plunder", 0))
			var food_pay: int = int(alloc.get("Food", 0))
			if salt_pay + plunder_pay + food_pay != amount_any:
				return {"ok": false, "reason": "any_allocation must sum to %d" % amount_any}
			if p.salt < salt_pay or p.plunder < plunder_pay or p.food < food_pay:
				return {"ok": false, "reason": "not enough resources"}
			p.salt -= salt_pay
			p.plunder -= plunder_pay
			p.food -= food_pay
			return {"ok": true}
	return {"ok": false, "reason": "unknown cost type"}


static func _end_turn(state: GameState, faction: String) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	p.has_acted_this_turn = false
	p.asheforge_coord = Vector2i.MIN
	state.open_build_until_turn_end = false
	_clear_orientable(state, faction)
	_advance_turn(state)
	return {"ok": true}


static func _pass(state: GameState, faction: String) -> Dictionary:
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return {"ok": false, "reason": "unknown faction"}
	p.has_passed = true
	_clear_orientable(state, faction)
	if is_players_turn(state, faction):
		_advance_turn(state)
	return {"ok": true}


static func _advance_turn(state: GameState) -> void:
	if state.players.is_empty():
		return
	var n: int = state.players.size()
	for _i: int in range(n):
		state.current_player_index = (state.current_player_index + 1) % n
		var p: PlayerFactionState = state.players[state.current_player_index]
		if p.action_points > 0 and not p.has_passed:
			return


static func _coord(action: Dictionary, key: String) -> Vector2i:
	var v: Dictionary = action.get(key, {"x": 0, "y": 0})
	return Vector2i(int(v.get("x", 0)), int(v.get("y", 0)))
