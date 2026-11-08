extends Node

# Set to true once a multiplayer session is active. Solo play leaves this false
# so all is_my_turn() checks pass unconditionally.
var is_multiplayer: bool = false
var is_host: bool = false

# Peer ID of the player whose turn it currently is.
var active_peer_id: int = 1

# Ordered list of peer IDs — determines turn rotation within a generation.
var player_order: Array[int] = []

# peer_id → player name string, populated from lobby before scene change.
var player_names: Dictionary = {}

# IDs of bot (dummy) players managed locally by the host.
var bot_ids: Array[int] = []

# Difficulty per bot: bot_id → int (BotAI.Difficulty). Set by lobby before scene change.
var bot_difficulty: Dictionary = {}

# Generation Fleet (co-op): set by the menu's Destination pick before the game
# scene loads. fleet_destination is the Destination card's No. (see FleetData).
var fleet_mode: bool = false
var fleet_destination: int = 0
var fleet_seed: int = 0   # online: the host's Danger-deck shuffle seed, the same on every peer

# Returns true when the local player is allowed to take an action.
func is_my_turn() -> bool:
	if not is_multiplayer:
		return true
	return multiplayer.get_unique_id() == active_peer_id

# Call this when starting a solo game.
func setup_solo() -> void:
	is_multiplayer = false
	is_host = true
	active_peer_id = 1
	player_order = [1]
	# The game asks "which player am I?" everywhere; without a peer (a solo game
	# started outside the lobby, e.g. the Tutorial) that's an error. The offline
	# peer answers 1, like a bots-only lobby game.
	if multiplayer.multiplayer_peer == null or not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

# Call this from the lobby before changing to the game scene.
# ordered_peer_ids must be in the same order on every client (sort them first).
func setup_multiplayer(host: bool, ordered_peer_ids: Array[int]) -> void:
	is_multiplayer = true
	is_host = host
	player_order = ordered_peer_ids
	active_peer_id = ordered_peer_ids[0]

func is_bot(peer_id: int) -> bool:
	return bot_ids.has(peer_id)

# ── Online version ───────────────────────────────────────────────────────────
# Rooms only list and join the exact same version string (server relay.py). config/version
# stays "1.0" from release to release, so builds whose RPCs no longer match met in one room:
# Godot addresses a node's RPCs by their place in its RPC list and checks argument counts, and
# CardRef sends cards as list indices. So the string also carries a fingerprint of exactly what
# peers must agree on: every RPC (script, name, argument count, mode) and the card sheets. It
# changes by itself whenever one of them does, and is the same on Steam and Android (the same
# scripts and CSVs). A rules-only change (same RPCs and cards) still needs NET_PROTOCOL raised.
const NET_PROTOCOL: int = 1
const _RPC_SCRIPTS: Array[String] = [
	"res://scenes/main/main.gd", "res://scenes/lobby/lobby.gd",
	"res://scripts/net/chat_manager.gd", "res://scripts/net/voice_manager.gd",
]
const _CARD_SHEETS: Array[String] = [
	"res://data/Generation Ship Full Card Details - Dust Sectors.csv",
	"res://data/Generation Ship Full Card Details - Advanced Sectors.csv",
	"res://data/Generation Ship Full Card Details - Techs.csv",
	"res://data/Generation Ship Full Card Details - Promos.csv",
	"res://data/Generation Ship Full Card Details - Expeditions.csv",
]
var _net_version: String = ""
var _rpc_script_refs: Array[Script] = []   # kept loaded: the game needs them anyway

func _ready() -> void:
	# main.gd takes about a second to compile: in the background now, during the studio intro,
	# rather than as a freeze when the menu's lobby first asks for net_version()
	for path: String in _RPC_SCRIPTS:
		if not ResourceLoader.has_cached(path):
			ResourceLoader.load_threaded_request(path)

func net_version() -> String:
	if _net_version.is_empty():
		var rpcs: PackedStringArray = PackedStringArray()
		for path: String in _RPC_SCRIPTS:
			var script: Script = null
			if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				script = ResourceLoader.load_threaded_get(path) as Script   # waits if still loading
			if script == null:
				script = load(path) as Script
			if script == null:
				continue
			_rpc_script_refs.append(script)
			var argc: Dictionary = {}
			for m: Dictionary in script.get_script_method_list():
				argc[str(m.get("name", ""))] = (m.get("args", []) as Array).size()
			var config: Variant = script.get_rpc_config()
			if typeof(config) != TYPE_DICTIONARY:
				continue
			for method: Variant in (config as Dictionary).keys():
				var c: Dictionary = (config as Dictionary)[method] as Dictionary
				rpcs.append("%s:%s/%d/%d/%d/%d/%d" % [path.get_file(), str(method), int(argc.get(str(method), -1)),
						int(c.get("rpc_mode", 0)), int(c.get("transfer_mode", 0)), int(bool(c.get("call_local", false))),
						int(c.get("channel", 0))])
		rpcs.sort()
		var parts: PackedStringArray = PackedStringArray([str(NET_PROTOCOL), ",".join(rpcs)])
		for sheet: String in _CARD_SHEETS:
			parts.append(FileAccess.get_md5(sheet))
		_net_version = "%s+%s" % [str(ProjectSettings.get_setting("application/config/version", "0")),
				"|".join(parts).md5_text().substr(0, 10)]
	return _net_version

# Advance to the next player in turn order.
func advance_turn() -> void:
	if player_order.is_empty():
		return
	var idx: int = player_order.find(active_peer_id)
	active_peer_id = player_order[(idx + 1) % player_order.size()]
