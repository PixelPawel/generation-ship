extends Control
const Haptics = preload("res://scripts/haptics.gd")
const TutorialSession = preload("res://scripts/tutorial_session.gd")
const MenuIconButton = preload("res://scenes/ui/menu_icon_button.gd")

# ── Layout ────────────────────────────────────────────────────────────────────
# Tutorial, Versus, Co-op (not yet) and Quit down the middle, the four tools as a row
# of art tiles along the bottom, Settings as a gear in the top-right corner. The stacked list of eight buttons had run off the bottom of the screen.
const PLAY_BTN_SIZE: Vector2 = Vector2(440, 84)
const PLAY_FONT: int = 40
const VBOX_RAISE: float = -10.0   # the scene's VBox sits at 40% + 40 px
const TILE_SIZE: Vector2 = Vector2(200, 176)
const TILE_GAP: int = 26
const TILE_BOTTOM: float = 96.0           # clear of the corner links
const CORNER_BTN: float = 64.0
const TILE_ART: Dictionary = {
	"Rule Book": "res://assets/cards/Rule Book/%s/GS Rule Book A5.png",
	"Collection": "res://assets/cards/Tech/%s/GS Techs 44x67mm125.png",
	"Scan Tableau": "res://assets/scan/guide.jpg",
	"Leaderboard": "res://assets/cards/ScoreBoard/%s/ScoreBoard.png",
}
var _tile_row: HBoxContainer = null
var _corner_btns: Array[Button] = []
# Background warm-up of the tool windows (see _warm_up_tools)
const WARM_UP_DELAY: float = 1.0
var _warm_cache: Array[Resource] = []   # keeps the preloaded art in the resource cache

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
	TutorialSession.active = false   # however the last game ended
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

	_build_menu_layout()
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
	_warm_up_tools()

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
	var hover_targets: Array[Node] = $Panels/MainView/VBox.find_children("*", "Button", true, false)
	if _tile_row:
		hover_targets.append_array(_tile_row.get_children())
	for btn: Node in hover_targets:
		if btn is Button:
			_setup_button_hover(btn as Button)
	for btn: TextureButton in _link_buttons:
		_setup_button_hover(btn)
		var tw: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.2)
		tw.tween_property(btn, "modulate:a", 1.0, 0.5)

# The 3D logo is two clips: an entrance that plays once, then a seamless idle
# loop. The loop player is loaded up front (hidden, paused) so it can take over
# on the entrance's last frame without a blank gap while a new file opens.
func _animate_logo() -> void:
	const INTRO_PATH: String = "res://assets/video/logo_intro.webm"
	const LOOP_PATH: String = "res://assets/video/logo_loop.webm"
	var title: TextureRect = $Panels/MainView/Title
	if not FileAccess.file_exists(INTRO_PATH) or not FileAccess.file_exists(LOOP_PATH):
		title.modulate.a = 1.0
		return
	title.hide()
	var loop_vp: VideoPlayback = _add_logo_player(title.get_parent(), LOOP_PATH, true)
	loop_vp.visible = false
	var intro_vp: VideoPlayback = _add_logo_player(title.get_parent(), INTRO_PATH, false)
	intro_vp.enable_auto_play = true
	intro_vp.video_ended.connect(func() -> void:
		loop_vp.visible = true
		loop_vp.play()
		intro_vp.queue_free())

func _add_logo_player(parent: Node, video_path: String, looping: bool) -> VideoPlayback:
	var vp: VideoPlayback = VideoPlayback.new()
	vp.enable_audio = false
	vp.loop = looping
	parent.add_child(vp)
	vp.anchor_left = 0.0
	vp.anchor_top = 0.0
	vp.anchor_right = 1.0
	vp.anchor_bottom = 0.0
	vp.offset_top = 48.0
	vp.offset_bottom = 408.0
	vp.video_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vp.set_video_path(video_path)
	return vp

func _animate_buttons() -> void:
	var buttons: Array[Node] = $Panels/MainView/VBox.get_children()
	if _tile_row:
		buttons.append_array(_tile_row.get_children())
	for b: Button in _corner_btns:
		buttons.append(b)
	for i: int in buttons.size():
		var btn: Control = buttons[i] as Control
		var tw: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.35 + float(i) * 0.12)
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

func _build_menu_layout() -> void:
	var vbox: VBoxContainer = $Panels/MainView/VBox
	# the tools leave the list: they become tiles / corner icons below
	for n: String in ["SettingsBtn", "RuleBookBtn", "CollectionBtn", "ScanTableauBtn", "LeaderboardBtn"]:
		var old: Node = vbox.get_node_or_null(n)
		if old:
			vbox.remove_child(old)
			old.queue_free()
	vbox.offset_top = VBOX_RAISE   # a little higher than the scene has it
	vbox.offset_bottom = VBOX_RAISE
	vbox.add_theme_constant_override("separation", 12)
	var start: Button = vbox.get_node("MultiplayerBtn")   # keeps its lobby connection
	start.text = "Versus"
	start.custom_minimum_size = PLAY_BTN_SIZE
	start.add_theme_font_size_override("font_size", PLAY_FONT)
	# Co-op (Generation Fleet): not playable yet
	var coop: Button = _menu_button("Co-op", 32, Vector2(440, 64))
	coop.disabled = true
	coop.tooltip_text = tr("Coming soon")
	vbox.add_child(coop)
	vbox.move_child(coop, start.get_index() + 1)
	# Quit under them, as before (phones close apps through the system instead)
	var quit: Button = vbox.get_node_or_null("QuitBtn")
	if quit:
		vbox.move_child(quit, vbox.get_child_count() - 1)
		quit.visible = not OS.has_feature("mobile")

	# Tutorial (recommended until finished once) above Play a Game
	var tut_box: VBoxContainer = VBoxContainer.new()
	tut_box.add_theme_constant_override("separation", 2)
	var tut_btn: Button = _menu_button("Tutorial", PLAY_FONT, PLAY_BTN_SIZE)
	tut_btn.pressed.connect(_on_tutorial_pressed)
	tut_box.add_child(tut_btn)
	if not _tutorial_done():
		var rec: Label = Label.new()
		rec.text = "Recommended for your first game"
		rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rec.add_theme_font_size_override("font_size", 18)
		rec.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		tut_box.add_child(rec)
	vbox.add_child(tut_box)
	vbox.move_child(tut_box, 0)

	# the tools: a row of art tiles along the bottom
	_tile_row = HBoxContainer.new()
	_tile_row.add_theme_constant_override("separation", TILE_GAP)
	_tile_row.alignment = BoxContainer.ALIGNMENT_CENTER
	$Panels/MainView.add_child(_tile_row)
	_tile_row.anchor_left = 0.0
	_tile_row.anchor_right = 1.0
	_tile_row.anchor_top = 1.0
	_tile_row.anchor_bottom = 1.0
	_tile_row.offset_top = -TILE_BOTTOM - TILE_SIZE.y
	_tile_row.offset_bottom = -TILE_BOTTOM
	_tile_row.add_child(_make_tile("Rule Book", _on_rule_book_pressed))
	_tile_row.add_child(_make_tile("Collection", _on_collection_pressed))
	_tile_row.add_child(_make_tile("Scan Tableau", _on_scan_tableau_pressed))
	_tile_row.add_child(_make_tile("Leaderboard", _on_leaderboard_pressed))

	# Settings: a gear in the top-right corner
	var side: float = GameTheme.TOUCH_CORNER_MARGIN if GameTheme.is_touch() else 28.0
	var size_px: float = GameTheme.TOUCH_MIN_SIZE if GameTheme.is_touch() else CORNER_BTN
	var icons: Array = [["gear", "Settings", _on_settings_btn_pressed]]
	for k: int in icons.size():
		var b: Button = MenuIconButton.new()
		b.set("kind", icons[k][0])
		b.tooltip_text = tr(str(icons[k][1]))
		GameTheme.apply_to_button(b)
		b.pressed.connect(icons[k][2] as Callable)
		$Panels/MainView.add_child(b)
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.offset_right = -side - float(k) * (size_px + 14.0)
		b.offset_left = b.offset_right - size_px
		b.offset_top = side
		b.offset_bottom = side + size_px
		b.modulate.a = 0.0
		_corner_btns.append(b)

# The first open of Collection / Rule Book / Leaderboard / Scan Tableau used
# to stutter: card art and rule book pages loading on the spot, the card grid
# being built, and shaders compiling on their first draw. All of that happens
# here instead, in the background, shortly after the menu appears.
func _warm_up_tools() -> void:
	await get_tree().create_timer(WARM_UP_DELAY).timeout
	var paths: Array[String] = []
	paths.append_array(_collection.call("warm_up_paths") as Array[String])
	paths.append_array(_manual.call("warm_up_paths") as Array[String])
	var pending: Array[String] = []
	for path: String in paths:
		if path.is_empty() or ResourceLoader.has_cached(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			pending.append(path)
	while not pending.is_empty():
		await get_tree().process_frame
		if not is_inside_tree():
			return
		for path: String in pending.duplicate():
			var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_warm_cache.append(ResourceLoader.load_threaded_get(path))
				pending.erase(path)
			elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pending.erase(path)
	_manual.call("warm_up")
	_collection.call("warm_up")
	# one invisible draw each, so their shaders compile now, not on first open
	var popups: Array[Control] = [_collection, _manual, _leaderboard, _photo_scan]
	for p: Control in popups:
		if not p.visible:
			p.modulate.a = 0.01
			p.visible = true
			p.set_meta(&"_warming", true)
	await get_tree().process_frame
	await get_tree().process_frame
	for p: Control in popups:
		if p.has_meta(&"_warming"):
			p.remove_meta(&"_warming")
			p.visible = false
			p.modulate.a = 1.0

func _menu_button(label: String, font_size: int, min_size: Vector2) -> Button:
	var b: Button = Button.new()
	b.text = label
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	return b

# A tool tile: the feature's own art with its name under it.
func _make_tile(label: String, on_press: Callable) -> Button:
	var tile: Button = Button.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.focus_mode = Control.FOCUS_NONE
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.tooltip_text = tr(label)
	tile.modulate.a = 0.0
	tile.pressed.connect(on_press)
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10.0
	box.offset_right = -10.0
	box.offset_top = 10.0
	box.offset_bottom = -8.0
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	var art: TextureRect = TextureRect.new()
	art.texture = _tile_art(label)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.clip_contents = true
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(art)
	var lbl: Label = Label.new()
	lbl.text = label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lbl)
	return tile

func _tile_art(label: String) -> Texture2D:
	var path: String = str(TILE_ART.get(label, ""))
	if path.contains("%s"):
		var lang: String = TranslationServer.get_locale().substr(0, 2).to_upper()
		var local: String = path % lang
		path = local if ResourceLoader.exists(local) else path % "EN"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _tutorial_done() -> bool:
	var cfg: ConfigFile = ConfigFile.new()
	return cfg.load(SETTINGS_PATH) == OK and bool(cfg.get_value("tutorial", "seen", false))

func _on_tutorial_pressed() -> void:
	TutorialSession.active = true
	GameNetwork.is_multiplayer = false
	GameNetwork.bot_ids = []
	GameNetwork.player_names = {}
	SceneTransition.change_scene("res://scenes/main/main.tscn")

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
