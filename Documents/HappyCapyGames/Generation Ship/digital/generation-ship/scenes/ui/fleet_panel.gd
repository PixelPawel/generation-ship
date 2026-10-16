extends Control
# Generation Fleet: the Dangers screen on the cockpit's info screen. Red switch
# 2 (gs_ui_switch_flat2) flips the info screen between the market and this: the
# Dangers revealed so far that aren't solved yet, and the Danger deck. (The
# Destination is on the control screen, see fleet_destination_view.gd.)
const FleetData = preload("res://scripts/game/fleet_data.gd")

signal danger_solve_pressed(danger_no: int)
signal danger_inspect_requested(danger_no: int)

const SCREEN_SIZE: Vector2 = Vector2(1200, 572)
const DANGER_SIZE: Vector2 = Vector2(210, 294)    # 63.5 x 89 mm
const DANGER_SIZE_SMALL: Vector2 = Vector2(150, 210)
const HEAD_COLOR: Color = Color(1.0, 0.85, 0.4)
const TEXT_COLOR: Color = Color(0.85, 0.9, 1.0)
const PLACE_COLOR: Color = Color(0.45, 0.85, 0.65)
const ALWAYS_COLOR: Color = Color(0.8, 0.55, 0.95)

var _danger_row: HBoxContainer = null
var _deck_label: Label = null
var _empty_label: Label = null

func _ready() -> void:
	_build_ui()

# dangers: [{no, solvable}] — the active (revealed, unsolved) Dangers, oldest first.
func set_dangers(dangers: Array, deck_left: int) -> void:
	for child: Node in _danger_row.get_children():
		child.queue_free()
	var size: Vector2 = DANGER_SIZE if dangers.size() <= 5 else DANGER_SIZE_SMALL
	for d: Dictionary in dangers:
		_danger_row.add_child(_make_danger(int(d["no"]), size, bool(d.get("solvable", false))))
	_empty_label.visible = dangers.is_empty()
	_deck_label.text = tr("Danger deck: %d") % deck_left

func _build_ui() -> void:
	size = SCREEN_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS

	var root: HBoxContainer = HBoxContainer.new()
	root.position = Vector2(24, 18)
	root.size = SCREEN_SIZE - Vector2(48, 36)
	root.add_theme_constant_override("separation", 28)
	add_child(root)

	# — Dangers —
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	var head_row: HBoxContainer = HBoxContainer.new()
	right.add_child(head_row)
	var head: Label = _header(tr("DANGERS"))
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(head)
	_deck_label = _text(20, Color(0.7, 0.75, 0.85))
	head_row.add_child(_deck_label)
	_danger_row = HBoxContainer.new()
	_danger_row.add_theme_constant_override("separation", 14)
	right.add_child(_danger_row)
	_empty_label = _text(24, Color(0.6, 0.65, 0.75))
	_empty_label.text = tr("No active dangers. Three are revealed at the start of every generation.")
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_empty_label)

func _make_danger(no: int, card_size: Vector2, solvable: bool) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var d: Dictionary = FleetData.danger(no)
	var always: bool = str(d.get("type", "")) == "always"
	var tag: Label = _text(18, ALWAYS_COLOR if always else PLACE_COLOR)
	tag.text = tr("ALWAYS") if always else tr("PLACE")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)
	var rect: TextureRect = _card_rect(card_size)
	rect.texture = FleetData.screen_texture(FleetData.danger_art(no), card_size)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.gui_input.connect(func(event: InputEvent) -> void:
		if _is_click(event):
			danger_inspect_requested.emit(no))
	box.add_child(rect)
	var solve: Button = Button.new()
	solve.text = tr("Solve")
	solve.add_theme_font_size_override("font_size", 20)
	solve.disabled = not solvable
	GameTheme.apply_to_button(solve)
	solve.pressed.connect(func() -> void: danger_solve_pressed.emit(no))
	box.add_child(solve)
	return box

func _card_rect(card_size: Vector2) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.custom_minimum_size = card_size
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = FleetData.screen_card_material()
	return rect

func _header(t: String) -> Label:
	var l: Label = _text(26, HEAD_COLOR)
	l.text = t
	return l

func _text(font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func _is_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
