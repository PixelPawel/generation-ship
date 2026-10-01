class_name GameTheme

static var _cached: Theme = null

static func get_theme() -> Theme:
	if not _cached:
		_cached = _build()
	return _cached

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

	# Godot's built-in tooltips (tooltip_text on buttons etc.) — same size as
	# the cockpit's floating tooltip (see tooltip_scale()).
	theme.set_font_size("font_size", "TooltipLabel", roundi(TOOLTIP_BASE_FONT * tooltip_scale()))

	return theme

# ── Touch-friendly buttons (phones) ───────────────────────────────────────────
# Buttons were sized for a mouse (36-64 px on the 1080p layout ≈ 4-7 mm on a
# phone). touchify() gives every button under `root` a ~9 mm (≈48 dp) minimum
# touch target and larger text — phones only, a no-op on desktop. Call it at
# the end of a panel's build, and again on any buttons created later.

const TOUCH_MIN_SIZE: float = 88.0   # canvas px on the 1920x1080 layout
const TOUCH_FONT_SCALE: float = 1.4
const TOUCH_DEFAULT_FONT: int = 16
const TOUCH_LARGE_FONT: int = 24
const TOUCH_SETTINGS_ROW: float = 64.0   # settings rows: many of them, so a bit less

static func is_touch() -> bool:
	return OS.has_feature("mobile")

static func touchify(root: Node) -> void:
	if not is_touch() or root == null:
		return
	if root is BaseButton:
		_touchify_button(root as BaseButton)
	for child: Node in root.find_children("*", "BaseButton", true, false):
		_touchify_button(child as BaseButton)

static func _touchify_button(btn: BaseButton) -> void:
	if btn.has_meta(&"_touchified"):
		return
	btn.set_meta(&"_touchified", true)
	# CheckBox/CheckButton: only the row height matters, the toggle itself is drawn by the theme.
	btn.custom_minimum_size = Vector2(maxf(btn.custom_minimum_size.x, TOUCH_MIN_SIZE),
			maxf(btn.custom_minimum_size.y, TOUCH_MIN_SIZE))
	if btn is Button:
		var size: int = btn.get_theme_font_size("font_size") if btn.has_theme_font_size_override("font_size") else TOUCH_DEFAULT_FONT
		if size < TOUCH_LARGE_FONT:   # already-big text (e.g. the vote buttons) stays as is
			btn.add_theme_font_size_override("font_size", roundi(size * TOUCH_FONT_SCALE))

# ── Tooltip size (Settings → Tooltip Size) ────────────────────────────────────
# Final tooltip scale = device factor (phones only, from the screen's physical
# height) × the player's chosen size. Default choice: 200% on phones (they were
# hard to read at 100%), 100% on desktop.

const SETTINGS_PATH: String = "user://settings.cfg"
const TOOLTIP_SIZES: Array[float] = [0.75, 1.0, 1.5, 2.0, 2.5, 3.0]
const TOOLTIP_BASE_FONT: float = 16.0
# Desktop needs no device factor: canvas_items stretch (1920x1080 base)
# already grows the UI with the window. A phone gets the same canvas scale as
# a 1080p monitor on a screen a few cm tall, so it's scaled by physical height.
const TOOLTIP_MOBILE_REF_HEIGHT_IN: float = 4.5  # screens this tall (inches) or taller need no boost
const TOOLTIP_MOBILE_MAX_SCALE: float = 1.8
const TOOLTIP_MOBILE_FALLBACK_SCALE: float = 1.6  # device reports no usable DPI

static var _tooltip_size: float = -1.0   # player's choice, loaded lazily

static func tooltip_scale() -> float:
	return _device_tooltip_scale() * tooltip_size()

static func tooltip_size() -> float:
	if _tooltip_size < 0.0:
		var cfg: ConfigFile = ConfigFile.new()
		var default_size: float = 2.0 if OS.has_feature("mobile") else 1.0
		_tooltip_size = default_size
		if cfg.load(SETTINGS_PATH) == OK:
			_tooltip_size = float(cfg.get_value("display", "tooltip_size", default_size))
	return _tooltip_size

# Saves the choice and resizes the built-in tooltips right away; the cockpit's
# floating tooltip picks it up the next time it's shown.
static func set_tooltip_size(size: float) -> void:
	_tooltip_size = size
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "tooltip_size", size)
	cfg.save(SETTINGS_PATH)
	get_theme().set_font_size("font_size", "TooltipLabel", roundi(TOOLTIP_BASE_FONT * tooltip_scale()))

static func _device_tooltip_scale() -> float:
	if not OS.has_feature("mobile"):
		return 1.0
	var dpi: int = DisplayServer.screen_get_dpi()
	if dpi <= 0:
		return TOOLTIP_MOBILE_FALLBACK_SCALE
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var screen_h_px: float = float(mini(screen_size.x, screen_size.y))  # short side = height in landscape
	var screen_h_in: float = screen_h_px / float(dpi)
	return clampf(TOOLTIP_MOBILE_REF_HEIGHT_IN / screen_h_in, 1.0, TOOLTIP_MOBILE_MAX_SCALE)

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
