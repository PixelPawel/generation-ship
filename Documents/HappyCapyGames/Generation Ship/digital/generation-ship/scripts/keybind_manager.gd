extends Node

const SETTINGS_PATH: String = "user://settings.cfg"

const ACTION_NAMES: Array[String] = ["end_turn", "pause_menu"]
const ACTION_LABELS: Dictionary = {
	"end_turn": "End Turn",
	"pause_menu": "Pause Menu",
}
const ACTION_DEFAULTS: Dictionary = {
	"end_turn": KEY_SPACE,
	"pause_menu": KEY_ESCAPE,
}

func _ready() -> void:
	for action: String in ACTION_NAMES:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_load_and_apply()

func _load_and_apply() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for action: String in ACTION_NAMES:
		var def: int = int(ACTION_DEFAULTS.get(action, 0))
		var primary: int = int(cfg.get_value("keybinds", action + "_primary", def))
		var secondary: int = int(cfg.get_value("keybinds", action + "_secondary", 0))
		_apply(action, primary, secondary)

func _apply(action: String, primary: int, secondary: int) -> void:
	InputMap.action_erase_events(action)
	if primary != 0:
		var ev := InputEventKey.new()
		ev.keycode = primary as Key
		InputMap.action_add_event(action, ev)
	if secondary != 0:
		var ev2 := InputEventKey.new()
		ev2.keycode = secondary as Key
		InputMap.action_add_event(action, ev2)

func save_binding(action: String, primary: int, secondary: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("keybinds", action + "_primary", primary)
	cfg.set_value("keybinds", action + "_secondary", secondary)
	cfg.save(SETTINGS_PATH)
	_apply(action, primary, secondary)

func get_primary(action: String) -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var def: int = int(ACTION_DEFAULTS.get(action, 0))
	return int(cfg.get_value("keybinds", action + "_primary", def))

func get_secondary(action: String) -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return int(cfg.get_value("keybinds", action + "_secondary", 0))
