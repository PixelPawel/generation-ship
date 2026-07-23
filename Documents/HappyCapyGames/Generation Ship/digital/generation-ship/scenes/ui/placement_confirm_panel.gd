class_name PlacementConfirmPanel
extends Control

signal confirmed
signal cancelled

var _title: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 36)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(_title)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)

	var confirm_btn := Button.new()
	confirm_btn.text = tr("Confirm")
	confirm_btn.custom_minimum_size = Vector2(220, 64)
	confirm_btn.add_theme_font_size_override("font_size", 26)
	confirm_btn.pressed.connect(func() -> void:
		hide()
		confirmed.emit()
	)
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = tr("Cancel")
	cancel_btn.custom_minimum_size = Vector2(220, 64)
	cancel_btn.add_theme_font_size_override("font_size", 26)
	cancel_btn.pressed.connect(func() -> void:
		hide()
		cancelled.emit()
	)
	btn_row.add_child(cancel_btn)

func show_confirm(card_name: String, target_name: String) -> void:
	_title.text = (tr("Place %s on %s?") % [card_name, target_name]) if not target_name.is_empty() else (tr("Place %s here?") % card_name)
	show()
