extends Control
## The project's actual entry point (run/main_scene): Start / Settings /
## Quit. Start hands off to scenes/lobby.tscn (Host/Join); Settings is an
## inline panel (fullscreen + master volume, both persisted via the
## Settings autoload) rather than a separate scene, since it's small enough
## not to need its own navigation stack.

var _menu_panel: VBoxContainer
var _settings_panel: VBoxContainer
var _fullscreen_check: CheckBox
var _volume_slider: HSlider


func _ready() -> void:
	_build_ui()
	_show_menu()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	margin.add_child(root)

	var title := Label.new()
	title.text = "Uprising: Curse of the Last Emperor"
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)

	root.add_child(_build_menu_panel())
	root.add_child(_build_settings_panel())


func _build_menu_panel() -> VBoxContainer:
	_menu_panel = VBoxContainer.new()

	var start_button := Button.new()
	start_button.text = "Start"
	start_button.pressed.connect(_on_start_pressed)
	_menu_panel.add_child(start_button)

	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(_show_settings)
	_menu_panel.add_child(settings_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(_on_quit_pressed)
	_menu_panel.add_child(quit_button)

	return _menu_panel


func _build_settings_panel() -> VBoxContainer:
	_settings_panel = VBoxContainer.new()

	var settings_title := Label.new()
	settings_title.text = "Settings"
	settings_title.add_theme_font_size_override("font_size", 20)
	_settings_panel.add_child(settings_title)

	_fullscreen_check = CheckBox.new()
	_fullscreen_check.text = "Fullscreen"
	_fullscreen_check.button_pressed = Settings.fullscreen
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_settings_panel.add_child(_fullscreen_check)

	var volume_row := HBoxContainer.new()
	_settings_panel.add_child(volume_row)
	var volume_label := Label.new()
	volume_label.text = "Master Volume:"
	volume_row.add_child(volume_label)
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = Settings.master_volume
	_volume_slider.custom_minimum_size = Vector2(200, 0)
	_volume_slider.value_changed.connect(_on_volume_changed)
	volume_row.add_child(_volume_slider)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(_show_menu)
	_settings_panel.add_child(back_button)

	return _settings_panel


func _show_menu() -> void:
	_menu_panel.visible = true
	_settings_panel.visible = false


func _show_settings() -> void:
	_menu_panel.visible = false
	_settings_panel.visible = true


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_fullscreen_toggled(pressed: bool) -> void:
	Settings.set_fullscreen(pressed)


func _on_volume_changed(value: float) -> void:
	Settings.set_master_volume(value)
