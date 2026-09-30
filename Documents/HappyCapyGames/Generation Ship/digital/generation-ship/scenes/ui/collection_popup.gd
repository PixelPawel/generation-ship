extends Control

const _SETTINGS_PATH: String = "user://settings.cfg"
const _LANGUAGE_CODES: Array[String] = ["en", "de", "it", "pl", "es", "fr"]

# folder: matches the on-disk assets/cards/<folder>/<LANG>/ directory name
# ("Destiniations" keeps the source export's spelling — not renaming assets).
# label_key: tr() key shown on the tab button.
# landscape: true for wide cards (Sector, Destination), false for portrait.
# file_base/count: same print-export naming convention as CardDatabase's
# _resolve_art() — page 1 has no numeric suffix, page N>=2 appends N.
# Sector doesn't fit that single-file_base shape (6 groups x 5 fronts + 1
# back each), so it's handled separately via _SECTOR_GROUPS below.
const _DECKS: Array[Dictionary] = [
	{"folder": "Tech", "label_key": "Tech", "landscape": false, "file_base": "GS Techs 44x67mm", "count": 137},
	{"folder": "Promo", "label_key": "Promo", "landscape": false, "file_base": "GS Techs Promos 44x67mm", "count": 6},
	{"folder": "Sector", "label_key": "Sector", "landscape": true},
	{"folder": "Expedition", "label_key": "Expedition", "landscape": false, "file_base": "GS Expeditions 44x67mm", "count": 26},
	{"folder": "Dangers", "label_key": "Danger", "landscape": false, "file_base": "GS Dangers 63,5x89mm", "count": 30},
	{"folder": "Destiniations", "label_key": "Destination", "landscape": true, "file_base": "GS Destiniations 89x63,5mm", "count": 18},
]

# Exact on-disk base filenames for each of the 6 sector groups — spacing is
# irregular (group 6 has a double space) so these can't be generated
# algorithmically; matches _ADV_SECTOR_ART/_DUST_SECTOR_ART in
# card_database.gd exactly, keep in sync if the print export ever changes.
const _SECTOR_GROUPS: Array[Dictionary] = [
	{"front": "GS Sector 1 67x44mm", "back": "GS Sector 1 Back 67x44mm"},
	{"front": "GS Sector 2 67x44mm", "back": "GS Sector 2 Back 67x44mm"},
	{"front": "GS Sector 3 67x44mm", "back": "GS Sector 3 Back  67x44mm"},
	{"front": "GS Sector 4 67x44mm", "back": "GS Sector 4 Back  67x44mm"},
	{"front": "GS Sector 5 67x44mm", "back": "GS Sector 5 Back  67x44mm"},
	{"front": "GS Sector 6  67x44mm", "back": "GS Sector 6  Back  67x44mm"},
]
const _SECTOR_FRONT_PAGES: int = 5

const _PORTRAIT_SIZE: Vector2 = Vector2(120, 168)
const _PORTRAIT_COLUMNS: int = 6
const _LANDSCAPE_SIZE: Vector2 = Vector2(184, 121)
const _LANDSCAPE_COLUMNS: int = 4
# Click-to-enlarge close-up sizes — same portrait/landscape split as the
# thumbnail grid, just scaled up (matches the pattern in bid_popup.gd). Two of these
# show side by side (English + current language) with a gap and a small
# language-code label above each — see _show_enlarged().
const _PORTRAIT_ENLARGE_SIZE: Vector2 = Vector2(340, 476)
const _LANDSCAPE_ENLARGE_SIZE: Vector2 = Vector2(520, 342)
const _ENLARGE_GAP: float = 24.0
const _ENLARGE_LABEL_HEIGHT: float = 20.0
# Cursor "light" on hover — a flat window-wide brighten didn't read right,
# so instead each card lights up individually as the mouse crosses it.
# card_rounded.gdshader writes COLOR straight from the sampled texture and
# never reads the node's built-in MODULATE, so a modulate tween is a no-op
# here — its own "brightness" uniform (shared shader default: 0.70, i.e.
# dimmed) is what actually has to move. Tween shape matches main_menu.gd's
# button hover glow.
const _REST_BRIGHTNESS: float = 1.0
const _HOVER_BRIGHTNESS: float = 1.35
const _HOVER_SCALE: Vector2 = Vector2(1.06, 1.06)
const _HOVER_IN_SEC: float = 0.15
const _HOVER_OUT_SEC: float = 0.22

var _active_tab: int = 0
var _tab_buttons: Array[Button] = []
var _grid: GridContainer = null
var _enlarge_left: TextureRect = null
var _enlarge_right: TextureRect = null
var _enlarge_left_label: Label = null
var _enlarge_right_label: Label = null
# Community translation vote under the translated (right-hand) close-up —
# see TranslationVotes. Hidden for English and when Steam isn't running.
# Looked up at runtime (_votes()), not by autoload name: the Android copy
# ships without the TranslationVotes autoload (see tools/sync_android.py).
const _VOTE_ROW_HEIGHT: float = 40.0
const _VOTE_UP_COLOR: Color = Color(0.45, 1.0, 0.55)
const _VOTE_DOWN_COLOR: Color = Color(1.0, 0.45, 0.45)
var _vote_row: HBoxContainer = null
var _vote_up_btn: Button = null
var _vote_down_btn: Button = null
var _vote_key: String = ""
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
	if _vote_up_btn:
		_vote_up_btn.tooltip_text = tr("Good translation")
		_vote_down_btn.tooltip_text = tr("Needs work")

func open() -> void:
	_hide_enlarged()
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

	var hint: Label = Label.new()
	hint.text = tr("Click a card to zoom")
	_tr_targets[hint] = "Click a card to zoom"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

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

	# Click-to-enlarge close-up, added last so it paints above the
	# panel and everything in it — same pattern as bid_popup.gd's
	# _card_enlarge_image, but two images side by side (English + the
	# current language) instead of one, sized/positioned per-tab in
	# _show_enlarged() since cards can be portrait or landscape.
	_enlarge_left = _make_enlarge_rect()
	add_child(_enlarge_left)
	_enlarge_right = _make_enlarge_rect()
	add_child(_enlarge_right)
	_enlarge_left_label = _make_enlarge_label()
	add_child(_enlarge_left_label)
	_enlarge_right_label = _make_enlarge_label()
	add_child(_enlarge_right_label)
	_build_vote_row()

func _build_vote_row() -> void:
	_vote_row = HBoxContainer.new()
	_vote_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_vote_row.add_theme_constant_override("separation", 8)
	_vote_row.anchor_left = 0.5
	_vote_row.anchor_right = 0.5
	_vote_row.anchor_top = 0.5
	_vote_row.anchor_bottom = 0.5
	_vote_row.visible = false
	add_child(_vote_row)

	var caption: Label = Label.new()
	caption.text = tr("Rate translation:")
	_tr_targets[caption] = "Rate translation:"
	caption.add_theme_font_size_override("font_size", 13)
	caption.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vote_row.add_child(caption)

	_vote_up_btn = _make_button("▲")
	_vote_up_btn.tooltip_text = tr("Good translation")
	_vote_up_btn.custom_minimum_size = Vector2(70, 0)
	_vote_up_btn.pressed.connect(_on_vote_pressed.bind(1))
	_vote_row.add_child(_vote_up_btn)

	_vote_down_btn = _make_button("▼")
	_vote_down_btn.tooltip_text = tr("Needs work")
	_vote_down_btn.custom_minimum_size = Vector2(70, 0)
	_vote_down_btn.pressed.connect(_on_vote_pressed.bind(-1))
	_vote_row.add_child(_vote_down_btn)

	var tv: Node = _votes()
	if tv:
		tv.votes_ready.connect(_on_votes_ready)

func _votes() -> Node:
	return get_node_or_null("/root/TranslationVotes")

func _show_vote_row(folder: String, fname: String, under: TextureRect) -> void:
	var lang: String = _current_lang()
	if lang == "EN" or not _votes() or not _votes().is_available():
		_vote_row.visible = false
		_vote_key = ""
		return
	_vote_key = _votes().board_name(lang, folder, fname)
	_vote_row.offset_left = under.offset_left
	_vote_row.offset_right = under.offset_right
	_vote_row.offset_top = under.offset_bottom + 8.0
	_vote_row.offset_bottom = _vote_row.offset_top + _VOTE_ROW_HEIGHT
	var c: Dictionary = _votes().cached(_vote_key)
	if c.is_empty():
		_set_vote_display(-1, -1, 0)
	else:
		_set_vote_display(int(c.up), int(c.down), int(c.mine))
	_vote_row.visible = true
	_votes().fetch(_vote_key)

# up/down -1 = not loaded yet.
func _set_vote_display(up: int, down: int, mine: int) -> void:
	_vote_up_btn.text = "▲ " + ("…" if up < 0 else str(up))
	_vote_down_btn.text = "▼ " + ("…" if down < 0 else str(down))
	_vote_up_btn.modulate = _VOTE_UP_COLOR if mine > 0 else Color.WHITE
	_vote_down_btn.modulate = _VOTE_DOWN_COLOR if mine < 0 else Color.WHITE

func _on_votes_ready(key: String, up: int, down: int, mine: int) -> void:
	if key == _vote_key and _vote_row.visible:
		_set_vote_display(up, down, mine)

# Clicking your current vote again retracts it.
func _on_vote_pressed(value: int) -> void:
	if _vote_key.is_empty():
		return
	var mine: int = int(_votes().cached(_vote_key).get("mine", 0))
	_votes().vote(_vote_key, 0 if mine == value else value)

func _make_enlarge_rect() -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.gui_input.connect(_on_enlarge_gui_input)
	rect.visible = false
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/card_rounded.gdshader")
	mat.set_shader_parameter("brightness", _REST_BRIGHTNESS)
	rect.material = mat
	rect.anchor_left = 0.5
	rect.anchor_right = 0.5
	rect.anchor_top = 0.5
	rect.anchor_bottom = 0.5
	return rect

func _make_enlarge_label() -> Label:
	var lbl: Label = Label.new()
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.visible = false
	lbl.anchor_left = 0.5
	lbl.anchor_right = 0.5
	lbl.anchor_top = 0.5
	lbl.anchor_bottom = 0.5
	return lbl

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
	_hide_enlarged()
	_thumb_tweens.clear()
	for child: Node in _grid.get_children():
		child.queue_free()
	var deck: Dictionary = _DECKS[_active_tab]
	var landscape: bool = deck.get("landscape", false)
	_grid.columns = _LANDSCAPE_COLUMNS if landscape else _PORTRAIT_COLUMNS
	var box_size: Vector2 = _LANDSCAPE_SIZE if landscape else _PORTRAIT_SIZE
	for entry: Dictionary in _list_deck_files(deck):
		var path: String = entry.get("path", "") as String
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
		rect.gui_input.connect(func(event: InputEvent) -> void: _on_thumb_gui_input(event, entry, landscape))
		rect.mouse_entered.connect(func() -> void: _on_thumb_hover(rect, true))
		rect.mouse_exited.connect(func() -> void: _on_thumb_hover(rect, false))
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = load("res://shaders/card_rounded.gdshader")
		mat.set_shader_parameter("brightness", _REST_BRIGHTNESS)
		rect.material = mat
		_grid.add_child(rect)

func _on_thumb_hover(rect: TextureRect, entered: bool) -> void:
	var mat: ShaderMaterial = rect.material as ShaderMaterial
	if not mat:
		return
	var prev: Tween = _thumb_tweens.get(rect) as Tween
	if prev and prev.is_valid():
		prev.kill()
	var tw: Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var target_brightness: float = _HOVER_BRIGHTNESS if entered else _REST_BRIGHTNESS
	var target_scale: Vector2 = _HOVER_SCALE if entered else Vector2.ONE
	var dur: float = _HOVER_IN_SEC if entered else _HOVER_OUT_SEC
	tw.tween_property(mat, "shader_parameter/brightness", target_brightness, dur)
	tw.parallel().tween_property(rect, "scale", target_scale, dur)
	_thumb_tweens[rect] = tw

func _on_thumb_gui_input(event: InputEvent, entry: Dictionary, landscape: bool) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT) and mb.pressed:
		_show_enlarged(entry, landscape)
		get_viewport().set_input_as_handled()

# English on the left, the current language on the right — if the current
# language IS English (or that specific card's art is missing and already
# fell back to English), there's nothing to compare, so just show the one
# image centered, same as before.
func _show_enlarged(entry: Dictionary, landscape: bool) -> void:
	var folder: String = entry.get("folder", "") as String
	var fname: String = entry.get("fname", "") as String
	var current_path: String = entry.get("path", "") as String
	var en_path: String = "res://assets/cards/%s/EN/%s" % [folder, fname]
	if not ResourceLoader.exists(en_path):
		en_path = current_path
	var sz: Vector2 = _LANDSCAPE_ENLARGE_SIZE if landscape else _PORTRAIT_ENLARGE_SIZE

	if en_path == current_path:
		_position_enlarge(_enlarge_left, _enlarge_left_label, sz, Vector2.ZERO, "")
		_enlarge_left.texture = load(current_path) as Texture2D
		_enlarge_left.visible = true
		_enlarge_right.visible = false
		_enlarge_right_label.visible = false
		# English (or art missing in this language): nothing translated to rate.
		_vote_row.visible = false
		_vote_key = ""
	else:
		var half_gap: float = _ENLARGE_GAP / 2.0
		_position_enlarge(_enlarge_left, _enlarge_left_label, sz, Vector2(-sz.x / 2.0 - half_gap, 0.0), "EN")
		_position_enlarge(_enlarge_right, _enlarge_right_label, sz, Vector2(sz.x / 2.0 + half_gap, 0.0), _current_lang())
		_enlarge_left.texture = load(en_path) as Texture2D
		_enlarge_right.texture = load(current_path) as Texture2D
		_enlarge_left.visible = true
		_enlarge_right.visible = true
		_show_vote_row(folder, fname, _enlarge_right)

func _position_enlarge(rect: TextureRect, lbl: Label, sz: Vector2, center: Vector2, label_text: String) -> void:
	rect.offset_left = center.x - sz.x / 2.0
	rect.offset_right = center.x + sz.x / 2.0
	rect.offset_top = center.y - sz.y / 2.0
	rect.offset_bottom = center.y + sz.y / 2.0
	if label_text.is_empty():
		lbl.visible = false
		return
	lbl.text = label_text
	lbl.offset_left = rect.offset_left
	lbl.offset_right = rect.offset_right
	lbl.offset_bottom = rect.offset_top - 4.0
	lbl.offset_top = lbl.offset_bottom - _ENLARGE_LABEL_HEIGHT
	lbl.visible = true

func _on_enlarge_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT) and mb.pressed:
		_hide_enlarged()
		get_viewport().set_input_as_handled()

func _hide_enlarged() -> void:
	if not _enlarge_left:
		return
	_enlarge_left.visible = false
	_enlarge_right.visible = false
	_enlarge_left_label.visible = false
	_enlarge_right_label.visible = false
	if _vote_row:
		_vote_row.visible = false
		_vote_key = ""

func _current_lang() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	var locale: String = "en"
	if cfg.load(_SETTINGS_PATH) == OK:
		locale = str(cfg.get_value("game", "locale", "en"))
	if not _LANGUAGE_CODES.has(locale):
		locale = "en"
	return locale.to_upper()


# Builds the exact expected filename list for a deck rather than scanning the
# folder at runtime: DirAccess.list_dir_begin() doesn't reliably enumerate
# imported/remapped resources inside an exported PCK (this is why the
# Collection showed every card in the editor/debug run but none at all in
# the Steam export, while CardDatabase's per-card art — which resolves exact
# paths via ResourceLoader.exists()/load(), never a directory scan — worked
# fine there the whole time). Generating the filename and checking it with
# ResourceLoader.exists() is the same proven approach as
# CardDatabase._resolve_art(), just applied to a whole deck instead of one
# card at a time.
func _list_deck_files(deck: Dictionary) -> Array[Dictionary]:
	var folder: String = deck.get("folder", "") as String
	var file_bases: Array[String] = []
	if folder == "Sector":
		for group: Dictionary in _SECTOR_GROUPS:
			for page: int in range(1, _SECTOR_FRONT_PAGES + 1):
				file_bases.append(_paged_filename(group.get("front", "") as String, page))
			file_bases.append(_paged_filename(group.get("back", "") as String, 1))
	else:
		var base: String = deck.get("file_base", "") as String
		var count: int = deck.get("count", 0) as int
		for page: int in range(1, count + 1):
			file_bases.append(_paged_filename(base, page))

	# fname/folder are carried alongside the resolved path so the click-to-
	# enlarge close-up can independently resolve the EN version of the same
	# card for the side-by-side comparison, regardless of which locale "path"
	# landed on.
	var out: Array[Dictionary] = []
	for fname: String in file_bases:
		var resolved: String = _resolve_file(folder, fname)
		if not resolved.is_empty():
			out.append({"path": resolved, "fname": fname, "folder": folder})
	return out

func _paged_filename(file_base: String, page: int) -> String:
	return file_base + ("" if page == 1 else str(page)) + ".png"

func _resolve_file(folder: String, fname: String) -> String:
	var lang: String = _current_lang()
	var path: String = "res://assets/cards/%s/%s/%s" % [folder, lang, fname]
	if ResourceLoader.exists(path):
		return path
	if lang != "EN":
		var fallback: String = "res://assets/cards/%s/EN/%s" % [folder, fname]
		if ResourceLoader.exists(fallback):
			return fallback
	return ""

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
