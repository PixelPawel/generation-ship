extends Node
## Autoload singleton. Host-authoritative networking: the host holds the only
## GameState that matters. Every peer (including the host's own UI) submits
## action *requests*; only the host validates and applies them, then
## broadcasts the resulting authoritative state to everyone. This keeps a
## single source of truth and sidesteps a whole class of desync bugs, which
## matters a lot more for a rules-heavy game like this than raw bandwidth
## efficiency -- so v1 broadcasts the full state dict rather than deltas.

signal state_updated(state: GameState)
signal action_rejected(reason: String)
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed
signal connected_to_host

const DEFAULT_PORT := 8910

var is_host: bool = false
var game_state: GameState = null


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit())
	multiplayer.connected_to_server.connect(func() -> void: connected_to_host.emit())


func host_game(state: GameState, port: int = DEFAULT_PORT, max_players: int = 4) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	game_state = state
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	is_host = false
	game_state = null


func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)
	if is_host and game_state != null:
		_receive_full_state.rpc_id(id, game_state.to_dict())


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)


## Call this from game logic on ANY peer (host or client) to request an
## action. Actions are plain Dictionaries, e.g. {"type": "move", "faction":
## "Krowh", "to": [1, 0]} -- kept as data (not custom objects) so they marshal
## over RPC with no extra work and double as a natural action-log format.
func submit_action(action: Dictionary) -> void:
	if is_host:
		_apply_action(action, multiplayer.get_unique_id())
	else:
		_request_action.rpc_id(1, action)


@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: Dictionary) -> void:
	if not is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_action(action, sender_id)


func _apply_action(action: Dictionary, sender_id: int) -> void:
	if game_state == null:
		_reject(sender_id, "no active game")
		return
	var result := GameActions.apply(game_state, action, sender_id, CardDatabase)
	if not result.get("ok", false):
		_reject(sender_id, result.get("reason", "action rejected"))
		return
	_receive_full_state.rpc(game_state.to_dict())


## Requests moving to the next Phase (GameFlow.advance_phase) -- separate
## from submit_action() since it isn't scoped to one faction; any connected
## peer can request it (e.g. whoever notices everyone's done with Actions).
## A refusal (still waiting on active players, etc.) surfaces the same way a
## rejected action does, via action_rejected.
func submit_advance_phase() -> void:
	if is_host:
		_apply_advance_phase(multiplayer.get_unique_id())
	else:
		_request_advance_phase.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_advance_phase() -> void:
	if not is_host:
		return
	_apply_advance_phase(multiplayer.get_remote_sender_id())


func _apply_advance_phase(sender_id: int) -> void:
	if game_state == null:
		_reject(sender_id, "no active game")
		return
	var result := GameFlow.advance_phase(game_state, CardDatabase)
	if not result.get("ok", false):
		_reject(sender_id, result.get("reason", "cannot advance yet"))
		return
	_receive_full_state.rpc(game_state.to_dict())


func _reject(sender_id: int, reason: String) -> void:
	if sender_id == multiplayer.get_unique_id():
		action_rejected.emit(reason)
	else:
		_notify_rejected.rpc_id(sender_id, reason)


@rpc("authority", "call_remote", "reliable")
func _notify_rejected(reason: String) -> void:
	action_rejected.emit(reason)


@rpc("authority", "call_local", "reliable")
func _receive_full_state(state_dict: Dictionary) -> void:
	game_state = GameState.from_dict(state_dict)
	state_updated.emit(game_state)
