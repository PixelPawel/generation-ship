extends Control
# "Now researching" on the control screen while Research waits for the card to
# discard (Main.EffectMode.RESEARCH), with a Cancel button: until a card is
# picked nothing has happened yet, so the player can still change their mind
# (Main._cancel_research). Sits above everything else on the control screen,
# the Fleet Destination view included.

signal cancelled

const HEAD_COLOR: Color = Color(1.0, 0.85, 0.4)
const TEXT_COLOR: Color = Color(0.85, 0.9, 1.0)
const PANEL_WIDTH: float = 300.0

var _hint: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	center.add_child(panel)
	panel.set_content_margin(16)

	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var head: Label = Label.new()
	head.text = tr("NOW RESEARCHING")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", HEAD_COLOR)
	box.add_child(head)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", TEXT_COLOR)
	box.add_child(_hint)

	var cancel: Button = Button.new()
	cancel.text = tr("Cancel")
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.custom_minimum_size = Vector2(0.0, 44.0)
	GameTheme.apply_to_button(cancel)
	GameTheme.style_negative(cancel)
	cancel.pressed.connect(func() -> void: cancelled.emit())
	box.add_child(cancel)

func open(how_text: String) -> void:
	_hint.text = how_text
	move_to_front()
	visible = true

func close() -> void:
	visible = false
