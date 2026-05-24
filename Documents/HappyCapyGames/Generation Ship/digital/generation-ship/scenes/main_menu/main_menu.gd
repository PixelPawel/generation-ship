extends Control

const SETTINGS_PATH: String = "user://settings.cfg"

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

func _on_multiplayer_pressed() -> void:
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
