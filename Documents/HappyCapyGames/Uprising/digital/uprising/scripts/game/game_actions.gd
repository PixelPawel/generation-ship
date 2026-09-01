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
##   {"type": "quest",   "faction": "Krowh", "quest": "A Deal with Demons"}
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
			return _quest(state, action, sender_id)
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


## Rulebook p25: Quest costs 1 AP, Actions Phase only. Choosing a Quest and
## rolling/resolving it needs actual Hero Dice face data (which color rolls
## which Skull/Shield/Bolt/blank faces) that isn't available anywhere in the
## CSVs or rulebook text -- this only handles the mechanical AP cost and
## marks the attempt; dice rolling and success/failure resolution stay
## manual (assisted) until that data exists.
static func _quest(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	if state.phase != GameState.Phase.ACTIONS:
		return {"ok": false, "reason": "Quest is only available during the Actions Phase"}
	var auth := _get_authorized_player(state, action, sender_id)
	if not auth.get("ok", false):
		return auth
	var player: PlayerFactionState = auth["player"]

	var quest_name: String = action.get("quest", "")
	if not state.quests_available.has(quest_name):
		return {"ok": false, "reason": "that Quest is not available"}
	if player.action_points < 1:
		return {"ok": false, "reason": "no Action Points left"}

	player.action_points -= 1
	return {"ok": true, "reason": "AP spent; roll Hero Dice and resolve the Quest manually"}
