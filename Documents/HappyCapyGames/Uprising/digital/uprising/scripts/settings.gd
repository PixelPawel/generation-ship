extends Node
## Autoload. Persisted user settings (window mode, master volume) --
## loaded and applied as early as possible (this node's own _ready(),
## since autoloads initialize before any scene), saved whenever changed.

const SAVE_PATH := "user://settings.cfg"

var fullscreen: bool = false
var master_volume: float = 1.0  # 0.0-1.0, linear -- converted to dB for AudioServer


func _ready() -> void:
	load_settings()
	apply_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # no saved settings yet -- keep the defaults above
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.save(SAVE_PATH)


## Pushes the current settings values into the engine (window mode, audio
## bus). Call after changing fullscreen/master_volume from a settings UI.
## "Not fullscreen" means Maximized, not plain Windowed -- project.godot's
## own window/size/mode already starts the game maximized (its resolution
## following whatever screen it's on, at a native 1:1 pixel scale, not a
## smaller fixed window) and this needs to keep reapplying that on every
## future launch instead of fighting it back down to the small design-time
## window/size/viewport_width/height. True Fullscreen (borderless, no
## window chrome) is still its own explicit opt-in via the Settings menu.
func apply_settings() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_MAXIMIZED
	)
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(clampf(master_volume, 0.0, 1.0)))


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	apply_settings()
	save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_settings()
	save_settings()
