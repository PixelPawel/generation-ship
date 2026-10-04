extends Control
const PopupAnim = preload("res://scripts/popup_anim.gd")
# Top-100 global leaderboard popup. Data comes from LeaderboardManager (our
# own API server, shared by Steam and Android) — see that autoload.

var _rows_container: VBoxContainer = null
var _status_label: Label = null
var _scroll: ScrollContainer = null
# Which scores to show: played games, scanned ships (Scan Tableau) or both.
var _source: String = "all"
var _filter_buttons: Dictionary = {}          # source -> Button
const FILTERS: Array[Array] = [   # [LeaderboardManager.SOURCE_*, label]
	["all", "All"],
	["play", "Real Play"],
	["scan", "Scan Tableau"],
]
const SCAN_TAG_COLOR: Color = Color(0.4, 0.85, 1.0)
# The look of the main menu's Leaderboard tile (tools/menu_leaderboard_tile.py).
const TITLE_COLOR: Color = Color(0.92, 0.97, 1.0)
const CYAN: Color = Color(0.35, 0.78, 1.0)
const GOLD: Color = Color(1.0, 0.84, 0.31)
const SILVER: Color = Color(0.8, 0.84, 0.9)
const BRONZE: Color = Color(0.8, 0.55, 0.31)
const TEXT: Color = Color(0.84, 0.88, 0.94)
const DIM: Color = Color(0.47, 0.55, 0.67)
const STAR_COLOR: Color = Color(1.0, 0.82, 0.24)
const PLATE_A: Color = Color(0.086, 0.149, 0.282)
const PLATE_B: Color = Color(0.063, 0.11, 0.22)
const ROW_FONT: int = 18
const BADGE: float = 34.0

func _ready() -> void:
	_build_ui()
	visible = false
	LeaderboardManager.top_scores_ready.connect(_on_top_scores_ready)
	LeaderboardManager.top_scores_failed.connect(_on_top_scores_failed)

func open() -> void:
	PopupAnim.open(self)
	_show_status(tr("Loading…"))
	LeaderboardManager.request_top_scores(_source)

func _set_source(source: String) -> void:
	_source = source
	for s: String in _filter_buttons:
		(_filter_buttons[s] as Button).button_pressed = s == source
	_show_status(tr("Loading…"))
	LeaderboardManager.request_top_scores(_source)

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
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_color_override("font_shadow_color", Color(CYAN.r, CYAN.g, CYAN.b, 0.55))
	title.add_theme_constant_override("shadow_outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var close_btn: Button = _make_button("✕")
	close_btn.custom_minimum_size = Vector2(36, 0)
	close_btn.pressed.connect(func() -> void: PopupAnim.close(self))
	title_row.add_child(close_btn)
	# phones: a proper touch target, like the Collection's and Rule Book's
	if GameTheme.is_touch():
		close_btn.add_theme_font_size_override("font_size", 32)
		GameTheme.touchify(close_btn)

	var sep: ColorRect = ColorRect.new()
	sep.color = CYAN
	sep.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(sep)

	var filter_row: HBoxContainer = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	vbox.add_child(filter_row)
	for f: Array in FILTERS:
		var btn: Button = _make_button(tr(f[1]))
		btn.toggle_mode = true
		btn.button_pressed = f[0] == _source
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_set_source.bind(f[0]))
		filter_row.add_child(btn)
		_filter_buttons[f[0]] = btn

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
	_rows_container.add_theme_constant_override("separation", 6)
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
	_status_label.text = text
	_status_label.visible = true

func _on_top_scores_failed() -> void:
	_show_status(tr("Couldn't reach the leaderboard. Try again later."))

func _on_top_scores_ready(entries: Array[Dictionary]) -> void:
	for child: Node in _rows_container.get_children():
		if child != _status_label:
			child.queue_free()
	if entries.is_empty():
		_show_status(tr("No scores yet — be the first!"))
		return
	_status_label.visible = false
	var me_listed: bool = false
	for entry: Dictionary in entries:
		_add_row(entry)
		me_listed = me_listed or bool(entry.get("me", false))
	# Outside the top 100: still show where the player's own best stands.
	var mine: Dictionary = LeaderboardManager.my_best
	if not me_listed and not mine.is_empty():
		_add_row({rank = int(mine.get("rank", 0)), score = int(mine.get("score", 0)),
				name = LeaderboardManager.player_name(), me = true, source = str(mine.get("source", ""))})

func _add_row(entry: Dictionary) -> void:
	var rank: int = int(entry.get("rank", 0))
	var score: int = int(entry.get("score", 0))
	var is_me: bool = bool(entry.get("me", false))

	var medal: Color = _medal_color(rank)

	# a rounded plate per row (alternating), gold outline for first place, cyan for you
	var row_panel: PanelContainer = PanelContainer.new()
	var plate: StyleBoxFlat = StyleBoxFlat.new()
	plate.bg_color = PLATE_A if rank % 2 == 1 else PLATE_B
	plate.set_corner_radius_all(10)
	plate.content_margin_left = 10.0
	plate.content_margin_right = 10.0
	plate.content_margin_top = 6.0
	plate.content_margin_bottom = 6.0
	if rank == 1 or is_me:
		plate.border_color = GOLD if rank == 1 else CYAN
		plate.set_border_width_all(2)
	row_panel.add_theme_stylebox_override("panel", plate)
	_rows_container.add_child(row_panel)

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	row_panel.add_child(outer)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	outer.add_child(row)

	row.add_child(_rank_badge(rank, medal))

	var player_name: String = str(entry.get("name", ""))
	if player_name.is_empty():
		player_name = tr("Player")
	if is_me:
		player_name = tr("%s (You)") % player_name

	var name_lbl: Label = Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", ROW_FONT)
	name_lbl.add_theme_color_override("font_color", TEXT if rank <= 3 or is_me else DIM)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	row.add_child(name_lbl)

	# a ship read from a photo, not a game played in the app
	if str(entry.get("source", "")) == LeaderboardManager.SOURCE_SCAN:
		var tag: Label = Label.new()
		tag.text = tr("Scan")
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color", SCAN_TAG_COLOR)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.tooltip_text = tr("Scan Tableau")
		tag.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(tag)

	var score_lbl: Label = Label.new()
	score_lbl.text = str(score)
	score_lbl.add_theme_font_size_override("font_size", ROW_FONT)
	score_lbl.add_theme_color_override("font_color", medal if rank <= 3 else TEXT)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_lbl.custom_minimum_size = Vector2(70, 0)
	row.add_child(score_lbl)

	var star_lbl: Label = Label.new()
	star_lbl.text = "★"
	star_lbl.add_theme_font_size_override("font_size", ROW_FONT + 2)
	star_lbl.add_theme_color_override("font_color", STAR_COLOR)
	star_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(star_lbl)

	var arrow_lbl: Label = Label.new()
	arrow_lbl.text = "▶"
	arrow_lbl.add_theme_font_size_override("font_size", 13)
	arrow_lbl.add_theme_color_override("font_color", DIM)
	arrow_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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

static func _medal_color(rank: int) -> Color:
	match rank:
		1:
			return GOLD
		2:
			return SILVER
		3:
			return BRONZE
	return DIM

# Ranks 1-3: a medal-coloured disc with a dark number; the rest: just the number.
static func _rank_badge(rank: int, medal: Color) -> Control:
	var badge: PanelContainer = PanelContainer.new()
	badge.custom_minimum_size = Vector2(BADGE, BADGE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var disc: StyleBoxFlat = StyleBoxFlat.new()
	disc.bg_color = medal if rank <= 3 else Color(0, 0, 0, 0)
	disc.set_corner_radius_all(int(BADGE / 2.0))
	badge.add_theme_stylebox_override("panel", disc)
	var num: Label = Label.new()
	num.text = str(rank)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", ROW_FONT)
	num.add_theme_color_override("font_color", Color(0.08, 0.1, 0.16) if rank <= 3 else DIM)
	badge.add_child(num)
	return badge

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

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		PopupAnim.close(self)
		get_viewport().set_input_as_handled()

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 14)
	GameTheme.apply_to_button(btn)
	return btn
