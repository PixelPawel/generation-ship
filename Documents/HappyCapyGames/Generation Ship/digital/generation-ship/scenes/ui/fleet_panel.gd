extends Control
# Generation Fleet: the Dangers screen on the cockpit's info screen. Red switch
# 2 (gs_ui_switch_flat2) flips the info screen between the market and this: the
# Dangers revealed so far that aren't solved yet, and the Danger deck. (The
# Destination is on the control screen, see fleet_destination_view.gd.)
# The cards fill the screen; like the market's, right-click (long press on
# touch) enlarges one and a click anywhere shrinks it again.
const FleetData = preload("res://scripts/game/fleet_data.gd")
const LongPressGestureScript := preload("res://scenes/ui/long_press_gesture.gd")

signal danger_solve_pressed(danger_no: int)
signal danger_inspect_requested(danger_no: int)
signal danger_hover_started(danger_no: int)
signal danger_hover_ended

const SCREEN_SIZE: Vector2 = Vector2(1200, 572)
const MARGIN: Vector2 = Vector2(24, 14)
const CARD_GAP: float = 16.0
const CARD_ASPECT: float = 63.5 / 89.0
const HEAD_H: float = 34.0         # "DANGERS" row
const TAG_H: float = 24.0          # PLACE / ALWAYS
const BUTTON_H: float = 44.0       # Solve
const V_SEP: float = 6.0
const HEAD_COLOR: Color = Color(1.0, 0.85, 0.4)
const PLACE_COLOR: Color = Color(0.45, 0.85, 0.65)
const ALWAYS_COLOR: Color = Color(0.8, 0.55, 0.95)

var _danger_row: HBoxContainer = null
var _deck_label: Label = null
var _empty_label: Label = null
var _rects: Dictionary = {}   # danger no -> TextureRect
var _solve_btns: Dictionary = {}   # danger no -> Button
var _shown: Array[int] = []        # danger nos currently built, in order

func _ready() -> void:
	_build_ui()

# dangers: [{no, solvable}] — the active (revealed, unsolved) Dangers, oldest first.
# Called every half second while shown: the cards are only rebuilt when the set
# of Dangers changes (a rebuild would drop the hover and a running long press).
func set_dangers(dangers: Array, deck_left: int) -> void:
	var nos: Array[int] = []
	for d: Dictionary in dangers:
		nos.append(int(d["no"]))
	if nos != _shown:
		for child: Node in _danger_row.get_children():
			child.queue_free()
		_rects.clear()
		_solve_btns.clear()
		_shown = nos
		var card_size: Vector2 = _card_size(dangers.size())
		for no: int in nos:
			_danger_row.add_child(_make_danger(no, card_size))
	for d: Dictionary in dangers:
		var btn: Button = _solve_btns.get(int(d["no"])) as Button
		if btn:
			btn.disabled = not bool(d.get("solvable", false))
	_empty_label.visible = dangers.is_empty()
	_deck_label.text = tr("Danger deck: %d") % deck_left

## Viewport position of a Danger card's centre (where its enlarge starts).
func get_danger_center(danger_no: int) -> Vector2:
	var rect: TextureRect = _rects.get(danger_no) as TextureRect
	return rect.get_global_rect().get_center() if rect else SCREEN_SIZE * 0.5

# As big as the screen allows: full height for a few cards, narrower when
# more are in play.
func _card_size(count: int) -> Vector2:
	var avail_w: float = SCREEN_SIZE.x - 2.0 * MARGIN.x
	var avail_h: float = SCREEN_SIZE.y - 2.0 * MARGIN.y - HEAD_H - TAG_H - BUTTON_H - 4.0 * V_SEP
	var h: float = avail_h
	var w: float = h * CARD_ASPECT
	var n: int = maxi(1, count)
	var fit_w: float = (avail_w - CARD_GAP * float(n - 1)) / float(n)
	if w > fit_w:
		w = fit_w
		h = w / CARD_ASPECT
	return Vector2(floorf(w), floorf(h))

func _build_ui() -> void:
	size = SCREEN_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS

	var col: VBoxContainer = VBoxContainer.new()
	col.position = MARGIN
	col.size = SCREEN_SIZE - 2.0 * MARGIN
	col.add_theme_constant_override("separation", int(V_SEP))
	add_child(col)
	var head_row: HBoxContainer = HBoxContainer.new()
	head_row.custom_minimum_size = Vector2(0, HEAD_H)
	col.add_child(head_row)
	var head: Label = _text(26, HEAD_COLOR)
	head.text = tr("DANGERS")
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(head)
	_deck_label = _text(20, Color(0.7, 0.75, 0.85))
	head_row.add_child(_deck_label)
	_danger_row = HBoxContainer.new()
	_danger_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_danger_row.add_theme_constant_override("separation", int(CARD_GAP))
	col.add_child(_danger_row)
	_empty_label = _text(24, Color(0.6, 0.65, 0.75))
	_empty_label.text = tr("No active dangers. Three are revealed at the start of every generation.")
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_empty_label)

func _make_danger(no: int, card_size: Vector2) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", int(V_SEP))
	var d: Dictionary = FleetData.danger(no)
	var always: bool = str(d.get("type", "")) == "always"
	var tag: Label = _text(18, ALWAYS_COLOR if always else PLACE_COLOR)
	tag.text = tr("ALWAYS") if always else tr("PLACE")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.custom_minimum_size = Vector2(0, TAG_H)
	box.add_child(tag)

	var rect: TextureRect = TextureRect.new()
	rect.custom_minimum_size = card_size
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.texture = FleetData.screen_texture(FleetData.danger_art(no), card_size)
	rect.material = FleetData.screen_card_material()
	var gesture := LongPressGestureScript.new()
	rect.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					gesture.begin(rect.get_tree(), mb.position, func(): danger_inspect_requested.emit(no))
				else:
					gesture.end()
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				danger_inspect_requested.emit(no)
		elif ev is InputEventMouseMotion:
			gesture.update_position((ev as InputEventMouseMotion).position))
	rect.mouse_entered.connect(func() -> void:
		CursorManager.set_hover()
		danger_hover_started.emit(no))
	rect.mouse_exited.connect(func() -> void:
		CursorManager.set_default()
		danger_hover_ended.emit())
	box.add_child(rect)
	_rects[no] = rect

	var solve: Button = Button.new()
	solve.text = tr("Solve")
	solve.custom_minimum_size = Vector2(0, BUTTON_H)
	solve.add_theme_font_size_override("font_size", 22)
	GameTheme.apply_to_button(solve)
	_solve_btns[no] = solve
	solve.pressed.connect(func() -> void: danger_solve_pressed.emit(no))
	box.add_child(solve)
	return box

func _text(font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
