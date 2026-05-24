class_name Scoreboard
extends Control

var _rows_container: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(24)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(480, 0)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Final Scores"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 8)
	vbox.add_child(_rows_container)

func show_scores(lines: Array[Dictionary], total: int) -> void:
	for child: Node in _rows_container.get_children():
		child.queue_free()

	for line: Dictionary in lines:
		var row := HBoxContainer.new()
		_rows_container.add_child(row)

		var name_label := Label.new()
		name_label.text = line.get("label", "")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(name_label)

		var vp_label := Label.new()
		vp_label.text = "%d VP" % int(line.get("vp", 0))
		vp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vp_label.add_theme_font_size_override("font_size", 18)
		vp_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
		row.add_child(vp_label)

	var sep := HSeparator.new()
	_rows_container.add_child(sep)

	var total_row := HBoxContainer.new()
	_rows_container.add_child(total_row)

	var total_name := Label.new()
	total_name.text = "TOTAL"
	total_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_name.add_theme_font_size_override("font_size", 22)
	total_name.add_theme_color_override("font_color", Color.WHITE)
	total_row.add_child(total_name)

	var total_vp := Label.new()
	total_vp.text = "%d VP" % total
	total_vp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_vp.add_theme_font_size_override("font_size", 22)
	total_vp.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	total_row.add_child(total_vp)

	var sep2 := HSeparator.new()
	_rows_container.add_child(sep2)

	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(0, 48)
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	GameTheme.apply_to_button(menu_btn)
	menu_btn.pressed.connect(func() -> void:
		SceneTransition.change_scene("res://scenes/main_menu/main_menu.tscn")
	)
	_rows_container.add_child(menu_btn)

	show()
