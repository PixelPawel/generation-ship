extends Control

# Text chat overlay. Unlike the other popups in this folder it's never fully
# hidden — a small pill toggle stays anchored in the corner at all times
# (collapsed), and the log + input box appear above it when opened. Works in
# both the lobby (added by lobby.gd) and in-match (added by main.gd) since
# both set multiplayer.multiplayer_peer before this could plausibly be used;
# ChatManager itself is the thing gating multiplayer-only sending.
#
# Anchored bottom-RIGHT specifically — supply_ui.gd's supply_panel already
# owns the bottom-left corner (offset_left 16, offset_bottom -16, ~230x280)
# during a match, and this panel is shared between the lobby and main scenes
# so it needs one placement that's clear of both.

const _MAX_LOG_LINES: int = 300
const _PEER_COLORS: Array[Color] = [
	Color(0.55, 0.85, 1.0),
	Color(1.0, 0.75, 0.45),
	Color(0.7, 1.0, 0.6),
	Color(1.0, 0.6, 0.85),
	Color(0.85, 0.7, 1.0),
]

var _expanded: bool = false
var _unread: int = 0

var _toggle_btn: Button = null
var _badge: Label = null
var _mic_indicator: Label = null
var _expanded_panel: Control = null
var _log: RichTextLabel = null
var _input_field: LineEdit = null
var _peer_color_index: Dictionary = {}   # peer_id -> index into _PEER_COLORS

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 0)
	_build_ui()
	ChatManager.message_received.connect(_on_message_received)
	for entry: Dictionary in ChatManager.history:
		_append_line(entry["peer_id"], entry["name"], entry["text"])
	_set_expanded(false)
	VoiceManager.local_recording_changed.connect(_on_local_recording_changed)

func _build_ui() -> void:
	# — Collapsed pill —
	_toggle_btn = Button.new()
	_toggle_btn.text = tr("💬 Chat")
	_toggle_btn.add_theme_font_size_override("font_size", 14)
	_toggle_btn.custom_minimum_size = Vector2(110, 36)
	_toggle_btn.position = Vector2(-122, -48)
	_toggle_btn.anchor_left = 1.0
	_toggle_btn.anchor_right = 1.0
	_toggle_btn.anchor_top = 1.0
	_toggle_btn.anchor_bottom = 1.0
	_toggle_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	GameTheme.apply_to_button(_toggle_btn)
	_toggle_btn.pressed.connect(func() -> void: _set_expanded(not _expanded))
	add_child(_toggle_btn)

	_badge = Label.new()
	_badge.text = ""
	_badge.add_theme_font_size_override("font_size", 12)
	_badge.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	_badge.position = Vector2(-38, -60)
	_badge.anchor_left = 1.0
	_badge.anchor_right = 1.0
	_badge.anchor_top = 1.0
	_badge.anchor_bottom = 1.0
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)

	# — Push-to-talk indicator — shows the bound key and lights up while
	# actively transmitting, since holding the key is otherwise the only
	# feedback a player gets that voice capture is doing anything at all.
	_mic_indicator = Label.new()
	_mic_indicator.text = _mic_label_text()
	_mic_indicator.add_theme_font_size_override("font_size", 14)
	_mic_indicator.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	_mic_indicator.position = Vector2(-232, -48)
	_mic_indicator.size = Vector2(100, 36)
	_mic_indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mic_indicator.anchor_left = 1.0
	_mic_indicator.anchor_right = 1.0
	_mic_indicator.anchor_top = 1.0
	_mic_indicator.anchor_bottom = 1.0
	_mic_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mic_indicator)

	# — Expanded log + input —
	_expanded_panel = load("res://scenes/ui/scifi_panel.gd").new()
	_expanded_panel.position = Vector2(-372, -420)
	_expanded_panel.anchor_left = 1.0
	_expanded_panel.anchor_right = 1.0
	_expanded_panel.anchor_top = 1.0
	_expanded_panel.anchor_bottom = 1.0
	_expanded_panel.custom_minimum_size = Vector2(360, 360)
	_expanded_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_expanded_panel)
	_expanded_panel.set_content_margin(10)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.custom_minimum_size = Vector2(340, 340)
	_expanded_panel.add_child(vbox)

	var title_row: HBoxContainer = HBoxContainer.new()
	vbox.add_child(title_row)
	var title: Label = Label.new()
	title.text = tr("CHAT")
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn: Button = Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.custom_minimum_size = Vector2(28, 0)
	GameTheme.apply_to_button(close_btn)
	close_btn.pressed.connect(func() -> void: _set_expanded(false))
	title_row.add_child(close_btn)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.fit_content = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 14)
	vbox.add_child(_log)

	var input_row: HBoxContainer = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(input_row)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = tr("Message…")
	_input_field.add_theme_font_size_override("font_size", 14)
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.text_submitted.connect(_on_text_submitted)
	input_row.add_child(_input_field)

	var send_btn: Button = Button.new()
	send_btn.text = tr("Send")
	send_btn.add_theme_font_size_override("font_size", 13)
	send_btn.custom_minimum_size = Vector2(60, 0)
	GameTheme.apply_to_button(send_btn)
	send_btn.pressed.connect(func() -> void: _on_text_submitted(_input_field.text))
	input_row.add_child(send_btn)

func _set_expanded(value: bool) -> void:
	_expanded = value
	_expanded_panel.visible = value
	if value:
		_unread = 0
		_update_badge()
		_input_field.grab_focus()
	else:
		if _input_field.has_focus():
			_input_field.release_focus()

func _on_text_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	ChatManager.send_message(text)
	_input_field.text = ""
	_input_field.grab_focus()

func _on_message_received(peer_id: int, player_name: String, text: String) -> void:
	_append_line(peer_id, player_name, text)
	if not _expanded:
		_unread += 1
		_update_badge()

# Both name and text are player-typed and land in a bbcode_enabled label —
# escape "[" to the literal-bracket tag so a chat message can't smuggle in
# BBCode ([img], [url], nested [color], etc.) instead of just displaying as
# text.
func _bbcode_safe(s: String) -> String:
	return s.replace("[", "[lb]")

func _append_line(peer_id: int, player_name: String, text: String) -> void:
	var color: Color = _color_for_peer(peer_id)
	_log.append_text("[color=#%s][b]%s:[/b][/color] %s\n" % [color.to_html(false), _bbcode_safe(player_name), _bbcode_safe(text)])
	if _log.get_line_count() > _MAX_LOG_LINES:
		_log.clear()
		for entry: Dictionary in ChatManager.history.slice(-_MAX_LOG_LINES):
			var c: Color = _color_for_peer(entry["peer_id"])
			_log.append_text("[color=#%s][b]%s:[/b][/color] %s\n" % [c.to_html(false), _bbcode_safe(String(entry["name"])), _bbcode_safe(String(entry["text"]))])

func _color_for_peer(peer_id: int) -> Color:
	if not _peer_color_index.has(peer_id):
		_peer_color_index[peer_id] = _peer_color_index.size() % _PEER_COLORS.size()
	return _PEER_COLORS[_peer_color_index[peer_id]]

func _update_badge() -> void:
	_badge.text = str(_unread) if _unread > 0 else ""

func _mic_label_text() -> String:
	var key: int = KeybindManager.get_primary("voice_ptt")
	var key_name: String = OS.get_keycode_string(key) if key != 0 else "?"
	return tr("🎤 Hold %s") % key_name

# Push-to-talk hint only where voice actually works (not in online relay
# rooms — see VoiceManager.is_available()). Checked per frame since the
# multiplayer peer can change after this panel is built.
func _process(_delta: float) -> void:
	if _mic_indicator:
		_mic_indicator.visible = VoiceManager.is_available()

func _on_local_recording_changed(recording: bool) -> void:
	_mic_indicator.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.4) if recording else Color(0.55, 0.6, 0.7))

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_chat") and not _expanded:
		_set_expanded(true)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _expanded:
		_set_expanded(false)
		get_viewport().set_input_as_handled()
