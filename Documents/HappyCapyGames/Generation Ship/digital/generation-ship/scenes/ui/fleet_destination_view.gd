extends Control
# Generation Fleet: the Destination on the cockpit's control screen (360x460).
# Red switch 1 (gs_ui_switch_flat1) flips the control screen between the
# supplies and this: the Destination card, generation, mission progress and
# shuttle cost.
const FleetData = preload("res://scripts/game/fleet_data.gd")
const LongPressGestureScript := preload("res://scenes/ui/long_press_gesture.gd")

signal destination_inspect_requested

const SCREEN_SIZE: Vector2 = Vector2(360, 460)
const CARD_SIZE: Vector2 = Vector2(324, 231)    # 89 x 63.5 mm
const HEAD_COLOR: Color = Color(1.0, 0.85, 0.4)
const TEXT_COLOR: Color = Color(0.85, 0.9, 1.0)
const DONE_COLOR: Color = Color(0.5, 1.0, 0.6)

var _card: TextureRect = null
var _gen_label: Label = null
var _mission_box: VBoxContainer = null
var _shuttle_label: Label = null

func _ready() -> void:
	size = SCREEN_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.09, 0.93)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var box: VBoxContainer = VBoxContainer.new()
	box.position = Vector2(18, 12)
	box.size = SCREEN_SIZE - Vector2(36, 24)
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var head: Label = _text(22, HEAD_COLOR)
	head.text = tr("DESTINATION")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)

	_card = TextureRect.new()
	_card.custom_minimum_size = CARD_SIZE
	_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.material = FleetData.screen_card_material()
	# like the market's cards: right-click (long press on touch) enlarges
	var gesture := LongPressGestureScript.new()
	_card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					gesture.begin(_card.get_tree(), mb.position, func(): destination_inspect_requested.emit())
				else:
					gesture.end()
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				destination_inspect_requested.emit()
		elif ev is InputEventMouseMotion:
			gesture.update_position((ev as InputEventMouseMotion).position))
	box.add_child(_card)

	_gen_label = _text(22, HEAD_COLOR)
	_gen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_gen_label)
	_mission_box = VBoxContainer.new()
	_mission_box.add_theme_constant_override("separation", 2)
	box.add_child(_mission_box)
	_shuttle_label = _text(17, Color(0.7, 0.75, 0.85))
	box.add_child(_shuttle_label)

func setup(destination_no: int) -> void:
	_card.texture = FleetData.screen_texture(FleetData.destination_art(destination_no), CARD_SIZE)
	_shuttle_label.text = tr("Shuttle cost: %d Dust") % int(FleetData.destination(destination_no).get("shuttle", 0))

func set_generation(current: int, total: int) -> void:
	_gen_label.text = tr("Generation %d / %d") % [current, total]

# lines: [{text, done}] — one per mission part.
func set_mission_progress(lines: Array) -> void:
	for child: Node in _mission_box.get_children():
		child.queue_free()
	for l: Dictionary in lines:
		var done: bool = bool(l.get("done", false))
		var lbl: Label = _text(19, DONE_COLOR if done else TEXT_COLOR)
		lbl.text = ("✔ " if done else "• ") + str(l.get("text", ""))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(CARD_SIZE.x, 0)
		_mission_box.add_child(lbl)

func _text(font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
