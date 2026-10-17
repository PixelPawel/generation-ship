extends Control

## Table screen, the first stop after the main menu: play solo (True Solo
## Mode, straight to the faction screen), host a table (for Steam friends or
## on this network) or join one, and watch the seats fill. Once
## everyone is here the host presses "Choose factions" - the table closes to
## newcomers (NetworkManager.begin_faction_choice) and every player moves to
## the faction screen together. The host can reopen the table from there,
## which brings everyone back here with their choices kept.
##
## Steam runs on App ID 480 until Uprising has its own (steam_manager.gd);
## joining by address works without Steam.

const HexArt := preload("res://scripts/ui/lobby/hex_art.gd")
const FactionCatalog := preload("res://scripts/data/tables/faction_catalog.gd")
const MENU_SCENE := "res://scenes/MainMenu.tscn"
const FACTION_SCENE := "res://scenes/FactionSelect.tscn"
const SEAT_NUMERALS: Array[String] = ["I", "II", "III", "IV"]
const GOLD := Color(0.875, 0.745, 0.424)
const TEAL := Color(0.055, 0.592, 0.635)
const BONE := Color(0.949, 0.91, 0.769)
const MIST := Color(0.58, 0.76, 0.78)
const PANEL_BG := Color(0.024, 0.102, 0.114, 0.86)
const MESSAGE_SECONDS := 6.0

@onready var status_label: Label = $Margin/Rows/Header/Status
@onready var leave_button: Button = $Margin/Rows/Header/LeaveButton
@onready var ways_panel: PanelContainer = $Margin/Rows/Body/Ways
@onready var solo_button: Button = $Margin/Rows/Body/Ways/VBox/SoloRow/SoloButton
@onready var steam_note: Label = $Margin/Rows/Body/Ways/VBox/SteamNote
@onready var host_steam_button: Button = $Margin/Rows/Body/Ways/VBox/SteamButtons/HostSteamButton
@onready var find_button: Button = $Margin/Rows/Body/Ways/VBox/SteamButtons/FindButton
@onready var found: ScrollContainer = $Margin/Rows/Body/Ways/VBox/Found
@onready var found_rows: VBoxContainer = $Margin/Rows/Body/Ways/VBox/Found/Rows
@onready var host_lan_button: Button = $Margin/Rows/Body/Ways/VBox/HostLanButton
@onready var address_edit: LineEdit = $Margin/Rows/Body/Ways/VBox/LanJoin/AddressEdit
@onready var join_lan_button: Button = $Margin/Rows/Body/Ways/VBox/LanJoin/JoinLanButton
@onready var table_heading: Label = $Margin/Rows/Body/Table/TableHeading
@onready var table_note: Label = $Margin/Rows/Body/Table/TableNote
@onready var seats_box: VBoxContainer = $Margin/Rows/Body/Table/Seats
@onready var invite_button: Button = $Margin/Rows/Body/Table/Actions/InviteButton
@onready var choose_button: Button = $Margin/Rows/Body/Table/Actions/ChooseButton

var net: Node
var _message: String = ""
var _message_time: float = -100.0
var _clock: float = 0.0
var _leaving: bool = false


func _ready() -> void:
	net = get_node("/root/NetworkManager")
	if net.in_lobby() and net.lobby_phase == "factions":
		_go_to_factions.call_deferred()
		return

	leave_button.pressed.connect(_on_leave_pressed)
	solo_button.pressed.connect(func() -> void: net.start_solo())  # straight on to the faction screen
	host_steam_button.pressed.connect(_on_host_steam_pressed)
	find_button.pressed.connect(_on_find_pressed)
	host_lan_button.pressed.connect(_on_host_lan_pressed)
	join_lan_button.pressed.connect(_on_join_lan_pressed)
	address_edit.text_submitted.connect(func(_t: String) -> void: _on_join_lan_pressed())
	invite_button.pressed.connect(func() -> void: net.invite_friends())
	choose_button.pressed.connect(_on_choose_pressed)

	net.roster_changed.connect(func(_r: Dictionary) -> void: _refresh())
	net.lobby_status.connect(_show_message)
	net.lobby_joined.connect(_refresh)
	net.lobby_phase_changed.connect(_on_phase_changed)
	net.steam.lobby_list_received.connect(_on_lobby_list)

	var carried: String = net.recent_status()
	if not carried.is_empty():
		_show_message(carried)
	_set_found_text("Friends hosting a table show up here.")
	_refresh()


func _process(delta: float) -> void:
	_clock += delta
	if not _message.is_empty() and _clock - _message_time > MESSAGE_SECONDS:
		_message = ""
		_update_status()


# --- Helpers ---------------------------------------------------------------------

func _tex(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1


func _host_name() -> String:
	return str(net.roster[1]["name"]) if net.roster.has(1) else "The host"


func _local_ip() -> String:
	for a: String in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			return a
	return "this computer's address"


func _show_message(text: String) -> void:
	_message = text
	_message_time = _clock
	_update_status()


# --- Refresh -------------------------------------------------------------------------

func _refresh() -> void:
	_refresh_ways()
	_refresh_table()
	_update_status()


func _refresh_ways() -> void:
	var in_lobby: bool = net.in_lobby()
	ways_panel.visible = not in_lobby
	if in_lobby:
		return
	var busy: bool = net.is_connecting()
	var steam_ok: bool = net.steam_available()
	solo_button.disabled = busy
	host_steam_button.disabled = not steam_ok or busy
	find_button.disabled = not steam_ok or busy
	host_lan_button.disabled = busy
	join_lan_button.disabled = busy
	address_edit.editable = not busy
	found.visible = steam_ok
	if steam_ok:
		steam_note.text = "Host a table for Steam friends, or join a friend's."
	else:
		steam_note.text = "%s You can still play on this network." % str(net.steam.init_message)


func _refresh_table() -> void:
	var in_lobby: bool = net.in_lobby()
	var host: bool = in_lobby and net.is_host()
	if not in_lobby:
		table_heading.text = "Your table"
		table_note.text = "Host a table or join one to take a seat."
	elif host:
		table_heading.text = "Your table"
		if net.transport == "steam":
			table_note.text = "Friends can join from their Steam friends list, or send them an invite."
		else:
			table_note.text = "Players on this network join with your address: %s" % _local_ip()
	else:
		table_heading.text = "%s's table" % _host_name()
		table_note.text = "%s starts choosing factions once everyone is here." % _host_name()

	for child: Node in seats_box.get_children():
		child.queue_free()
	var ids: Array = net.seats() if in_lobby else []
	for i: int in range(int(net.MAX_PLAYERS)):
		seats_box.add_child(_seat_plaque(i, int(ids[i]) if i < ids.size() else 0, in_lobby))

	invite_button.visible = in_lobby and net.transport == "steam"
	choose_button.visible = host
	if host:
		var enough: bool = net.roster.size() >= 2
		choose_button.disabled = not enough
		choose_button.tooltip_text = "" if enough else "Waiting for at least one more player."
	if host:
		leave_button.text = "Close the table"
	elif in_lobby:
		leave_button.text = "Leave the table"
	elif net.is_connecting():
		leave_button.text = "Cancel"
	else:
		leave_button.text = "Back to menu"


## One seat: its number, who sits there and, after a trip to the faction
## screen, the faction they picked.
func _seat_plaque(index: int, id: int, in_lobby: bool) -> Control:
	var taken: bool = id != 0 and net.roster.has(id)
	var m: Dictionary = net.roster[id] if taken else {}
	var me: bool = taken and id == _my_id()
	var faction: String = str(m.get("faction", ""))

	var plaque := PanelContainer.new()
	plaque.custom_minimum_size = Vector2(0, 62)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG if taken else Color(PANEL_BG, 0.55)
	sb.border_width_left = 4
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	if me:
		sb.border_color = GOLD
	elif taken:
		sb.border_color = Color(TEAL, 0.75)
	else:
		sb.border_color = Color(TEAL, 0.2)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	plaque.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	plaque.add_child(row)

	var numeral := Label.new()
	numeral.theme_type_variation = &"HeadingLabel"
	numeral.add_theme_font_size_override("font_size", 28)
	numeral.custom_minimum_size = Vector2(46, 0)
	numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	numeral.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	numeral.text = SEAT_NUMERALS[index] if index < SEAT_NUMERALS.size() else str(index + 1)
	numeral.add_theme_color_override("font_color", GOLD if me else (BONE if taken else Color(MIST, 0.35)))
	row.add_child(numeral)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 21)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var detail := Label.new()
	detail.theme_type_variation = &"MutedLabel"
	detail.add_theme_font_size_override("font_size", 15)
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if taken:
		name_label.text = str(m["name"]) + (" (you)" if me else "")
		var parts: Array[String] = []
		if id == 1:
			parts.append("Host")
		if not faction.is_empty():
			parts.append("%s, as %s" % [faction, str(m["hero"])])
		elif id != 1:
			parts.append("Joined")
		detail.text = ", ".join(parts)
	else:
		name_label.text = "Open seat"
		name_label.add_theme_color_override("font_color", Color(MIST, 0.55))
		detail.text = "Waiting for a player" if in_lobby else ""
	col.add_child(name_label)
	if not detail.text.is_empty():
		col.add_child(detail)

	if taken and not faction.is_empty():
		var token: HexArt = HexArt.new()
		token.custom_minimum_size = Vector2(58, 50)
		token.mouse_filter = Control.MOUSE_FILTER_IGNORE
		token.texture = _tex(str(FactionCatalog.HOME_ATLAS.get(faction, "")))
		token.region = FactionCatalog.home_region(faction)
		token.border_color = Color(FactionCatalog.accent(faction), 0.85)
		row.add_child(token)
	return plaque


func _update_status() -> void:
	if not _message.is_empty():
		status_label.text = _message
		return
	var seats: String = "%d of %d seats taken." % [net.roster.size(), int(net.MAX_PLAYERS)]
	if net.in_lobby():
		status_label.text = seats
	elif net.is_connecting():
		status_label.text = "Connecting..."
	else:
		status_label.text = "Not at a table yet."


# --- Finding a friend's table ----------------------------------------------------

func _set_found_text(text: String) -> void:
	for child: Node in found_rows.get_children():
		child.queue_free()
	var label := Label.new()
	label.theme_type_variation = &"MutedLabel"
	label.add_theme_font_size_override("font_size", 15)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(340, 0)
	label.text = text
	found_rows.add_child(label)


func _on_find_pressed() -> void:
	_set_found_text("Looking for your friends' tables...")
	net.request_steam_lobbies()


func _on_lobby_list(lobbies: Array) -> void:
	if lobbies.is_empty():
		_set_found_text("None of your friends is hosting right now. A friend's Steam invite brings you straight to their table.")
		return
	for child: Node in found_rows.get_children():
		child.queue_free()
	for l: Variant in lobbies:
		var entry: Dictionary = l
		var members: int = int(entry.get("members", -1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.text = "Table with %s" % str(entry.get("host", "a friend"))
		if members >= 0:
			label.text += ", %d of %d seats" % [members, int(net.MAX_PLAYERS)]
		row.add_child(label)
		var join := Button.new()
		join.text = "Join"
		join.custom_minimum_size = Vector2(70, 0)
		join.disabled = members >= int(net.MAX_PLAYERS)
		join.pressed.connect(func() -> void:
			net.join_steam(int(entry["id"]))
			_refresh())
		row.add_child(join)
		found_rows.add_child(row)


# --- Actions and scene flow ------------------------------------------------------------

func _on_host_steam_pressed() -> void:
	net.host_steam(true)
	_refresh()


func _on_host_lan_pressed() -> void:
	var err: Error = net.host_lan()
	if err != OK:
		_show_message("Couldn't open a table on port %d (error %d). Another copy of the game may be hosting." % [int(net.LAN_PORT), err])


func _on_join_lan_pressed() -> void:
	var address: String = address_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var err: Error = net.join_lan(address)
	if err != OK:
		_show_message("Couldn't connect to %s (error %d)." % [address, err])
	_refresh()


func _on_choose_pressed() -> void:
	if net.begin_faction_choice() != OK:
		_show_message("Waiting for at least one more player.")


func _on_leave_pressed() -> void:
	if net.in_lobby() or net.is_connecting():
		net.leave_lobby()
		_refresh()
	else:
		_leaving = true
		get_tree().change_scene_to_file(MENU_SCENE)


func _on_phase_changed(phase: String) -> void:
	if phase == "factions" and net.in_lobby():
		_go_to_factions()


func _go_to_factions() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(FACTION_SCENE)
