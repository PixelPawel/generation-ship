class_name Scoreboard
extends Control

var _rows_container: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(24)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Final Scores"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 8)
	vbox.add_child(_rows_container)

# Solo / single-player: flat expanded list
func show_scores(lines: Array[Dictionary], total: int) -> void:
	for child: Node in _rows_container.get_children():
		child.queue_free()

	for line: Dictionary in lines:
		var row := HBoxContainer.new()
		_rows_container.add_child(row)

		var name_label := Label.new()
		name_label.text = line.get("label", "")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(name_label)

		var vp_label := Label.new()
		vp_label.text = "%d VP" % int(line.get("vp", 0))
		vp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vp_label.add_theme_font_size_override("font_size", 22)
		vp_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
		row.add_child(vp_label)

	_add_total_and_menu(total)
	show()

# Multiplayer: one collapsible section per player, sorted by score
func show_multiplayer_scores(players: Array[Dictionary]) -> void:
	for child: Node in _rows_container.get_children():
		child.queue_free()

	for i: int in players.size():
		var player: Dictionary = players[i]
		var player_name: String = player.get("name", "Player")
		var player_total: int = player.get("total", 0)
		var player_lines: Array = player.get("lines", [])
		var is_winner: bool = i == 0

		_add_player_section(player_name, player_total, player_lines, is_winner, i == 0)

	_add_total_and_menu(-1)
	show()

func _add_player_section(player_name: String, total: int, lines: Array, is_winner: bool, start_expanded: bool) -> void:
	# Collapsible container
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 2)
	_rows_container.add_child(section)

	# Header row — acts as expand/collapse toggle
	var header := Button.new()
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.custom_minimum_size = Vector2(0, 40)
	section.add_child(header)

	var header_hbox := HBoxContainer.new()
	header_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_theme_constant_override("separation", 8)
	header.add_child(header_hbox)

	var arrow_lbl := Label.new()
	arrow_lbl.text = "▼" if start_expanded else "▶"
	arrow_lbl.add_theme_font_size_override("font_size", 17)
	arrow_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	arrow_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(arrow_lbl)

	var crown_lbl := Label.new()
	crown_lbl.text = "★ " if is_winner else ""
	crown_lbl.add_theme_font_size_override("font_size", 22)
	crown_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	crown_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(crown_lbl)

	var name_lbl := Label.new()
	name_lbl.text = player_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55) if is_winner else Color.WHITE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(name_lbl)

	var total_lbl := Label.new()
	total_lbl.text = "%d VP" % total
	total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_lbl.add_theme_font_size_override("font_size", 24)
	total_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3) if is_winner else Color(0.9, 0.85, 0.4))
	total_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hbox.add_child(total_lbl)

	# Detail rows — indented
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 4)
	detail_box.visible = start_expanded
	section.add_child(detail_box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	detail_box.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)
	margin.add_child(inner)

	if lines.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No score details available"
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		inner.add_child(empty_lbl)
	else:
		for line: Variant in lines:
			var ld: Dictionary = line as Dictionary
			var row := HBoxContainer.new()
			inner.add_child(row)

			var line_lbl := Label.new()
			line_lbl.text = ld.get("label", "")
			line_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line_lbl.add_theme_font_size_override("font_size", 18)
			line_lbl.add_theme_color_override("font_color", Color(0.82, 0.82, 0.9))
			row.add_child(line_lbl)

			var vp_lbl := Label.new()
			vp_lbl.text = "%d VP" % int(ld.get("vp", 0))
			vp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			vp_lbl.add_theme_font_size_override("font_size", 18)
			vp_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
			row.add_child(vp_lbl)

	header.pressed.connect(func() -> void:
		var expanded: bool = not detail_box.visible
		detail_box.visible = expanded
		arrow_lbl.text = "▼" if expanded else "▶"
	)

	var sep := HSeparator.new()
	sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	_rows_container.add_child(sep)

func _add_total_and_menu(total: int) -> void:
	if total >= 0:
		var sep := HSeparator.new()
		_rows_container.add_child(sep)

		var total_row := HBoxContainer.new()
		_rows_container.add_child(total_row)

		var total_name := Label.new()
		total_name.text = "TOTAL"
		total_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		total_name.add_theme_font_size_override("font_size", 26)
		total_name.add_theme_color_override("font_color", Color.WHITE)
		total_row.add_child(total_name)

		var total_vp := Label.new()
		total_vp.text = "%d VP" % total
		total_vp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		total_vp.add_theme_font_size_override("font_size", 26)
		total_vp.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		total_row.add_child(total_vp)

	var sep2 := HSeparator.new()
	_rows_container.add_child(sep2)

	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(0, 52)
	menu_btn.add_theme_font_size_override("font_size", 24)
	menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	GameTheme.apply_to_button(menu_btn)
	menu_btn.pressed.connect(func() -> void:
		SceneTransition.change_scene("res://scenes/main_menu/main_menu.tscn")
	)
	_rows_container.add_child(menu_btn)
