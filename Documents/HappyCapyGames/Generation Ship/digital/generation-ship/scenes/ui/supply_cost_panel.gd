class_name SupplyCostPanel
extends Control

signal supply_chosen(color: CardData.SupplyColor)
signal cancelled

var _title: Label
var _hint: Label
var _buttons_row: HBoxContainer
var _supply_chosen_fired: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   0)
	margin.add_theme_constant_override("margin_right",  0)
	margin.add_theme_constant_override("margin_top",    0)
	margin.add_theme_constant_override("margin_bottom", 0)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(360, 0)
	margin.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(_hint)

	_buttons_row = HBoxContainer.new()
	_buttons_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_buttons_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 15)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.pressed.connect(func() -> void: hide())
	vbox.add_child(cancel_btn)

	visibility_changed.connect(func() -> void:
		if not visible:
			if not _supply_chosen_fired:
				cancelled.emit()
			_supply_chosen_fired = false
	)

func show_cost(card_name: String, cost: int, affordable: Array) -> void:
	_title.text = card_name
	_hint.text = "Choose supply to pay %d:" % cost
	for child: Node in _buttons_row.get_children():
		child.queue_free()
	for color: Variant in affordable:
		_buttons_row.add_child(_make_btn(color as CardData.SupplyColor, cost))
	show()

func _make_btn(color: CardData.SupplyColor, cost: int) -> Button:
	var btn := Button.new()
	btn.text = "%s ×%d" % [CardData.color_name(color), cost]
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", CardData.color_tint(color))
	btn.custom_minimum_size = Vector2(130, 46)
	btn.pressed.connect(func() -> void:
		_supply_chosen_fired = true
		supply_chosen.emit(color)
		hide()
	)
	return btn
