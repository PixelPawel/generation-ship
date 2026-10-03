extends Control
const Haptics = preload("res://scripts/haptics.gd")

const SETTINGS_PATH: String = "user://settings.cfg"
const _BTN_HOVER_IN_SEC: float = 0.15
const _BTN_HOVER_OUT_SEC: float = 0.22
const _SLIDE_DURATION: float = 0.5

var _btn_tweens: Dictionary = {}
var _music_player: AudioStreamPlayer = null
var _manual: Control = null
var _collection: Control = null
var _leaderboard: Control = null
var _photo_scan: Control = null

const GAMEFOUND_LOGO: String = "res://assets/ui/gamefound_logo_white.png"
const GAMEFOUND_URL: String = "https://gamefound.com/en/projects/happy-capy-games/generation-ship#/section/project-story"
const DISCORD_LOGO: String = "res://assets/ui/Discord-Logo-Blurple.png"
const DISCORD_URL: String = "https://discord.gg/AGJvpkrpFX"
const _LINK_MARGIN: float = 28.0

var _link_buttons: Array[TextureButton] = []

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]
const FULLSCREEN_IDX: int = 5

func _ready() -> void:
	theme = GameTheme.get_theme()
	_apply_saved_settings()
	_setup_video()
	_setup_music()

	var vp: Vector2 = get_viewport_rect().size
	$Panels.position = Vector2.ZERO
	$Panels/MainView.size = vp
	$Panels/LobbyView.position = Vector2(0.0, vp.y)
	$Panels/LobbyView.size = vp
	$Panels/LobbyView/StagingPanel.position = Vector2(0.0, vp.y)
	$Panels/LobbyView/StagingPanel.size = vp

	for btn: Node in $Panels/MainView/VBox.get_children():
		(btn as CanvasItem).modulate.a = 0.0
	_manual = load("res://scenes/ui/manual_popup.gd").new()
	add_child(_manual)
	_collection = load("res://scenes/ui/collection_popup.gd").new()
	add_child(_collection)
	_leaderboard = load("res://scenes/ui/leaderboard_popup.gd").new()
	add_child(_leaderboard)
	_photo_scan = load("res://scenes/photo_scan/photo_scan.gd").new()
	add_child(_photo_scan)
	call_deferred("_start_animations")

	var ver_lbl := Label.new()
	ver_lbl.text = "v" + ProjectSettings.get_setting("application/config/version")
	ver_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver_lbl.position = Vector2(-60.0, -28.0)
	ver_lbl.add_theme_font_size_override("font_size", 13)
	ver_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.45))
	ver_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver_lbl)

	_add_link_button(GAMEFOUND_LOGO, GAMEFOUND_URL, 44.0, false)
	_add_link_button(DISCORD_LOGO, DISCORD_URL, 34.0, true)

# Logo button pinned to a bottom corner of MainView (so it slides away with the
# menu). Height drives size; width follows the logo's aspect ratio.
func _add_link_button(tex_path: String, url: String, height: float, right: bool) -> void:
	var tex: Texture2D = load(tex_path) as Texture2D
	if tex == null:
		return
	var btn := TextureButton.new()
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = url
	btn.modulate.a = 0.0
	btn.pressed.connect(func() -> void: OS.shell_open(url))
	$Panels/MainView.add_child(btn)
	var w: float = height * float(tex.get_width()) / float(tex.get_height())
	var x_anchor: float = 1.0 if right else 0.0
	btn.anchor_left = x_anchor
	btn.anchor_right = x_anchor
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	# Right-side button sits a bit higher to clear the version label.
	var bottom: float = -_LINK_MARGIN - (16.0 if right else 0.0)
	# Phones: further in from the side, clear of the rounded screen corners.
	var side: float = GameTheme.TOUCH_CORNER_MARGIN if GameTheme.is_touch() else _LINK_MARGIN
	btn.offset_left = -side - w if right else side
	btn.offset_right = -side if right else side + w
	btn.offset_top = bottom - height
	btn.offset_bottom = bottom
	_link_buttons.append(btn)

func _setup_video() -> void:
	const VIDEO_PATH: String = "res://assets/video/flythrough.mp4"
	if not FileAccess.file_exists(VIDEO_PATH):
		return
	var vp := VideoPlayback.new()
	vp.enable_audio = false
	vp.loop = true
	vp.enable_auto_play = true
	vp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vp)
	move_child(vp, $Background.get_index())
	vp.video_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	vp.set_video_path(VIDEO_PATH)
	$Background.visible = false

func _setup_music() -> void:
	var stream: AudioStreamWAV = load("res://assets/music/ambience.wav") as AudioStreamWAV
	if not stream:
		return
	# Don't rely on the .import file's baked loop_mode/loop_end — Godot's WAV
	# importer has been observed to bake loop_end as 0 regardless of the
	# "edit/loop_end" import setting (confirmed by forcing a clean reimport
	# with an explicit frame count and it still coming back 0). A loop_end
	# of 0 makes the player loop back to the start after a single sample,
	# which sounds like no music is playing at all. Set both explicitly
	# from the stream's own real length instead of trusting the import.
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	if stream.loop_end <= stream.loop_begin:
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = stream
	_music_player.bus = &"Music"
	_music_player.volume_db = -80.0
	_music_player.finished.connect(_music_player.play)
	add_child(_music_player)
	_music_player.play()
	var tw: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_music_player, "volume_db", 0.0, 2.0)

func _start_animations() -> void:
	_animate_logo()
	_animate_buttons()
	for btn: Node in $Panels/MainView/VBox.get_children():
		_setup_button_hover(btn as Button)
	for btn: TextureButton in _link_buttons:
		_setup_button_hover(btn)
		var tw: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.2)
		tw.tween_property(btn, "modulate:a", 1.0, 0.5)

func _animate_logo() -> void:
	const LOGO_PATH: String = "res://assets/video/logo.webm"
	var title: TextureRect = $Panels/MainView/Title
	if not FileAccess.file_exists(LOGO_PATH):
		title.modulate.a = 1.0
		return
	title.hide()
	var logo_vp: VideoPlayback = VideoPlayback.new()
	logo_vp.enable_audio = false
	logo_vp.loop = true
	logo_vp.enable_auto_play = true
	title.get_parent().add_child(logo_vp)
	logo_vp.anchor_left = 0.0
	logo_vp.anchor_top = 0.0
	logo_vp.anchor_right = 1.0
	logo_vp.anchor_bottom = 0.0
	logo_vp.offset_top = 48.0
	logo_vp.offset_bottom = 408.0
	logo_vp.video_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_vp.set_video_path(LOGO_PATH)

func _animate_buttons() -> void:
	var buttons: Array[Node] = $Panels/MainView/VBox.get_children()
	for i: int in buttons.size():
		var btn: Control = buttons[i] as Control
		var tw: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.35 + float(i) * 0.15)
		tw.tween_property(btn, "modulate:a", 1.0, 0.40)

func _setup_button_hover(btn: BaseButton) -> void:
	btn.pivot_offset = btn.size / 2.0
	btn.mouse_entered.connect(func() -> void: _on_btn_hover_enter(btn))
	btn.mouse_exited.connect(func() -> void: _on_btn_hover_exit(btn))

func _on_btn_hover_enter(btn: BaseButton) -> void:
	var tw: Tween = _btn_tweens.get(btn) as Tween
	if tw and tw.is_valid():
		tw.kill()
	tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(btn, "scale", Vector2(1.06, 1.06), _BTN_HOVER_IN_SEC)
	tw.parallel().tween_property(btn, "modulate", Color(1.4, 1.4, 1.4, 1.0), _BTN_HOVER_IN_SEC)
	_btn_tweens[btn] = tw

func _on_btn_hover_exit(btn: BaseButton) -> void:
	var tw: Tween = _btn_tweens.get(btn) as Tween
	if tw and tw.is_valid():
		tw.kill()
	tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), _BTN_HOVER_OUT_SEC)
	tw.parallel().tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), _BTN_HOVER_OUT_SEC)
	_btn_tweens[btn] = tw

func _on_rule_book_pressed() -> void:
	_manual.open()

func _on_collection_pressed() -> void:
	_collection.open()

func _on_leaderboard_pressed() -> void:
	_leaderboard.open()

func _on_settings_btn_pressed() -> void:
	$PauseMenu.open_settings()

func _on_multiplayer_pressed() -> void:
	_slide_to_lobby()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_scan_tableau_pressed() -> void:
	_photo_scan.open()

func _on_lobby_back_requested() -> void:
	_slide_to_main()

func _on_lobby_staging_requested() -> void:
	_slide_to_staging()

func _on_lobby_view_requested() -> void:
	_slide_to_lobby()

func _slide_to_main() -> void:
	var tw: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property($Panels, "position:y", 0.0, _SLIDE_DURATION)

func _slide_to_lobby() -> void:
	var vp_h: float = get_viewport_rect().size.y
	var tw: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property($Panels, "position:y", -vp_h, _SLIDE_DURATION)

func _slide_to_staging() -> void:
	var vp_h: float = get_viewport_rect().size.y
	var tw: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property($Panels, "position:y", -vp_h * 2.0, _SLIDE_DURATION)

func _apply_saved_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return

	# Window mode/size/monitor are desktop-only. On a phone, WINDOWED means
	# "show the system bars", so re-applying the saved (default 1920x1080
	# windowed) resolution kicked the game out of the export's immersive
	# fullscreen as soon as any setting had ever been saved.
	if not OS.has_feature("mobile"):
		var res_idx: int = clampi(int(cfg.get_value("display", "resolution_index", 2)), 0, FULLSCREEN_IDX)
		if res_idx == FULLSCREEN_IDX:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(RESOLUTIONS[res_idx])

		var screen_count: int = DisplayServer.get_screen_count()
		var mon_idx: int = clampi(int(cfg.get_value("display", "monitor_index", 0)), 0, screen_count - 1)
		DisplayServer.window_set_current_screen(mon_idx)
		var screen_pos: Vector2i = DisplayServer.screen_get_position(mon_idx)
		var screen_size: Vector2i = DisplayServer.screen_get_size(mon_idx)
		var win_size: Vector2i = DisplayServer.window_get_size()
		DisplayServer.window_set_position(screen_pos + Vector2i((screen_size - win_size) / 2.0))

	Card.screen_shake_enabled = bool(cfg.get_value("display", "screen_shake", true))
	Haptics.enabled = bool(cfg.get_value("display", "vibration", true))
