@tool
extends Control

## A flat-top hexagon filled with a region of a texture - the faction screen
## shows each Home hex's face-down art this way (the TTS hex atlases have
## opaque black corners, so a rectangle crop won't do). Optional extras:
## - a name plate across the bottom (`label`);
## - a seal in the upper right marking a claim: gold = yours, crimson =
##   someone else's - or a padlock while the faction can't be played yet;
## - hover, selection (accent outline and glow) and keyboard focus, with
##   clicks only counting inside the hexagon, so tokens can share edges in
##   a honeycomb. `pressed` fires on click or ui_accept.
## No class_name - preload it.

signal pressed

@export var texture: Texture2D:
	set(v):
		texture = v
		queue_redraw()
## Region of `texture` in pixels that maps onto the hexagon's bounding box.
@export var region: Rect2 = Rect2(0, 0, 1, 1):
	set(v):
		region = v
		queue_redraw()
@export var label: String = "":
	set(v):
		label = v
		queue_redraw()
@export var accent: Color = Color(0.875, 0.745, 0.424):
	set(v):
		accent = v
		queue_redraw()
@export var border_color: Color = Color(0.055, 0.592, 0.635, 0.6):
	set(v):
		border_color = v
		queue_redraw()
@export var border_width: float = 1.5:
	set(v):
		border_width = v
		queue_redraw()
@export var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()
## Darkened art: the faction is someone else's.
@export var dimmed: bool = false:
	set(v):
		dimmed = v
		queue_redraw()
## Cool grey art and a padlock: the faction can't be played yet.
@export var locked: bool = false:
	set(v):
		locked = v
		queue_redraw()
## "" (none), "gold" or "crimson".
@export var seal: String = "":
	set(v):
		seal = v
		queue_redraw()
## Gap kept between the hexagon and the control's edges.
@export var inset: float = 0.0:
	set(v):
		inset = v
		queue_redraw()

const GOLD := Color(0.875, 0.745, 0.424)
const CRIMSON := Color(0.70, 0.15, 0.23)
const BONE := Color(0.949, 0.91, 0.769)
const PLATE := Color(0.01, 0.045, 0.055, 0.84)

var _hover: bool = false


func _ready() -> void:
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


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
	var avail: Vector2 = size - Vector2(inset, inset) * 2.0
	var w: float = avail.x
	var h: float = w / ratio
	if h > avail.y:
		h = avail.y
		w = h * ratio
	return Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))


func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, _hex_points(_hex_rect()))


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		if focus_mode != FOCUS_NONE:
			grab_focus()
		pressed.emit()
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		pressed.emit()
		accept_event()


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = pts.duplicate()
	out.append(pts[0])
	return out


## The hexagon grown by `d` pixels around its centre.
func _grown(r: Rect2, d: float) -> PackedVector2Array:
	var grown := Rect2(r.position - Vector2(d, d * sqrt(3.0) * 0.5), r.size + Vector2(d * 2.0, d * sqrt(3.0)))
	return _hex_points(grown)


func _draw() -> void:
	var r: Rect2 = _hex_rect()
	var pts: PackedVector2Array = _hex_points(r)
	var lit: bool = selected or _hover

	if selected:
		for i: int in range(4):
			var a: float = 0.32 - 0.07 * float(i)
			draw_polyline(_closed(_grown(r, 2.0 + 2.5 * float(i))), Color(accent, a), 2.5, true)

	if texture != null:
		var tex_size: Vector2 = texture.get_size()
		var uvs := PackedVector2Array()
		for p: Vector2 in pts:
			var t: Vector2 = (p - r.position) / r.size
			uvs.append((region.position + t * region.size) / tex_size)
		var tint: Color = Color.WHITE if lit else Color(0.84, 0.87, 0.88)
		if locked:
			tint = Color(0.62, 0.67, 0.7) if lit else Color(0.42, 0.48, 0.52)
		elif dimmed:
			tint = Color(0.6, 0.62, 0.64) if lit else Color(0.42, 0.45, 0.47)
		draw_polygon(pts, PackedColorArray([tint, tint, tint, tint, tint, tint]), uvs, texture)
	else:
		draw_colored_polygon(pts, Color(0.03, 0.12, 0.14))

	if not label.is_empty():
		_draw_plate(r, lit)

	var edge: Color = border_color
	var edge_w: float = border_width
	if selected:
		edge = accent
		edge_w = maxf(border_width, 3.0)
	elif _hover:
		edge = Color(BONE, 0.7)
		edge_w = maxf(border_width, 2.0)
	draw_polyline(_closed(pts), edge, edge_w, true)
	if has_focus() and not selected:
		draw_polyline(_closed(_grown(r, 3.0)), Color(GOLD, 0.8), 1.5, true)

	var mark_c: Vector2 = r.position + Vector2(r.size.x * 0.7, r.size.y * 0.19)
	var mark_r: float = maxf(5.0, r.size.y * 0.085)
	if r.size.y < 40.0:  # a legend-sized glyph: the mark is the whole point
		mark_c = r.get_center()
		mark_r = r.size.y * 0.3
	if locked:
		_draw_padlock(mark_c, mark_r)
	elif not seal.is_empty():
		var col: Color = GOLD if seal == "gold" else CRIMSON
		draw_circle(mark_c, mark_r + 2.0, Color(0.01, 0.04, 0.05, 0.9))
		draw_circle(mark_c, mark_r, col)
		draw_arc(mark_c, mark_r * 0.55, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 1.5, true)


## Dark band across the bottom of the hexagon with the name centred on it.
func _draw_plate(r: Rect2, lit: bool) -> void:
	var w: float = r.size.x
	var h: float = r.size.y
	var o: Vector2 = r.position
	var top: float = 0.7
	var top_inset: float = (top - 0.5) * 0.5 * w   # where the slanted sides cross the band's top
	draw_colored_polygon(PackedVector2Array([
		o + Vector2(top_inset, h * top), o + Vector2(w - top_inset, h * top),
		o + Vector2(w * 0.75, h), o + Vector2(w * 0.25, h),
	]), PLATE)
	var font: Font = get_theme_font("font", "Label")
	var font_size: int = clampi(int(round(w * 0.14)), 11, 18)
	var band_mid: float = h * (top + 1.0) * 0.5
	var baseline: float = o.y + band_mid + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var color: Color = BONE
	if locked or dimmed:
		color = Color(0.7, 0.74, 0.75) if lit else Color(0.56, 0.62, 0.64)
	elif selected:
		color = accent.lerp(BONE, 0.35)
	draw_string(font, Vector2(o.x, baseline), label, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, color)


func _draw_padlock(c: Vector2, rad: float) -> void:
	draw_circle(c, rad + 2.0, Color(0.01, 0.04, 0.05, 0.9))
	var body := Rect2(c + Vector2(-rad * 0.55, -rad * 0.1), Vector2(rad * 1.1, rad * 0.75))
	var steel := Color(0.72, 0.78, 0.8)
	draw_arc(c + Vector2(0.0, -rad * 0.12), rad * 0.36, PI, TAU, 12, steel, maxf(1.5, rad * 0.18), true)
	draw_rect(body, steel)
	draw_circle(body.get_center(), maxf(1.0, rad * 0.12), Color(0.01, 0.04, 0.05))
