class_name GameActions
extends RefCounted
## Pure game-rule action handlers. Each takes the authoritative GameState and
## a plain-Dictionary action request, mutates state in place if valid, and
## returns {"ok": bool, "reason": String}. Called only by NetworkManager on
## the host; kept separate from networking so it's testable standalone
## (no ENet/multiplayer setup needed to test rules logic).
##
## Action dict shapes so far:
##   {"type": "trade",   "faction": "Krowh"}
##   {"type": "move",    "faction": "Krowh", "to": [q, r]}
##   {"type": "explore", "faction": "Krowh"}
##   {"type": "haven",   "faction": "Krowh"}
##   {"type": "command", "faction": "Krowh", "to": [q, r]}
##   {"type": "market",  "faction": "Krowh", "item": "Abad Warpaint"}
##   {"type": "quest",   "faction": "Krowh", "quest": "A Deal with Demons",
##    "guile_white": 2, "guile_yellow": 1}  -- Guile split, must sum to the
##    Hero's Guile; omit both for an all-White default
##   {"type": "build_unit", "faction": "Krowh", "unit": "Deadeyes", "at": [q, r],
##    "cost_choice": 0}  -- index into the unit's cost_options, default 0;
##    "any_alloc": {"salt": 1, "plunder": 1} for Mohyar's ANY-cost Units,
##    must sum to the option's "any" amount
##   {"type": "build_defense", "faction": "Krowh", "defense": "tower", "at": [q, r]}
##    -- defense is "tower" or "wall"
##   {"type": "pass", "faction": "Krowh"}  -- done taking Actions for this
##    Chapter even if AP remains; GameFlow's turn loop treats 0 AP and a
##    voluntary Pass the same way
## More plug in the same way: add a case in apply() and a
## _handler(state, action, sender_id, card_db) -> {ok, reason} function.
## `card_db` is the CardDatabase autoload, needed by handlers (Market, Quest)
## that must check static card data like Item cost/attribute requirements.


static func apply(state: GameState, action: Dictionary, sender_id: int, card_db: Node = null) -> Dictionary:
	var type: String = action.get("type", "")
	match type:
		"trade":
			return _trade(state, action, sender_id)
		"move":
			return _move(state, action, sender_id)
		"explore":
			return _explore(state, action, sender_id)
		"haven":
			return _haven(state, action, sender_id)
		"command":
			return _command(state, action, sender_id)
		"market":
			return _market(state, action, sender_id, card_db)
		"quest":
			return _quest(state, action, sender_id, card_db)
		"build_unit":
			return _build_unit(state, action, sender_id)
		"build_defense":
			return _build_defense(state, action, sender_id)
		"pass":
			return _pass(state, action, sender_id)
		_:
			return {"ok": false, "reason": "unknown action type '%s'" % type}


static func _get_authorized_player(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	var faction: String = action.get("faction", "")
	var player := state.get_player(faction)
	if player == null:
		return {"ok": false, "reason": "no such faction '%s'" % faction}
	# TODO: once a "claim this faction" flow exists, reject when
	# player.controlled_by_peer_id != sender_id. Unclaimed (-1) is allowed
	# through for now so actions are testable/usable before that's built.
	if player.controlled_by_peer_id != -1 and player.controlled_by_peer_id != sender_id:
		return {"ok": false, "reason": "faction '%s' is controlled by another player" % faction}
	return {"ok": true, "player": player}


## Rulebook p19: Trade is ALWAYS available (any Phase), 1 AP -> 1 Salt.
static func _trade(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]
	if player.action_points < 1:
		return {"ok": false, "reason": "no Action Points left"}
	player.action_points -= 1
	player.salt += 1
	return {"ok": true, "reason": ""}


## Voluntarily done taking Actions this Chapter, even with AP remaining
## (unlike running out of AP, which GameFlow's turn loop already detects on
## its own). Always available, like Trade -- there's no rule against passing
## outside the Actions Phase, it just has no effect there.
static func _pass(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]
	player.has_passed = true
	return {"ok": true, "reason": ""}


## Rulebook p18: Move costs 1 AP per hex, Actions Phase only, only to an
## adjacent hex -- or between two explored Sea Towers, which count as
## adjacent to every hex.
static func _move(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	if state.phase != GameState.Phase.ACTIONS:
		return {"ok": false, "reason": "Move is only available during the Actions Phase"}
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]

	var to_arr: Array = action.get("to", [])
	if to_arr.size() != 2:
		return {"ok": false, "reason": "missing/invalid 'to' coordinate"}
	var to := Vector2i(to_arr[0], to_arr[1])

	if player.action_points < 1:
		return {"ok": false, "reason": "no Action Points left"}

	var from_tile := state.get_hex(player.hero_hex)
	var to_tile := state.get_hex(to)
	if to_tile == null:
		return {"ok": false, "reason": "target hex does not exist"}

	var adjacent := HexMath.distance(player.hero_hex, to) == 1
	var via_sea_tower := (
		from_tile != null and from_tile.is_sea_tower and from_tile.explored
		and to_tile.is_sea_tower and to_tile.explored
	)
	if not adjacent and not via_sea_tower:
		return {"ok": false, "reason": "hex is not adjacent (and not a Sea Tower shortcut)"}

	player.action_points -= 1
	player.hero_hex = to
	return {"ok": true, "reason": ""}


## Rulebook p22: Explore costs 1 AP, flips an unexplored hex the Hero is on,
## ends the turn. The specific flip-effect text (place Garrison/Skeleton/
## resources/etc) is deliberately NOT auto-applied here -- per the
## automation-scope decision, hex/card effect text stays assisted: the host
## flips the hex, the player reads the now-visible effect and applies it via
## the (not yet built) primitive toolkit actions.
static func _explore(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	if state.phase != GameState.Phase.ACTIONS:
		return {"ok": false, "reason": "Explore is only available during the Actions Phase"}
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]

	var tile := state.get_hex(player.hero_hex)
	if tile == null:
		return {"ok": false, "reason": "Hero is not on a valid hex"}
	if tile.explored:
		return {"ok": false, "reason": "hex is already explored"}
	if tile.has_curse:
		return {"ok": false, "reason": "cannot Explore a hex with a Curse"}
	if player.action_points < 1:
		return {"ok": false, "reason": "no Action Points left"}

	player.action_points -= 1
	tile.explored = true
	return {"ok": true, "reason": ""}


## Rulebook p23: Haven costs 1 AP + 2 Plunder (3 for Krowh), Actions Phase
## only. Requires an explored hex with no X icon, no existing Haven, and no
## other faction's Units present.
static func _haven(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	if state.phase != GameState.Phase.ACTIONS:
		return {"ok": false, "reason": "Haven is only available during the Actions Phase"}
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]

	var tile := state.get_hex(player.hero_hex)
	if tile == null or not tile.explored:
		return {"ok": false, "reason": "Hero must be on an explored hex"}
	if tile.no_haven:
		return {"ok": false, "reason": "this hex can never have a Haven"}
	if tile.haven_faction != "":
		return {"ok": false, "reason": "this hex already has a Haven"}
	if _other_faction_present(tile, player.faction):
		return {"ok": false, "reason": "another faction's Units are here"}

	var plunder_cost := 3 if player.faction == "Krowh" else 2
	if player.action_points < 1:
		return {"ok": false, "reason": "no Action Points left"}
	if player.plunder < plunder_cost:
		return {"ok": false, "reason": "not enough Plunder"}

	player.action_points -= 1
	player.plunder -= plunder_cost
	tile.haven_faction = player.faction
	player.havens.append(tile.coord)
	return {"ok": true, "reason": ""}


## Rulebook p20: Command costs 1 AP + 1 Food, Actions Phase only. Moves the
## Hero and gathers this faction's Units from every hex adjacent to the
## target into it (respecting the 5-Unit-per-hex cap), then moves the Hero
## there too. Target must be explored and not hold another faction's
## Haven/Units. Simplifications, documented rather than silently assumed:
## brings in as many Units as fit without letting the player choose which,
## and doesn't yet account for impassable terrain or the Sea Tower shortcut
## when gathering Units (HexTile doesn't model per-edge impassability yet).
static func _command(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	if state.phase != GameState.Phase.ACTIONS:
		return {"ok": false, "reason": "Command is only available during the Actions Phase"}
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]

	var to_arr: Array = action.get("to", [])
	if to_arr.size() != 2:
		return {"ok": false, "reason": "missing/invalid 'to' coordinate"}
	var to := Vector2i(to_arr[0], to_arr[1])
	var to_tile := state.get_hex(to)
	if to_tile == null or not to_tile.explored:
		return {"ok": false, "reason": "target hex must be explored"}
	if _other_faction_present(to_tile, player.faction):
		return {"ok": false, "reason": "another faction's Units are on that hex"}
	if to_tile.haven_faction != "" and to_tile.haven_faction != player.faction:
		return {"ok": false, "reason": "another faction's Haven is on that hex"}

	if player.action_points < 1:
		return {"ok": false, "reason": "no Action Points left"}
	if player.food < 1:
		return {"ok": false, "reason": "not enough Food"}

	var incoming: Array = (to_tile.units.get(player.faction, []) as Array).duplicate()
	var capacity: int = 5 - incoming.size()
	if capacity > 0:
		for n in HexMath.neighbors(to):
			if capacity <= 0:
				break
			var nt := state.get_hex(n)
			if nt == null:
				continue
			var here: Array = (nt.units.get(player.faction, []) as Array).duplicate()
			while not here.is_empty() and capacity > 0:
				incoming.append(here.pop_back())
				capacity -= 1
			nt.units[player.faction] = here

	to_tile.units[player.faction] = incoming
	player.action_points -= 1
	player.food -= 1
	player.hero_hex = to
	return {"ok": true, "reason": ""}


static func _other_faction_present(tile: HexTile, faction: String) -> bool:
	for other in tile.units:
		if other != faction and not (tile.units[other] as Array).is_empty():
			return true
	return false


## Rulebook p24: Market costs 1 AP + the Item's printed Salt cost (1 less if
## the Hero is on a Sea Tower), Actions Phase only. The Hero must meet the
## Item's attribute requirement (if any). Bought Items leave the Market slot
## empty until the next Refresh Phase, per the rules -- this does NOT
## auto-refill, unlike GameSetup's initial fill.
static func _market(state: GameState, action: Dictionary, sender_id: int, card_db: Node) -> Dictionary:
	if state.phase != GameState.Phase.ACTIONS:
		return {"ok": false, "reason": "Market is only available during the Actions Phase"}
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]

	var item_name: String = action.get("item", "")
	if not state.market.has(item_name):
		return {"ok": false, "reason": "that Item is not in the Market"}
	if card_db == null:
		return {"ok": false, "reason": "no card database available to validate the Item"}

	var item_card: ItemCard = null
	for c in card_db.items:
		if c.lang == "EN" and c.card_name == item_name:
			item_card = c
			break
	if item_card == null:
		return {"ok": false, "reason": "unknown Item '%s'" % item_name}

	if item_card.might > 0 and player.might < item_card.might:
		return {"ok": false, "reason": "Might too low to use this Item"}
	if item_card.magic > 0 and player.magic < item_card.magic:
		return {"ok": false, "reason": "Magic too low to use this Item"}
	if item_card.lead > 0 and player.leadership < item_card.lead:
		return {"ok": false, "reason": "Leadership too low to use this Item"}
	if item_card.guile > 0 and player.guile < item_card.guile:
		return {"ok": false, "reason": "Guile too low to use this Item"}

	var hero_tile := state.get_hex(player.hero_hex)
	var on_sea_tower := hero_tile != null and hero_tile.is_sea_tower and hero_tile.explored
	var cost: int = maxi(0, item_card.cost - (1 if on_sea_tower else 0))

	if player.action_points < 1:
		return {"ok": false, "reason": "no Action Points left"}
	if player.salt < cost:
		return {"ok": false, "reason": "not enough Salt"}

	player.action_points -= 1
	player.salt -= cost
	player.items_in_play.append(item_name)
	state.market.erase(item_name)
	return {"ok": true, "reason": ""}


## Rulebook p25: Quest costs 1 AP, Actions Phase only. Rolls the Hero's
## attribute dice (Might->Red, Magic->Purple, Leadership->Blue, Guile->the
## player's White/Yellow split) via DiceModel, and checks the result against
## the Quest's three goal thresholds to determine which succeeded and
## whether it's Solved overall. Returns the roll and outcome in the result
## dict for the UI to show. Deliberately does NOT apply the Quest's Solve/
## Failure effect text or touch quests_available/discard piles -- which
## specific effect text applies and whether the card is discarded/kept is
## per-Quest free text, so that stays a manual step per the automation-scope
## decision (same boundary as Explore's hex-flip-only approach).
static func _quest(state: GameState, action: Dictionary, sender_id: int, card_db: Node) -> Dictionary:
	if state.phase != GameState.Phase.ACTIONS:
		return {"ok": false, "reason": "Quest is only available during the Actions Phase"}
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]

	var quest_name: String = action.get("quest", "")
	if not state.quests_available.has(quest_name):
		return {"ok": false, "reason": "that Quest is not available"}
	if card_db == null:
		return {"ok": false, "reason": "no card database available to resolve the Quest"}

	var quest_card: QuestCard = null
	for c in card_db.quests:
		if c.lang == "EN" and c.card_name == quest_name:
			quest_card = c
			break
	if quest_card == null:
		return {"ok": false, "reason": "unknown Quest '%s'" % quest_name}

	var guile_white: int = action.get("guile_white", player.guile)
	var guile_yellow: int = action.get("guile_yellow", 0)
	if guile_white + guile_yellow != player.guile:
		return {"ok": false, "reason": "guile_white + guile_yellow must equal the Hero's Guile"}

	if player.action_points < 1:
		return {"ok": false, "reason": "no Action Points left"}
	player.action_points -= 1

	var dice := DiceModel.roll_mixed({
		"Red": player.might,
		"Purple": player.magic,
		"Blue": player.leadership,
		"White": guile_white,
		"Yellow": guile_yellow,
	})

	var goals_met := {
		"skulls": quest_card.skulls_threshold > 0 and dice["skulls"] >= quest_card.skulls_threshold,
		"shields": quest_card.shields_threshold > 0 and dice["shields"] >= quest_card.shields_threshold,
		"bolts": quest_card.bolts_threshold > 0 and dice["bolts"] >= quest_card.bolts_threshold,
	}
	var successes := 0
	for goal in goals_met:
		if goals_met[goal]:
			successes += 1
	var solved: bool = successes >= quest_card.successes_needed

	return {
		"ok": true,
		"reason": "Solved!" if solved else "Failed.",
		"dice": dice,
		"goals_met": goals_met,
		"successes": successes,
		"successes_needed": quest_card.successes_needed,
		"solved": solved,
	}


## True if `hex` is one of the player's own Havens, OR the player has no
## Havens at all and `hex` is their Hero's current explored, empty hex
## (rulebook p17: "If you have no Havens, place your Hero on any explored
## empty hex and build Units there").
static func _valid_build_hex(state: GameState, player: PlayerFactionState, coord: Vector2i) -> bool:
	var tile := state.get_hex(coord)
	if tile == null or not tile.explored:
		return false
	if tile.haven_faction == player.faction:
		return true
	return player.havens.is_empty() and player.hero_hex == coord and HexTile.is_empty(tile)


static func _cost_affordable(player: PlayerFactionState, cost: Dictionary, any_alloc: Dictionary) -> bool:
	if cost.has("any"):
		var alloc_total: int = int(any_alloc.get("salt", 0)) + int(any_alloc.get("plunder", 0)) + int(any_alloc.get("food", 0))
		if alloc_total != int(cost["any"]):
			return false
		return (
			player.salt >= int(any_alloc.get("salt", 0))
			and player.plunder >= int(any_alloc.get("plunder", 0))
			and player.food >= int(any_alloc.get("food", 0))
		)
	return (
		player.salt >= int(cost.get("salt", 0))
		and player.plunder >= int(cost.get("plunder", 0))
		and player.food >= int(cost.get("food", 0))
	)


static func _cost_pay(player: PlayerFactionState, cost: Dictionary, any_alloc: Dictionary) -> void:
	if cost.has("any"):
		player.salt -= int(any_alloc.get("salt", 0))
		player.plunder -= int(any_alloc.get("plunder", 0))
		player.food -= int(any_alloc.get("food", 0))
	else:
		player.salt -= int(cost.get("salt", 0))
		player.plunder -= int(cost.get("plunder", 0))
		player.food -= int(cost.get("food", 0))


## How many of `unit_name` this faction already has in play, across every
## hex -- the hard reserve cap from FactionData.UNITS' `count` field.
static func _units_in_play(state: GameState, faction: String, unit_name: String) -> int:
	var total := 0
	for k in state.hexes:
		var tile: HexTile = state.hexes[k]
		for u in (tile.units.get(faction, []) as Array):
			if u == unit_name:
				total += 1
	return total


## Rulebook p17: Build Phase, no AP cost. Pay a Unit's printed resource cost
## (from FactionData, the transcribed player-board table) to place one copy
## on one of your own Havens -- or, if you have no Havens yet, on your
## Hero's own explored empty hex. Respects both the 5-Units-per-hex cap and
## the Unit's total reserve size (e.g. Druwhn only ever has 4 Swordsisters).
static func _build_unit(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	if state.phase != GameState.Phase.BUILD:
		return {"ok": false, "reason": "Units can only be built during the Build Phase"}
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]

	var unit_name: String = action.get("unit", "")
	var unit_def := FactionData.find_unit(player.faction, unit_name)
	if unit_def.is_empty():
		return {"ok": false, "reason": "unknown Unit '%s' for faction '%s'" % [unit_name, player.faction]}

	var to_arr: Array = action.get("at", [])
	if to_arr.size() != 2:
		return {"ok": false, "reason": "missing/invalid 'at' coordinate"}
	var coord := Vector2i(to_arr[0], to_arr[1])
	if not _valid_build_hex(state, player, coord):
		return {"ok": false, "reason": "hex must be one of your Havens (or, with no Havens, your Hero's own empty hex)"}

	var tile := state.get_hex(coord)
	var here: Array = (tile.units.get(player.faction, []) as Array)
	if here.size() >= 5:
		return {"ok": false, "reason": "hex already has 5 of your Units"}

	if _units_in_play(state, player.faction, unit_name) >= int(unit_def["count"]):
		return {"ok": false, "reason": "no more %s left in reserve" % unit_name}

	var cost_options: Array = unit_def["cost_options"]
	var choice: int = action.get("cost_choice", 0)
	if choice < 0 or choice >= cost_options.size():
		return {"ok": false, "reason": "invalid cost_choice"}
	var cost: Dictionary = cost_options[choice]
	var any_alloc: Dictionary = action.get("any_alloc", {})
	if not _cost_affordable(player, cost, any_alloc):
		return {"ok": false, "reason": "cannot afford this Unit's cost"}

	_cost_pay(player, cost, any_alloc)
	here.append(unit_name)
	tile.units[player.faction] = here
	return {"ok": true, "reason": ""}


## Rulebook p17 + p42: Build Phase, no AP cost, 1 Plunder. Requires a Haven
## you own on the target hex, and no existing Defense of that kind there
## (max 1 Tower + 1 Wall per Haven).
static func _build_defense(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	if state.phase != GameState.Phase.BUILD:
		return {"ok": false, "reason": "Defenses can only be built during the Build Phase"}
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]

	var defense: String = action.get("defense", "")
	if defense != "tower" and defense != "wall":
		return {"ok": false, "reason": "defense must be 'tower' or 'wall'"}

	var to_arr: Array = action.get("at", [])
	if to_arr.size() != 2:
		return {"ok": false, "reason": "missing/invalid 'at' coordinate"}
	var coord := Vector2i(to_arr[0], to_arr[1])
	var tile := state.get_hex(coord)
	if tile == null or tile.haven_faction != player.faction:
		return {"ok": false, "reason": "you must have a Haven on that hex"}
	if defense == "tower" and tile.has_tower:
		return {"ok": false, "reason": "this Haven already has a Tower"}
	if defense == "wall" and tile.has_wall:
		return {"ok": false, "reason": "this Haven already has a Wall"}

	if not _cost_affordable(player, FactionData.TOWER_WALL_COST, {}):
		return {"ok": false, "reason": "not enough Plunder"}
	_cost_pay(player, FactionData.TOWER_WALL_COST, {})
	if defense == "tower":
		tile.has_tower = true
	else:
		tile.has_wall = true
	return {"ok": true, "reason": ""}
