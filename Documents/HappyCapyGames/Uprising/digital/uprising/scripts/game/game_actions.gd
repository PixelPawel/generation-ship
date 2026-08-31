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
## More (Command/Haven/Market/Quest/...) plug in the same way: add a case in
## apply() and a _handler(state, action, sender_id) -> {ok, reason} function.


static func apply(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	var type: String = action.get("type", "")
	match type:
		"trade":
			return _trade(state, action, sender_id)
		"move":
			return _move(state, action, sender_id)
		"explore":
			return _explore(state, action, sender_id)
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
