extends Control

signal main_menu_pressed

const SETTINGS_PATH: String = "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]
const FULLSCREEN_IDX: int = 5

var _settings_panel: Control = null
var _resolution_option: OptionButton = null
var _monitor_option: OptionButton = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _rebind_buttons: Dictionary = {}   # action -> [primary_btn, secondary_btn]
var _listening_action: String = ""
var _listening_slot: int = -1
var _listen_btn: Button = null

func _ready() -> void:
	_build_ui()
	visible = false

func toggle() -> void:
	visible = not visible

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.65)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(28)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(sep)

	var resume_btn := _make_button("Resume")
	resume_btn.pressed.connect(func(): visible = false)
	vbox.add_child(resume_btn)

	var main_menu_btn := _make_button("Main Menu")
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	vbox.add_child(main_menu_btn)

	var settings_btn := _make_button("Settings")
	settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_btn)

	var sep2 := HSeparator.new()
	sep2.modulate = Color(0.4, 0.4, 0.5, 0.3)
	vbox.add_child(sep2)

	var quit_btn := _make_button("Quit Game")
	quit_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)

	_build_settings_panel()

func _make_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 52)
	btn.add_theme_font_size_override("font_size", 22)
	return btn

func _build_settings_panel() -> void:
	_settings_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.09, 0.98)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.set_content_margin_all(28)
	_settings_panel.add_theme_stylebox_override("panel", style)
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings_panel.custom_minimum_size = Vector2(300, 0)
	_settings_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings_panel.visible = false
	add_child(_settings_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_settings_panel.add_child(vbox)

	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(sep)

	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 10)
	vbox.add_child(res_row)

	var res_lbl := Label.new()
	res_lbl.text = "Resolution"
	res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_lbl.add_theme_font_size_override("font_size", 16)
	res_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res_row.add_child(res_lbl)

	_resolution_option = OptionButton.new()
	_resolution_option.add_theme_font_size_override("font_size", 16)
	_resolution_option.item_selected.connect(_on_resolution_selected)
	for res: Vector2i in RESOLUTIONS:
		_resolution_option.add_item("%d × %d" % [res.x, res.y])
	_resolution_option.add_item("Fullscreen")
	res_row.add_child(_resolution_option)

	var mon_row := HBoxContainer.new()
	mon_row.add_theme_constant_override("separation", 10)
	vbox.add_child(mon_row)

	var mon_lbl := Label.new()
	mon_lbl.text = "Monitor"
	mon_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mon_lbl.add_theme_font_size_override("font_size", 16)
	mon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mon_row.add_child(mon_lbl)

	_monitor_option = OptionButton.new()
	_monitor_option.add_theme_font_size_override("font_size", 16)
	_monitor_option.item_selected.connect(_on_monitor_selected)
	var screen_count: int = DisplayServer.get_screen_count()
	for i: int in screen_count:
		var sz: Vector2i = DisplayServer.screen_get_size(i)
		_monitor_option.add_item("Monitor %d  (%d×%d)" % [i + 1, sz.x, sz.y])
	mon_row.add_child(_monitor_option)

	var audio_sep := HSeparator.new()
	audio_sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(audio_sep)

	var audio_title := Label.new()
	audio_title.text = "AUDIO"
	audio_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	audio_title.add_theme_font_size_override("font_size", 18)
	audio_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	vbox.add_child(audio_title)

	var audio_rows: Array = [["Music", "Music"], ["Sound Effects", "SFX"]]
	for entry: Array in audio_rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)
		var lbl := Label.new()
		lbl.text = entry[0]
		lbl.custom_minimum_size = Vector2(130, 0)
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lbl)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = 1.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bus_name: String = entry[1]
		slider.value_changed.connect(func(v: float) -> void:
			_set_bus_volume(bus_name, v)
			_save_audio_settings()
		)
		row.add_child(slider)
		if bus_name == "Music":
			_music_slider = slider
		else:
			_sfx_slider = slider

	var kb_sep := HSeparator.new()
	kb_sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(kb_sep)

	var kb_title := Label.new()
	kb_title.text = "KEYBINDS"
	kb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kb_title.add_theme_font_size_override("font_size", 18)
	kb_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	vbox.add_child(kb_title)

	# Column headers
	var col_header := HBoxContainer.new()
	col_header.add_theme_constant_override("separation", 6)
	vbox.add_child(col_header)
	var ch_spacer := Label.new()
	ch_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_header.add_child(ch_spacer)
	for col_name: String in ["Primary", "Secondary"]:
		var ch := Label.new()
		ch.text = col_name
		ch.custom_minimum_size = Vector2(110, 0)
		ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ch.add_theme_font_size_override("font_size", 13)
		ch.add_theme_color_override("font_color", Color(0.55, 0.6, 0.75))
		col_header.add_child(ch)

	# Fixed mouse-driven actions (informational, not rebindable)
	var fixed_binds: Array = [
		["Play Card",       "LMB + Drag"],
		["Buy Market Card", "LMB / Drag"],
		["Open Sector",     "LMB (placed)"],
		["Recycle Card",    "RMB (hand)"],
		["Inspect Card",    "RMB (market/placed)"],
	]
	for bind: Array in fixed_binds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vbox.add_child(row)
		var n := Label.new()
		n.text = bind[0]
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.add_theme_font_size_override("font_size", 14)
		n.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
		row.add_child(n)
		var v := Label.new()
		v.text = bind[1]
		v.custom_minimum_size = Vector2(110, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_theme_font_size_override("font_size", 13)
		v.add_theme_color_override("font_color", Color(0.5, 0.55, 0.7))
		row.add_child(v)
		var empty := Label.new()
		empty.text = "—"
		empty.custom_minimum_size = Vector2(110, 0)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.35, 0.38, 0.5))
		row.add_child(empty)

	# Rebindable keyboard actions
	for action: String in KeybindManager.ACTION_NAMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vbox.add_child(row)
		var n := Label.new()
		n.text = str(KeybindManager.ACTION_LABELS.get(action, action))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.add_theme_font_size_override("font_size", 14)
		n.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
		row.add_child(n)
		var primary: int = KeybindManager.get_primary(action)
		var secondary: int = KeybindManager.get_secondary(action)
		var btns: Array[Button] = []
		for slot: int in 2:
			var keycode: int = primary if slot == 0 else secondary
			var btn := Button.new()
			btn.text = OS.get_keycode_string(keycode) if keycode != 0 else "—"
			btn.custom_minimum_size = Vector2(110, 30)
			btn.add_theme_font_size_override("font_size", 13)
			row.add_child(btn)
			btns.append(btn)
			var captured_slot: int = slot
			btn.pressed.connect(_start_listen.bind(action, captured_slot, btn))
			if slot == 1:
				btn.gui_input.connect(func(event: InputEvent) -> void:
					if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
						var cur_primary: int = KeybindManager.get_primary(action)
						KeybindManager.save_binding(action, cur_primary, 0)
						btn.text = "—"
						btn.accept_event()
				)
		_rebind_buttons[action] = btns

	var close_btn := _make_button("Close")
	close_btn.pressed.connect(func(): _settings_panel.visible = false)
	vbox.add_child(close_btn)

	_load_resolution_setting()
	_load_monitor_setting()
	_load_audio_settings()

func _input(event: InputEvent) -> void:
	if _listening_action.is_empty():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	accept_event()
	var keycode: int = int((event as InputEventKey).keycode)
	if keycode == KEY_ESCAPE:
		_cancel_listen()
		return
	var primary: int = KeybindManager.get_primary(_listening_action)
	var secondary: int = KeybindManager.get_secondary(_listening_action)
	if _listening_slot == 0:
		primary = keycode
	else:
		secondary = keycode
	KeybindManager.save_binding(_listening_action, primary, secondary)
	if _listen_btn:
		_listen_btn.text = OS.get_keycode_string(keycode)
	_end_listen()

func _start_listen(action: String, slot: int, btn: Button) -> void:
	if not _listening_action.is_empty():
		_cancel_listen()
	_listening_action = action
	_listening_slot = slot
	_listen_btn = btn
	btn.text = "Press key…"
	for a: String in _rebind_buttons:
		for b: Button in (_rebind_buttons[a] as Array[Button]):
			if b != btn:
				b.modulate = Color(1.0, 1.0, 1.0, 0.4)

func _cancel_listen() -> void:
	if not _listening_action.is_empty() and _listen_btn:
		var cur: int = KeybindManager.get_primary(_listening_action) if _listening_slot == 0 else KeybindManager.get_secondary(_listening_action)
		_listen_btn.text = OS.get_keycode_string(cur) if cur != 0 else "—"
	_end_listen()

func _end_listen() -> void:
	_listening_action = ""
	_listening_slot = -1
	_listen_btn = null
	for a: String in _rebind_buttons:
		for b: Button in (_rebind_buttons[a] as Array[Button]):
			b.modulate = Color.WHITE

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db: float = linear_to_db(linear) if linear > 0.0 else -80.0
	AudioServer.set_bus_volume_db(idx, db)

func _load_audio_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var music_vol: float = 1.0
	var sfx_vol: float = 1.0
	if cfg.load(SETTINGS_PATH) == OK:
		music_vol = float(cfg.get_value("audio", "music_volume", 1.0))
		sfx_vol = float(cfg.get_value("audio", "sfx_volume", 1.0))
	if _music_slider:
		_music_slider.value = music_vol
	if _sfx_slider:
		_sfx_slider.value = sfx_vol
	_set_bus_volume("Music", music_vol)
	_set_bus_volume("SFX", sfx_vol)

func _save_audio_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music_volume", _music_slider.value if _music_slider else 1.0)
	cfg.set_value("audio", "sfx_volume", _sfx_slider.value if _sfx_slider else 1.0)
	cfg.save(SETTINGS_PATH)

func _on_settings_pressed() -> void:
	_settings_panel.visible = true

func _on_main_menu_pressed() -> void:
	visible = false
	main_menu_pressed.emit()

func _on_resolution_selected(index: int) -> void:
	_apply_resolution(index)
	_save_settings(index)

func _apply_resolution(index: int) -> void:
	if index == FULLSCREEN_IDX:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(RESOLUTIONS[index])
		var screen: Vector2i = DisplayServer.screen_get_size()
		var win: Vector2i = DisplayServer.window_get_size()
		DisplayServer.window_set_position((screen - win) / 2)

func _load_resolution_setting() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var idx: int = 2
	if cfg.load(SETTINGS_PATH) == OK:
		idx = int(cfg.get_value("display", "resolution_index", 2))
	idx = clampi(idx, 0, FULLSCREEN_IDX)
	if _resolution_option:
		_resolution_option.selected = idx

func _save_settings(index: int) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "resolution_index", index)
	cfg.save(SETTINGS_PATH)

func _on_monitor_selected(index: int) -> void:
	_apply_monitor(index)
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "monitor_index", index)
	cfg.save(SETTINGS_PATH)

func _apply_monitor(index: int) -> void:
	var screen_count: int = DisplayServer.get_screen_count()
	if index < 0 or index >= screen_count:
		return
	DisplayServer.window_set_current_screen(index)
	var screen_pos: Vector2i = DisplayServer.screen_get_position(index)
	var screen_size: Vector2i = DisplayServer.screen_get_size(index)
	var win_size: Vector2i = DisplayServer.window_get_size()
	DisplayServer.window_set_position(screen_pos + (screen_size - win_size) / 2)

func _load_monitor_setting() -> void:
	var current: int = DisplayServer.window_get_current_screen()
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		current = int(cfg.get_value("display", "monitor_index", current))
	current = clampi(current, 0, DisplayServer.get_screen_count() - 1)
	if _monitor_option:
		_monitor_option.selected = current
	_apply_monitor(current)
