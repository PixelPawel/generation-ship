extends Button
# A square icon button for the main menu's corner (Settings gear, Quit power
# symbol) — drawn in code, since the game font has no such glyphs. Keeps the
# theme's button frame; the icon brightens on hover.

const ICON_COLOR: Color = Color(0.85, 0.92, 1.0, 0.9)
const ICON_HOVER: Color = Color(1.0, 1.0, 1.0)

var kind: String = "gear"   # "gear" or "power"

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)

func _draw() -> void:
	var c: Vector2 = size / 2.0
	var r: float = minf(size.x, size.y) * 0.28
	var col: Color = ICON_HOVER if is_hovered() else ICON_COLOR
	var w: float = maxf(2.0, r * 0.22)
	match kind:
		"gear":
			# 8 teeth around a ring with a hole
			for i: int in 8:
				var a: float = TAU * float(i) / 8.0
				var d: Vector2 = Vector2(cos(a), sin(a))
				draw_line(c + d * r * 0.95, c + d * r * 1.35, col, r * 0.42, false)
			draw_circle(c, r, col)
			draw_circle(c, r * 0.42, get_theme_stylebox("normal").get("bg_color") if get_theme_stylebox("normal") is StyleBoxFlat else Color(0.05, 0.08, 0.15))
		"power":
			# an open ring with a bar through the gap at the top
			draw_arc(c, r * 1.1, deg_to_rad(-60.0), deg_to_rad(240.0), 32, col, w, true)
			draw_line(c + Vector2(0.0, -r * 1.45), c + Vector2(0.0, -r * 0.2), col, w, true)
