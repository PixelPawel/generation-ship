class_name GameActions
extends RefCounted

## Per-Action rules dispatcher, deliberately separate from NetworkManager
## so rules logic is testable without any networking (NetworkManager's
## action_handler just wraps GameActions.apply once a peer_id->faction
## lookup exists - Milestone 5's job). apply() returns {ok:bool,
## reason:String} matching NetworkManager's expected action_handler shape.
##
## Known, documented simplifications (consistent with this project's
## existing "flag rather than silently guess" pattern): HexTileState has
## no per-edge impassable-terrain data, so Move/Command don't enforce the
## rulebook's impassable-edge rule; Sea Tower "adjacent to everywhere" is
## not yet enforced either. Both are real rulebook mechanics (p14, p44)
## deferred until hex data carries that information.

const AP_COST := 1


static func apply(state: GameState, action: Dictionary, faction: String, card_db: Node) -> Dictionary:
	var type: String = str(action.get("type", ""))
	match type:
		"move":
			return _move(state, action, faction)
		"trade":
			return _trade(state, action, faction)
		"command":
			return _command(state, action, faction)
		"explore":
			return _explore(state, action, faction, card_db)
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
static func _move(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.action_points < AP_COST:
		return {"ok": false, "reason": "not enough AP"}
	var to: Vector2i = _coord(action, "to")
	# Hero movement doesn't have a tracked position in GameState yet (no
	# "hero_coord" field) - this deducts AP and logs the move; Hero
	# position tracking is a Milestone 5 UI/state concern once the board
	# view needs to actually place the Hero standee.
	p.action_points -= AP_COST
	state.phase_log = "%s moves Hero toward %s" % [faction, to]
	return {"ok": true}


# --- Trade: 1 AP -> 1 Salt, ALWAYS usable, any phase, doesn't end turn. ---
static func _trade(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return {"ok": false, "reason": "unknown faction"}
	if p.action_points < AP_COST:
		return {"ok": false, "reason": "not enough AP"}
	p.action_points -= AP_COST
	p.salt += 1
	return {"ok": true}


# --- Command: 1 AP + 1 Food, gathers adjacent Units/Hero into target hex, ends turn. ---
static func _command(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.has_acted_this_turn:
		return {"ok": false, "reason": "already took your one Action this turn"}
	if p.action_points < AP_COST or p.food < 1:
		return {"ok": false, "reason": "not enough AP/Food"}
	var target: Vector2i = _coord(action, "to")
	var target_tile: HexTileState = state.ensure_hex(target)
	if not target_tile.explored:
		return {"ok": false, "reason": "target hex is unexplored"}

	var gathered: int = int(target_tile.units.get(faction, 0))
	for neighbor: Vector2i in HexMath.neighbors(target):
		var nt: HexTileState = state.get_hex(neighbor)
		if nt == null:
			continue
		var here: int = int(nt.units.get(faction, 0))
		if here <= 0:
			continue
		var moving: int = mini(here, 5 - gathered)
		if moving <= 0:
			continue
		nt.units[faction] = here - moving
		gathered += moving
	target_tile.units[faction] = mini(5, gathered)

	p.action_points -= AP_COST
	p.food -= 1
	p.has_acted_this_turn = true
	state.phase_log = "%s Commands Units to %s" % [faction, target]
	return {"ok": true}


# --- Explore: 1 AP, flips an unexplored hex under the Hero, ends turn. ---
static func _explore(state: GameState, action: Dictionary, faction: String, card_db: Node) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.has_acted_this_turn:
		return {"ok": false, "reason": "already took your one Action this turn"}
	if p.action_points < AP_COST:
		return {"ok": false, "reason": "not enough AP"}
	var coord: Vector2i = _coord(action, "at")
	var tile: HexTileState = state.get_hex(coord)
	if tile == null:
		return {"ok": false, "reason": "no hex there"}
	if tile.explored:
		return {"ok": false, "reason": "already explored"}
	if tile.curse:
		return {"ok": false, "reason": "cannot Explore a Cursed hex"}

	tile.explored = true
	p.action_points -= AP_COST
	p.has_acted_this_turn = true

	if not tile.hex_card_name.is_empty() and HexEffectPrograms.has_program(tile.hex_card_name):
		var ctx := EffectContext.new()
		ctx.state = state
		ctx.card_db = card_db
		ctx.rng = RandomNumberGenerator.new()
		ctx.acting_faction = faction
		ctx.hex_coord = coord
		ctx.has_hex_coord = true
		EffectInterpreter.run(HexEffectPrograms.get_program(tile.hex_card_name), ctx)
		state.phase_log = "%s explores '%s': %s" % [faction, tile.hex_card_name, "; ".join(ctx.log_lines)]
	else:
		state.phase_log = "%s explores '%s' (no automated effect)" % [faction, tile.hex_card_name]
	return {"ok": true}


# --- Haven: 1 AP + faction-specific Plunder cost, ends turn. ---
static func _haven(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.has_acted_this_turn:
		return {"ok": false, "reason": "already took your one Action this turn"}
	var board: PlayerboardTable.FactionBoard = PlayerboardTable.get_board(faction)
	var cost: int = board.haven_plunder_cost if board != null else 2
	if p.action_points < AP_COST or p.plunder < cost:
		return {"ok": false, "reason": "not enough AP/Plunder"}
	var coord: Vector2i = _coord(action, "at")
	var tile: HexTileState = state.get_hex(coord)
	if tile == null or not tile.explored:
		return {"ok": false, "reason": "hex must be explored"}
	if tile.curse:
		return {"ok": false, "reason": "cannot build a Haven on a Cursed hex"}
	if not tile.haven_faction.is_empty():
		return {"ok": false, "reason": "hex already has a Haven"}
	for other_faction: Variant in tile.units.keys():
		if str(other_faction) != faction and int(tile.units[other_faction]) > 0:
			return {"ok": false, "reason": "another faction's Units are here"}

	tile.haven_faction = faction
	p.action_points -= AP_COST
	p.plunder -= cost
	p.has_acted_this_turn = true
	state.phase_log = "%s builds a Haven at %s" % [faction, coord]
	return {"ok": true}


# --- Market: 1 AP + Salt cost, ends turn. ---
static func _market(state: GameState, action: Dictionary, faction: String, card_db: Node) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.has_acted_this_turn:
		return {"ok": false, "reason": "already took your one Action this turn"}
	var item_name: String = str(action.get("item", ""))
	if not p.items_in_hand.has(item_name) and not state.item_deck.has(item_name):
		pass  # item source not modeled as a distinct "Market row" yet - see below.
	# The rulebook's "always-full Market" of 3 face-up Items isn't a
	# separate tracked zone in GameState yet (only item_deck/item_discard
	# exist) - this simplification buys directly from the deck by name,
	# refilling isn't needed since nothing was removed to a display row.
	if not state.item_deck.has(item_name):
		return {"ok": false, "reason": "item not available"}
	var cost: int = int(action.get("salt_cost", 0))
	var on_sea_tower: bool = bool(action.get("on_sea_tower", false))
	if on_sea_tower:
		cost = maxi(0, cost - 1)
	if p.action_points < AP_COST or p.salt < cost:
		return {"ok": false, "reason": "not enough AP/Salt"}

	state.item_deck.erase(item_name)
	p.items_in_hand.append(item_name)
	p.action_points -= AP_COST
	p.salt -= cost
	p.has_acted_this_turn = true
	state.phase_log = "%s buys Item '%s' from the Market" % [faction, item_name]
	return {"ok": true}


# --- Quest: 1 AP, rolls Hero Dice against the Quest's goal thresholds, ends turn. ---
static func _quest(state: GameState, action: Dictionary, faction: String, card_db: Node) -> Dictionary:
	if not is_players_turn(state, faction):
		return {"ok": false, "reason": "not your turn"}
	var p: PlayerFactionState = state.find_player(faction)
	if p.has_acted_this_turn:
		return {"ok": false, "reason": "already took your one Action this turn"}
	if p.action_points < AP_COST:
		return {"ok": false, "reason": "not enough AP"}
	var quest_name: String = str(action.get("quest", ""))
	if not state.quest_deck.has(quest_name):
		return {"ok": false, "reason": "quest not available"}

	p.action_points -= AP_COST
	p.has_acted_this_turn = true
	# Real dice count depends on Hero attributes (Might/Magic/Lead/Guile) -
	# same documented placeholder boundary as RollHeroDiceRewardOp
	# (Milestone 4 TODO: wire to the acting Hero's actual HeroCard).
	var dice_count: int = int(action.get("dice_count", 3))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var skulls: int = 0
	for _i: int in range(dice_count):
		if rng.randi_range(0, 3) == 0:  # placeholder 25% Skull, see EffectContext.roll_symbol()
			skulls += 1
	state.phase_log = "%s attempts Quest '%s': rolled %d Skulls (dice_count is a placeholder, see comment)" % [faction, quest_name, skulls]
	return {"ok": true, "skulls": skulls}


static func _build_unit(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	if state.phase != GameState.Phase.BUILD:
		return {"ok": false, "reason": "can only build during the Build Phase"}
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return {"ok": false, "reason": "unknown faction"}
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
	if tile == null or tile.haven_faction != faction:
		return {"ok": false, "reason": "must build on your own Haven"}
	var current: int = int(tile.units.get(faction, 0))
	if current >= 5:
		return {"ok": false, "reason": "hex already has 5 Units"}

	var pay_result: Dictionary = _pay_cost(p, entry.cost, action)
	if not pay_result.get("ok", false):
		return pay_result

	tile.units[faction] = current + 1
	state.phase_log = "%s builds a %s at %s" % [faction, unit_name, coord]
	return {"ok": true}


static func _build_defense(state: GameState, action: Dictionary, faction: String) -> Dictionary:
	if state.phase != GameState.Phase.BUILD:
		return {"ok": false, "reason": "can only build during the Build Phase"}
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return {"ok": false, "reason": "unknown faction"}
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
	_advance_turn(state)
	return {"ok": true}


static func _pass(state: GameState, faction: String) -> Dictionary:
	var p: PlayerFactionState = state.find_player(faction)
	if p == null:
		return {"ok": false, "reason": "unknown faction"}
	p.has_passed = true
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
