extends Control
## Pre-game lobby, the project's actual entry point (run/main_scene). Choose
## to Host (pick which of the 4 Core factions are playing, their Heroes,
## difficulty, Chapter count) or Join an existing host by address/port.
## Fills in the LobbyConfig autoload and hands off to game_board.tscn, which
## reads it back in _ready() -- Godot's change_scene_to_file() doesn't pass
## arguments directly, so LobbyConfig is the bridge between the two scenes.

const FACTIONS := ["Druwhn", "Duerkhar", "Krowh", "Mohyar"]
const DIFFICULTIES := ["Rebel", "Veteran", "Nightmare", "Apocalypse"]

var _host_panel: VBoxContainer
var _join_panel: VBoxContainer
var _status_label: Label

var _faction_checks: Dictionary = {}  # faction -> CheckBox
var _faction_hero_options: Dictionary = {}  # faction -> OptionButton
var _difficulty_option: OptionButton
var _chapters_option: OptionButton
var _host_port_edit: LineEdit

var _join_address_edit: LineEdit
var _join_port_edit: LineEdit


func _ready() -> void:
	_build_ui()
	_set_mode(true)


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

	var mode_row := HBoxContainer.new()
	root.add_child(mode_row)
	var host_mode_button := Button.new()
	host_mode_button.text = "Host New Game"
	host_mode_button.pressed.connect(func() -> void: _set_mode(true))
	mode_row.add_child(host_mode_button)
	var join_mode_button := Button.new()
	join_mode_button.text = "Join Game"
	join_mode_button.pressed.connect(func() -> void: _set_mode(false))
	mode_row.add_child(join_mode_button)

	_status_label = Label.new()
	root.add_child(_status_label)

	_host_panel = _build_host_panel()
	root.add_child(_host_panel)

	_join_panel = _build_join_panel()
	root.add_child(_join_panel)


func _build_host_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()

	for faction in FACTIONS:
		var row := HBoxContainer.new()
		panel.add_child(row)

		var check := CheckBox.new()
		check.text = faction
		check.button_pressed = faction == "Druwhn" or faction == "Krowh"
		row.add_child(check)
		_faction_checks[faction] = check

		var hero_option := OptionButton.new()
		var heroes := _heroes_for_faction(faction)
		for h in heroes:
			hero_option.add_item(h)
		if not heroes.is_empty():
			hero_option.select(0)
		row.add_child(hero_option)
		_faction_hero_options[faction] = hero_option

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


func _heroes_for_faction(faction: String) -> Array[String]:
	var names: Array[String] = []
	for h in CardDatabase.heroes:
		if h.lang == "EN" and h.box == "Core" and h.faction == faction:
			names.append(h.card_name)
	return names


func _build_join_panel() -> VBoxContainer:
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


func _set_mode(host: bool) -> void:
	_host_panel.visible = host
	_join_panel.visible = not host


func _on_start_hosting_pressed() -> void:
	var pairs: Array = []
	for faction in FACTIONS:
		var check: CheckBox = _faction_checks[faction]
		if not check.button_pressed:
			continue
		var hero_option: OptionButton = _faction_hero_options[faction]
		if hero_option.selected < 0:
			continue
		pairs.append([faction, hero_option.get_item_text(hero_option.selected)])

	if pairs.is_empty():
		_status_label.text = "Pick at least one faction to play."
		return

	LobbyConfig.configured = true
	LobbyConfig.is_host = true
	LobbyConfig.faction_hero_pairs = pairs
	LobbyConfig.difficulty = DIFFICULTIES[_difficulty_option.selected]
	LobbyConfig.max_chapters = int(_chapters_option.get_item_text(_chapters_option.selected))
	LobbyConfig.port = int(_host_port_edit.text) if _host_port_edit.text.is_valid_int() else NetworkManager.DEFAULT_PORT

	get_tree().change_scene_to_file("res://scenes/game_board.tscn")


func _on_join_pressed() -> void:
	LobbyConfig.configured = true
	LobbyConfig.is_host = false
	LobbyConfig.join_address = _join_address_edit.text
	LobbyConfig.join_port = int(_join_port_edit.text) if _join_port_edit.text.is_valid_int() else NetworkManager.DEFAULT_PORT

	get_tree().change_scene_to_file("res://scenes/game_board.tscn")
