extends Control
const Haptics = preload("res://scripts/haptics.gd")
const ContextHints = preload("res://scenes/ui/context_hints.gd")

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

# Locale codes offered in the Language dropdown, in display order — matches
# project.godot's locale/locale_filter and the LANG_* keys in "UI Strings.csv".
const LANGUAGE_CODES: Array[String] = ["en", "de", "it", "pl", "es", "fr"]

var _settings_panel: Control = null
var _manual: Control = null
var _collection: Control = null
var _main_panel: Control = null
var _resolution_option: OptionButton = null
var _monitor_option: OptionButton = null
var _music_slider: HSlider = null
var _sfx_slider: HSlider = null
var _voice_slider: HSlider = null
var _output_device_option: OptionButton = null
var _input_device_option: OptionButton = null
var _shake_check: CheckButton = null
var _vibration_check: CheckButton = null
var _tutorial_check: CheckButton = null
var _language_option: OptionButton = null
var _tr_targets: Dictionary = {}   # Control (Label/Button) -> untranslated key, refreshed on locale change

func _tr_set(ctrl: Control, key: String) -> void:
	ctrl.text = tr(key)
	_tr_targets[ctrl] = key

func _ready() -> void:
	_build_ui()
	visible = false

func toggle() -> void:
	visible = not visible

func open_settings() -> void:
	if _main_panel:
		_main_panel.visible = false
	if _settings_panel:
		_settings_panel.visible = true
	visible = true
	_load_tutorial_setting()
	_load_language_setting()

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
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	_main_panel = panel

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(500, 0)
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_child(vbox)

	var title := Label.new()
	_tr_set(title, "PAUSED")
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

	var manual_btn := _make_button("Rule Book")
	manual_btn.pressed.connect(_on_manual_pressed)
	vbox.add_child(manual_btn)

	var collection_btn := _make_button("Collection")
	collection_btn.pressed.connect(_on_collection_pressed)
	vbox.add_child(collection_btn)

	var sep2 := HSeparator.new()
	sep2.modulate = Color(0.4, 0.4, 0.5, 0.3)
	vbox.add_child(sep2)

	var quit_btn := _make_button("Quit Game")
	quit_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)

	GameTheme.touchify(panel)
	_build_settings_panel()
	_manual = load("res://scenes/ui/manual_popup.gd").new()
	add_child(_manual)
	_collection = load("res://scenes/ui/collection_popup.gd").new()
	add_child(_collection)

func _make_button(key: String) -> Button:
	var btn := Button.new()
	_tr_set(btn, key)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 52)
	btn.add_theme_font_size_override("font_size", 22)
	return btn

# Phones: everything in Settings at twice its desktop size — text, rows, label
# columns and the panel itself — and, since that no longer fits the screen's
# height, the list scrolls (Close stays below it).
const TOUCH_SETTINGS_SCALE: float = 2.0
const TOUCH_SETTINGS_MAX_HEIGHT: float = 0.8   # of the screen, for the scrolling list

func _double_settings_for_touch(vbox: VBoxContainer, close_btn: Button) -> void:
	var k: float = TOUCH_SETTINGS_SCALE
	_settings_panel.custom_minimum_size.x *= k
	vbox.add_theme_constant_override("separation", roundi(12 * k))
	for node: Node in vbox.find_children("*", "Control", true, false):
		var ctrl: Control = node as Control
		if ctrl is Label or ctrl is Button:
			ctrl.add_theme_font_size_override("font_size", roundi(ctrl.get_theme_font_size("font_size") * k))
		if ctrl is BoxContainer:
			ctrl.add_theme_constant_override("separation", roundi(10 * k))
		var row_h: float = GameTheme.TOUCH_SETTINGS_ROW * k * 0.75 if (ctrl is OptionButton or ctrl is CheckButton or ctrl is HSlider) else ctrl.custom_minimum_size.y * k
		ctrl.custom_minimum_size = Vector2(ctrl.custom_minimum_size.x * k, row_h)
	# the list scrolls; Close stays put underneath
	vbox.remove_child(close_btn)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", roundi(12 * k))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, get_viewport_rect().size.y * TOUCH_SETTINGS_MAX_HEIGHT - GameTheme.TOUCH_MIN_SIZE * k)
	_settings_panel.remove_child(vbox)
	_settings_panel.add_child(outer)
	outer.add_child(scroll)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	outer.add_child(close_btn)   # already doubled with the rest

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
	_settings_panel.custom_minimum_size = Vector2(480, 0)
	_settings_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings_panel.visible = false
	add_child(_settings_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_settings_panel.add_child(vbox)

	var title := Label.new()
	_tr_set(title, "SETTINGS")
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
	_tr_set(res_lbl, "Resolution")
	res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_lbl.add_theme_font_size_override("font_size", 16)
	res_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res_row.add_child(res_lbl)

	_resolution_option = OptionButton.new()
	_resolution_option.add_theme_font_size_override("font_size", 16)
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_refresh_resolution_items()
	res_row.add_child(_resolution_option)

	var mon_row := HBoxContainer.new()
	mon_row.add_theme_constant_override("separation", 10)
	vbox.add_child(mon_row)

	var mon_lbl := Label.new()
	_tr_set(mon_lbl, "Monitor")
	mon_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mon_lbl.add_theme_font_size_override("font_size", 16)
	mon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mon_row.add_child(mon_lbl)

	_monitor_option = OptionButton.new()
	_monitor_option.add_theme_font_size_override("font_size", 16)
	_monitor_option.item_selected.connect(_on_monitor_selected)
	_refresh_monitor_items()
	mon_row.add_child(_monitor_option)

	# Phones are always fullscreen on their one screen (the Android export
	# sets immersive mode) — resolution/monitor choices don't apply there.
	if OS.has_feature("mobile"):
		res_row.visible = false
		mon_row.visible = false

	var shake_row := HBoxContainer.new()
	shake_row.add_theme_constant_override("separation", 10)
	vbox.add_child(shake_row)

	var shake_lbl := Label.new()
	_tr_set(shake_lbl, "Screen Shake")
	shake_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shake_lbl.add_theme_font_size_override("font_size", 16)
	shake_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shake_row.add_child(shake_lbl)

	_shake_check = CheckButton.new()
	_shake_check.toggled.connect(func(on: bool) -> void:
		Card.screen_shake_enabled = on
		_save_shake_setting(on)
	)
	shake_row.add_child(_shake_check)

	# Phones only: short vibrations (see Haptics).
	if Haptics.available():
		var vib_row := HBoxContainer.new()
		vib_row.add_theme_constant_override("separation", 10)
		vbox.add_child(vib_row)
		var vib_lbl := Label.new()
		_tr_set(vib_lbl, "Vibration")
		vib_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vib_lbl.add_theme_font_size_override("font_size", 16)
		vib_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vib_row.add_child(vib_lbl)
		_vibration_check = CheckButton.new()
		_vibration_check.toggled.connect(func(on: bool) -> void:
			Haptics.enabled = on
			_save_display_flag("vibration", on)
			if on:
				Haptics.thump()
		)
		vib_row.add_child(_vibration_check)

	# Tooltip size (see GameTheme.tooltip_size) — defaults to 200% on phones.
	var tip_row := HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", 10)
	vbox.add_child(tip_row)

	var tip_lbl := Label.new()
	_tr_set(tip_lbl, "Tooltip Size")
	tip_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_lbl.add_theme_font_size_override("font_size", 16)
	tip_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip_row.add_child(tip_lbl)

	var tip_option := OptionButton.new()
	tip_option.add_theme_font_size_override("font_size", 16)
	var current_size: float = GameTheme.tooltip_size()
	for i: int in GameTheme.TOOLTIP_SIZES.size():
		var tip_size: float = GameTheme.TOOLTIP_SIZES[i]
		tip_option.add_item("%d%%" % roundi(tip_size * 100.0))
		if is_equal_approx(tip_size, current_size):
			tip_option.selected = i
	tip_option.item_selected.connect(func(index: int) -> void:
		GameTheme.set_tooltip_size(GameTheme.TOOLTIP_SIZES[index]))
	tip_row.add_child(tip_option)

	var tutorial_row := HBoxContainer.new()
	tutorial_row.add_theme_constant_override("separation", 10)
	vbox.add_child(tutorial_row)

	var tutorial_lbl := Label.new()
	_tr_set(tutorial_lbl, "Replay Tutorial")
	tutorial_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_lbl.add_theme_font_size_override("font_size", 16)
	tutorial_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_row.add_child(tutorial_lbl)

	_tutorial_check = CheckButton.new()
	_tutorial_check.toggled.connect(_save_tutorial_setting)
	tutorial_row.add_child(_tutorial_check)

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 10)
	vbox.add_child(lang_row)

	var lang_lbl := Label.new()
	_tr_set(lang_lbl, "Language")
	lang_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lang_lbl.add_theme_font_size_override("font_size", 16)
	lang_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lang_row.add_child(lang_lbl)

	_language_option = OptionButton.new()
	_language_option.add_theme_font_size_override("font_size", 16)
	_language_option.item_selected.connect(_on_language_selected)
	_refresh_language_items()
	lang_row.add_child(_language_option)

	var audio_sep := HSeparator.new()
	audio_sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(audio_sep)

	var audio_title := Label.new()
	_tr_set(audio_title, "AUDIO")
	audio_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	audio_title.add_theme_font_size_override("font_size", 18)
	audio_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	vbox.add_child(audio_title)

	var audio_rows: Array = [["Music", "Music"], ["Sound Effects", "SFX"], ["Voice Chat", "Voice"]]
	for entry: Array in audio_rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vbox.add_child(row)
		var lbl := Label.new()
		_tr_set(lbl, entry[0])
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
		elif bus_name == "SFX":
			_sfx_slider = slider
		else:
			_voice_slider = slider

	var out_row := HBoxContainer.new()
	out_row.add_theme_constant_override("separation", 10)
	vbox.add_child(out_row)
	var out_lbl := Label.new()
	_tr_set(out_lbl, "Output Device")
	out_lbl.custom_minimum_size = Vector2(130, 0)
	out_lbl.add_theme_font_size_override("font_size", 15)
	out_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
	out_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	out_row.add_child(out_lbl)
	_output_device_option = OptionButton.new()
	_output_device_option.add_theme_font_size_override("font_size", 13)
	_output_device_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output_device_option.item_selected.connect(_on_output_device_selected)
	out_row.add_child(_output_device_option)

	var in_row := HBoxContainer.new()
	in_row.add_theme_constant_override("separation", 10)
	vbox.add_child(in_row)
	var in_lbl := Label.new()
	_tr_set(in_lbl, "Input Device")
	in_lbl.custom_minimum_size = Vector2(130, 0)
	in_lbl.add_theme_font_size_override("font_size", 15)
	in_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
	in_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	in_row.add_child(in_lbl)
	_input_device_option = OptionButton.new()
	_input_device_option.add_theme_font_size_override("font_size", 13)
	_input_device_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_device_option.item_selected.connect(_on_input_device_selected)
	in_row.add_child(_input_device_option)
	_refresh_output_device_items()
	_refresh_input_device_items()

	var close_btn := _make_button("Close")
	close_btn.pressed.connect(func() -> void:
		_settings_panel.visible = false
		if _main_panel and not _main_panel.visible:
			visible = false)
	vbox.add_child(close_btn)

	# Voice chat is off everywhere while online games run over our relay
	# server (see VoiceManager.is_available) — hide its volume and mic choice.
	# The output device stays on desktop: it routes all game audio.
	in_row.visible = false
	_voice_slider.get_parent().visible = false
	if GameTheme.is_touch():
		# No audio-device choice on phones.
		out_row.visible = false
		_double_settings_for_touch(vbox, close_btn)

	_load_resolution_setting()
	_load_monitor_setting()
	_load_audio_settings()
	_load_output_device_setting()
	_load_input_device_setting()
	_load_shake_setting()
	_load_tutorial_setting()
	_load_language_setting()

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
	var voice_vol: float = 1.0
	if cfg.load(SETTINGS_PATH) == OK:
		music_vol = float(cfg.get_value("audio", "music_volume", 1.0))
		sfx_vol = float(cfg.get_value("audio", "sfx_volume", 1.0))
		voice_vol = float(cfg.get_value("audio", "voice_volume", 1.0))
	if _music_slider:
		_music_slider.value = music_vol
	if _sfx_slider:
		_sfx_slider.value = sfx_vol
	if _voice_slider:
		_voice_slider.value = voice_vol
	_set_bus_volume("Music", music_vol)
	_set_bus_volume("SFX", sfx_vol)
	_set_bus_volume("Voice", voice_vol)

func _save_audio_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music_volume", _music_slider.value if _music_slider else 1.0)
	cfg.set_value("audio", "sfx_volume", _sfx_slider.value if _sfx_slider else 1.0)
	cfg.set_value("audio", "voice_volume", _voice_slider.value if _voice_slider else 1.0)
	cfg.save(SETTINGS_PATH)

# ── Audio devices ────────────────────────────────────────────────────────────
# Devices are matched and persisted by name rather than list index — the
# index a device sits at can shift between launches (a USB headset plugged
# in later, etc.), so re-selecting by index on a refreshed list could pick
# the wrong device. "Default" (index 0 on both lists) always exists and is
# the fallback when a saved device is no longer present.

func _refresh_output_device_items() -> void:
	if not _output_device_option:
		return
	var current: String = _output_device_option.get_item_text(_output_device_option.selected) if _output_device_option.item_count > 0 else ""
	_output_device_option.clear()
	for d: String in AudioServer.get_output_device_list():
		_output_device_option.add_item(d)
	_select_device_item(_output_device_option, current)

func _refresh_input_device_items() -> void:
	if not _input_device_option:
		return
	var current: String = _input_device_option.get_item_text(_input_device_option.selected) if _input_device_option.item_count > 0 else ""
	_input_device_option.clear()
	for d: String in AudioServer.get_input_device_list():
		_input_device_option.add_item(d)
	_select_device_item(_input_device_option, current)

func _select_device_item(option: OptionButton, device_name: String) -> void:
	for i: int in option.item_count:
		if option.get_item_text(i) == device_name:
			option.selected = i
			return
	option.selected = 0

func _on_output_device_selected(index: int) -> void:
	var device_name: String = _output_device_option.get_item_text(index)
	AudioServer.output_device = device_name
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "output_device", device_name)
	cfg.save(SETTINGS_PATH)

func _on_input_device_selected(index: int) -> void:
	var device_name: String = _input_device_option.get_item_text(index)
	AudioServer.input_device = device_name
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "input_device", device_name)
	cfg.save(SETTINGS_PATH)

func _load_output_device_setting() -> void:
	_refresh_output_device_items()
	if not _output_device_option:
		return
	# get_output_device_list() can come back empty for a frame or two while
	# the audio driver is still enumerating devices at boot; if so the
	# OptionButton has no item 0 to read, and assigning "" to
	# AudioServer.output_device (unlike "Default") silences all audio
	# instead of falling back to the system default.
	if _output_device_option.item_count == 0:
		return
	var cfg: ConfigFile = ConfigFile.new()
	var saved: String = "Default"
	if cfg.load(SETTINGS_PATH) == OK:
		saved = String(cfg.get_value("audio", "output_device", "Default"))
	_select_device_item(_output_device_option, saved)
	var device_name: String = _output_device_option.get_item_text(_output_device_option.selected)
	if device_name != "":
		AudioServer.output_device = device_name

func _load_input_device_setting() -> void:
	_refresh_input_device_items()
	if not _input_device_option:
		return
	if _input_device_option.item_count == 0:
		return
	var cfg: ConfigFile = ConfigFile.new()
	var saved: String = "Default"
	if cfg.load(SETTINGS_PATH) == OK:
		saved = String(cfg.get_value("audio", "input_device", "Default"))
	_select_device_item(_input_device_option, saved)
	var device_name: String = _input_device_option.get_item_text(_input_device_option.selected)
	if device_name != "":
		AudioServer.input_device = device_name

func _load_shake_setting() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var on: bool = true
	if cfg.load(SETTINGS_PATH) == OK:
		on = bool(cfg.get_value("display", "screen_shake", true))
	if _shake_check:
		_shake_check.set_pressed_no_signal(on)
	Card.screen_shake_enabled = on
	var vib: bool = bool(cfg.get_value("display", "vibration", true))
	if _vibration_check:
		_vibration_check.set_pressed_no_signal(vib)
	Haptics.enabled = vib

func _save_shake_setting(on: bool) -> void:
	_save_display_flag("screen_shake", on)

func _save_display_flag(key: String, on: bool) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", key, on)
	cfg.save(SETTINGS_PATH)

# Same "tutorial"/"seen" flag main.gd's FirstTurnTutorial gate reads/marks —
# this checkbox is just a manual way to flip it back to "not seen" (checked)
# so it plays again next solo game start; main.gd marks it seen again the
# instant the tutorial actually starts, so reopening Settings afterward
# correctly shows it unchecked again.
func _load_tutorial_setting() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var seen: bool = false
	if cfg.load(SETTINGS_PATH) == OK:
		seen = bool(cfg.get_value("tutorial", "seen", false))
	if _tutorial_check:
		_tutorial_check.set_pressed_no_signal(not seen)

func _save_tutorial_setting(want_replay: bool) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("tutorial", "seen", not want_replay)
	cfg.save(SETTINGS_PATH)
	if want_replay:
		ContextHints.reset_all()   # the first-time tips come back too

func _load_language_setting() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var locale: String = "en"
	if cfg.load(SETTINGS_PATH) == OK:
		locale = str(cfg.get_value("game", "locale", "en"))
	var idx: int = LANGUAGE_CODES.find(locale)
	if idx == -1:
		idx = 0
		locale = "en"
	TranslationServer.set_locale(locale)
	if _language_option:
		_language_option.selected = idx
	_refresh_all_ui_text()

func _on_language_selected(idx: int) -> void:
	if idx < 0 or idx >= LANGUAGE_CODES.size():
		return
	var locale: String = LANGUAGE_CODES[idx]
	TranslationServer.set_locale(locale)
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("game", "locale", locale)
	cfg.save(SETTINGS_PATH)
	_refresh_all_ui_text()
	# CardDatabase resolved every card's art for the boot-time locale in
	# _ready() and never revisits it — without this, card faces keep showing
	# the old language until the app is fully restarted. See
	# CardDatabase.refresh_locale() for why.
	CardDatabase.refresh_locale()
	ImageCache.refresh_local_art()
	get_tree().call_group("cards", "refresh_locale_art")
	get_tree().call_group("locale_refresh", "refresh_locale_text")

# Re-applies tr() to every UI element after a live locale change. Most
# labels/buttons are simple key lookups tracked in _tr_targets; OptionButton
# items and the keybind value buttons mix in dynamic/OS content and need
# bespoke rebuilding instead.
func _refresh_all_ui_text() -> void:
	for ctrl: Control in _tr_targets:
		if is_instance_valid(ctrl):
			ctrl.text = tr(_tr_targets[ctrl] as String)
	_refresh_resolution_items()
	_refresh_monitor_items()
	_refresh_language_items()

func _refresh_resolution_items() -> void:
	if not _resolution_option:
		return
	var sel: int = _resolution_option.selected
	_resolution_option.clear()
	for res: Vector2i in RESOLUTIONS:
		_resolution_option.add_item(tr("%d × %d") % [res.x, res.y])
	_resolution_option.add_item(tr("Fullscreen"))
	if sel >= 0:
		_resolution_option.selected = sel

func _refresh_monitor_items() -> void:
	if not _monitor_option:
		return
	var sel: int = _monitor_option.selected
	_monitor_option.clear()
	var screen_count: int = DisplayServer.get_screen_count()
	for i: int in screen_count:
		var sz: Vector2i = DisplayServer.screen_get_size(i)
		_monitor_option.add_item(tr("Monitor %d  (%d×%d)") % [i + 1, sz.x, sz.y])
	if sel >= 0:
		_monitor_option.selected = sel

func _refresh_language_items() -> void:
	if not _language_option:
		return
	var sel: int = _language_option.selected
	_language_option.clear()
	for code: String in LANGUAGE_CODES:
		_language_option.add_item(tr("LANG_" + code.to_upper()))
	if sel >= 0:
		_language_option.selected = sel

func _on_manual_pressed() -> void:
	_manual.open()

func _on_collection_pressed() -> void:
	_collection.open()

func _on_settings_pressed() -> void:
	_settings_panel.visible = true
	_refresh_output_device_items()
	_refresh_input_device_items()
	_load_tutorial_setting()
	_load_language_setting()

func _on_main_menu_pressed() -> void:
	visible = false
	main_menu_pressed.emit()

func _on_resolution_selected(index: int) -> void:
	_apply_resolution(index)
	_save_settings(index)

func _apply_resolution(index: int) -> void:
	if OS.has_feature("mobile"):
		return
	if index == FULLSCREEN_IDX:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(RESOLUTIONS[index])
		var screen: Vector2i = DisplayServer.screen_get_size()
		var win: Vector2i = DisplayServer.window_get_size()
		DisplayServer.window_set_position(Vector2i((Vector2(screen - win)) / 2.0))

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
	if OS.has_feature("mobile"):
		return
	var screen_count: int = DisplayServer.get_screen_count()
	if index < 0 or index >= screen_count:
		return
	DisplayServer.window_set_current_screen(index)
	var screen_pos: Vector2i = DisplayServer.screen_get_position(index)
	var screen_size: Vector2i = DisplayServer.screen_get_size(index)
	var win_size: Vector2i = DisplayServer.window_get_size()
	DisplayServer.window_set_position(screen_pos + Vector2i(Vector2(screen_size - win_size) / 2.0))

func _load_monitor_setting() -> void:
	var current: int = DisplayServer.window_get_current_screen()
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		current = int(cfg.get_value("display", "monitor_index", current))
	current = clampi(current, 0, DisplayServer.get_screen_count() - 1)
	if _monitor_option:
		_monitor_option.selected = current
	_apply_monitor(current)
