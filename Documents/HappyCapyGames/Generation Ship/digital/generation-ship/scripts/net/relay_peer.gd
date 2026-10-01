class_name RelayMultiplayerPeer
extends MultiplayerPeerExtension
# Multiplayer transport through the Happy Capy Games relay server
# (digital/server/app/relay.py) — replaces SteamMultiplayerPeer so Steam and
# Android players can meet in the same online rooms.
#
# Keeps the same shape the game already relies on: the host is peer 1,
# every other player only talks to the host, and SceneMultiplayer relays any
# client-to-client traffic through the host (server relay supported).
# Everything goes over one secure WebSocket (built into Godot, all platforms).
#
# Usage: create_host(...) / create_client(...), assign to
# multiplayer.multiplayer_peer, then wait for room_ready (host) or
# multiplayer.connected_to_server (client). On failure, `error_reason` holds
# the server's reason ("wrong_password", "full", "not_found", ...) or
# "unreachable".

signal room_ready(code: String)

const RELAY_URL: String = "wss://api.happycapygames.com/v1/relay"
const _MAX_PACKET: int = 1 << 20
const _BUFFER: int = 4 << 20   # 4 MiB in/out, game state snapshots can be big
const _CONNECT_TIMEOUT_MS: int = 10000

var room_code: String = ""
var error_reason: String = ""

var _ws: WebSocketPeer = WebSocketPeer.new()
var _is_host: bool = false
var _unique_id: int = 0
var _status: MultiplayerPeer.ConnectionStatus = MultiplayerPeer.CONNECTION_DISCONNECTED
var _hello: Dictionary = {}
var _hello_sent: bool = false
# Connect timeout counts only time the game was actually running: a long
# frame (editor debug run loading right after launch) used to eat the whole
# budget before the first poll, failing a connection that never got a chance.
var _connect_elapsed_ms: int = 0
var _last_poll_ms: int = 0
const _MAX_COUNTED_FRAME_MS: int = 100
var _incoming: Array[Dictionary] = []   # {from, mode, channel, data}
var _target_peer: int = 0
var _transfer_mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _refusing: bool = false
var _peers: Dictionary = {}   # host only: peer id -> true

func create_host(player_name: String, password: String, max_players: int, version: String) -> Error:
	_is_host = true
	_unique_id = 1
	return _open({op = "host", name = player_name, password = password, max_players = max_players, version = version})

func create_client(code: String, player_name: String, password: String, version: String) -> Error:
	_is_host = false
	_unique_id = 0
	return _open({op = "join", room = code.strip_edges().to_upper(), name = player_name, password = password, version = version})

# Host only: tells the server the room has started (hidden from the list,
# no more joins) — call when the match loads.
func mark_started() -> void:
	_send_control({op = "start"})

# Host only: player count shown in the room list, including bots.
func report_player_count(count: int) -> void:
	_send_control({op = "players", count = count})

func _open(hello: Dictionary) -> Error:
	_ws.inbound_buffer_size = _BUFFER
	_ws.outbound_buffer_size = _BUFFER
	_ws.max_queued_packets = 4096
	var err: Error = _ws.connect_to_url(RELAY_URL)
	if err != OK:
		error_reason = "unreachable"
		return err
	_hello = hello
	_hello_sent = false
	_connect_elapsed_ms = 0
	_last_poll_ms = Time.get_ticks_msec()
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	return OK

func _send_control(msg: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))

# ── MultiplayerPeerExtension ─────────────────────────────────────────────────

func _poll() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	_ws.poll()
	var state: WebSocketPeer.State = _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _hello_sent:
			_ws.send_text(JSON.stringify(_hello))
			_hello_sent = true
		while _ws.get_available_packet_count() > 0:
			var data: PackedByteArray = _ws.get_packet()
			if _ws.was_string_packet():
				_on_control(data.get_string_from_utf8())
			elif data.size() >= 6:
				_incoming.append({
					from = data.decode_s32(0), mode = data[4], channel = data[5], data = data.slice(6),
				})
	elif state == WebSocketPeer.STATE_CLOSED:
		_on_closed()
	var now: int = Time.get_ticks_msec()
	_connect_elapsed_ms += mini(now - _last_poll_ms, _MAX_COUNTED_FRAME_MS)
	_last_poll_ms = now
	if _status == MultiplayerPeer.CONNECTION_CONNECTING and _connect_elapsed_ms > _CONNECT_TIMEOUT_MS:
		error_reason = "unreachable"
		_ws.close()
		_on_closed()

func _on_control(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	match str(msg.get("op", "")):
		"welcome":
			_unique_id = int(msg.get("id", 0))
			room_code = str(msg.get("room", ""))
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			if _is_host:
				room_ready.emit(room_code)
			else:
				peer_connected.emit(1)   # SceneMultiplayer -> connected_to_server
		"error":
			error_reason = str(msg.get("reason", "error"))
		"peer_joined":
			var id: int = int(msg.get("id", 0))
			if _refusing:
				_send_control({op = "kick", id = id})
			elif id > 1:
				_peers[id] = true
				peer_connected.emit(id)
		"peer_left":
			var left: int = int(msg.get("id", 0))
			if _peers.erase(left):
				peer_disconnected.emit(left)

func _on_closed() -> void:
	if _status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	if _status == MultiplayerPeer.CONNECTION_CONNECTING and error_reason.is_empty():
		error_reason = "unreachable"
	var was_connected: bool = _status == MultiplayerPeer.CONNECTION_CONNECTED
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	if was_connected:
		if _is_host:
			for id: int in _peers.keys():
				peer_disconnected.emit(id)
		else:
			peer_disconnected.emit(1)
	_peers.clear()

func _close() -> void:
	_ws.close()
	_incoming.clear()
	_peers.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED

func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	if _is_host and _peers.has(p_peer):
		_send_control({op = "kick", id = p_peer})

func _get_available_packet_count() -> int:
	return _incoming.size()

func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front().data

# SceneMultiplayer asks for the sender/channel/mode of the NEXT packet before
# fetching it, so these all look at the front of the queue.
func _get_packet_peer() -> int:
	return int(_incoming.front().from) if not _incoming.is_empty() else 0

func _get_packet_channel() -> int:
	return int(_incoming.front().channel) if not _incoming.is_empty() else 0

func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	if _incoming.is_empty():
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	return int(_incoming.front().mode) as MultiplayerPeer.TransferMode

func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if p_buffer.size() > _MAX_PACKET:
		return ERR_OUT_OF_MEMORY
	var header: PackedByteArray = PackedByteArray()
	header.resize(6)
	header.encode_s32(0, _target_peer if _is_host else 1)
	header[4] = int(_transfer_mode)
	header[5] = _transfer_channel
	return _ws.send(header + p_buffer)

func _get_max_packet_size() -> int:
	return _MAX_PACKET

func _set_transfer_channel(p_channel: int) -> void:
	_transfer_channel = clampi(p_channel, 0, 255)

func _get_transfer_channel() -> int:
	return _transfer_channel

func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void:
	_transfer_mode = p_mode

func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _transfer_mode

func _set_target_peer(p_peer: int) -> void:
	_target_peer = p_peer

func _is_server() -> bool:
	return _is_host

func _get_unique_id() -> int:
	return _unique_id

func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status

func _set_refuse_new_connections(p_enable: bool) -> void:
	_refusing = p_enable

func _is_refusing_new_connections() -> bool:
	return _refusing

func _is_server_relay_supported() -> bool:
	return true
