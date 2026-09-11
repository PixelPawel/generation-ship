extends Control

const _SETTINGS_PATH: String = "user://settings.cfg"
const _LANGUAGE_CODES: Array[String] = ["en", "de", "it", "pl", "es", "fr"]

# folder: matches the on-disk assets/cards/<folder>/<LANG>/ directory name
# ("Destiniations" keeps the source export's spelling — not renaming assets).
# label_key: tr() key shown on the tab button.
# landscape: true for wide cards (Sector, Destination), false for portrait.
const _DECKS: Array[Dictionary] = [
	{"folder": "Tech", "label_key": "Tech", "landscape": false},
	{"folder": "Sector", "label_key": "Sector", "landscape": true},
	{"folder": "Expedition", "label_key": "Expedition", "landscape": false},
	{"folder": "Dangers", "label_key": "Danger", "landscape": false},
	{"folder": "Destiniations", "label_key": "Destination", "landscape": true},
]

const _PORTRAIT_SIZE: Vector2 = Vector2(120, 168)
const _PORTRAIT_COLUMNS: int = 6
const _LANDSCAPE_SIZE: Vector2 = Vector2(184, 121)
const _LANDSCAPE_COLUMNS: int = 4
# Right-click close-up sizes — same portrait/landscape split as the thumbnail
# grid, just scaled up (matches the pattern in bid_popup.gd).
const _PORTRAIT_ENLARGE_SIZE: Vector2 = Vector2(340, 476)
const _LANDSCAPE_ENLARGE_SIZE: Vector2 = Vector2(520, 342)
# Cursor "light" on hover — a flat window-wide brighten looked wrong, so
# instead each card lights up individually as the mouse crosses it. Same
# tween shape as main_menu.gd's button hover glow.
const _HOVER_MODULATE: Color = Color(1.45, 1.45, 1.45, 1.0)
const _HOVER_SCALE: Vector2 = Vector2(1.06, 1.06)
const _HOVER_IN_SEC: float = 0.15
const _HOVER_OUT_SEC: float = 0.22

var _active_tab: int = 0
var _tab_buttons: Array[Button] = []
var _grid: GridContainer = null
var _enlarge_image: TextureRect = null
var _thumb_tweens: Dictionary = {}   # TextureRect -> Tween, so a re-hover kills the fade-out mid-flight
var _tr_targets: Dictionary = {}   # Control (Label/Button) -> untranslated key, refreshed on locale change

func _ready() -> void:
	add_to_group("locale_refresh")
	_build_ui()
	visible = false

# This popup is built once, long before the pause menu's language dropdown
# ever runs — tr() calls made at _build_ui() time freeze to whatever locale
# was active at that moment (see CardDatabase.refresh_locale() for the same
# issue with card art). pause_menu.gd broadcasts to the "locale_refresh"
# group on every language change so static text like the tab labels and
# title actually follow it instead of staying stuck on the boot locale.
func refresh_locale_text() -> void:
	for ctrl: Control in _tr_targets:
		if is_instance_valid(ctrl):
			ctrl.text = tr(_tr_targets[ctrl] as String)

func open() -> void:
	if _enlarge_image:
		_enlarge_image.visible = false
	_select_tab(0)
	visible = true

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel: Control = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(960, 860)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(920, 0)
	panel.add_child(vbox)

	# — Title bar —
	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)

	var title: Label = Label.new()
	title.text = tr("COLLECTION")
	_tr_targets[title] = "COLLECTION"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var close_btn: Button = _make_button("✕")
	close_btn.custom_minimum_size = Vector2(36, 0)
	close_btn.pressed.connect(func(): visible = false)
	title_row.add_child(close_btn)

	var sep: HSeparator = HSeparator.new()
	sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(sep)

	# — Tab row —
	var tab_row: HBoxContainer = HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 8)
	vbox.add_child(tab_row)

	var group: ButtonGroup = ButtonGroup.new()
	for i: int in _DECKS.size():
		var deck: Dictionary = _DECKS[i]
		var label_key: String = deck.get("label_key", "") as String
		var btn: Button = _make_button(tr(label_key))
		_tr_targets[btn] = label_key
		btn.custom_minimum_size = Vector2(150, 40)
		btn.toggle_mode = true
		btn.button_group = group
		btn.pressed.connect(_select_tab.bind(i))
		tab_row.add_child(btn)
		_tab_buttons.append(btn)

	var sep2: HSeparator = HSeparator.new()
	sep2.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(sep2)

	# — Scrollable card grid —
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 660)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	# CenterContainer fills the scroll area's width (no horizontal scrolling,
	# so ScrollContainer stretches it) and centers the grid within that —
	# without it the grid just hugs the left edge.
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	center.add_child(_grid)

	# Right-click-to-enlarge close-up, added last so it paints above the
	# panel and everything in it — same pattern as bid_popup.gd's
	# _card_enlarge_image. Centered on the whole popup, sized per-tab in
	# _on_thumb_gui_input() since cards can be portrait or landscape.
	_enlarge_image = TextureRect.new()
	_enlarge_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_enlarge_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_enlarge_image.mouse_filter = Control.MOUSE_FILTER_STOP
	_enlarge_image.gui_input.connect(_on_enlarge_gui_input)
	_enlarge_image.visible = false
	var enlarge_mat: ShaderMaterial = ShaderMaterial.new()
	enlarge_mat.shader = load("res://shaders/card_rounded.gdshader")
	_enlarge_image.material = enlarge_mat
	_enlarge_image.anchor_left = 0.5
	_enlarge_image.anchor_right = 0.5
	_enlarge_image.anchor_top = 0.5
	_enlarge_image.anchor_bottom = 0.5
	add_child(_enlarge_image)

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 14)
	GameTheme.apply_to_button(btn)
	return btn

func _select_tab(idx: int) -> void:
	_active_tab = idx
	for i: int in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == idx)
	_populate_grid()

func _populate_grid() -> void:
	if _enlarge_image:
		_enlarge_image.visible = false
	_thumb_tweens.clear()
	for child: Node in _grid.get_children():
		child.queue_free()
	var deck: Dictionary = _DECKS[_active_tab]
	var landscape: bool = deck.get("landscape", false)
	_grid.columns = _LANDSCAPE_COLUMNS if landscape else _PORTRAIT_COLUMNS
	var box_size: Vector2 = _LANDSCAPE_SIZE if landscape else _PORTRAIT_SIZE
	for path: String in _list_deck_files(deck.get("folder", "") as String):
		var tex: Texture2D = load(path) as Texture2D
		if not tex:
			continue
		var rect: TextureRect = TextureRect.new()
		rect.texture = tex
		rect.custom_minimum_size = box_size
		rect.pivot_offset = box_size / 2.0
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.mouse_filter = Control.MOUSE_FILTER_STOP
		rect.gui_input.connect(func(event: InputEvent) -> void: _on_thumb_gui_input(event, tex, landscape))
		rect.mouse_entered.connect(func() -> void: _on_thumb_hover(rect, true))
		rect.mouse_exited.connect(func() -> void: _on_thumb_hover(rect, false))
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = load("res://shaders/card_rounded.gdshader")
		rect.material = mat
		_grid.add_child(rect)

func _on_thumb_hover(rect: TextureRect, entered: bool) -> void:
	var prev: Tween = _thumb_tweens.get(rect) as Tween
	if prev and prev.is_valid():
		prev.kill()
	var tw: Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if entered:
		tw.tween_property(rect, "modulate", _HOVER_MODULATE, _HOVER_IN_SEC)
		tw.parallel().tween_property(rect, "scale", _HOVER_SCALE, _HOVER_IN_SEC)
	else:
		tw.tween_property(rect, "modulate", Color(1.0, 1.0, 1.0, 1.0), _HOVER_OUT_SEC)
		tw.parallel().tween_property(rect, "scale", Vector2.ONE, _HOVER_OUT_SEC)
	_thumb_tweens[rect] = tw

func _on_thumb_gui_input(event: InputEvent, tex: Texture2D, landscape: bool) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		var sz: Vector2 = _LANDSCAPE_ENLARGE_SIZE if landscape else _PORTRAIT_ENLARGE_SIZE
		_enlarge_image.offset_left = -sz.x / 2.0
		_enlarge_image.offset_right = sz.x / 2.0
		_enlarge_image.offset_top = -sz.y / 2.0
		_enlarge_image.offset_bottom = sz.y / 2.0
		_enlarge_image.texture = tex
		_enlarge_image.visible = true
		get_viewport().set_input_as_handled()

func _on_enlarge_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_enlarge_image.visible = false
		get_viewport().set_input_as_handled()

func _current_lang() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	var locale: String = "en"
	if cfg.load(_SETTINGS_PATH) == OK:
		locale = str(cfg.get_value("game", "locale", "en"))
	if not _LANGUAGE_CODES.has(locale):
		locale = "en"
	return locale.to_upper()

func _list_deck_files(folder: String) -> Array[String]:
	var lang: String = _current_lang()
	var files: Array[String] = _scan_png_dir("res://assets/cards/%s/%s" % [folder, lang])
	if files.is_empty() and lang != "EN":
		files = _scan_png_dir("res://assets/cards/%s/EN" % folder)
	return files

func _scan_png_dir(path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(path)
	if not dir:
		return out
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f != "." and f != ".." and not dir.current_is_dir() and f.get_extension().to_lower() == "png":
			out.append(path + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(_natural_less)
	return out

# Plain string sort would order "...10.png" before "...2.png" — this compares
# runs of digits numerically (and everything else lexically) so multi-page
# decks like Tech (137 cards) browse in the same order they print in.
static func _natural_less(a: String, b: String) -> bool:
	var ai: int = 0
	var bi: int = 0
	while ai < a.length() and bi < b.length():
		var ac: String = a[ai]
		var bc: String = b[bi]
		if ac.is_valid_int() and bc.is_valid_int():
			var a_start: int = ai
			var b_start: int = bi
			while ai < a.length() and a[ai].is_valid_int():
				ai += 1
			while bi < b.length() and b[bi].is_valid_int():
				bi += 1
			var an: int = int(a.substr(a_start, ai - a_start))
			var bn: int = int(b.substr(b_start, bi - b_start))
			if an != bn:
				return an < bn
		else:
			if ac != bc:
				return ac < bc
			ai += 1
			bi += 1
	return a.length() < b.length()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
