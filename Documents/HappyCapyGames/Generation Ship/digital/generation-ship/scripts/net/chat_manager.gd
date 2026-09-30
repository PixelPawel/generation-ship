extends Node

# Text chat for multiplayer sessions. Relays through the host the same way
# lobby.gd's own player-list sync does (any_peer -> rpc_id(1, ...) -> host
# re-broadcasts with @rpc("authority", ..., "call_local")) rather than
# peer-to-peer .rpc(), since that's the only delivery path this project's
# SteamMultiplayerPeer setup is already proven to guarantee reaches every
# client. Gated on multiplayer.multiplayer_peer (set the moment lobby.gd
# hosts/joins) rather than GameNetwork.is_multiplayer (only true once a
# match has actually started), so chat works in the lobby too — and each
# sender includes their own Steam display name in the payload rather than
# looking it up via GameNetwork.player_names, which likewise isn't
# populated until a match begins.

signal message_received(peer_id: int, player_name: String, text: String)

const MAX_HISTORY: int = 300
const MAX_MESSAGE_LEN: int = 300

var history: Array[Dictionary] = []   # [{peer_id, name, text}, ...]

func send_message(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	text = text.substr(0, MAX_MESSAGE_LEN)
	if not multiplayer.multiplayer_peer:
		return
	var my_id: int = multiplayer.get_unique_id()
	var my_name: String = _local_name()
	if multiplayer.is_server():
		_rpc_deliver.rpc(my_id, my_name, text)
	else:
		_rpc_relay.rpc_id(1, my_name, text)

func clear_history() -> void:
	history.clear()

# The name typed in the lobby first (also the only one Android players
# have), then the Steam persona name.
func _local_name() -> String:
	var lobby_name: String = str(GameNetwork.player_names.get(multiplayer.get_unique_id(), ""))
	if not lobby_name.is_empty():
		return lobby_name
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		var saved: String = str(cfg.get_value("player", "name", ""))
		if not saved.is_empty():
			return saved
	if SteamManager.is_initialized:
		var n: String = Steam.getPersonaName()
		if not n.is_empty():
			return n
	return tr("Player")

@rpc("any_peer", "reliable")
func _rpc_relay(sender_name: String, text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	text = text.strip_edges().substr(0, MAX_MESSAGE_LEN)
	if text.is_empty():
		return
	_rpc_deliver.rpc(sender_id, sender_name.substr(0, 60), text)

@rpc("authority", "reliable", "call_local")
func _rpc_deliver(peer_id: int, player_name: String, text: String) -> void:
	history.append({"peer_id": peer_id, "name": player_name, "text": text})
	if history.size() > MAX_HISTORY:
		history.pop_front()
	message_received.emit(peer_id, player_name, text)
