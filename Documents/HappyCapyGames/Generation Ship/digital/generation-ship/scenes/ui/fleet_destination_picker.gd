extends Control
# Generation Fleet setup (main menu): "Pick 1 of the 18 Destinations or reveal
# 3 randomly, then pick 1." Opens on 3 random Destinations; "Show all 18" lists
# every one. Clicking a card selects it, Launch starts the game with it.
const PopupAnim = preload("res://scripts/popup_anim.gd")
const FleetData = preload("res://scripts/game/fleet_data.gd")

signal launch_requested(destination_no: int)

const _BIG_SIZE: Vector2 = Vector2(300, 214)     # 89 x 63.5 mm landscape
const _SMALL_SIZE: Vector2 = Vector2(150, 107)
const _REST_BRIGHTNESS: float = 1.0
const _SELECTED_COLOR: Color = Color(1.0, 0.85, 0.4)

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _show_all: bool = false
var _revealed: Array[int] = []
var _selected: int = 0
var _cards_box: GridContainer = null
var _info: Label = null
var _launch_btn: Button = null
var _toggle_btn: Button = null
var _reveal_btn: Button = null
var _frames: Dictionary = {}   # destination no -> PanelContainer (selection frame)

func _ready() -> void:
	_rng.randomize()
	_build_ui()
	visible = false

func open() -> void:
	_show_all = false
	_reveal_three()
	PopupAnim.open(self)

func _reveal_three() -> void:
	_revealed = FleetData.shuffled_destinations(_rng).slice(0, 3)
	_selected = 0
	_populate()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel: Control = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(1000, 0)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(960, 0)
	panel.add_child(vbox)

	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)
	var title: Label = Label.new()
	title.text = tr("GENERATION FLEET — CHOOSE YOUR DESTINATION")
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn: Button = _make_button("✕")
	close_btn.custom_minimum_size = Vector2(36, 0)
	close_btn.pressed.connect(func() -> void: PopupAnim.close(self))
	title_row.add_child(close_btn)

	var center: CenterContainer = CenterContainer.new()
	center.custom_minimum_size = Vector2(0, 360)
	vbox.add_child(center)
	_cards_box = GridContainer.new()
	_cards_box.add_theme_constant_override("h_separation", 16)
	_cards_box.add_theme_constant_override("v_separation", 12)
	center.add_child(_cards_box)

	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	vbox.add_child(_info)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vbox.add_child(row)
	_reveal_btn = _make_button(tr("Reveal 3 others"))
	_reveal_btn.pressed.connect(_reveal_three)
	row.add_child(_reveal_btn)
	_toggle_btn = _make_button("")
	_toggle_btn.pressed.connect(func() -> void:
		_show_all = not _show_all
		_populate())
	row.add_child(_toggle_btn)
	_launch_btn = _make_button(tr("Launch"))
	_launch_btn.custom_minimum_size = Vector2(180, 0)
	_launch_btn.pressed.connect(func() -> void:
		if _selected > 0:
			launch_requested.emit(_selected))
	row.add_child(_launch_btn)

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 18)
	btn.custom_minimum_size = Vector2(0, 44)
	GameTheme.apply_to_button(btn)
	return btn

func _populate() -> void:
	for child: Node in _cards_box.get_children():
		child.queue_free()
	_frames.clear()
	var nos: Array[int] = []
	if _show_all:
		for d: Dictionary in FleetData.DESTINATIONS:
			nos.append(int(d["no"]))
	else:
		nos = _revealed
	_cards_box.columns = 6 if _show_all else 3
	var size: Vector2 = _SMALL_SIZE if _show_all else _BIG_SIZE
	for no: int in nos:
		_cards_box.add_child(_make_card(no, size))
	_toggle_btn.text = tr("Show 3 random") if _show_all else tr("Show all 18")
	_reveal_btn.visible = not _show_all
	if not nos.has(_selected):
		_selected = 0
	_update_selection()

func _make_card(no: int, size: Vector2) -> Control:
	# PanelContainer lays the art out at its minimum size; a plain Panel left the
	# TextureRect at the PNG's full resolution.
	var frame: PanelContainer = PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	frame.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_selected = no
			_update_selection())
	var rect: TextureRect = TextureRect.new()
	var path: String = FleetData.destination_art(no)
	if not path.is_empty():
		rect.texture = load(path) as Texture2D
	rect.custom_minimum_size = size
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = load("res://shaders/card_rounded.gdshader")
	mat.set_shader_parameter("brightness", _REST_BRIGHTNESS)
	rect.material = mat
	frame.add_child(rect)
	_frames[no] = frame
	return frame

func _update_selection() -> void:
	for no: int in _frames:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(4)
		if no == _selected:
			sb.border_color = _SELECTED_COLOR
			sb.set_border_width_all(4)
		(_frames[no] as PanelContainer).add_theme_stylebox_override("panel", sb)
	_launch_btn.disabled = _selected == 0
	if _selected == 0:
		_info.text = tr("Pick a Destination for your fleet.")
	else:
		var d: Dictionary = FleetData.destination(_selected)
		var diff: int = int(d["difficulty"])
		_info.text = tr("%s — %s, %d generations") % [d["name"], tr(FleetData.DIFFICULTY_NAMES[diff]), FleetData.DIFFICULTY_GENERATIONS[diff]]

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		PopupAnim.close(self)
		get_viewport().set_input_as_handled()
