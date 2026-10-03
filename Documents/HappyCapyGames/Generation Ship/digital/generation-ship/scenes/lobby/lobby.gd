extends Control

signal back_requested
signal staging_requested
signal lobby_view_requested

const MAX_PLAYERS: int = 4
const SETTINGS_PATH: String = "user://settings.cfg"
const LOBBY_REFRESH_INTERVAL: float = 5.0
const BOT_NAMES: Array[String] = ["Rusty", "Circuit", "Quantum"]  # Easy, Normal, Hard — proper nouns, not translated; original names, not references to copyrighted characters/products
# Online rooms live on the Happy Capy Games server (digital/server/app/relay.py),
# shared by Steam and Android players. Only rooms of the same game version
# are listed/joinable.
const ROOMS_URL: String = "https://api.happycapygames.com/v1/rooms"

var _player_name: String = ""
var _players: Dictionary = {}      # peer_id (int) -> name (String)
var _preload_done: bool = false
var _players_ready: Dictionary = {}   # peer_id (int) -> true, tracked on host only
var _lobby_refresh_timer: float = 0.0
var _is_host: bool = false
var _spinner_active: bool = false
var _spinner_time: float = 0.0
var _bot_count: int = 0
var _manual: Control = null
var _bot_row: HBoxContainer = null
var _add_bot_btn: Button = null
var _remove_bot_btn: Button = null
var _diff_btn: OptionButton = null
var _bot_difficulties: Dictionary = {}   # bot_id → int (BotAI.Difficulty)
var _rooms: Array[Dictionary] = []   # from the server: {code, name, players, max_players, locked}
var _rooms_http: HTTPRequest = null
var _relay: RelayMultiplayerPeer = null
var _hosting_pending: bool = false   # waiting for the server to confirm our new room
var _room_code: String = ""
var _pending_join_code: String = ""
var _password_prompt: Control = null
var _password_prompt_input: LineEdit = null
var _password_prompt_error: Label = null
var _chat_panel: Control = null

const _SPINNER_FRAMES: Array[String] = [
	"|", "/", "—", "\\", "|", "/", "—", "\\", "|", "/",
	"—", "\\", "|", "/", "—", "\\", "|", "/", "—", "\\",
	"|", "/", "—", "\\", "|", "/", "—", "\\", "|", "/",
	"—", "\\", "|", "/", "—", "\\", "|", "/", "—", "\\",
]

@onready var _lobby_panel: VBoxContainer = $LobbyPanel
@onready var _name_input: LineEdit = $LobbyPanel/NameRow/NameInput
@onready var _password_input: LineEdit = $LobbyPanel/PasswordRow/PasswordInput
@onready var _host_btn: Button = $LobbyPanel/HostBtn
@onready var _password_only_check: CheckBox = $LobbyPanel/FiltersRow/PasswordOnlyCheck
@onready var _friends_only_check: CheckBox = $LobbyPanel/FiltersRow/FriendsOnlyCheck
@onready var _game_list: ItemList = $LobbyPanel/GameList
@onready var _join_selected_btn: Button = $LobbyPanel/JoinSelectedBtn
@onready var _status_label: Label = $LobbyPanel/StatusLabel
@onready var _code_input: LineEdit = $LobbyPanel/DirectRow/IPInput
@onready var _code_join_btn: Button = $LobbyPanel/DirectRow/DirectJoinBtn

@onready var _staging_panel: Control = $StagingPanel
@onready var _staging_player_list: Label = $StagingPanel/VBox/PlayerList
@onready var _staging_start_btn: Button = $StagingPanel/VBox/StartBtn
@onready var _staging_ip_row: HBoxContainer = $StagingPanel/VBox/IPRow
@onready var _staging_code_label: Label = $StagingPanel/VBox/IPRow/IPLabel
@onready var _staging_copy_btn: Button = $StagingPanel/VBox/IPRow/CopyIPBtn

func _ready() -> void:
	theme = GameTheme.get_theme()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	_rooms_http = HTTPRequest.new()
	_rooms_http.timeout = 10.0
	_rooms_http.request_completed.connect(_on_rooms_received)
	add_child(_rooms_http)
	# Repurpose the scene's old Steam/LAN-era widgets for online rooms.
	($LobbyPanel/GamesRow/GamesLabel as Label).text = tr("Online Games:")
	_friends_only_check.visible = false   # no friends list outside Steam
	($StagingPanel/VBox/InviteBtn as Control).visible = false   # the room code replaces Steam invites
	_code_input.text = ""
	_code_input.placeholder_text = tr("Room code…")
	_code_input.max_length = 6
	_code_input.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	_code_join_btn.text = tr("Join Code")
	_staging_copy_btn.text = tr("Copy Code")
	($LobbyPanel/DirectRow as Control).visible = true
	_staging_ip_row.visible = false
	_manual = load("res://scenes/ui/manual_popup.gd").new()
	add_child(_manual)
	_chat_panel = load("res://scenes/ui/chat_panel.gd").new()
	add_child(_chat_panel)
	_build_password_prompt()
	_load_saved_name()
	_request_lobby_list()
	_lobby_refresh_timer = LOBBY_REFRESH_INTERVAL

func _process(delta: float) -> void:
	if _spinner_active:
		_spinner_time += delta
		var frame: int = int(_spinner_time * 8.0) % _SPINNER_FRAMES.size()
		_status_label.text = tr("Creating lobby…  ") + _SPINNER_FRAMES[frame]
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
	# Room code (online games only) so friends can join directly.
	_staging_ip_row.visible = not _room_code.is_empty()
	_staging_code_label.text = tr("Room code: %s") % _room_code
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
		_bot_row = bot_row
		_add_bot_btn = Button.new()
		_add_bot_btn.text = tr("Add Bot")
		_add_bot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_add_bot_btn.custom_minimum_size = Vector2(0, 44)
		_add_bot_btn.add_theme_font_size_override("font_size", 20)
		_add_bot_btn.pressed.connect(_on_add_bot_pressed)
		bot_row.add_child(_add_bot_btn)
		_remove_bot_btn = Button.new()
		_remove_bot_btn.text = tr("Remove Bot")
		_remove_bot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_remove_bot_btn.custom_minimum_size = Vector2(0, 44)
		_remove_bot_btn.add_theme_font_size_override("font_size", 20)
		_remove_bot_btn.disabled = true
		_remove_bot_btn.pressed.connect(_on_remove_bot_pressed)
		bot_row.add_child(_remove_bot_btn)
		_diff_btn = OptionButton.new()
		_diff_btn.add_item(tr("Easy"))
		_diff_btn.add_item(tr("Normal"))
		_diff_btn.add_item(tr("Hard"))
		_diff_btn.selected = 1
		_diff_btn.custom_minimum_size = Vector2(100, 44)
		_diff_btn.add_theme_font_size_override("font_size", 18)
		bot_row.add_child(_diff_btn)
	staging_requested.emit()

func _start_preload() -> void:
	ImageCache.preload_local_art()
	_on_preload_done()

func _on_preload_done() -> void:
	_preload_done = true
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
	_room_code = ""
	lobby_view_requested.emit()

# ── Room list ─────────────────────────────────────────────────────────────────

func _request_lobby_list() -> void:
	if _rooms_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return   # previous request still running
	_rooms_http.request(ROOMS_URL + "?version=" + _game_version().uri_encode())

func _on_rooms_received(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_rooms = []
		_rebuild_game_list()
		_set_status(tr("Can't reach the online server — you can still host a game with bots."))
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	_rooms = []
	if typeof(data) == TYPE_DICTIONARY and typeof(data.get("rooms")) == TYPE_ARRAY:
		for r: Variant in data["rooms"]:
			if typeof(r) == TYPE_DICTIONARY:
				_rooms.append(r as Dictionary)
	if not _spinner_active:
		_set_status(tr("Found %d lobbies") % _rooms.size())
	_rebuild_game_list()

# Re-applies the password filter to the room list already fetched, without a
# fresh request, so toggling the checkbox filters instantly.
func _rebuild_game_list() -> void:
	var prev_selected: String = ""
	var sel: PackedInt32Array = _game_list.get_selected_items()
	if not sel.is_empty():
		prev_selected = str(_game_list.get_item_metadata(sel[0]))
	_game_list.clear()
	for room: Dictionary in _rooms:
		var locked: bool = bool(room.get("locked", false))
		if _password_only_check.button_pressed and not locked:
			continue
		var host_name: String = str(room.get("name", ""))
		if host_name.is_empty():
			host_name = tr("Unknown")
		var label: String = "%s  (%d/%d)" % [host_name, int(room.get("players", 1)), int(room.get("max_players", MAX_PLAYERS))]
		if locked:
			label = tr("[Locked] ") + label
		var room_code: String = str(room.get("code", ""))
		_game_list.add_item(label)
		_game_list.set_item_metadata(_game_list.item_count - 1, room_code)
		if room_code == prev_selected:
			_game_list.select(_game_list.item_count - 1)

func _on_filter_toggled(_toggled_on: bool) -> void:
	_rebuild_game_list()

# ── Hosting ───────────────────────────────────────────────────────────────────

func _on_host_pressed() -> void:
	_player_name = _read_name()
	_relay = RelayMultiplayerPeer.new()
	if _relay.create_host(_player_name, _password_input.text.strip_edges(), MAX_PLAYERS, _game_version()) != OK:
		_start_offline_host()
		return
	_relay.room_ready.connect(_on_room_ready)
	multiplayer.multiplayer_peer = _relay
	_hosting_pending = true
	_set_controls_locked(true)
	_spinner_active = true
	_spinner_time = 0.0

func _on_room_ready(code: String) -> void:
	_hosting_pending = false
	_spinner_active = false
	_room_code = code
	_is_host = true
	_players[1] = _player_name
	_show_staging()

# Server unreachable (offline, or it's down) — fall back to a local session
# for playing against bots, on Godot's offline placeholder peer: is_server()
# is true there and @rpc calls resolve locally, so the staging/start flow
# below works unchanged. (Assigning null leaves *no* peer, not the offline
# one — is_server()/get_unique_id() then error out.)
func _start_offline_host() -> void:
	_hosting_pending = false
	_spinner_active = false
	_relay = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_room_code = ""
	_is_host = true
	_players[1] = _player_name
	_set_status(tr("Can't reach the online server — playing offline."))
	_show_staging()

# ── Joining ───────────────────────────────────────────────────────────────────

func _on_join_selected_pressed() -> void:
	var selected: PackedInt32Array = _game_list.get_selected_items()
	if selected.is_empty():
		_set_status(tr("Select a game from the list first."))
		return
	var code: String = str(_game_list.get_item_metadata(selected[0]))
	for room: Dictionary in _rooms:
		if str(room.get("code", "")) == code and bool(room.get("locked", false)):
			_show_password_prompt(code, false)
			return
	_join_room(code, "")

# "Join Code" (typed room code from a friend). If the room has a password the
# server answers wrong_password and the prompt opens from there.
func _on_join_pressed() -> void:
	var code: String = _code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		_set_status(tr("Room codes have 6 characters."))
		return
	_join_room(code, "")

func _join_room(code: String, password: String) -> void:
	_player_name = _read_name()
	_pending_join_code = code
	_relay = RelayMultiplayerPeer.new()
	if _relay.create_client(code, _player_name, password, _game_version()) != OK:
		_relay = null
		_set_status(tr("Can't reach the online server."))
		return
	multiplayer.multiplayer_peer = _relay
	_set_controls_locked(true)
	_set_status(tr("Joining lobby…"))

# ── Password prompt ───────────────────────────────────────────────────────────

func _build_password_prompt() -> void:
	_password_prompt = Control.new()
	_password_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_password_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	_password_prompt.visible = false
	add_child(_password_prompt)

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(360, 0)
	_password_prompt.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = tr("This lobby is password protected")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	_password_prompt_input = LineEdit.new()
	_password_prompt_input.secret = true
	_password_prompt_input.placeholder_text = tr("Password")
	_password_prompt_input.add_theme_font_size_override("font_size", 20)
	_password_prompt_input.text_submitted.connect(func(_t: String) -> void: _on_password_confirm_pressed())
	vbox.add_child(_password_prompt_input)

	_password_prompt_error = Label.new()
	_password_prompt_error.text = tr("Incorrect password.")
	_password_prompt_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_password_prompt_error.add_theme_font_size_override("font_size", 16)
	_password_prompt_error.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	_password_prompt_error.visible = false
	vbox.add_child(_password_prompt_error)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var confirm_btn: Button = Button.new()
	confirm_btn.text = tr("Join")
	confirm_btn.custom_minimum_size = Vector2(120, 44)
	confirm_btn.add_theme_font_size_override("font_size", 18)
	confirm_btn.pressed.connect(_on_password_confirm_pressed)
	btn_row.add_child(confirm_btn)

	var cancel_btn: Button = Button.new()
	cancel_btn.text = tr("Cancel")
	cancel_btn.custom_minimum_size = Vector2(120, 44)
	cancel_btn.add_theme_font_size_override("font_size", 18)
	cancel_btn.pressed.connect(_on_password_cancel_pressed)
	btn_row.add_child(cancel_btn)

func _show_password_prompt(code: String, show_error: bool) -> void:
	_pending_join_code = code
	_password_prompt_input.text = ""
	_password_prompt_error.visible = show_error
	_password_prompt.visible = true
	_password_prompt_input.grab_focus()

# The server checks the password; a wrong one comes back as a failed join
# (see _on_connection_failed), which reopens this prompt with the error.
func _on_password_confirm_pressed() -> void:
	_password_prompt.visible = false
	_join_room(_pending_join_code, _password_prompt_input.text)

func _on_password_cancel_pressed() -> void:
	_password_prompt.visible = false
	_pending_join_code = ""

# ── Start / Leave / Back ──────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		if _relay:
			_relay.mark_started()
		_rpc_load_game.rpc()

func _on_leave_pressed() -> void:
	_close_connection()
	_players.clear()
	_bot_count = 0
	if is_instance_valid(_bot_row):
		_bot_row.queue_free()
	_bot_row = null
	_add_bot_btn = null
	_remove_bot_btn = null
	_diff_btn = null
	ChatManager.clear_history()
	_show_lobby()

func _on_rule_book_pressed() -> void:
	_manual.open()

func _on_back_pressed() -> void:
	_close_connection()
	ChatManager.clear_history()
	if back_requested.get_connections().size() > 0:
		back_requested.emit()
	else:
		SceneTransition.change_scene("res://scenes/main_menu/main_menu.tscn")

func _close_connection() -> void:
	_hosting_pending = false
	_spinner_active = false
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_relay = null
	_room_code = ""

# InviteBtn (Steam overlay invites) is hidden since online rooms replaced
# Steam lobbies — the room code is how friends join now. Kept because the
# scene still connects the button's signal here.
func _on_invite_pressed() -> void:
	pass

func _on_copy_ip_pressed() -> void:
	if _room_code.is_empty():
		return
	DisplayServer.clipboard_set(_room_code)
	_staging_code_label.text = tr("Room code: %s (copied)") % _room_code

# ── Multiplayer signals ───────────────────────────────────────────────────────

func _on_peer_connected(_id: int) -> void:
	pass

func _on_connection_failed() -> void:
	var reason: String = _relay.error_reason if _relay else ""
	if _hosting_pending:
		# Couldn't create an online room — still let them play with bots.
		_start_offline_host()
		return
	multiplayer.multiplayer_peer = null
	_relay = null
	_is_host = false
	_set_controls_locked(false)
	if reason == "wrong_password":
		_show_password_prompt(_pending_join_code, _password_prompt_input.text != "")
		_set_status("")
		return
	_set_status(_join_error_text(reason))

func _join_error_text(reason: String) -> String:
	match reason:
		"not_found":
			return tr("No game with that room code.")
		"full":
			return tr("That game is full.")
		"already_started":
			return tr("That game has already started.")
		"version_mismatch":
			return tr("That game uses a different game version.")
		"unreachable":
			return tr("Can't reach the online server.")
	return tr("Connection to host failed.")

func _on_peer_disconnected(id: int) -> void:
	_players.erase(id)
	_players_ready.erase(id)
	if multiplayer.is_server():
		_rpc_sync_players.rpc(_players)
	_refresh_player_list()

func _on_connected_to_server() -> void:
	_room_code = _relay.room_code if _relay else ""
	_player_name = _read_name()
	_rpc_register.rpc_id(1, _player_name)
	_show_staging()

func _on_server_disconnected() -> void:
	_set_status(tr("Lost connection to host."))
	_players.clear()
	multiplayer.multiplayer_peer = null
	_relay = null
	ChatManager.clear_history()
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
	GameNetwork.bot_difficulty = _bot_difficulties.duplicate()
	# from the main menu: the parked cockpit powers up first (MainMenu.launch_game)
	var menu: Node = get_tree().current_scene
	if menu and menu.has_method("launch_game"):
		menu.call("launch_game", "res://scenes/main/main.tscn")
	else:
		SceneTransition.change_scene("res://scenes/main/main.tscn")

# ── Helpers ───────────────────────────────────────────────────────────────────

func _on_add_bot_pressed() -> void:
	if _players.size() >= MAX_PLAYERS:
		return
	_bot_count += 1
	var bot_id: int = -_bot_count
	var diff: int = _diff_btn.selected if _diff_btn else 1
	_bot_difficulties[bot_id] = diff
	_players[bot_id] = BOT_NAMES[diff]
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
		_staging_player_list.text = tr("(no players)")
	else:
		var lines: Array[String] = []
		for id: int in _players:
			var tag: String = ""
			if id == 1:
				tag = tr("  ★ host")
			elif id < 0:
				tag = tr("  [bot]")
			lines.append(tr("• %s%s") % [_players[id], tag])
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
	# Keep the room list's player count (incl. bots) up to date, which is also
	# what the server uses to refuse joins once the room is full.
	if _relay and multiplayer.is_server():
		_relay.report_player_count(_players.size())

func _set_status(msg: String) -> void:
	_status_label.text = msg

func _set_controls_locked(locked: bool) -> void:
	_host_btn.disabled = locked
	_join_selected_btn.disabled = locked
	_code_join_btn.disabled = locked
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

# Only rooms of the exact same game version can see/join each other, so a
# Steam and an Android build must be on the same version to play together.
func _game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0"))

func _on_refresh_pressed() -> void:
	_request_lobby_list()
	_lobby_refresh_timer = LOBBY_REFRESH_INTERVAL

func _load_saved_name() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved: String = str(cfg.get_value("player", "name", ""))
		if not saved.is_empty():
			_name_input.text = saved
			return
	# No saved name yet (first launch, or it was cleared) — default to the
	# Steam display name instead of leaving the field blank. Still just a
	# starting value: typing over it and hosting/joining saves the edit via
	# _read_name()/_save_name() same as before.
	if SteamManager.is_initialized:
		var steam_name: String = Steam.getPersonaName()
		if not steam_name.is_empty():
			_name_input.text = steam_name
