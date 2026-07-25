extends Control

signal back_requested
signal staging_requested
signal lobby_view_requested

const MAX_PLAYERS: int = 4
const SETTINGS_PATH: String = "user://settings.cfg"
const LOBBY_REFRESH_INTERVAL: float = 5.0
const BOT_NAMES: Array[String] = ["Wally", "Bender", "Deep Blue"]  # Easy, Normal, Hard — proper nouns, not translated

var _player_name: String = ""
var _players: Dictionary = {}      # peer_id (int) -> name (String)
var _preload_done: bool = false
var _players_ready: Dictionary = {}   # peer_id (int) -> true, tracked on host only
var _steam_lobby_id: int = 0
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
var _cached_lobbies: Array[int] = []
var _pending_password: String = ""
var _pending_join_lobby_id: int = 0
var _password_prompt: Control = null
var _password_prompt_input: LineEdit = null
var _password_prompt_error: Label = null

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
	_manual = load("res://scenes/ui/manual_popup.gd").new()
	add_child(_manual)
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
	lobby_view_requested.emit()

# ── Lobby list ────────────────────────────────────────────────────────────────

func _request_lobby_list() -> void:
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("game", "generation_ship", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array) -> void:
	_cached_lobbies = []
	for entry: Variant in lobbies:
		_cached_lobbies.append(int(entry))
	_set_status(tr("Found %d lobbies") % _cached_lobbies.size())
	_rebuild_game_list()

# Re-applies the two filter checkboxes to the lobby list already fetched by
# _on_lobby_match_list, without a fresh Steam request — both filters only
# need data Steam already cached locally from that same search (lobby data
# and member lists are available for any listed lobby, not just ones we've
# joined), so toggling a checkbox can re-filter instantly.
func _rebuild_game_list() -> void:
	var prev_selected: int = 0
	var sel: PackedInt32Array = _game_list.get_selected_items()
	if not sel.is_empty():
		prev_selected = int(_game_list.get_item_metadata(sel[0]))
	_game_list.clear()
	for lobby_id: int in _cached_lobbies:
		var has_password: bool = Steam.getLobbyData(lobby_id, "has_password") == "1"
		if _password_only_check.button_pressed and not has_password:
			continue
		if _friends_only_check.button_pressed and not _lobby_has_friend(lobby_id):
			continue
		var host_name: String = Steam.getLobbyData(lobby_id, "host_name")
		if host_name.is_empty():
			host_name = tr("Unknown")
		var member_count: int = Steam.getNumLobbyMembers(lobby_id)
		var member_limit: int = Steam.getLobbyMemberLimit(lobby_id)
		var label: String = "%s  (%d/%d)" % [host_name, member_count, member_limit]
		if has_password:
			label = tr("[Locked] ") + label
		_game_list.add_item(label)
		_game_list.set_item_metadata(_game_list.item_count - 1, lobby_id)
		if lobby_id == prev_selected:
			_game_list.select(_game_list.item_count - 1)

func _on_filter_toggled(_toggled_on: bool) -> void:
	_rebuild_game_list()

# True if any current member of this (not-necessarily-joined) lobby is one
# of the local player's Steam friends — Steam caches member lists for
# listed lobbies, same as it caches their lobby data, so this works from
# the browser list without actually joining first.
func _lobby_has_friend(lobby_id: int) -> bool:
	var member_count: int = Steam.getNumLobbyMembers(lobby_id)
	for i: int in member_count:
		var member_id: int = Steam.getLobbyMemberByIndex(lobby_id, i)
		if Steam.hasFriend(member_id, Steam.FRIEND_FLAG_IMMEDIATE):
			return true
	return false

# ── Hosting ───────────────────────────────────────────────────────────────────

func _on_host_pressed() -> void:
	_player_name = _read_name()
	_pending_password = _password_input.text.strip_edges()
	_set_controls_locked(true)
	_spinner_active = true
	_spinner_time = 0.0
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)

func _on_lobby_created(connect_result: int, lobby_id: int) -> void:
	_spinner_active = false
	if connect_result != 1:
		_set_status(tr("Failed to create lobby."))
		_set_controls_locked(false)
		return
	_steam_lobby_id = lobby_id
	Steam.setLobbyData(lobby_id, "game", "generation_ship")
	Steam.setLobbyData(lobby_id, "host_name", _player_name)
	var has_password: bool = not _pending_password.is_empty()
	Steam.setLobbyData(lobby_id, "has_password", "1" if has_password else "0")
	if has_password:
		# Not real cryptographic protection (SHA-256 is fast to brute-force
		# and this is public lobby data anyone browsing can read) — just
		# enough to keep the password itself off the wire and out of the
		# lobby list, for a casual "keep randos out" gate, not a secure one.
		Steam.setLobbyData(lobby_id, "password_hash", _pending_password.sha256_text())
	_pending_password = ""
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		_set_status(tr("SteamMultiplayerPeer not found — install the GodotSteam MultiplayerPeer addon."))
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
		_set_status(tr("Select a game from the list first."))
		return
	var lobby_id: int = int(_game_list.get_item_metadata(selected[0]))
	if Steam.getLobbyData(lobby_id, "has_password") == "1":
		_show_password_prompt(lobby_id)
		return
	_join_lobby(lobby_id)

func _join_lobby(lobby_id: int) -> void:
	_set_controls_locked(true)
	_set_status(tr("Joining lobby…"))
	Steam.joinLobby(lobby_id)

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

func _show_password_prompt(lobby_id: int) -> void:
	_pending_join_lobby_id = lobby_id
	_password_prompt_input.text = ""
	_password_prompt_error.visible = false
	_password_prompt.visible = true
	_password_prompt_input.grab_focus()

func _on_password_confirm_pressed() -> void:
	var expected_hash: String = Steam.getLobbyData(_pending_join_lobby_id, "password_hash")
	if _password_prompt_input.text.sha256_text() != expected_hash:
		_password_prompt_error.visible = true
		return
	_password_prompt.visible = false
	_join_lobby(_pending_join_lobby_id)

func _on_password_cancel_pressed() -> void:
	_password_prompt.visible = false
	_pending_join_lobby_id = 0

func _on_lobby_entered(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_set_status(tr("Failed to join lobby."))
		_set_controls_locked(false)
		return
	_steam_lobby_id = lobby_id
	if _is_host:
		return
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		_set_status(tr("SteamMultiplayerPeer not found — install the GodotSteam MultiplayerPeer addon."))
		_set_controls_locked(false)
		return
	var host_steam_id: int = Steam.getLobbyOwner(lobby_id)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	peer.call("create_client", host_steam_id, 0)
	multiplayer.multiplayer_peer = peer
	_set_status(tr("Connecting…"))

func _on_lobby_join_requested(lobby_id: int, _steam_id: int) -> void:
	_set_controls_locked(true)
	_set_status(tr("Joining lobby…"))
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
	if is_instance_valid(_bot_row):
		_bot_row.queue_free()
	_bot_row = null
	_add_bot_btn = null
	_remove_bot_btn = null
	_diff_btn = null
	_show_lobby()

func _on_rule_book_pressed() -> void:
	_manual.open()

func _on_back_pressed() -> void:
	if _steam_lobby_id > 0:
		Steam.leaveLobby(_steam_lobby_id)
		_steam_lobby_id = 0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if back_requested.get_connections().size() > 0:
		back_requested.emit()
	else:
		SceneTransition.change_scene("res://scenes/main_menu/main_menu.tscn")

# ── Multiplayer signals ───────────────────────────────────────────────────────

func _on_peer_connected(_id: int) -> void:
	pass

func _on_connection_failed() -> void:
	_set_status(tr("Connection to host failed."))
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
	_set_status(tr("Lost connection to host."))
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
	GameNetwork.bot_difficulty = _bot_difficulties.duplicate()
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
	if _steam_lobby_id <= 0:
		return
	# activateGameOverlayInviteDialog silently no-ops whenever the Steam
	# overlay itself can't render — the player disabled it in their Steam
	# client settings, or (a GodotSteam/Vulkan limitation, not fixable here)
	# the game is running from the Godot editor instead of a real Steam
	# launch. Either way "nothing happens" with zero feedback is the worst
	# outcome, so surface it instead of failing silently.
	if not Steam.isOverlayEnabled():
		_set_status(tr("Steam overlay is disabled — enable it in Steam's settings to invite friends."))
		return
	Steam.activateGameOverlayInviteDialog(_steam_lobby_id)

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
