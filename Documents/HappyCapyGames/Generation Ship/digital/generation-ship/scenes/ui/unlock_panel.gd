extends Control
# Android only: Versus or Co-op tapped while still locked (FullGame). Buy the
# full game through Google Play, or enter a code. Once unlocked it closes and
# emits `unlocked`, so the menu carries on into the mode that was tapped.
const PopupAnim = preload("res://scripts/popup_anim.gd")

signal unlocked

const TEXT_COLOR: Color = Color(0.8, 0.85, 0.95)
const GOLD: Color = Color(1.0, 0.85, 0.4)
const ERROR_COLOR: Color = Color(1.0, 0.55, 0.5)
const MUTED_COLOR: Color = Color(0.6, 0.65, 0.78)

var _buy_btn: Button = null
var _code_input: LineEdit = null
var _redeem_btn: Button = null
var _status: Label = null
var _games_note: Label = null
var _games_btn: Button = null

func _ready() -> void:
	_build_ui()
	visible = false
	FullGame.changed.connect(_on_changed)
	FullGame.purchase_result.connect(_on_result)
	FullGame.redeem_result.connect(_on_result)
	FullGame.games_changed.connect(_refresh_games)

func open() -> void:
	_status.text = ""
	_code_input.text = ""
	_set_busy(false)
	_refresh_price()
	_refresh_games()
	PopupAnim.open(self)

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

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

	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)
	var title: Label = Label.new()
	title.text = tr("UNLOCK THE FULL GAME")
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn: Button = _make_button("✕")
	close_btn.custom_minimum_size = Vector2(44, 44)
	close_btn.pressed.connect(func() -> void: PopupAnim.close(self))
	title_row.add_child(close_btn)

	var body: Label = Label.new()
	body.text = tr("Versus and Co-op open with a one-time purchase: online games, games against bots and Generation Fleet. The Tutorial, Rule Book, Collection and Scan Tableau stay free.")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 20)
	body.add_theme_color_override("font_color", TEXT_COLOR)
	vbox.add_child(body)

	_buy_btn = _make_button("")
	_buy_btn.add_theme_font_size_override("font_size", 26)
	_buy_btn.custom_minimum_size = Vector2(0, 64)
	GameTheme.style_positive(_buy_btn)
	_buy_btn.pressed.connect(func() -> void:
		_set_busy(true)
		_status.text = ""
		FullGame.buy())
	vbox.add_child(_buy_btn)

	var code_head: Label = Label.new()
	code_head.text = tr("Have a code?")
	code_head.add_theme_font_size_override("font_size", 20)
	code_head.add_theme_color_override("font_color", GOLD)
	vbox.add_child(code_head)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vbox.add_child(row)
	_code_input = LineEdit.new()
	_code_input.placeholder_text = "XXXX-XXXX-XXXX"
	_code_input.max_length = 40
	_code_input.add_theme_font_size_override("font_size", 24)
	_code_input.custom_minimum_size = Vector2(0, 52)
	_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_input.text_submitted.connect(func(_t: String) -> void: _redeem())
	row.add_child(_code_input)
	_redeem_btn = _make_button(tr("Redeem"))
	_redeem_btn.custom_minimum_size = Vector2(160, 52)
	_redeem_btn.pressed.connect(_redeem)
	row.add_child(_redeem_btn)

	# Google Play Games: a code then follows the account to other phones
	var games_row: HBoxContainer = HBoxContainer.new()
	games_row.add_theme_constant_override("separation", 12)
	vbox.add_child(games_row)
	_games_note = Label.new()
	_games_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_games_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_games_note.add_theme_font_size_override("font_size", 16)
	_games_note.add_theme_color_override("font_color", MUTED_COLOR)
	games_row.add_child(_games_note)
	_games_btn = _make_button(tr("Sign in with Google Play Games"))
	_games_btn.add_theme_font_size_override("font_size", 16)
	_games_btn.pressed.connect(func() -> void: FullGame.sign_in_games())
	games_row.add_child(_games_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_status)

func _make_button(label: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 20)
	btn.custom_minimum_size = Vector2(0, 48)
	GameTheme.apply_to_button(btn)
	return btn

func _redeem() -> void:
	if _code_input.text.strip_edges().is_empty():
		return
	_set_busy(true)
	_status.add_theme_color_override("font_color", TEXT_COLOR)
	_status.text = tr("Checking…")
	FullGame.redeem(_code_input.text)

func _refresh_price() -> void:
	_buy_btn.text = tr("Unlock for %s") % FullGame.price_text if not FullGame.price_text.is_empty() else tr("Unlock")

func _refresh_games() -> void:
	var row: Control = _games_note.get_parent() as Control
	row.visible = FullGame.games_available()
	if FullGame.games_signed_in():
		_games_note.text = tr("Your codes are linked to your Google Play Games account %s.") % FullGame.games_name
		_games_btn.visible = false
	else:
		_games_note.text = tr("Sign in to Google Play Games and a code unlocks the game on every phone with that account.")
		_games_btn.visible = true

func _set_busy(busy: bool) -> void:
	_buy_btn.disabled = busy
	_redeem_btn.disabled = busy

func _on_changed() -> void:
	_refresh_price()
	if visible and FullGame.unlocked:
		PopupAnim.close(self)
		unlocked.emit()

func _on_result(_ok: bool, message: String) -> void:
	_set_busy(false)
	_status.add_theme_color_override("font_color", ERROR_COLOR)
	_status.text = message   # success closes the panel through `changed`; cancel has no message
