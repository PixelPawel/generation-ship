extends Control

const SETTINGS_PATH: String = "user://settings.cfg"
const _PARALLAX_STRENGTH: float = 10.0
const _PARALLAX_SPEED: float = 3.0
const _BTN_HOVER_IN_SEC: float = 0.15
const _BTN_HOVER_OUT_SEC: float = 0.22

var _btn_tweens: Dictionary = {}
var _music_player: AudioStreamPlayer = null

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
	_setup_starfield()
	_setup_music()
	$VBox/MultiplayerBtn.modulate.a = 0.0
	$VBox/SettingsBtn.modulate.a = 0.0
	$VBox/QuitBtn.modulate.a = 0.0
	call_deferred("_start_animations")
	var ver_lbl := Label.new()
	ver_lbl.text = "v" + ProjectSettings.get_setting("application/config/version")
	ver_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver_lbl.position = Vector2(-60.0, -28.0)
	ver_lbl.add_theme_font_size_override("font_size", 13)
	ver_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.45))
	ver_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver_lbl)

func _process(delta: float) -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	var norm: Vector2 = (get_viewport().get_mouse_position() / vp_size - Vector2(0.5, 0.5)) * 2.0
	$Background.position = $Background.position.lerp(norm * -_PARALLAX_STRENGTH, delta * _PARALLAX_SPEED)

func _setup_music() -> void:
	var stream: AudioStreamOggVorbis = load("res://assets/music/ambience.ogg") as AudioStreamOggVorbis
	if not stream:
		return
	stream.loop = true
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = stream
	_music_player.bus = &"Music"
	_music_player.volume_db = -80.0
	add_child(_music_player)
	_music_player.play()
	var tw: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_music_player, "volume_db", 0.0, 2.0)

func _setup_starfield() -> void:
	var sf: Control = Control.new()
	sf.set_script(load("res://scenes/ui/starfield.gd"))
	add_child(sf)
	move_child(sf, $DarkOverlay.get_index() + 1)
	sf.z_index = 0

func _start_animations() -> void:
	_animate_overlay()
	_animate_logo()
	_animate_buttons()
	_setup_button_hover($VBox/MultiplayerBtn as Button)
	_setup_button_hover($VBox/SettingsBtn as Button)
	_setup_button_hover($VBox/QuitBtn as Button)

func _animate_overlay() -> void:
	var tw: Tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property($DarkOverlay, "color:a", 0.58, 4.0)
	tw.tween_property($DarkOverlay, "color:a", 0.45, 4.0)

func _animate_logo() -> void:
	var title: TextureRect = $Title
	var base_y: float = title.position.y
	var tw: Tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(title, "position:y", base_y - 6.0, 2.0)
	tw.tween_property(title, "position:y", base_y + 6.0, 2.0)

func _animate_buttons() -> void:
	var buttons: Array[Node] = [$VBox/MultiplayerBtn, $VBox/SettingsBtn, $VBox/QuitBtn]
	for i: int in buttons.size():
		var btn: Control = buttons[i] as Control
		var tw: Tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.35 + float(i) * 0.15)
		tw.tween_property(btn, "modulate:a", 1.0, 0.40)

func _setup_button_hover(btn: Button) -> void:
	btn.pivot_offset = btn.size / 2.0
	btn.mouse_entered.connect(func() -> void: _on_btn_hover_enter(btn))
	btn.mouse_exited.connect(func() -> void: _on_btn_hover_exit(btn))

func _on_btn_hover_enter(btn: Button) -> void:
	var tw: Tween = _btn_tweens.get(btn) as Tween
	if tw and tw.is_valid():
		tw.kill()
	tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(btn, "scale", Vector2(1.06, 1.06), _BTN_HOVER_IN_SEC)
	tw.parallel().tween_property(btn, "modulate", Color(1.4, 1.4, 1.4, 1.0), _BTN_HOVER_IN_SEC)
	_btn_tweens[btn] = tw

func _on_btn_hover_exit(btn: Button) -> void:
	var tw: Tween = _btn_tweens.get(btn) as Tween
	if tw and tw.is_valid():
		tw.kill()
	tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(btn, "scale", Vector2(1.0, 1.0), _BTN_HOVER_OUT_SEC)
	tw.parallel().tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), _BTN_HOVER_OUT_SEC)
	_btn_tweens[btn] = tw

func _on_settings_btn_pressed() -> void:
	$PauseMenu.open_settings()

func _on_multiplayer_pressed() -> void:
	if _music_player:
		create_tween().tween_property(_music_player, "volume_db", -80.0, 0.25)
	SceneTransition.change_scene("res://scenes/lobby/lobby.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _apply_saved_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return

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
