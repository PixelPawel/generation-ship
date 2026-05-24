extends Control

signal payment_confirmed
signal payment_forfeited
signal recycle_requested

var _needed: int = 0
var _cost_color: CardData.SupplyColor = CardData.SupplyColor.DUST
var _supply_ui: Control = null
var _title_label: Label
var _status_label: Label
var _pay_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_title_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 17)
	vbox.add_child(_status_label)

	var hint := Label.new()
	hint.text = "Recycle hand cards or fuse supply to pay.\nThe supply UI on the left remains active."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	vbox.add_child(hint)

	var recycle_btn := Button.new()
	recycle_btn.text = "Recycle a Card"
	recycle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recycle_btn.add_theme_font_size_override("font_size", 16)
	recycle_btn.pressed.connect(func(): recycle_requested.emit())
	vbox.add_child(recycle_btn)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	var forfeit_btn := Button.new()
	forfeit_btn.text = "Forfeit"
	forfeit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forfeit_btn.add_theme_font_size_override("font_size", 16)
	forfeit_btn.pressed.connect(_on_forfeit)
	btn_row.add_child(forfeit_btn)

	_pay_btn = Button.new()
	_pay_btn.text = "Pay & Place"
	_pay_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pay_btn.add_theme_font_size_override("font_size", 16)
	_pay_btn.pressed.connect(_on_pay)
	btn_row.add_child(_pay_btn)

	visible = false

func show_payment(card_name: String, bid_amount: int, cost_color: CardData.SupplyColor, supply_ui: Control) -> void:
	_needed = bid_amount
	_cost_color = cost_color
	_supply_ui = supply_ui
	_title_label.text = "Pay for %s" % card_name
	refresh()
	show()

func refresh() -> void:
	if not _supply_ui:
		return
	var have: int = _supply_ui.get_supply(_cost_color)
	var color_name: String = CardData.SupplyColor.keys()[_cost_color]
	_status_label.text = "%s — Have: %d  /  Need: %d" % [color_name, have, _needed]
	_pay_btn.disabled = have < _needed

func _on_pay() -> void:
	hide()
	payment_confirmed.emit()

func _on_forfeit() -> void:
	hide()
	payment_forfeited.emit()
