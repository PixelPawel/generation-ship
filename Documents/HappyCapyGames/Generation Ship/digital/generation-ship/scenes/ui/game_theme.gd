class_name GameTheme

static var _cached: Theme = null

static func get_theme() -> Theme:
	if not _cached:
		_cached = _build()
	return _cached

# Adds a persistent hide/show tab to a popup root Control.
# contents: nodes to hide/show (panel, backdrop, etc.)
# modal: if true, also toggles root mouse_filter so interaction passes through when hidden.
static func add_hide_button(root: Control, label: String, contents: Array, modal: bool = false) -> void:
	var tab := Button.new()
	tab.text = label
	tab.z_index = 100
	tab.anchor_left = 0.5
	tab.anchor_right = 0.5
	tab.anchor_top = 1.0
	tab.anchor_bottom = 1.0
	tab.offset_left = -65.0
	tab.offset_right = 65.0
	tab.offset_top = 8.0
	tab.offset_bottom = 38.0
	root.add_child(tab)
	apply_to_button(tab)

	tab.pressed.connect(func() -> void:
		var showing: bool = not (contents[0] as CanvasItem).visible
		for c: Variant in contents:
			(c as CanvasItem).visible = showing
		if modal:
			root.mouse_filter = Control.MOUSE_FILTER_STOP if showing else Control.MOUSE_FILTER_IGNORE
		tab.text = "Hide Panel" if showing else "Reveal Panel"
	)

static func apply_to_button(btn: Button) -> void:
	var t: Theme = get_theme()
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, t.get_stylebox(state, "Button"))
	btn.add_theme_color_override("font_color",          t.get_color("font_color",          "Button"))
	btn.add_theme_color_override("font_hover_color",    t.get_color("font_hover_color",    "Button"))
	btn.add_theme_color_override("font_pressed_color",  t.get_color("font_pressed_color",  "Button"))
	btn.add_theme_color_override("font_disabled_color", t.get_color("font_disabled_color", "Button"))
	btn.add_theme_color_override("font_focus_color",    t.get_color("font_focus_color",    "Button"))

static func _build() -> Theme:
	var theme := Theme.new()

	var normal   := _btn(Color(0.06, 0.09, 0.15, 0.90), Color(0.22, 0.40, 0.65, 0.60), 1)
	var hover    := _btn(Color(0.10, 0.18, 0.30, 0.95), Color(0.35, 0.70, 1.00, 0.90), 2)
	hover.shadow_color = Color(0.20, 0.50, 1.00, 0.45)
	hover.shadow_size = 6
	var pressed  := _btn(Color(0.04, 0.06, 0.11, 1.00), Color(0.28, 0.55, 0.85, 0.70), 1)
	var disabled := _btn(Color(0.04, 0.05, 0.08, 0.50), Color(0.15, 0.20, 0.30, 0.30), 1)

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(0.35, 0.70, 1.00, 0.60)
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(3)

	theme.set_stylebox("normal",        "Button", normal)
	theme.set_stylebox("hover",         "Button", hover)
	theme.set_stylebox("pressed",       "Button", pressed)
	theme.set_stylebox("hover_pressed", "Button", pressed)
	theme.set_stylebox("disabled",      "Button", disabled)
	theme.set_stylebox("focus",         "Button", focus)

	theme.set_color("font_color",          "Button", Color(0.78, 0.88, 1.00))
	theme.set_color("font_hover_color",    "Button", Color(0.92, 0.97, 1.00))
	theme.set_color("font_pressed_color",  "Button", Color(0.65, 0.80, 1.00))
	theme.set_color("font_disabled_color", "Button", Color(0.38, 0.45, 0.58))
	theme.set_color("font_focus_color",    "Button", Color(0.78, 0.88, 1.00))

	return theme

static func _btn(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(3)
	s.content_margin_left = 10.0
	s.content_margin_right = 10.0
	s.content_margin_top = 5.0
	s.content_margin_bottom = 5.0
	return s
