extends Control

## The seven phases of a Chapter as numbered diamonds - the current one
## crimson with a gold edge, finished ones dim gold, coming ones dim teal.
## No class_name - preload it.

const Style := preload("res://scripts/ui/hud/hud_style.gd")
const NUMERALS: Array[String] = ["I", "II", "III", "IV", "V", "VI", "VII"]
const STEP: float = 27.0
const RADIUS: float = 11.0

var current: int = 0:
	set(v):
		current = v
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(STEP * NUMERALS.size() + 4.0, RADIUS * 2.0 + 6.0)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var cy: float = size.y * 0.5
	for i: int in range(NUMERALS.size()):
		var c := Vector2(RADIUS + 3.0 + STEP * float(i), cy)
		var pts := PackedVector2Array([c + Vector2(0, -RADIUS), c + Vector2(RADIUS, 0), c + Vector2(0, RADIUS), c + Vector2(-RADIUS, 0)])
		var fill: Color = Color(0.024, 0.157, 0.172)
		var edge: Color = Color(Style.TEAL, 0.45)
		var ink: Color = Color(Style.MUTED, 0.6)
		var width: float = 1.0
		if i == current:
			fill = Style.CRIMSON
			edge = Style.GOLD
			ink = Style.BONE
			width = 2.0
		elif i < current:
			fill = Color(0.16, 0.13, 0.08)
			edge = Color(Style.GOLD, 0.55)
			ink = Color(Style.GOLD, 0.7)
		draw_colored_polygon(pts, fill)
		var ring: PackedVector2Array = pts.duplicate()
		ring.append(pts[0])
		draw_polyline(ring, edge, width, true)
		var size_px: int = 9 if NUMERALS[i].length() > 2 else 10
		var font: Font = Style.FONT_DISPLAY
		var w: float = font.get_string_size(NUMERALS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var baseline: float = c.y + (font.get_ascent(size_px) - font.get_descent(size_px)) * 0.5
		draw_string(font, Vector2(c.x - w * 0.5, baseline), NUMERALS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, ink)


func _get_tooltip(at_position: Vector2) -> String:
	var i: int = clampi(int((at_position.x - 3.0) / STEP), 0, NUMERALS.size() - 1)
	return "%s. %s phase" % [NUMERALS[i], ["Refresh", "Events", "Build", "Actions", "Nemesis", "Production", "Scoring"][i]]
