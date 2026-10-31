extends Control
# Asked once, before the first score would go to the public leaderboard
# (LeaderboardManager.submit_score / ask_consent): post the scores under this
# name, or not. Settings can change the answer later. Nothing is uploaded
# before a yes (privacy policy, digital/legal/).
const PopupAnim = preload("res://scripts/popup_anim.gd")

signal answered(yes: bool, board_name: String)

const TEXT_COLOR: Color = Color(0.8, 0.85, 0.95)
const MUTED_COLOR: Color = Color(0.6, 0.65, 0.78)
const GOLD: Color = Color(1.0, 0.85, 0.4)
const NAME_MAX: int = 24   # the server keeps 24 characters

var _name_input: LineEdit = null

func _ready() -> void:
	_build_ui()
	visible = false

func open(current_name: String) -> void:
	_name_input.text = "" if current_name == "Player" else current_name
	PopupAnim.open(self)

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # needs an answer; no dimming, the game stays visible

	var panel: Control = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(20)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.custom_minimum_size = Vector2(640, 0)
	panel.add_child(vbox)

	var title: Label = Label.new()
	title.text = "PUBLIC LEADERBOARD"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	vbox.add_child(title)

	var body: Label = Label.new()
	body.text = "Post your scores to the public leaderboard? Everyone who plays Generation Ship will see the name below with your scores."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", TEXT_COLOR)
	vbox.add_child(body)

	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	vbox.add_child(name_row)
	var name_lbl: Label = Label.new()
	name_lbl.text = "Name"
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", GOLD)
	name_row.add_child(name_lbl)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Player"
	_name_input.max_length = NAME_MAX
	_name_input.add_theme_font_size_override("font_size", 22)
	_name_input.custom_minimum_size = Vector2(0, 52)
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.text_submitted.connect(func(_t: String) -> void: _answer(true))
	name_row.add_child(_name_input)

	var note: Label = Label.new()
	note.text = "Only the name, your scores and their breakdown are shown. You can change this any time in Settings."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", MUTED_COLOR)
	vbox.add_child(note)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons)
	var no_btn: Button = _make_button("Don't post")
	no_btn.pressed.connect(func() -> void: _answer(false))
	buttons.add_child(no_btn)
	var yes_btn: Button = _make_button("Post my scores")
	GameTheme.style_positive(yes_btn)
	yes_btn.pressed.connect(func() -> void: _answer(true))
	buttons.add_child(yes_btn)

	var policy_btn: Button = Button.new()
	policy_btn.text = "Privacy Policy"
	policy_btn.flat = true
	policy_btn.add_theme_font_size_override("font_size", 16)
	policy_btn.add_theme_color_override("font_color", MUTED_COLOR)
	policy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	policy_btn.pressed.connect(func() -> void: OS.shell_open(LeaderboardManager.privacy_url()))
	vbox.add_child(policy_btn)

	GameTheme.touchify(panel)

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 20)
	btn.custom_minimum_size = Vector2(0, 52)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameTheme.apply_to_button(btn)
	return btn

func _answer(yes: bool) -> void:
	var board_name: String = _name_input.text.strip_edges()
	PopupAnim.close(self)
	answered.emit(yes, board_name if not board_name.is_empty() else "Player")
