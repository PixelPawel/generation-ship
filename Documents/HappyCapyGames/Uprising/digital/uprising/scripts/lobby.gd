extends Control
## Pre-game lobby, reached from the main menu's Start button. Host or Join
## a networked game, then everyone picks their own faction and Hero from
## the Lobby Room. Nobody can hold two factions: claiming one releases
## whatever you already had. For any faction nobody claims, the HOST
## decides (per faction, via the Bot checkbox) whether it gets a "simple
## dummy" bot (the default -- see NetworkManager.start_game /
## PlayerFactionState.is_bot) or is left out of the game entirely.

const FACTIONS := ["Druwhn", "Duerkhar", "Krowh", "Mohyar"]
const DIFFICULTIES := ["Rebel", "Veteran", "Nightmare", "Apocalypse"]

var _setup_panel: VBoxContainer
var _host_panel: VBoxContainer
var _join_panel: VBoxContainer
var _room_panel: VBoxContainer
var _status_label: Label
var _room_status_label: Label

var _difficulty_option: OptionButton
var _chapters_option: OptionButton
var _host_port_edit: LineEdit

var _join_address_edit: LineEdit
var _join_port_edit: LineEdit

var _faction_status_labels: Dictionary = {}  # faction -> Label
var _faction_hero_options: Dictionary = {}  # faction -> OptionButton
var _faction_claim_buttons: Dictionary = {}  # faction -> Button
var _faction_bot_checks: Dictionary = {}  # faction -> CheckBox, host-only control
var _start_game_button: Button


func _ready() -> void:
	_build_ui()
	_set_mode(true)
	NetworkManager.lobby_claims_updated.connect(_on_lobby_claims_updated)
	NetworkManager.lobby_bot_enabled_updated.connect(func(_b: Dictionary) -> void: _refresh_room())
	NetworkManager.game_starting.connect(_on_game_starting)
	NetworkManager.peer_connected.connect(func(_id: int) -> void: _refresh_room())
	NetworkManager.peer_disconnected.connect(func(_id: int) -> void: _refresh_room())
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.connected_to_host.connect(_on_connected_to_host)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	var title := Label.new()
	title.text = "Uprising: Curse of the Last Emperor"
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)

	_setup_panel = _build_setup_panel()
	root.add_child(_setup_panel)

	_room_panel = _build_room_panel()
	_room_panel.visible = false
	root.add_child(_room_panel)


func _build_setup_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()

	var mode_row := HBoxContainer.new()
	panel.add_child(mode_row)
	var host_mode_button := Button.new()
	host_mode_button.text = "Host New Game"
	host_mode_button.pressed.connect(func() -> void: _set_mode(true))
	mode_row.add_child(host_mode_button)
	var join_mode_button := Button.new()
	join_mode_button.text = "Join Game"
	join_mode_button.pressed.connect(func() -> void: _set_mode(false))
	mode_row.add_child(join_mode_button)
	var back_button := Button.new()
	back_button.text = "Back to Main Menu"
	back_button.pressed.connect(_on_back_pressed)
	mode_row.add_child(back_button)

	_status_label = Label.new()
	panel.add_child(_status_label)

	_host_panel = _build_host_setup_panel()
	panel.add_child(_host_panel)

	_join_panel = _build_join_setup_panel()
	panel.add_child(_join_panel)

	return panel


func _build_host_setup_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()

	var diff_row := HBoxContainer.new()
	panel.add_child(diff_row)
	var diff_label := Label.new()
	diff_label.text = "Difficulty:"
	diff_row.add_child(diff_label)
	_difficulty_option = OptionButton.new()
	for d in DIFFICULTIES:
		_difficulty_option.add_item(d)
	_difficulty_option.select(DIFFICULTIES.find("Veteran"))
	diff_row.add_child(_difficulty_option)

	var chap_row := HBoxContainer.new()
	panel.add_child(chap_row)
	var chap_label := Label.new()
	chap_label.text = "Chapters:"
	chap_row.add_child(chap_label)
	_chapters_option = OptionButton.new()
	for c in [2, 3, 4]:
		_chapters_option.add_item(str(c))
	_chapters_option.select(1)  # "3", the standard full-game length
	chap_row.add_child(_chapters_option)

	var port_row := HBoxContainer.new()
	panel.add_child(port_row)
	var port_label := Label.new()
	port_label.text = "Port:"
	port_row.add_child(port_label)
	_host_port_edit = LineEdit.new()
	_host_port_edit.text = str(NetworkManager.DEFAULT_PORT)
	_host_port_edit.custom_minimum_size = Vector2(80, 0)
	port_row.add_child(_host_port_edit)

	var start_button := Button.new()
	start_button.text = "Start Hosting"
	start_button.pressed.connect(_on_start_hosting_pressed)
	panel.add_child(start_button)

	return panel


func _build_join_setup_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()

	var addr_row := HBoxContainer.new()
	panel.add_child(addr_row)
	var addr_label := Label.new()
	addr_label.text = "Host Address:"
	addr_row.add_child(addr_label)
	_join_address_edit = LineEdit.new()
	_join_address_edit.text = "127.0.0.1"
	addr_row.add_child(_join_address_edit)

	var port_row := HBoxContainer.new()
	panel.add_child(port_row)
	var port_label := Label.new()
	port_label.text = "Port:"
	port_row.add_child(port_label)
	_join_port_edit = LineEdit.new()
	_join_port_edit.text = str(NetworkManager.DEFAULT_PORT)
	_join_port_edit.custom_minimum_size = Vector2(80, 0)
	port_row.add_child(_join_port_edit)

	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_on_join_pressed)
	panel.add_child(join_button)

	return panel


func _build_room_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()

	_room_status_label = Label.new()
	panel.add_child(_room_status_label)

	var hint := Label.new()
	hint.text = "Pick a faction and Hero. For anyone left unclaimed, the host decides below: Bot fills it in, unchecked leaves it out of the game."
	panel.add_child(hint)

	for faction in FACTIONS:
		panel.add_child(_build_faction_row(faction))

	_start_game_button = Button.new()
	_start_game_button.text = "Start Game"
	_start_game_button.pressed.connect(_on_start_game_pressed)
	panel.add_child(_start_game_button)

	var leave_button := Button.new()
	leave_button.text = "Leave Lobby"
	leave_button.pressed.connect(_on_leave_pressed)
	panel.add_child(leave_button)

	return panel


## `faction` is this call's own parameter (a fresh local binding, not a
## shared loop variable), so the closures built here each correctly close
## over their own faction -- not the classic "lambda in a for-loop captures
## the same mutable variable" trap.
func _build_faction_row(faction: String) -> HBoxContainer:
	var row := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = faction + ":"
	name_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(name_label)

	var status_label := Label.new()
	status_label.text = "Open"
	status_label.custom_minimum_size = Vector2(170, 0)
	row.add_child(status_label)
	_faction_status_labels[faction] = status_label

	var hero_option := OptionButton.new()
	for h in _heroes_for_faction(faction):
		hero_option.add_item(h)
	if hero_option.item_count > 0:
		hero_option.select(0)
	hero_option.item_selected.connect(func(_index: int) -> void: _on_hero_reselected(faction))
	row.add_child(hero_option)
	_faction_hero_options[faction] = hero_option

	var bot_check := CheckBox.new()
	bot_check.text = "Bot"
	bot_check.button_pressed = true
	bot_check.toggled.connect(func(pressed: bool) -> void: NetworkManager.set_bot_enabled(faction, pressed))
	row.add_child(bot_check)
	_faction_bot_checks[faction] = bot_check

	var claim_button := Button.new()
	claim_button.text = "Claim"
	claim_button.pressed.connect(func() -> void: _on_claim_pressed(faction))
	row.add_child(claim_button)
	_faction_claim_buttons[faction] = claim_button

	return row


func _heroes_for_faction(faction: String) -> Array[String]:
	var names: Array[String] = []
	for h in CardDatabase.heroes:
		if h.lang == "EN" and h.box == "Core" and h.faction == faction:
			names.append(h.card_name)
	return names


func _set_mode(host: bool) -> void:
	_host_panel.visible = host
	_join_panel.visible = not host


# ---------------------------------------------------------------------------
# Host / Join / connection
# ---------------------------------------------------------------------------

func _on_start_hosting_pressed() -> void:
	var port: int = int(_host_port_edit.text) if _host_port_edit.text.is_valid_int() else NetworkManager.DEFAULT_PORT
	var err: Error = NetworkManager.host_game(port)
	if err != OK:
		_status_label.text = "host_game failed (%s)" % err
		return
	_enter_room()


func _on_join_pressed() -> void:
	var address := _join_address_edit.text
	var port: int = int(_join_port_edit.text) if _join_port_edit.text.is_valid_int() else NetworkManager.DEFAULT_PORT
	_status_label.text = "Connecting to %s:%d ..." % [address, port]
	var err: Error = NetworkManager.join_game(address, port)
	if err != OK:
		_status_label.text = "join_game failed (%s)" % err


func _on_connected_to_host() -> void:
	_enter_room()


func _on_connection_failed() -> void:
	_status_label.text = "Connection failed."


func _enter_room() -> void:
	_setup_panel.visible = false
	_room_panel.visible = true
	_start_game_button.visible = NetworkManager.is_host
	_refresh_room()


func _on_leave_pressed() -> void:
	NetworkManager.disconnect_game()
	_room_panel.visible = false
	_setup_panel.visible = true
	_status_label.text = ""


func _on_back_pressed() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ---------------------------------------------------------------------------
# Lobby Room: claiming factions
# ---------------------------------------------------------------------------

func _on_claim_pressed(faction: String) -> void:
	var my_id := NetworkManager.multiplayer.get_unique_id()
	var claim: Dictionary = NetworkManager.lobby_claims.get(faction, {})
	if int(claim.get("peer_id", -1)) == my_id:
		NetworkManager.request_release()
		return
	var hero_option: OptionButton = _faction_hero_options[faction]
	if hero_option.selected < 0:
		return
	NetworkManager.request_claim(faction, hero_option.get_item_text(hero_option.selected))


## If I already hold this faction, switching Hero re-claims it with the new
## pick instead of requiring a separate Release + Claim round trip.
func _on_hero_reselected(faction: String) -> void:
	var my_id := NetworkManager.multiplayer.get_unique_id()
	var claim: Dictionary = NetworkManager.lobby_claims.get(faction, {})
	if int(claim.get("peer_id", -1)) != my_id:
		return
	var hero_option: OptionButton = _faction_hero_options[faction]
	NetworkManager.request_claim(faction, hero_option.get_item_text(hero_option.selected))


func _on_lobby_claims_updated(_claims: Dictionary) -> void:
	_refresh_room()


func _refresh_room() -> void:
	var my_id := NetworkManager.multiplayer.get_unique_id()
	_room_status_label.text = "Connected as Peer %d%s" % [my_id, " (Host)" if NetworkManager.is_host else ""]

	for faction in FACTIONS:
		var claim: Dictionary = NetworkManager.lobby_claims.get(faction, {})
		var status_label: Label = _faction_status_labels[faction]
		var hero_option: OptionButton = _faction_hero_options[faction]
		var claim_button: Button = _faction_claim_buttons[faction]
		var bot_check: CheckBox = _faction_bot_checks[faction]

		if claim.is_empty():
			status_label.text = "Open"
			hero_option.disabled = false
			claim_button.text = "Claim"
			claim_button.disabled = false
			# set_pressed_no_signal: this is syncing FROM NetworkManager's
			# state, not a user click -- assigning button_pressed directly
			# would re-fire `toggled` and bounce a redundant set_bot_enabled
			# broadcast back out for no reason.
			bot_check.set_pressed_no_signal(bool(NetworkManager.lobby_bot_enabled.get(faction, true)))
			bot_check.disabled = not NetworkManager.is_host
		elif int(claim["peer_id"]) == my_id:
			status_label.text = "You: %s" % claim["hero"]
			hero_option.disabled = false
			claim_button.text = "Release"
			claim_button.disabled = false
			bot_check.disabled = true
		else:
			status_label.text = "Peer %d: %s" % [int(claim["peer_id"]), claim["hero"]]
			hero_option.disabled = true
			claim_button.text = "Taken"
			claim_button.disabled = true
			bot_check.disabled = true


func _on_start_game_pressed() -> void:
	var result: Dictionary = NetworkManager.start_game(
		FACTIONS,
		DIFFICULTIES[_difficulty_option.selected],
		int(_chapters_option.get_item_text(_chapters_option.selected))
	)
	if not result.get("ok", false):
		_room_status_label.text = "Can't start: %s" % result.get("reason", "unknown error")


func _on_game_starting(_state: GameState) -> void:
	get_tree().change_scene_to_file("res://scenes/game_board.tscn")
