class_name ScifiPanel
extends PanelContainer

const CLIP_SZ   := 10.0
const CORNER_LEN := 18.0
const BORDER_W  := 1.2
const CORNER_W  := 2.5

const COL_BG     := Color(0.03, 0.04, 0.09, 0.93)
const COL_BORDER := Color(0.22, 0.44, 0.70, 0.38)
const COL_CORNER := Color(0.38, 0.80, 1.00, 0.95)
const COL_GLOW   := Color(0.18, 0.52, 0.90, 0.055)

var _style: StyleBoxFlat = null

func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = Color.TRANSPARENT
	_style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", _style)
	resized.connect(queue_redraw)
	theme = GameTheme.get_theme()

func set_content_margin(m: int) -> void:
	if _style:
		_style.set_content_margin_all(m)

func _draw() -> void:
	var sz := size
	if sz.x < 1 or sz.y < 1:
		return
	var cs := CLIP_SZ

	# Clipped octagon background
	var pts := PackedVector2Array([
		Vector2(cs, 0),         Vector2(sz.x - cs, 0),
		Vector2(sz.x, cs),      Vector2(sz.x, sz.y - cs),
		Vector2(sz.x - cs, sz.y), Vector2(cs, sz.y),
		Vector2(0, sz.y - cs),  Vector2(0, cs),
	])
	draw_colored_polygon(pts, COL_BG)

	# Inner glow — faint rect outlines fading inward
	for i: int in range(4):
		var inset: float = float(i) * 2.5 + 1.0
		var a: float = COL_GLOW.a * (1.0 - float(i) * 0.22)
		draw_rect(
			Rect2(Vector2(inset, inset), sz - Vector2(inset * 2.0, inset * 2.0)),
			Color(COL_GLOW.r, COL_GLOW.g, COL_GLOW.b, a), false, 1.5
		)

	# Outer border along the clipped polygon
	var closed := PackedVector2Array(Array(pts) + [pts[0]])
	draw_polyline(closed, COL_BORDER, BORDER_W, true)

	# Corner brackets
	_draw_corners(sz)

func _draw_corners(sz: Vector2) -> void:
	var c := COL_CORNER
	var w := CORNER_W
	var cl := CORNER_LEN
	var cs := CLIP_SZ

	# Top-left
	draw_line(Vector2(cs, 0),        Vector2(cs + cl, 0),       c, w, true)
	draw_line(Vector2(0, cs),        Vector2(0, cs + cl),        c, w, true)
	draw_line(Vector2(0, cs),        Vector2(cs, 0),             c, w, true)

	# Top-right
	draw_line(Vector2(sz.x - cs, 0),        Vector2(sz.x - cs - cl, 0),   c, w, true)
	draw_line(Vector2(sz.x, cs),            Vector2(sz.x, cs + cl),        c, w, true)
	draw_line(Vector2(sz.x - cs, 0),        Vector2(sz.x, cs),             c, w, true)

	# Bottom-left
	draw_line(Vector2(0, sz.y - cs),        Vector2(0, sz.y - cs - cl),    c, w, true)
	draw_line(Vector2(cs, sz.y),            Vector2(cs + cl, sz.y),        c, w, true)
	draw_line(Vector2(0, sz.y - cs),        Vector2(cs, sz.y),             c, w, true)

	# Bottom-right
	draw_line(Vector2(sz.x, sz.y - cs),     Vector2(sz.x, sz.y - cs - cl), c, w, true)
	draw_line(Vector2(sz.x - cs, sz.y),     Vector2(sz.x - cs - cl, sz.y), c, w, true)
	draw_line(Vector2(sz.x, sz.y - cs),     Vector2(sz.x - cs, sz.y),      c, w, true)
