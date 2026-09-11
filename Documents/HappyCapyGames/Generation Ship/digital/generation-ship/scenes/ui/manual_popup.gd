extends Control

const PAGE_COUNT: int = 12
const PAGE_BASE: String = "res://assets/manual/manual_page_%02d.png"

const ZOOM_STEP: float = 0.25
const ZOOM_MIN: float = 1.0
const ZOOM_MAX: float = 3.0
# A5 portrait at 536px panel width
const BASE_W: float = 536.0
const BASE_H: float = 760.0

var _page: int = 1
var _zoom: float = 1.0
var _pages: Array[Texture2D] = []
var _page_image: TextureRect = null
var _scroll: ScrollContainer = null
var _page_label: Label = null
var _zoom_label: Label = null
var _tr_targets: Dictionary = {}   # Control (Label/Button) -> untranslated key, refreshed on locale change

func _ready() -> void:
	add_to_group("locale_refresh")
	_load_pages()
	_build_ui()
	visible = false

# Same fix as CollectionPopup.refresh_locale_text() — this popup's static
# text is built once via tr() long before the pause menu's language dropdown
# ever runs, so it freezes on the boot locale unless something re-applies
# tr() after a live language change. pause_menu.gd broadcasts to the
# "locale_refresh" group on every change.
func refresh_locale_text() -> void:
	for ctrl: Control in _tr_targets:
		if is_instance_valid(ctrl):
			ctrl.text = tr(_tr_targets[ctrl] as String)
	_go_to(_page)
	_set_zoom(_zoom)

func _load_pages() -> void:
	_pages.resize(PAGE_COUNT)
	for i: int in range(PAGE_COUNT):
		var path: String = PAGE_BASE % (i + 1)
		if ResourceLoader.exists(path):
			_pages[i] = load(path) as Texture2D

func open() -> void:
	_go_to(1)
	_set_zoom(1.0)
	visible = true

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel: Control = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(12)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(830, 860)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.custom_minimum_size = Vector2(804, 0)
	panel.add_child(vbox)

	# — Title bar —
	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)

	var title: Label = Label.new()
	title.text = tr("RULE BOOK")
	_tr_targets[title] = "RULE BOOK"
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

	# — Scrollable page image —
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 720)
	vbox.add_child(_scroll)

	_page_image = TextureRect.new()
	_page_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_page_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_page_image)

	var sep2: HSeparator = HSeparator.new()
	sep2.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(sep2)

	# — Navigation bar —
	var nav: HBoxContainer = HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	vbox.add_child(nav)

	var prev_btn: Button = _make_button(tr("◀  Prev"))
	_tr_targets[prev_btn] = "◀  Prev"
	prev_btn.pressed.connect(_on_prev)
	nav.add_child(prev_btn)

	_page_label = Label.new()
	_page_label.add_theme_font_size_override("font_size", 15)
	_page_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(80, 0)
	nav.add_child(_page_label)

	var next_btn: Button = _make_button(tr("Next  ▶"))
	_tr_targets[next_btn] = "Next  ▶"
	next_btn.pressed.connect(_on_next)
	nav.add_child(next_btn)

	# spacer between page nav and zoom controls
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	nav.add_child(spacer)

	var zoom_out_btn: Button = _make_button("−")
	zoom_out_btn.custom_minimum_size = Vector2(36, 0)
	zoom_out_btn.pressed.connect(_on_zoom_out)
	nav.add_child(zoom_out_btn)

	_zoom_label = Label.new()
	_zoom_label.add_theme_font_size_override("font_size", 15)
	_zoom_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.custom_minimum_size = Vector2(52, 0)
	nav.add_child(_zoom_label)

	var zoom_in_btn: Button = _make_button("+")
	zoom_in_btn.custom_minimum_size = Vector2(36, 0)
	zoom_in_btn.pressed.connect(_on_zoom_in)
	nav.add_child(zoom_in_btn)

func _go_to(page: int) -> void:
	_page = clampi(page, 1, PAGE_COUNT)
	if _page_image:
		_page_image.texture = _pages[_page - 1]
	if _page_label:
		_page_label.text = tr("%d / %d") % [_page, PAGE_COUNT]

func _set_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	if _zoom_label:
		_zoom_label.text = tr("%d%%") % roundi(_zoom * 100.0)
	if not _page_image:
		return
	if _zoom <= 1.0:
		_page_image.custom_minimum_size = Vector2.ZERO
		_page_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_page_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		_page_image.custom_minimum_size = Vector2(BASE_W * _zoom, BASE_H * _zoom)
		_page_image.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_page_image.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

func _on_prev() -> void:
	_go_to(_page - 1)

func _on_next() -> void:
	_go_to(_page + 1)

func _on_zoom_in() -> void:
	_set_zoom(_zoom + ZOOM_STEP)

func _on_zoom_out() -> void:
	_set_zoom(_zoom - ZOOM_STEP)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				visible = false
				get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_A:
				_on_prev()
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				_on_next()
				get_viewport().set_input_as_handled()
			KEY_EQUAL, KEY_KP_ADD:
				_on_zoom_in()
				get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_on_zoom_out()
				get_viewport().set_input_as_handled()

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 14)
	GameTheme.apply_to_button(btn)
	return btn
