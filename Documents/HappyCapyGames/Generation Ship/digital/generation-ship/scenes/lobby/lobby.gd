extends Control

const MAX_PLAYERS: int = 4
const SETTINGS_PATH: String = "user://settings.cfg"
const LOBBY_REFRESH_INTERVAL: float = 5.0

var _player_name: String = ""
var _players: Dictionary = {}      # peer_id (int) -> name (String)
var _preload_done: bool = false
var _loading_label: Label = null
var _players_ready: Dictionary = {}   # peer_id (int) -> true, tracked on host only
var _steam_lobby_id: int = 0
var _lobby_refresh_timer: float = 0.0
var _is_host: bool = false
var _spinner_active: bool = false
var _spinner_time: float = 0.0
var _bot_count: int = 0
var _add_bot_btn: Button = null
var _remove_bot_btn: Button = null

const _SPINNER_FRAMES: Array[String] = [
	"|", "/", "—", "\\", "|", "/", "—", "\\", "|", "/",
	"—", "\\", "|", "/", "—", "\\", "|", "/", "—", "\\",
	"|", "/", "—", "\\", "|", "/", "—", "\\", "|", "/",
	"—", "\\", "|", "/", "—", "\\", "|", "/", "—", "\\",
]

@onready var _lobby_panel: VBoxContainer = $LobbyPanel
@onready var _name_input: LineEdit = $LobbyPanel/NameRow/NameInput
@onready var _host_btn: Button = $LobbyPanel/HostBtn
@onready var _game_list: ItemList = $LobbyPanel/GameList
@onready var _join_selected_btn: Button = $LobbyPanel/JoinSelectedBtn
@onready var _status_label: Label = $LobbyPanel/StatusLabel

@onready var _staging_panel: Control = $StagingPanel
@onready var _staging_player_list: Label = $StagingPanel/VBox/PlayerList
@onready var _staging_start_btn: Button = $StagingPanel/VBox/StartBtn
@onready var _staging_ip_row: HBoxContainer = $StagingPanel/VBox/IPRow

func _ready() -> void:
	theme = GameTheme.get_theme()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_joined.connect(_on_lobby_entered)
	Steam.join_requested.connect(_on_lobby_join_requested)
	_staging_ip_row.visible = false
	($LobbyPanel/DirectRow as Control).visible = false
	_load_saved_name()
	_request_lobby_list()

func _process(delta: float) -> void:
	if _spinner_active:
		_spinner_time += delta
		var frame: int = int(_spinner_time * 8.0) % _SPINNER_FRAMES.size()
		_status_label.text = "Creating lobby…  " + _SPINNER_FRAMES[frame]
	if not _lobby_panel.visible:
		return
	_lobby_refresh_timer -= delta
	if _lobby_refresh_timer <= 0.0:
		_lobby_refresh_timer = LOBBY_REFRESH_INTERVAL
		_request_lobby_list()

# ── Panel switching ───────────────────────────────────────────────────────────

func _show_staging() -> void:
	_lobby_panel.visible = false
	_staging_panel.visible = true
	_staging_start_btn.visible = multiplayer.is_server()
	_preload_done = false
	_players_ready.clear()
	_refresh_player_list()
	_start_preload()
	if multiplayer.is_server() and not _add_bot_btn:
		var vbox: VBoxContainer = $StagingPanel/VBox
		var insert_idx: int = _staging_start_btn.get_index()
		var bot_row: HBoxContainer = HBoxContainer.new()
		bot_row.add_theme_constant_override("separation", 8)
		vbox.add_child(bot_row)
		vbox.move_child(bot_row, insert_idx)
		_add_bot_btn = Button.new()
		_add_bot_btn.text = "Add Bot"
		_add_bot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_add_bot_btn.custom_minimum_size = Vector2(0, 44)
		_add_bot_btn.add_theme_font_size_override("font_size", 20)
		_add_bot_btn.pressed.connect(_on_add_bot_pressed)
		bot_row.add_child(_add_bot_btn)
		_remove_bot_btn = Button.new()
		_remove_bot_btn.text = "Remove Bot"
		_remove_bot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_remove_bot_btn.custom_minimum_size = Vector2(0, 44)
		_remove_bot_btn.add_theme_font_size_override("font_size", 20)
		_remove_bot_btn.disabled = true
		_remove_bot_btn.pressed.connect(_on_remove_bot_pressed)
		bot_row.add_child(_remove_bot_btn)

func _start_preload() -> void:
	var vbox: VBoxContainer = $StagingPanel/VBox
	if not _loading_label:
		_loading_label = Label.new()
		_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading_label.add_theme_font_size_override("font_size", 13)
		_loading_label.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
		vbox.add_child(_loading_label)
	_loading_label.text = "Loading card images…"
	if not ImageCache.progress_updated.is_connected(_on_preload_progress):
		ImageCache.progress_updated.connect(_on_preload_progress)
	if not ImageCache.all_loaded.is_connected(_on_preload_done):
		ImageCache.all_loaded.connect(_on_preload_done)
	var urls: Array[String] = []
	for cd: CardData in CardDatabase.sectors:
		if not cd.image_url.is_empty():
			urls.append(cd.image_url)
		if not cd.adv_image_url.is_empty():
			urls.append(cd.adv_image_url)
	for cd: CardData in CardDatabase.techs:
		if not cd.image_url.is_empty():
			urls.append(cd.image_url)
	for cd: CardData in CardDatabase.expeditions:
		if not cd.image_url.is_empty():
			urls.append(cd.image_url)
	ImageCache.preload_urls(urls)

func _on_preload_progress(loaded: int, total: int) -> void:
	if _loading_label:
		_loading_label.text = "Loading card images… %d / %d" % [loaded, total]

func _on_preload_done() -> void:
	_preload_done = true
	if _loading_label:
		_loading_label.text = "Card images ready"
	if ImageCache.progress_updated.is_connected(_on_preload_progress):
		ImageCache.progress_updated.disconnect(_on_preload_progress)
	if ImageCache.all_loaded.is_connected(_on_preload_done):
		ImageCache.all_loaded.disconnect(_on_preload_done)
	if multiplayer.is_server():
		_players_ready[1] = true
		_refresh_player_list()
	else:
		_rpc_notify_ready.rpc_id(1)

func _show_lobby() -> void:
	_staging_panel.visible = false
	_lobby_panel.visible = true
	_set_controls_locked(false)
	_lobby_refresh_timer = 0.0
	_is_host = false

# ── Lobby list ────────────────────────────────────────────────────────────────

func _request_lobby_list() -> void:
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("game", "generation_ship", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array) -> void:
	_set_status("Found %d lobbies" % lobbies.size())
	var prev_selected: int = 0
	var sel: PackedInt32Array = _game_list.get_selected_items()
	if not sel.is_empty():
		prev_selected = int(_game_list.get_item_metadata(sel[0]))
	_game_list.clear()
	for entry: Variant in lobbies:
		var lobby_id: int = int(entry)
		var host_name: String = Steam.getLobbyData(lobby_id, "host_name")
		if host_name.is_empty():
			host_name = "Unknown"
		_game_list.add_item(host_name)
		_game_list.set_item_metadata(_game_list.item_count - 1, lobby_id)
		if lobby_id == prev_selected:
			_game_list.select(_game_list.item_count - 1)

# ── Hosting ───────────────────────────────────────────────────────────────────

func _on_host_pressed() -> void:
	_player_name = _read_name()
	_set_controls_locked(true)
	_spinner_active = true
	_spinner_time = 0.0
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)

func _on_lobby_created(connect_result: int, lobby_id: int) -> void:
	_spinner_active = false
	if connect_result != 1:
		_set_status("Failed to create lobby.")
		_set_controls_locked(false)
		return
	_steam_lobby_id = lobby_id
	Steam.setLobbyData(lobby_id, "game", "generation_ship")
	Steam.setLobbyData(lobby_id, "host_name", _player_name)
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		_set_status("SteamMultiplayerPeer not found — install the GodotSteam MultiplayerPeer addon.")
		_set_controls_locked(false)
		return
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	peer.call("create_host", 0)
	multiplayer.multiplayer_peer = peer
	_is_host = true
	_players[1] = _player_name
	_show_staging()

# ── Joining ───────────────────────────────────────────────────────────────────

func _on_join_selected_pressed() -> void:
	var selected: PackedInt32Array = _game_list.get_selected_items()
	if selected.is_empty():
		_set_status("Select a game from the list first.")
		return
	var lobby_id: int = int(_game_list.get_item_metadata(selected[0]))
	_set_controls_locked(true)
	_set_status("Joining lobby…")
	Steam.joinLobby(lobby_id)

func _on_lobby_entered(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_set_status("Failed to join lobby.")
		_set_controls_locked(false)
		return
	_steam_lobby_id = lobby_id
	if _is_host:
		return
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		_set_status("SteamMultiplayerPeer not found — install the GodotSteam MultiplayerPeer addon.")
		_set_controls_locked(false)
		return
	var host_steam_id: int = Steam.getLobbyOwner(lobby_id)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	peer.call("create_client", host_steam_id, 0)
	multiplayer.multiplayer_peer = peer
	_set_status("Connecting…")

func _on_lobby_join_requested(lobby_id: int, _steam_id: int) -> void:
	_set_controls_locked(true)
	_set_status("Joining lobby…")
	Steam.joinLobby(lobby_id)

# ── Start / Leave / Back ──────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		_rpc_load_game.rpc()

func _on_leave_pressed() -> void:
	if _steam_lobby_id > 0:
		Steam.leaveLobby(_steam_lobby_id)
		_steam_lobby_id = 0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_players.clear()
	_bot_count = 0
	_add_bot_btn = null
	_remove_bot_btn = null
	_show_lobby()

func _on_back_pressed() -> void:
	if _steam_lobby_id > 0:
		Steam.leaveLobby(_steam_lobby_id)
		_steam_lobby_id = 0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	SceneTransition.change_scene("res://scenes/main_menu/main_menu.tscn")

# ── Multiplayer signals ───────────────────────────────────────────────────────

func _on_peer_connected(_id: int) -> void:
	pass

func _on_connection_failed() -> void:
	_set_status("Connection to host failed.")
	_set_controls_locked(false)
	multiplayer.multiplayer_peer = null
	_is_host = false

func _on_peer_disconnected(id: int) -> void:
	_players.erase(id)
	_players_ready.erase(id)
	if multiplayer.is_server():
		_rpc_sync_players.rpc(_players)
	_refresh_player_list()

func _on_connected_to_server() -> void:
	_player_name = _read_name()
	_rpc_register.rpc_id(1, _player_name)
	_show_staging()

func _on_server_disconnected() -> void:
	_set_status("Lost connection to host.")
	_players.clear()
	if _steam_lobby_id > 0:
		Steam.leaveLobby(_steam_lobby_id)
		_steam_lobby_id = 0
	multiplayer.multiplayer_peer = null
	_show_lobby()

# ── RPCs ──────────────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func _rpc_notify_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_players_ready[sender_id] = true
	_refresh_player_list()

@rpc("any_peer", "reliable")
func _rpc_register(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	_players[multiplayer.get_remote_sender_id()] = player_name
	_rpc_sync_players.rpc(_players)

@rpc("authority", "reliable", "call_local")
func _rpc_sync_players(players: Dictionary) -> void:
	_players = players
	_refresh_player_list()

@rpc("authority", "reliable", "call_local")
func _rpc_load_game() -> void:
	if _steam_lobby_id > 0:
		Steam.leaveLobby(_steam_lobby_id)
		_steam_lobby_id = 0
	var real_ids: Array[int] = []
	var bot_ids_local: Array[int] = []
	for k: Variant in _players.keys():
		var id: int = int(k)
		if id < 0:
			bot_ids_local.append(id)
		else:
			real_ids.append(id)
	real_ids.sort()
	real_ids.append_array(bot_ids_local)
	GameNetwork.setup_multiplayer(multiplayer.is_server(), real_ids)
	GameNetwork.player_names = _players.duplicate()
	GameNetwork.bot_ids = bot_ids_local
	SceneTransition.change_scene("res://scenes/main/main.tscn")

# ── Helpers ───────────────────────────────────────────────────────────────────

func _on_add_bot_pressed() -> void:
	if _players.size() >= MAX_PLAYERS:
		return
	_bot_count += 1
	var bot_id: int = -_bot_count
	_players[bot_id] = "Bot %d" % _bot_count
	_players_ready[bot_id] = true
	_rpc_sync_players.rpc(_players)
	_refresh_player_list()

func _on_remove_bot_pressed() -> void:
	for i: int in range(_bot_count, 0, -1):
		var bot_id: int = -i
		if _players.has(bot_id):
			_players.erase(bot_id)
			_players_ready.erase(bot_id)
			_bot_count = i - 1
			_rpc_sync_players.rpc(_players)
			_refresh_player_list()
			return

func _refresh_player_list() -> void:
	if _players.is_empty():
		_staging_player_list.text = "(no players)"
	else:
		var lines: Array[String] = []
		for id: int in _players:
			var tag: String = ""
			if id == 1:
				tag = "  ★ host"
			elif id < 0:
				tag = "  [bot]"
			lines.append("• %s%s" % [_players[id], tag])
		_staging_player_list.text = "\n".join(lines)
	var all_ready: bool = not _players.is_empty()
	for pid: Variant in _players:
		if not _players_ready.has(int(pid)):
			all_ready = false
			break
	_staging_start_btn.disabled = not all_ready
	var has_any_bot: bool = false
	for pid: Variant in _players:
		if int(pid) < 0:
			has_any_bot = true
			break
	if _add_bot_btn:
		_add_bot_btn.disabled = _players.size() >= MAX_PLAYERS
	if _remove_bot_btn:
		_remove_bot_btn.disabled = not has_any_bot

func _set_status(msg: String) -> void:
	_status_label.text = msg

func _set_controls_locked(locked: bool) -> void:
	_host_btn.disabled = locked
	_join_selected_btn.disabled = locked
	_game_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP

func _read_name() -> String:
	var n: String = _name_input.text.strip_edges()
	if n.is_empty():
		n = "Player"
	_save_name(n)
	return n

func _save_name(n: String) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("player", "name", n)
	cfg.save(SETTINGS_PATH)

func _on_refresh_pressed() -> void:
	_request_lobby_list()
	_lobby_refresh_timer = LOBBY_REFRESH_INTERVAL

func _on_invite_pressed() -> void:
	if _steam_lobby_id > 0:
		Steam.activateGameOverlayInviteDialog(_steam_lobby_id)

func _load_saved_name() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved: String = str(cfg.get_value("player", "name", ""))
		if not saved.is_empty():
			_name_input.text = saved
