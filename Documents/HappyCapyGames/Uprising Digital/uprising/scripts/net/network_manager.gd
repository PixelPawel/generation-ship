extends Node

## Autoload. Host-authoritative networking over Godot's high-level
## multiplayer API, on either transport:
## - Steam: a Steam lobby (friends or public) plus SteamMultiplayerPeer P2P
##   (steam_manager.gd, created here at runtime);
## - LAN: ENet host/join by address, for local testing without Steam.
##
## Two layers, both rules-agnostic:
## 1. The lobby roster (before a game): peer id -> {name, faction, hero,
##    ready, seat}. The host owns it: clients ask for a pick/ready change by
##    RPC, the host validates (a faction can only be held by one seat) and
##    re-broadcasts the whole roster. start_game() turns the roster into a
##    GameState and moves everyone to the board.
## 2. The game (after start): any peer calls submit_action(dict); the host
##    applies it through `action_handler` (Callable(state, action, sender)
##    -> {ok, reason}) and re-broadcasts the full GameState, or tells only
##    the sender why it was rejected.

const SteamManagerScript := preload("res://scripts/net/steam_manager.gd")

const MAX_PLAYERS: int = 4
const LAN_PORT: int = 8955

signal state_updated(state: GameState)
signal action_rejected(reason: String)
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed()
signal server_disconnected()
## Lobby layer.
signal roster_changed(roster: Dictionary)
signal lobby_status(text: String)
signal lobby_joined()
signal game_starting()

## Set by the game layer (host-side only - never called on clients).
## func(state: GameState, action: Dictionary, sender_peer_id: int) -> Dictionary
var action_handler: Callable = Callable()

var current_state: GameState = null

## peer_id -> faction for the running game (host fills it in start_game()).
var peer_factions: Dictionary = {}

## Lobby roster: peer id -> {"name", "faction", "hero", "ready", "seat"}.
var roster: Dictionary = {}
var transport: String = ""   # "" | "lan" | "steam"
var steam: Node = null
var local_name: String = ""
var _next_seat: int = 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	steam = SteamManagerScript.new()
	steam.name = "Steam"
	add_child(steam)
	steam.lobby_hosted.connect(_on_steam_lobby_hosted)
	steam.lobby_entered.connect(_on_steam_lobby_entered)
	steam.lobby_failed.connect(func(reason: String) -> void: lobby_status.emit(reason))
	steam.invite_accepted.connect(_on_steam_invite_accepted)
	local_name = _default_name()


func _default_name() -> String:
	var n: String = steam.persona_name() if steam != null else ""
	if n.is_empty():
		n = OS.get_environment("USERNAME")
	return n if not n.is_empty() else "Player"


func assign_faction(peer_id: int, faction: String) -> void:
	peer_factions[peer_id] = faction


## The faction THIS process plays: from the roster in a lobby game, else
## from peer_factions.
func my_faction() -> String:
	var me: int = multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	if roster.has(me) and not str(roster[me].get("faction", "")).is_empty():
		return str(roster[me]["faction"])
	return str(peer_factions.get(me, ""))


## Default host-side action_handler: wraps GameActions with the
## peer_id->faction lookup. Bound to THIS autoload (not a scene node) because
## scene nodes get freed on change_scene_to_file().
func default_action_handler(state: GameState, action: Dictionary, sender_id: int) -> Dictionary:
	var faction: String = str(peer_factions.get(sender_id, ""))
	if faction.is_empty():
		return {"ok": false, "reason": "sender has no assigned faction yet"}
	var card_db: Node = get_node("/root/CardDatabase")
	return GameActions.apply(state, action, faction, card_db)


# --- Transports ----------------------------------------------------------------

func host_game(port: int, max_clients: int = MAX_PLAYERS - 1) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, max_clients)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func join_game(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## LAN lobby (ENet), mainly for testing without Steam.
func host_lan(port: int = LAN_PORT) -> Error:
	var err: Error = host_game(port)
	if err != OK:
		return err
	transport = "lan"
	_start_roster()
	return OK


func join_lan(address: String, port: int = LAN_PORT) -> Error:
	var err: Error = join_game(address, port)
	if err != OK:
		return err
	transport = "lan"
	lobby_status.emit("Connecting to %s..." % address)
	return OK


func steam_available() -> bool:
	return steam != null and steam.is_initialized and steam.peer_available()


func host_steam(friends_only: bool = true) -> void:
	if not steam_available():
		lobby_status.emit(steam.init_message if steam != null else "Steam isn't available.")
		return
	lobby_status.emit("Opening a Steam lobby...")
	steam.host_lobby(friends_only)


func request_steam_lobbies() -> void:
	if steam_available():
		steam.request_lobby_list()


func join_steam(lobby_id: int) -> void:
	if not steam_available():
		lobby_status.emit(steam.init_message if steam != null else "Steam isn't available.")
		return
	lobby_status.emit("Joining the Steam lobby...")
	steam.join_lobby(lobby_id)


func invite_friends() -> void:
	if transport == "steam":
		steam.invite_friends()


func leave_lobby() -> void:
	if steam != null:
		steam.leave_lobby()
	disconnect_network()


func disconnect_network() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	current_state = null
	roster.clear()
	peer_factions.clear()
	transport = ""
	_next_seat = 0
	roster_changed.emit(roster)


func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func in_lobby() -> bool:
	return multiplayer.multiplayer_peer != null and not roster.is_empty()


func _on_steam_lobby_hosted(_lobby_id: int) -> void:
	var peer: MultiplayerPeer = steam.make_host_peer()
	if peer == null:
		lobby_status.emit("Steam networking couldn't start a host.")
		steam.leave_lobby()
		return
	multiplayer.multiplayer_peer = peer
	transport = "steam"
	_start_roster()


func _on_steam_lobby_entered(_lobby_id: int, owner_steam_id: int) -> void:
	if owner_steam_id == steam.steam_id():
		return  # our own freshly hosted lobby
	var peer: MultiplayerPeer = steam.make_client_peer(owner_steam_id)
	if peer == null:
		lobby_status.emit("Steam networking couldn't reach the host.")
		steam.leave_lobby()
		return
	multiplayer.multiplayer_peer = peer
	transport = "steam"
	lobby_status.emit("Connecting to %s..." % steam.friend_name(owner_steam_id))


func _on_steam_invite_accepted(lobby_id: int) -> void:
	if current_state != null:
		return  # already in a game
	leave_lobby()
	join_steam(lobby_id)


# --- Lobby roster ----------------------------------------------------------------

func _start_roster() -> void:
	roster.clear()
	_next_seat = 0
	_add_member(1, local_name)
	lobby_joined.emit()
	lobby_status.emit("Lobby open - waiting for players.")
	_broadcast_roster()


func _add_member(peer_id: int, member_name: String) -> void:
	roster[peer_id] = {"name": member_name, "faction": "", "hero": "", "ready": false, "seat": _next_seat}
	_next_seat += 1


func _on_connected_to_server() -> void:
	_rpc_hello.rpc_id(1, local_name)
	lobby_joined.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(member_name: String) -> void:
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if current_state != null or roster.size() >= MAX_PLAYERS:
		return  # game already running or lobby full - the peer just watches
	if not roster.has(sender):
		_add_member(sender, member_name.substr(0, 32))
	_broadcast_roster()


## Asks the host for a faction/Hero (empty faction = release the seat's pick).
func request_pick(faction: String, hero: String) -> void:
	if is_host():
		_apply_pick(1, faction, hero)
	else:
		_rpc_pick.rpc_id(1, faction, hero)


func set_ready_state(is_ready: bool) -> void:
	if is_host():
		_apply_ready(1, is_ready)
	else:
		_rpc_ready.rpc_id(1, is_ready)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pick(faction: String, hero: String) -> void:
	if is_host():
		_apply_pick(multiplayer.get_remote_sender_id(), faction, hero)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready(is_ready: bool) -> void:
	if is_host():
		_apply_ready(multiplayer.get_remote_sender_id(), is_ready)


func _apply_pick(peer_id: int, faction: String, hero: String) -> void:
	if not roster.has(peer_id) or current_state != null:
		return
	var reason: String = validate_pick(roster, peer_id, faction, hero, get_node_or_null("/root/CardDatabase"))
	if not reason.is_empty():
		if peer_id == 1:
			lobby_status.emit(reason)
		else:
			_rpc_lobby_message.rpc_id(peer_id, reason)
		_broadcast_roster()
		return
	roster[peer_id]["faction"] = faction
	roster[peer_id]["hero"] = hero
	roster[peer_id]["ready"] = false
	_broadcast_roster()


func _apply_ready(peer_id: int, is_ready: bool) -> void:
	if not roster.has(peer_id) or current_state != null:
		return
	if is_ready and str(roster[peer_id]["faction"]).is_empty():
		is_ready = false
	roster[peer_id]["ready"] = is_ready
	_broadcast_roster()


## "" if `peer_id` may take `faction` with `hero`; else why not. An empty
## faction releases the pick. Each faction can be held by one seat only.
static func validate_pick(r: Dictionary, peer_id: int, faction: String, hero: String, card_db: Node) -> String:
	if faction.is_empty():
		return ""
	for other: Variant in r.keys():
		if int(other) != peer_id and str(r[other].get("faction", "")) == faction:
			return "%s already leads the %s." % [str(r[other].get("name", "Someone")), faction]
	if card_db != null:
		var ok: bool = false
		for h: HeroCard in card_db.heroes:
			if h.faction == faction and h.card_name == hero:
				ok = true
		if not ok:
			return "%s isn't a %s Hero." % [hero, faction]
	return ""


func _broadcast_roster() -> void:
	if multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0:
		_rpc_roster.rpc(roster)
	roster_changed.emit(roster)


@rpc("authority", "call_remote", "reliable")
func _rpc_roster(data: Dictionary) -> void:
	roster = data
	roster_changed.emit(roster)


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_message(text: String) -> void:
	lobby_status.emit(text)


## Roster members in seat order.
func seats() -> Array:
	var ids: Array = roster.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(roster[a]["seat"]) < int(roster[b]["seat"]))
	return ids


## "" when the host may start; else what's missing.
func start_blocker() -> String:
	if roster.size() < 2:
		return "Waiting for at least one more player."
	for id: Variant in roster.keys():
		var m: Dictionary = roster[id]
		if str(m["faction"]).is_empty():
			return "%s hasn't chosen a faction yet." % str(m["name"])
		if int(id) != 1 and not bool(m["ready"]):
			return "Waiting for %s to be ready." % str(m["name"])
	return ""


## Host: builds the game from the roster and sends everyone to the board.
func start_game() -> Error:
	if not is_host() or not start_blocker().is_empty():
		return ERR_UNAVAILABLE
	var card_db: Node = get_node("/root/CardDatabase")
	var picks: Array = []
	for id: Variant in seats():
		picks.append({"faction": str(roster[id]["faction"]), "hero": str(roster[id]["hero"])})
		assign_faction(int(id), str(roster[id]["faction"]))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var state: GameState = GameSetup.build_game_state(card_db, picks, rng)
	action_handler = Callable(self, "default_action_handler")
	if steam != null:
		steam.set_lobby_joinable(false)
	set_initial_state(state)
	_rpc_begin_game.rpc()
	return OK


@rpc("authority", "call_local", "reliable")
func _rpc_begin_game() -> void:
	if not is_host():
		for id: Variant in roster.keys():
			assign_faction(int(id), str(roster[id]["faction"]))
	game_starting.emit()


# --- Game state ------------------------------------------------------------------

## Host-only: sets the starting state and broadcasts it immediately.
func set_initial_state(state: GameState) -> void:
	current_state = state
	_broadcast_state()


## Any peer calls this to propose a state change. Host applies immediately;
## clients RPC it to the host and wait for the resulting broadcast (or a
## rejection notice).
func submit_action(action: Dictionary) -> void:
	if is_host():
		_apply_action(action, multiplayer.get_unique_id())
	else:
		_rpc_submit_action.rpc_id(1, action)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_submit_action(action: Dictionary) -> void:
	if not is_host():
		return  # a non-host somehow received this - ignore.
	var sender_id: int = multiplayer.get_remote_sender_id()
	_apply_action(action, sender_id)


func _apply_action(action: Dictionary, sender_id: int) -> void:
	if current_state == null:
		_rpc_notify_rejected.rpc_id(sender_id, "no active game state")
		return
	if not action_handler.is_valid():
		_rpc_notify_rejected.rpc_id(sender_id, "no action_handler registered on host")
		return

	var result: Dictionary = action_handler.call(current_state, action, sender_id)
	if result.get("ok", false):
		_broadcast_state()
	elif sender_id == multiplayer.get_unique_id():
		action_rejected.emit(str(result.get("reason", "rejected")))
	else:
		_rpc_notify_rejected.rpc_id(sender_id, str(result.get("reason", "rejected")))


func _broadcast_state() -> void:
	if current_state == null:
		return
	var payload: Dictionary = current_state.to_dict()
	if multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0:
		_rpc_receive_state.rpc(payload)
	# Apply locally too (the host is also "a peer" of its own game).
	current_state = GameState.from_dict(payload)
	state_updated.emit(current_state)


@rpc("authority", "call_remote", "reliable")
func _rpc_receive_state(state_dict: Dictionary) -> void:
	current_state = GameState.from_dict(state_dict)
	state_updated.emit(current_state)


@rpc("authority", "call_remote", "reliable")
func _rpc_notify_rejected(reason: String) -> void:
	action_rejected.emit(reason)


func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)
	if is_host() and current_state != null:
		_rpc_receive_state.rpc_id(id, current_state.to_dict())


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)
	if is_host() and roster.has(id) and current_state == null:
		var who: String = str(roster[id]["name"])
		roster.erase(id)
		lobby_status.emit("%s left the lobby." % who)
		_broadcast_roster()


func _on_connection_failed() -> void:
	connection_failed.emit()
	lobby_status.emit("Couldn't connect to the host.")
	disconnect_network()


func _on_server_disconnected() -> void:
	server_disconnected.emit()
	lobby_status.emit("The host closed the lobby.")
	if steam != null:
		steam.leave_lobby()
	disconnect_network()
