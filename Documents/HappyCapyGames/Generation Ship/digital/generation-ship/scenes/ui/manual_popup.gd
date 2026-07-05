extends Control

const PAGE_COUNT: int = 12
const PAGE_BASE: String = "res://assets/manual/manual_page_%02d.png"

var _page: int = 1
var _pages: Array[Texture2D] = []
var _page_image: TextureRect = null
var _page_label: Label = null

func _ready() -> void:
	_load_pages()
	_build_ui()
	visible = false

func _load_pages() -> void:
	_pages.resize(PAGE_COUNT)
	for i: int in range(PAGE_COUNT):
		var path: String = PAGE_BASE % (i + 1)
		if ResourceLoader.exists(path):
			_pages[i] = load(path) as Texture2D

func open() -> void:
	_go_to(1)
	visible = true

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel: Control = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(12)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 860)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.custom_minimum_size = Vector2(536, 0)
	panel.add_child(vbox)

	# — Title bar —
	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)

	var title: Label = Label.new()
	title.text = "RULE BOOK"
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

	# — Page image —
	_page_image = TextureRect.new()
	_page_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_page_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_image.custom_minimum_size = Vector2(0, 720)
	vbox.add_child(_page_image)

	var sep2: HSeparator = HSeparator.new()
	sep2.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(sep2)

	# — Navigation bar —
	var nav: HBoxContainer = HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 16)
	vbox.add_child(nav)

	var prev_btn: Button = _make_button("◀  Prev")
	prev_btn.pressed.connect(_on_prev)
	nav.add_child(prev_btn)

	_page_label = Label.new()
	_page_label.add_theme_font_size_override("font_size", 15)
	_page_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(100, 0)
	nav.add_child(_page_label)

	var next_btn: Button = _make_button("Next  ▶")
	next_btn.pressed.connect(_on_next)
	nav.add_child(next_btn)

func _go_to(page: int) -> void:
	_page = clampi(page, 1, PAGE_COUNT)
	var tex: Texture2D = _pages[_page - 1]
	if _page_image:
		_page_image.texture = tex
	if _page_label:
		_page_label.text = "%d / %d" % [_page, PAGE_COUNT]

func _on_prev() -> void:
	_go_to(_page - 1)

func _on_next() -> void:
	_go_to(_page + 1)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			visible = false
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_LEFT or event.keycode == KEY_A:
			_on_prev()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			_on_next()
			get_viewport().set_input_as_handled()

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 14)
	GameTheme.apply_to_button(btn)
	return btn
