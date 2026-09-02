extends Node

## Autoload. Host-authoritative networking over Godot's high-level ENet
## multiplayer API. Deliberately knows NOTHING about Uprising's rules - it
## just moves an arbitrary GameState and routes action-dicts through one
## pluggable handler the game layer supplies. This keeps GameActions
## (Milestone 4) addable later without touching this file at all.
##
## Flow: any peer calls submit_action(dict). If we ARE the host, apply
## locally. If we're a client, RPC it to the host. The host validates/
## applies via `action_handler` (Callable(state, action, sender_peer_id) ->
## {ok: bool, reason: String}) and, on success, rebroadcasts the full
## resulting state to everyone; on failure, notifies only the requester.

signal state_updated(state: GameState)
signal action_rejected(reason: String)
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal connection_failed()
signal server_disconnected()

## Set by the game layer (host-side only - never called on clients).
## func(state: GameState, action: Dictionary, sender_peer_id: int) -> Dictionary
var action_handler: Callable = Callable()

var current_state: GameState = null


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void: server_disconnected.emit())


func host_game(port: int, max_clients: int = 8) -> Error:
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


func disconnect_network() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	current_state = null


func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


## Host-only: sets the starting state and broadcasts it immediately - call
## once, right after host_game(), before anyone submits actions.
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
