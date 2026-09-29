extends Control
# Top-100 global leaderboard popup. Data comes from LeaderboardManager
# (Steamworks leaderboard "TotalScore") — see that autoload for the upload/
# download plumbing and the async persona-name-resolution caveat.

var _rows_container: VBoxContainer = null
var _status_label: Label = null
var _scroll: ScrollContainer = null
var _row_by_steam_id: Dictionary = {}   # steam_id (int) -> Label (name cell), for late name patch-in
var _my_steam_id: int = 0

func _ready() -> void:
	_build_ui()
	visible = false
	LeaderboardManager.top_scores_ready.connect(_on_top_scores_ready)
	LeaderboardManager.top_scores_failed.connect(_on_top_scores_failed)
	LeaderboardManager.entry_name_resolved.connect(_on_entry_name_resolved)

func open() -> void:
	visible = true
	_my_steam_id = Steam.getSteamID() if SteamManager.is_initialized else 0
	_show_status(tr("Loading…"))
	LeaderboardManager.request_top_scores()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel: Control = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(12)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(620, 780)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.custom_minimum_size = Vector2(596, 0)
	panel.add_child(vbox)

	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)

	var title: Label = Label.new()
	title.text = tr("LEADERBOARD")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var close_btn: Button = _make_button("✕")
	close_btn.custom_minimum_size = Vector2(36, 0)
	close_btn.pressed.connect(func(): visible = false)
	title_row.add_child(close_btn)

	var sep: HSeparator = HSeparator.new()
	sep.modulate = Color(0.4, 0.4, 0.5, 0.5)
	vbox.add_child(sep)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)
	header.add_child(_header_cell(tr("#"), 44))
	header.add_child(_header_cell(tr("Player"), 0, true))
	header.add_child(_header_cell(tr("Score"), 90))

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 640)
	vbox.add_child(_scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 2)
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows_container)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.visible = false
	_rows_container.add_child(_status_label)

func _header_cell(text: String, min_width: float, expand: bool = false) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	if min_width > 0.0:
		lbl.custom_minimum_size = Vector2(min_width, 0)
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl

func _show_status(text: String) -> void:
	for child: Node in _rows_container.get_children():
		if child != _status_label:
			child.queue_free()
	_row_by_steam_id.clear()
	_status_label.text = text
	_status_label.visible = true

func _on_top_scores_failed() -> void:
	_show_status(tr("Couldn't reach Steam's leaderboard. Try again later."))

func _on_top_scores_ready(entries: Array[Dictionary]) -> void:
	for child: Node in _rows_container.get_children():
		if child != _status_label:
			child.queue_free()
	_row_by_steam_id.clear()
	if entries.is_empty():
		_show_status(tr("No scores yet — be the first!"))
		return
	_status_label.visible = false
	for entry: Dictionary in entries:
		_add_row(entry)

func _add_row(entry: Dictionary) -> void:
	var rank: int = int(entry.get("global_rank", 0))
	var score: int = int(entry.get("score", 0))
	var steam_id: int = int(entry.get("steam_id", 0))
	var is_me: bool = steam_id != 0 and steam_id == _my_steam_id

	var row_panel: PanelContainer = PanelContainer.new()
	if is_me:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = Color(1.0, 0.85, 0.2, 0.12)
		row_panel.add_theme_stylebox_override("panel", box)
	_rows_container.add_child(row_panel)

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	row_panel.add_child(outer)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	outer.add_child(row)

	var rank_color: Color = Color(0.85, 0.85, 0.9)
	if rank == 1:
		rank_color = Color(1.0, 0.85, 0.2)
	elif rank == 2:
		rank_color = Color(0.8, 0.85, 0.9)
	elif rank == 3:
		rank_color = Color(0.8, 0.55, 0.3)

	var rank_lbl: Label = Label.new()
	rank_lbl.text = str(rank)
	rank_lbl.add_theme_font_size_override("font_size", 15)
	rank_lbl.add_theme_color_override("font_color", rank_color)
	rank_lbl.custom_minimum_size = Vector2(44, 0)
	row.add_child(rank_lbl)

	var player_name: String = LeaderboardManager.resolve_name(steam_id) if steam_id != 0 else ""
	if player_name == "":
		player_name = tr("Player #%d") % (steam_id % 10000)
	if is_me:
		player_name = tr("%s (You)") % player_name

	var name_lbl: Label = Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0) if is_me else Color(0.85, 0.85, 0.9))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	row.add_child(name_lbl)
	if steam_id != 0:
		_row_by_steam_id[steam_id] = name_lbl

	var score_lbl: Label = Label.new()
	score_lbl.text = str(score)
	score_lbl.add_theme_font_size_override("font_size", 15)
	score_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(score_lbl)

	var arrow_lbl: Label = Label.new()
	arrow_lbl.text = "▶"
	arrow_lbl.add_theme_font_size_override("font_size", 13)
	arrow_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	arrow_lbl.custom_minimum_size = Vector2(20, 0)
	row.add_child(arrow_lbl)

	# A lambda captures locals by value — mutating a plain `var` inside it
	# does NOT persist to the next time this same Callable runs (confirmed:
	# a minimal repro toggling a captured bool across 3 calls printed
	# "true" all three times instead of true/false/true). Use a 1-element
	# Array as a mutable cell instead, so state actually survives between
	# clicks on this row.
	var state: Array = [null]  # [0] = the detail Control once built, else null
	row.gui_input.connect(func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			return
		if state[0] == null:
			var built: Control = _build_detail(entry)
			built.visible = false
			outer.add_child(built)
			state[0] = built
		var detail: Control = state[0]
		detail.visible = not detail.visible
		arrow_lbl.text = "▼" if detail.visible else "▶"
	)

func _build_detail(entry: Dictionary) -> Control:
	var score_lines: Array[Dictionary] = LeaderboardManager.decode_snapshot(entry)
	var box: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", style)

	if score_lines.is_empty():
		var lbl: Label = Label.new()
		lbl.text = tr("No score breakdown available for this game.")
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		box.add_child(lbl)
		return box

	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	box.add_child(list)
	for line: Dictionary in score_lines:
		list.add_child(_make_score_line_row(line))
	return box

func _make_score_line_row(line: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label_lbl: Label = Label.new()
	label_lbl.text = String(line.get("label", ""))
	label_lbl.add_theme_font_size_override("font_size", 13)
	label_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	label_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_lbl.clip_text = true
	row.add_child(label_lbl)

	var vp_lbl: Label = Label.new()
	vp_lbl.text = tr("%d VP") % int(line.get("vp", 0))
	vp_lbl.add_theme_font_size_override("font_size", 13)
	vp_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	vp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vp_lbl.custom_minimum_size = Vector2(50, 0)
	row.add_child(vp_lbl)
	return row

func _on_entry_name_resolved(steam_id: int, player_name: String) -> void:
	var lbl: Label = _row_by_steam_id.get(steam_id) as Label
	if not lbl:
		return
	lbl.text = tr("%s (You)") % player_name if steam_id == _my_steam_id else player_name

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 14)
	GameTheme.apply_to_button(btn)
	return btn
