extends Control
# A prompt in the middle of the control screen, above everything else on it
# (the Fleet Destination view included). Main owns two:
#  - "Now researching" while Research waits for the card to discard
#    (Main.EffectMode.RESEARCH), with Cancel: until a card is picked nothing
#    has happened yet, so the player can still change their mind
#    (Main._cancel_research).
#  - "Pass?" after the Pass button, with Pass + Cancel: passing ends the
#    player's Generation, so it only happens once confirmed (Main._confirm_pass).

signal cancelled
signal confirmed

const HEAD_COLOR: Color = Color(1.0, 0.85, 0.4)
const TEXT_COLOR: Color = Color(0.85, 0.9, 1.0)
const PANEL_WIDTH: float = 300.0

var _head: Label = null
var _hint: Label = null
var _confirm: Button = null
var _cancel: Button = null

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

	_head = Label.new()
	_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head.add_theme_font_size_override("font_size", 22)
	_head.add_theme_color_override("font_color", HEAD_COLOR)
	box.add_child(_head)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", TEXT_COLOR)
	box.add_child(_hint)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_cancel = _make_button(row)
	GameTheme.style_negative(_cancel)
	_cancel.pressed.connect(func() -> void: cancelled.emit())
	_confirm = _make_button(row)
	GameTheme.style_positive(_confirm)
	_confirm.pressed.connect(func() -> void: confirmed.emit())

func _make_button(row: HBoxContainer) -> Button:
	var btn: Button = Button.new()
	btn.add_theme_font_size_override("font_size", 18)
	btn.custom_minimum_size = Vector2(0.0, 44.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameTheme.apply_to_button(btn)
	row.add_child(btn)
	return btn

## confirm_text empty = Cancel only (Research); otherwise the confirm button
## (e.g. "Pass") sits beside Cancel.
func open(head_text: String, how_text: String, confirm_text: String = "") -> void:
	_head.text = head_text
	_hint.text = how_text
	_cancel.text = tr("Cancel")
	_confirm.text = confirm_text
	_confirm.visible = not confirm_text.is_empty()
	move_to_front()
	visible = true

func close() -> void:
	visible = false
