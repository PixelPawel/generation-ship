extends Control

var _market_panel: Control = null
var _pinned: bool = false

func _ready() -> void:
	_build_ui()

func set_market_panel(panel: Control) -> void:
	_market_panel = panel

func _process(_delta: float) -> void:
	if _pinned or not _market_panel:
		return
	var market_inner: Control = _market_panel.get_child(0) as Control
	var my_inner: Control = get_child(0) as Control
	if not market_inner or market_inner.size.y <= 0:
		return
	if not my_inner or my_inner.size.x <= 0:
		return
	position = Vector2(
		_market_panel.position.x,
		_market_panel.position.y + market_inner.size.y + 8.0
	)
	_pinned = true
	set_process(false)

func _build_ui() -> void:
	var panel: ScifiPanel = load("res://scenes/ui/scifi_panel.gd").new()
	panel.set_content_margin(12)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	var lines: Array[String] = [
		"Hold Left Mouse Button to Drag",
		"Right Mouse Button to Recycle",
		"Spacebar to End Turn",
	]
	for line: String in lines:
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 1.0))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(lbl)
