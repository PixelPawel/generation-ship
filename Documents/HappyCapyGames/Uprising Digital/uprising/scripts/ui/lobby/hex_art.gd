@tool
extends Control

## A flat-top hexagon filled with a region of a texture - the lobby's
## faction banners show each Home hex's face-down art this way (the TTS hex
## atlases have opaque black corners, so a rectangle crop won't do). An
## optional seal in the upper right marks a claim: gold = yours, crimson =
## someone else's. No class_name - preload it.

@export var texture: Texture2D:
	set(v):
		texture = v
		queue_redraw()
## Region of `texture` in pixels that maps onto the hexagon's bounding box.
@export var region: Rect2 = Rect2(0, 0, 1, 1):
	set(v):
		region = v
		queue_redraw()
@export var border_color: Color = Color(0.055, 0.592, 0.635, 0.6):
	set(v):
		border_color = v
		queue_redraw()
@export var border_width: float = 2.0:
	set(v):
		border_width = v
		queue_redraw()
@export var dimmed: bool = false:
	set(v):
		dimmed = v
		queue_redraw()
## "" (none), "gold" or "crimson".
@export var seal: String = "":
	set(v):
		seal = v
		queue_redraw()

const GOLD := Color(0.875, 0.745, 0.424)
const CRIMSON := Color(0.70, 0.15, 0.23)


func _hex_points(r: Rect2) -> PackedVector2Array:
	var w: float = r.size.x
	var h: float = r.size.y
	var o: Vector2 = r.position
	return PackedVector2Array([
		o + Vector2(0.0, h * 0.5), o + Vector2(w * 0.25, 0.0), o + Vector2(w * 0.75, 0.0),
		o + Vector2(w, h * 0.5), o + Vector2(w * 0.75, h), o + Vector2(w * 0.25, h),
	])


## The largest flat-top hex (width : height = 2 : sqrt 3) that fits.
func _hex_rect() -> Rect2:
	var ratio: float = 2.0 / sqrt(3.0)
	var w: float = size.x
	var h: float = w / ratio
	if h > size.y:
		h = size.y
		w = h * ratio
	return Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))


func _draw() -> void:
	var r: Rect2 = _hex_rect()
	var pts: PackedVector2Array = _hex_points(r)
	if texture != null:
		var tex_size: Vector2 = texture.get_size()
		var uvs := PackedVector2Array()
		for p: Vector2 in pts:
			var t: Vector2 = (p - r.position) / r.size
			uvs.append((region.position + t * region.size) / tex_size)
		var tint: Color = Color(0.45, 0.48, 0.5) if dimmed else Color.WHITE
		draw_polygon(pts, PackedColorArray([tint, tint, tint, tint, tint, tint]), uvs, texture)
	else:
		draw_colored_polygon(pts, Color(0.03, 0.12, 0.14))
	var outline: PackedVector2Array = pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, border_color, border_width, true)
	if not seal.is_empty():
		var c: Vector2 = r.position + Vector2(r.size.x * 0.84, r.size.y * 0.16)
		var rad: float = maxf(6.0, r.size.y * 0.1)
		var col: Color = GOLD if seal == "gold" else CRIMSON
		draw_circle(c, rad + 2.0, Color(0.01, 0.04, 0.05, 0.9))
		draw_circle(c, rad, col)
		draw_arc(c, rad * 0.55, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 1.5, true)
